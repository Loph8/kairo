# Architecture notes

## Data flow
`LocalDemoRepository` (locked read-modify-write on `state.json` in the App Group) → after every mutation it writes `snapshot.json` atomically → widgets read only that snapshot. App Intents in the widget process use the same repository and file lock, so repeated taps and simultaneous confirmations serialize.

All displayed times derive from one injected instant (`TimeSource` + demo `clockOffset`). Instants are UTC `Date`s; preferences (quiet hours, busy windows) are minutes in the person's own IANA zone; local views come from Foundation `Calendar`. Nonexistent local times move forward, repeated ones resolve to the first occurrence (`TimeKit.resolve`, tested for New York 2026).

## Availability model (on device)
30-minute slots over a local week (336). For each slot:

```
score = (k·prior + E⁺) / (k + E⁺ + E⁻)          k = 2
E±    = Σ |w(event)| · 0.5^(age_days / 10)        spread: same slot ×1, adjacent slots ×0.5,
                                                  same slot on same-type days ×0.35
confidence = min(1, (E⁺+E⁻) / 4)
```
Prior: 0 in quiet hours, 0.15 in stated busy windows, else 0.5. Weights: answered call +1.0 (+1.2 if ≥5 min), callback +0.8/+0.4, fast reply +0.7/+0.4/+0.15, first/last activity +0.2, **missed call −0.25 (deliberately weak)**, declined −0.5, self-reported connected +0.6 / not −0.15.
Precedence: explicit Busy > quiet hours > stated busy window > learned > Learning. Below 0.25 confidence the state is **Learning**, never a guess.

**Limits.** Weights and thresholds (0.62 likely, 0.38 maybe) are hand-set heuristics, not fitted. Scores rank slots; they are not calibrated probabilities. Silence is ambiguous, so quiet hours say "Quiet hours" (a preference), never "asleep". Pooling by weekday/weekend assumes routine. Half-hour UTC steps approximate zones with 45-minute offsets.

## Scheduling
Filter hard constraints (quiet hours, Busy overrides, busy windows, existing bookings), then
`fit(p) = meanScore × (1 − 0.35·inconvenience)`, `total = 0.5·mean(fit) + 0.5·min(fit) − 0.3·fairnessPenalty`,
`fairnessPenalty = mean_p(burdenLoad(p)·inconvenience(p))`. Burden memory: last 10 inconvenient confirmed calls per person, half-life 14 days. Top three with ≥2 h separation, presented by absolute instant. All weights live in `SchedulingConfig`. The LLM only calls tools and writes short explanations; it can't change a window or override constraints.

## What is shared (production design)
Per slot: coarse level, a low/medium/high evidence bucket, validity period; plus explicit restrictions (quiet hours) needed to schedule. **Numeric scores and raw events stay on the device.** Even coarse levels reveal a person's rhythm to family; that's the minimum scheduling needs. If a future optimizer needs numeric scores, that is a bigger disclosure and should be opt-in.

Provider caveats: an in-app calling/messaging provider may process transport metadata; the availability model receives metadata only. An SMS bridge (e.g. Twilio) would process message content, is not end-to-end encrypted, offers only limited reply metadata, and "delivered" doesn't mean "read". Non-app participants would need a separate explicit confirmation flow.

## Widget and Live Activity constraints
- Timelines are system-scheduled, best effort; entries here are 30 minutes apart plus proposal start times.
- Interactive controls are App Intent buttons; widgets can't run arbitrary gestures or continuous code.
- Activities need a foreground app (or push-to-start) to begin, last at most ~8 hours, so start only near the call; use a local notification for far-out calls. ActivityKit push ≠ VoIP push; CallKit does not transport audio.
- Focus status, if ever added, is an optional permission-gated hint (no Focus names or reasons).

## Backend (proposed)
`supabase/migrations/0001_kairo.sql`: RLS on every table; no direct writes to proposals; `create/confirm/decline/cancel_proposal` are `SECURITY DEFINER`, derive the actor from `auth.uid()`, lock the row (`FOR UPDATE`), are idempotent, and check expiry. `proposals.id` is deterministic and unique, one Busy row per person. `supabase/functions/agent` uses only the caller's JWT, offers Claude read/rank/create tools (never confirm/decline), validates every argument, sends only scheduling facts, and falls back to deterministic ranking when the API fails.
