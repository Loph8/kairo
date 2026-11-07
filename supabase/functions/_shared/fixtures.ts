// Demo fixtures: each member's learner after two weeks of seeded channel history.
import { DEMO_ANCHOR, FAMILY, TRUTH_BANDS, type Member } from './family.ts';
import { createLearner, observeAll, type Learner } from './learning.ts';
import { seedObservations } from './seed.ts';
import type { Person } from './explore.ts';

const SEED_START_OFFSET_MS = 15 * 24 * 60 * 60 * 1000;

export function seededLearner(member: Member, anchor: Date = DEMO_ANCHOR): Learner {
  const start = new Date(anchor.getTime() - SEED_START_OFFSET_MS);
  const fresh = createLearner(member.onboarding, start);
  return observeAll(fresh, member.tz, seedObservations(member, TRUTH_BANDS[member.id], anchor));
}

export function seededFamily(anchor: Date = DEMO_ANCHOR): Person[] {
  return FAMILY.map((m) => ({ id: m.id, tz: m.tz, learner: seededLearner(m, anchor) }));
}

export function onboardingOnlyFamily(anchor: Date = DEMO_ANCHOR): Person[] {
  return FAMILY.map((m) => ({ id: m.id, tz: m.tz, learner: createLearner(m.onboarding, anchor) }));
}
