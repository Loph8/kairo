// Where what someone said differs from what the channel shows. The agents narrate these; the person approves.
import { CELLS, learnedLevel, adoptLevels, type Learner, type Level } from './learning.ts';
import { SLOTS_PER_DAY, fmtSlot, type DayKind } from './time.ts';

export const MIN_EVIDENCE = 3;

export interface Insight {
  readonly memberId: string;
  readonly dayKind: DayKind;
  readonly fromSlot: number;
  readonly toSlot: number; // exclusive
  readonly said: Level;
  readonly learned: Level;
  readonly hits: number;
  readonly seen: number;
  readonly cells: readonly number[];
  readonly text: string;
}

const WORD: Record<Level, string> = { G: 'free', Y: 'maybe', R: 'busy' };

function describe(name: string, kind: DayKind, from: number, to: number, said: Level, learned: Level, hits: number, seen: number): string {
  const when = `${kind === 'weekday' ? 'weekdays' : 'weekends'} ${fmtSlot(from)}–${fmtSlot(to % SLOTS_PER_DAY)}`;
  const better = learned === 'G' || (learned === 'Y' && said === 'R');
  return better
    ? `${name} said ${when} is ${WORD[said]}, but picked up ${hits} of ${seen} times. Suggest: ${WORD[learned]}.`
    : `${name} said ${when} is ${WORD[said]}, but picked up only ${hits} of ${seen} times. Suggest: ${WORD[learned]}.`;
}

export function findInsights(memberId: string, name: string, learner: Learner, now: Date): Insight[] {
  const out: Insight[] = [];
  let run: number[] = [];
  const flush = () => {
    if (!run.length) return;
    const first = run[0];
    const said = learner.prelim[first];
    const learned = learnedLevel(learner, first, now);
    const hits = run.reduce((s, c) => s + learner.hits[c], 0);
    const seen = run.reduce((s, c) => s + learner.seen[c], 0);
    const kind: DayKind = first < SLOTS_PER_DAY ? 'weekday' : 'weekend';
    const from = first % SLOTS_PER_DAY;
    const to = from + run.length;
    if (seen >= MIN_EVIDENCE) {
      out.push({ memberId, dayKind: kind, fromSlot: from, toSlot: to, said, learned, hits, seen, cells: run,
        text: describe(name, kind, from, to, said, learned, hits, seen) });
    }
    run = [];
  };
  for (let c = 0; c < CELLS; c++) {
    const differs = learner.prelim[c] !== learnedLevel(learner, c, now);
    const continues = run.length > 0 && c % SLOTS_PER_DAY !== 0 &&
      learner.prelim[c] === learner.prelim[run[0]] &&
      learnedLevel(learner, c, now) === learnedLevel(learner, run[0], now);
    if (!differs || !continues) flush();
    if (differs) run.push(c);
  }
  flush();
  return out.sort((a, b) => b.seen - a.seen);
}

export function acceptInsight(learner: Learner, insight: Insight): Learner {
  return adoptLevels(learner, insight.cells, insight.learned);
}
