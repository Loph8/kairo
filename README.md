# Golden Hour

A family's own call and text channel. It learns when each person actually picks up, then books
family calls at times that work across time zones. It only knows *when* you talk, never *what* you say.

## How the schedule learns (`supabase/functions/_shared/`)

1. **Preliminary schedule → prior.** Onboarding asks for wake time, bed time and busy hours
   (`prelimGrid`). Each half-hour of a weekday or weekend becomes a Beta prior (`createLearner`):
   free ≈ 75% pickup, maybe ≈ 50%, busy/asleep ≈ 12%. The prior has a weight of 2 calls, so real
   behaviour overrides it quickly.
2. **Every channel event is a reward.** Answered call = 1, missed = 0, text reply within 10 min = 1,
   within an hour = 0.5, no reply = 0, a widget tap ("I'm free"/"busy") = a strong label (`reward`, `observe`).
   Old evidence fades with a 28-day half-life, so the schedule follows life changes.
3. **Agents analyze.** `findInsights` finds slots where what someone typed disagrees with how they
   actually answer ("Grandpa said weekdays 9 AM is busy, but he picks up 9 of 10 times"). Each
   person's agent explains it in plain words and asks them to accept the update (`acceptInsight`).
4. **Optimizer picks the family call.** `optimizePick` maximizes the chance *everyone* picks up for
   the whole 45-minute call, minus a fairness cost that rotates the inconvenient hour (ledger), and
   never rings anyone whose pickup chance is under 20%.
5. **Careful exploration.** `carefulPick` is Thompson sampling restricted to slots already within
   ~1.5× of the best. It re-tests close runners-up without gambling a family call on a long shot.
   Each call's outcome feeds back into step 2.

## Does it work? `bun sim/learning_sim.ts --seeds 30`

Each person's real rhythm differs from what they typed. The metric is the chance all four pick up for the whole call (30 seeds, 8 weeks).

| Scheduler | Week 1 | Week 2+ | Calls/week ringing someone asleep or busy |
|---|---|---|---|
| Typed schedule only (no learning) | 29% | 29% | 0 |
| Plain Thompson sampling | 27% | 31-34% | ~1 in week 1 |
| **Careful Thompson (ours)** | 31% | **34-36%** | 0 |
| Oracle (knows the truth) | 36% | 36% | 0 |

When Dad's meetings start running to 3:30 PM in week 5, the typed schedule drops to 14-24% and rings
him in meetings 1-3 times a week. The learning schedulers recover within the first week (33-35%).

The ceiling is 36% because with these four lives no half-hour is green for everyone. Learning gets
within about 1 point of that ceiling by week 2. Plain greedy learning does about as well as careful
Thompson here; careful exploration is a hedge for slower or noisier changes. Plain Thompson explores
too much: a family call is an expensive experiment.

## Tests

`bun test`: priors, rewards, decay, the seeded demo history (learned levels match the truth in every
cell for all four people), the demo pick (Tue 7 AM Durham / 9 PM Seoul / 3 PM Addis), the insights,
and a check that exploration never rings anyone in a known-asleep slot.
