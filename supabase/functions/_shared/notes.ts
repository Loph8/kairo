// One plain-English sentence explaining the suggested family time. Claude writes it when a key is
// configured; otherwise (or if Claude is slow or fails) a template does. Cached per suggestion.
import type { FamilyState } from './familyState.ts';
import { fmtLocal } from './time.ts';

export interface NoteFacts {
  readonly viewer: string;
  readonly people: readonly { name: string; localTime: string; pickupPercent: number; isViewer: boolean }[];
  readonly everyoneLikely: boolean;
  readonly latestSignal: string | null;
}

export interface NoteWriter { write(facts: NoteFacts): Promise<string> }

export interface NoteStore { getNote(key: string): Promise<string | null>; putNote(key: string, text: string): Promise<void> }

export async function noteFor(state: FamilyState, viewerId: string, store: NoteStore, writer?: NoteWriter): Promise<string | null> {
  const s = state.suggestion;
  if (!s) return null;
  const facts = factsOf(state, viewerId);
  if (!facts) return null;
  const key = `${viewerId}:${s.start}:${Object.entries(s.levels).sort().map(([k, v]) => k + v).join(',')}`;
  const cached = await store.getNote(key);
  if (cached) return cached;
  const text = writer ? await writer.write(facts).catch(() => templateNote(facts)) : templateNote(facts);
  const clean = text.replace(/\s+/g, ' ').trim().slice(0, 300);
  await store.putNote(key, clean).catch(() => {});
  return clean;
}

function factsOf(state: FamilyState, viewerId: string): NoteFacts | null {
  const s = state.suggestion;
  const viewer = state.members.find((m) => m.id === viewerId);
  if (!s || !viewer) return null;
  const at = new Date(s.start);
  const last = state.lastChange;
  const lastName = last ? state.members.find((m) => m.id === last.memberId)?.name : null;
  return {
    viewer: viewer.name,
    people: state.members.map((m) => ({
      name: m.name, localTime: fmtLocal(m.tz, at), pickupPercent: Math.round((s.pickup[m.id] ?? 0) * 100), isViewer: m.id === viewerId,
    })),
    everyoneLikely: s.everyoneLikely,
    latestSignal: last && lastName ? `${lastName} ${describeSignal(last.kind, last.positive)}` : null,
  };
}

function describeSignal(kind: string, positive: boolean): string {
  if (kind === 'call') return positive ? 'just picked up a call' : 'just missed a call';
  if (kind === 'text') return positive ? 'just replied to a text quickly' : 'did not reply to a text';
  return positive ? 'just marked themselves free' : 'just marked themselves busy';
}

export function templateNote(f: NoteFacts): string {
  const others = f.people.filter((p) => !p.isViewer);
  const me = f.people.find((p) => p.isViewer);
  const weakest = [...f.people].sort((a, b) => a.pickupPercent - b.pickupPercent)[0];
  const times = others.map((p) => `${p.localTime.split(' ').slice(1).join(' ')} for ${p.name}`).join(', ');
  const head = me ? `${me.localTime.split(' ').slice(1).join(' ')} for you, ${times}.` : `${times}.`;
  if (f.everyoneLikely) return `${head} Everyone usually picks up then.`;
  return `${head} Best overlap today; ${weakest.isViewer ? 'you are' : `${weakest.name} is`} the stretch at ${weakest.pickupPercent}%.`;
}

const CLAUDE_TIMEOUT_MS = 4000;
const CLAUDE_MODEL = 'claude-haiku-5-5';

/** Calls the Messages API directly (no SDK in the edge bundle). Only names, local times and percentages are sent. */
export function claudeWriter(apiKey: string, fetchFn: typeof fetch = fetch): NoteWriter {
  return {
    async write(f) {
      const ctl = new AbortController();
      const timer = setTimeout(() => ctl.abort(), CLAUDE_TIMEOUT_MS);
      try {
        const res = await fetchFn('https://api.anthropic.com/v1/messages', {
          method: 'POST', signal: ctl.signal,
          headers: { 'x-api-key': apiKey, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
          body: JSON.stringify({
            model: CLAUDE_MODEL, max_tokens: 120,
            system: 'You write the one-sentence note under a suggested family call time in a phone widget. ' +
              'Warm, specific, under 25 words, no emoji, no greeting. Mention local times and who is the stretch, ' +
              'or the latest signal if it explains the choice. Address the viewer as "you".',
            messages: [{ role: 'user', content: JSON.stringify(f) }],
          }),
        });
        if (!res.ok) throw new Error(`claude ${res.status}`);
        const body = await res.json() as { content?: { type: string; text?: string }[] };
        const text = body.content?.find((c) => c.type === 'text')?.text?.trim();
        if (!text) throw new Error('claude returned no text');
        return text;
      } finally {
        clearTimeout(timer);
      }
    },
  };
}
