// Directory + per-family Db backed by Postgres through supabase-js (service role).
// Every query is scoped by family_id; rows ↔ domain types live here only.
import type { SupabaseClient } from 'npm:@supabase/supabase-js@2.119.0';
import type { Db, Directory, Membership } from '../_shared/api.ts';
import type { BusyBlock } from '../_shared/calendar.ts';
import { NO_CONTACT, type BookingRow, type Contact, type MemberRow, type StoredObservation } from '../_shared/familyState.ts';
import type { Level, Outcome } from '../_shared/learning.ts';
import type { Ledger } from '../_shared/schedule.ts';

const OBSERVATION_LOOKBACK_DAYS = 60;   // older outcomes have decayed to almost nothing (28-day half-life)
const INSERT_CHUNK = 500;
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';   // no I, O, 0, 1
const CODE_ATTEMPTS = 5;

type Row = Record<string, unknown>;
function must<T>(res: { data: T | null; error: { message: string; code?: string } | null }, what: string): T {
  if (res.error) throw new Error(`${what}: ${res.error.message}`);
  return res.data as T;
}

export function inviteCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(6));
  return [...bytes].map((b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join('');
}

const toBooking = (r: Row): BookingRow => ({
  id: String(r.id), start: new Date(String(r.slot_utc)), durationMin: Number(r.duration_min),
  acceptedBy: (r.accepted_by as string[]) ?? [], status: r.status as BookingRow['status'],
  levels: (r.levels as Record<string, Level>) ?? {},
});

function toOutcome(r: Row): Outcome {
  if (r.kind === 'call') return { kind: 'call', answered: Boolean(r.answered) };
  if (r.kind === 'label') return { kind: 'label', free: Boolean(r.free) };
  return { kind: 'text', replySeconds: r.reply_seconds === null ? null : Number(r.reply_seconds) };
}

export class SupabaseDirectory implements Directory {
  constructor(private readonly sb: SupabaseClient) {}

  async memberships(userId: string): Promise<Membership[]> {
    const rows = must(await this.sb.from('members').select('id, family_id, families(name, invite_code, call_link, call_started_at, call_started_by)')
      .eq('user_id', userId).order('created_at'), 'memberships') as Row[];
    return rows.map((r) => {
      const f = r.families as Row;
      return { familyId: String(r.family_id), familyName: String(f.name), inviteCode: String(f.invite_code),
        callLink: f.call_link == null ? null : String(f.call_link), memberId: String(r.id),
        groupCall: f.call_started_at == null ? null : { startedBy: String(f.call_started_by), at: new Date(String(f.call_started_at)).toISOString() } };
    });
  }

  async setCallLink(familyId: string, link: string | null) {
    must(await this.sb.from('families').update({ call_link: link }).eq('id', familyId), 'set call link');
  }
  async startGroupCall(familyId: string, memberId: string, at: Date) {
    must(await this.sb.from('families').update({ call_started_at: at.toISOString(), call_started_by: memberId }).eq('id', familyId), 'start group call');
  }


  async setContact(userId: string, contact: Contact) {
    must(await this.sb.from('members').update({ contact }).eq('user_id', userId), 'set contact');
  }

  async createFamily(name: string) {
    for (let i = 0; i < CODE_ATTEMPTS; i++) {
      const code = inviteCode();
      const res = await this.sb.from('families').insert({ name, invite_code: code }).select('id').single();
      if (res.error?.code === '23505') continue;     // code collision: try another
      return { familyId: String(must(res, 'create family').id), inviteCode: code };
    }
    throw new Error('could not find a free invite code');
  }

  async familyByCode(code: string) {
    const r = must(await this.sb.from('families').select('id, name, members(count)').eq('invite_code', code).maybeSingle(), 'family by code') as Row | null;
    if (!r) return null;
    const count = Number(((r.members as Row[] | undefined)?.[0]?.count) ?? 0);
    return { familyId: String(r.id), familyName: String(r.name), memberCount: count };
  }

  family(familyId: string): Db { return new SupabaseFamily(this.sb, familyId); }

  async leaveFamily(m: Membership) {
    // Observations and busy blocks go with the member row (on delete cascade).
    must(await this.sb.from('members').delete().eq('id', m.memberId).eq('family_id', m.familyId), 'leave family');
    // Open proposals counted this person; drop them so the rest of the family can book again.
    must(await this.sb.from('bookings').delete().eq('family_id', m.familyId).eq('status', 'proposed'), 'drop proposals');
    // head: true returns no rows, only the count, so read res.count (must() would hand back null).
    const left = await this.sb.from('members').select('id', { count: 'exact', head: true })
      .eq('family_id', m.familyId).eq('simulated', false);
    if (left.error) throw new Error(`count members: ${left.error.message}`);
    if (left.count === 0) {
      // Nobody real is left: delete the family. Demo relatives, bookings and notes cascade with it.
      must(await this.sb.from('families').delete().eq('id', m.familyId), 'delete empty family');
    }
  }
}

class SupabaseFamily implements Db {
  constructor(private readonly sb: SupabaseClient, private readonly fid: string) {}

  async load() {
    const since = new Date(Date.now() - OBSERVATION_LOOKBACK_DAYS * 86_400_000).toISOString();
    const [m, o, b, k] = await Promise.all([
      this.sb.from('members').select('*').eq('family_id', this.fid).order('created_at'),
      this.sb.from('observations').select('member_id, at, kind, answered, reply_seconds, free, source, historical')
        .eq('family_id', this.fid).gte('at', since).order('at').limit(20_000),
      this.sb.from('busy_blocks').select('*').eq('family_id', this.fid),
      this.sb.from('bookings').select('*').eq('family_id', this.fid).neq('status', 'completed'),
    ]);
    const members: MemberRow[] = must(m, 'members').map((r: Row) => ({
      id: String(r.id), name: String(r.name), city: String(r.city ?? ''), tz: String(r.tz),
      onboarding: r.onboarding as MemberRow['onboarding'], burdenMin: Number(r.burden_min),
      simulated: Boolean(r.simulated), persona: r.persona === null ? null : String(r.persona),
      contact: toContact(r.contact),
    }));
    const observations: StoredObservation[] = must(o, 'observations').map((r: Row) => ({
      memberId: String(r.member_id), at: new Date(String(r.at)), outcome: toOutcome(r),
      source: r.source as StoredObservation['source'], historical: Boolean(r.historical),
    }));
    const blocks: BusyBlock[] = must(b, 'busy_blocks').map((r: Row) => ({
      id: String(r.id), memberId: String(r.member_id), start: new Date(String(r.starts_at)),
      end: new Date(String(r.ends_at)), movable: Boolean(r.movable),
    }));
    return { members, observations, blocks, bookings: must(k, 'bookings').map(toBooking) };
  }

  async addMember(row: MemberRow & { userId: string | null }) {
    must(await this.sb.from('members').insert({
      id: row.id, family_id: this.fid, user_id: row.userId, simulated: row.simulated, persona: row.persona,
      name: row.name, city: row.city, tz: row.tz, onboarding: row.onboarding, burden_min: row.burdenMin,
      contact: row.contact ?? NO_CONTACT,
    }), 'add member');
  }

  async addObservations(rows: readonly StoredObservation[]) {
    const out = rows.map((o) => ({
      family_id: this.fid, member_id: o.memberId, at: o.at.toISOString(), kind: o.outcome.kind, source: o.source,
      historical: o.historical ?? false,
      answered: o.outcome.kind === 'call' ? o.outcome.answered : null,
      reply_seconds: o.outcome.kind === 'text' ? o.outcome.replySeconds : null,
      free: o.outcome.kind === 'label' ? o.outcome.free : null,
    }));
    for (let i = 0; i < out.length; i += INSERT_CHUNK) {
      must(await this.sb.from('observations').insert(out.slice(i, i + INSERT_CHUNK)), 'add observations');
    }
  }

  async replaceBusyBlocks(memberId: string, blocks: readonly BusyBlock[], from: Date) {
    must(await this.sb.from('busy_blocks').delete().eq('family_id', this.fid).eq('member_id', memberId)
      .gt('ends_at', from.toISOString()), 'clear busy blocks');
    if (!blocks.length) return;
    must(await this.sb.from('busy_blocks').upsert(blocks.map((b) => ({
      family_id: this.fid, member_id: b.memberId, id: b.id, starts_at: b.start.toISOString(), ends_at: b.end.toISOString(), movable: b.movable,
    })), { onConflict: 'member_id,id' }), 'insert busy blocks');
  }

  async dropBlocksBefore(cutoff: Date) {
    must(await this.sb.from('busy_blocks').delete().eq('family_id', this.fid).lt('ends_at', cutoff.toISOString()), 'drop old blocks');
  }

  async findOpenBooking(start: Date) {
    const r = must(await this.sb.from('bookings').select('*').eq('family_id', this.fid).eq('slot_utc', start.toISOString())
      .neq('status', 'completed').maybeSingle(), 'find booking');
    return r ? toBooking(r as Row) : null;
  }

  async createBooking(start: Date, levels: Record<string, Level>) {
    const res = await this.sb.from('bookings').insert({ family_id: this.fid, slot_utc: start.toISOString(), levels }).select().single();
    if (res.error?.code === '23505') {            // someone opened the same slot a moment ago: join theirs
      const existing = await this.findOpenBooking(start);
      if (existing) return existing;
    }
    return toBooking(must(res, 'create booking') as Row);
  }

  async acceptBooking(id: string, memberIds: readonly string[]) {
    return toBooking(must(await this.sb.rpc('accept_booking', { booking_id: id, member_ids: memberIds }).single(), 'accept booking') as Row);
  }

  async setBurden(ledger: Ledger) {
    await Promise.all(Object.entries(ledger).map(async ([id, min]) =>
      must(await this.sb.from('members').update({ burden_min: min }).eq('family_id', this.fid).eq('id', id), `burden ${id}`)));
  }

  async clearHistory() {
    for (const t of ['bookings', 'busy_blocks', 'observations', 'ai_notes'] as const) {
      must(await this.sb.from(t).delete().eq('family_id', this.fid), `clear ${t}`);
    }
    must(await this.sb.from('members').delete().eq('family_id', this.fid).eq('simulated', true), 'remove simulated');
    must(await this.sb.from('members').update({ burden_min: 0 }).eq('family_id', this.fid), 'zero burden');
  }

  async getNote(key: string) {
    const r = must(await this.sb.from('ai_notes').select('text').eq('family_id', this.fid).eq('key', key).maybeSingle(), 'get note') as Row | null;
    return r ? String(r.text) : null;
  }

  async putNote(key: string, text: string) {
    must(await this.sb.from('ai_notes').upsert({ family_id: this.fid, key, text }), 'put note');
  }
}

function toContact(v: unknown): Contact {
  const r = (v ?? {}) as { phone?: unknown; apps?: unknown };
  const apps = r.apps && typeof r.apps === 'object' ? r.apps as Contact['apps'] : {};
  return { phone: typeof r.phone === 'string' ? r.phone : null, apps };
}
