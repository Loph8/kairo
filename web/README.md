# Kairo website

Single-page marketing site for Kairo. Isolated from the iOS app: Vite + React + TypeScript, no backend, no analytics, no cookies, no external requests (the font is self-hosted).

```bash
cd web
npm install
npm run dev        # http://localhost:5173
npm run build      # typecheck + production build into dist/
npm test           # demo logic: time zones, best-time scoring, demo reducer, CTA selection
npm run lint
```

## Full-stack mode (server-rendered HTML + waitlist API)
```bash
npm install
npm run build:all   # client bundle (dist/) + server-render bundle (dist-server/)
npm start           # http://127.0.0.1:3000  (PORT, HOST env vars)
```
`server/index.mjs` is a dependency-free Node server (no Express):
- `GET /` returns the full page as **server-rendered HTML** (readable without JavaScript); the React client then takes over for the interactive demo.
- Static files from `dist/` with hashed-asset caching, path-traversal protection, and security headers (CSP, nosniff, no-referrer, frame-deny).
- `POST /api/waitlist` `{ email }`: validates the address, drops honeypot hits, rate-limits to 5 requests/minute per IP (kept in memory only), checks same-origin, caps the body at 2 KB, and appends `{ email, at }` to `data/waitlist.jsonl` (git-ignored, file mode 600). No IP, user agent or analytics is stored. Duplicates get the same reply as new addresses.
- `GET /api/health`.

The waitlist CTA and form appear **only** when the page is served by this server (it injects `window.__KAIRO__ = { waitlist: true }`). With plain `npm run dev` or a static host the site falls back to "Try the demo", so no form ever pretends to save anything.

Config: `WAITLIST_FILE` (default `data/waitlist.jsonl`), `TRUST_PROXY=1` when behind a reverse proxy that sets `X-Forwarded-For`. Count signups with `npm run waitlist:count`.

Before going public: put it behind HTTPS (a reverse proxy or host), back up `data/`, and add a real privacy notice and a way to remove an address; the page only states what the code does and is not a legal policy. The server does not send email.

## Release state and CTAs
No App Store or TestFlight URL exists in the repository. The primary CTA is **Join the waitlist** when served by the Node server, otherwise **Try the demo** (`#demo`). Set `VITE_APP_STORE_URL` or `VITE_TESTFLIGHT_URL` (see `.env.example`) and it switches automatically (`src/lib/site.ts`).
`VITE_SITE_URL` adds canonical, `og:url` and absolute `og:image` / Twitter tags at build time. It is unset, so they are omitted rather than guessing a domain.

## Source of truth
The current app lives on the repository's **`golden-hour`** branch (`ios/`, `supabase/`). `main` holds an older iOS prototype. The site was derived from `golden-hour` plus three screenshots of the running app. Screenshot details (real name, email, family name and invite code) are **not** used anywhere: the demo family, email and the code `SAMPLE` are made up.

### Design tokens (exact values from source, `src/styles/tokens.css`)
| Trait | Source |
|---|---|
| Palette: sky-deep 241C33, card 382C4F, amethyst 51416E, gold F5E6A3, lavender C8BADD, text F8F9F4, text-soft C5C1B8, rose E89AAE, neutral 8E82A8, night 2A2140 | `ios/Shared/Theme.swift` (`enum GH`) |
| Member colors (gold, lavender, rose, moon blue) | `MemberPalette` in `Theme.swift` |
| Night-sky background (diagonal gradient + lavender nebulas) and the 38-star field (same LCG, seed 11) | `ios/Widget/SyncClockWidget.swift` (`NightSkyBackground`) |
| Font: Sulphur Point Light/Regular/Bold (SIL OFL, files and licence in `public/fonts/`) | `Night.font` in `SyncClockWidget.swift`, `ios/Widget/Fonts/` |
| Glass cards radius 26 (insights card 24, chips 22), hairline white .28→.04, capsule buttons, gold primary with night text | `ios/App/Views/Glass.swift` |
| Pick-up levels: "Likely free" (gold), "Maybe" (lavender), "Unlikely" (amethyst), each with symbol + word | `Pickup` in `Glass.swift` |
| 24-hour dial, 48-cell lanes, "Now / +12h / +24h", step list, "Best time to call" | `ios/App/Views/InsightsView.swift`, `AgentCard.swift`, `FamilyView.swift` |
| Logo: current app icon, resized (`public/icon-*.png`) | `ios/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png` |

### Feature-to-source map
| Website claim | Evidence |
|---|---|
| Family with a shareable invite code; others download, sign in, tap Join | `FamilyView.swift` ("Bring your family in", ShareLink), `SignInView.swift` (email + one-time code) |
| "I'm free / I'm busy" check-ins are a learning signal | `FamilyView.swift`, `AppModel.markFree/markBusy` → `logLabel`; root `README.md` ("a strong label") |
| Calendar busy times: read via iOS calendars; last 4 weeks learned from, next 4 days avoided; sync on demand | `CalendarSync.swift` (EventKit), `CalendarBusy.swift` (`lookback` 28 days, `lookahead` 4 days), `SettingsView.swift` |
| Only start/end, anonymous ID and a "movable" flag leave the phone; all-day, "free" and declined events dropped | `CalendarBusy.swift` (`BusyBlockPayload`, `blocks(from:in:)`) |
| Clear history removes calendar blocks | `SettingsView.swift` ("Removes calls, calendar blocks, …") |
| Suggested 45-minute window across time zones, nobody "Unlikely" | `supabase/functions/_shared/schedule.ts` (`CALL_MINUTES = 45`, `NEVER_RING_BELOW = 0.2`), `AgentCard.swift` |
| It is a learning scheduler, not an LLM | no LLM references anywhere in `golden-hour`; Beta priors + Thompson sampling in `learning.ts` / `README.md` |
| Call opens the chosen calling app; afterwards "Did they pick up?" | `CallApps.swift`, `RootView.swift` |
| "Times, not content" | `SettingsView.swift`, `InsightsView.swift` |

## Deliberately omitted (not verified, or not the focus)
In-app messaging and text-reply timing, SMS/Twilio, end-to-end encryption claims, two-person booking confirmation, automatic call scheduling or dialing, widgets, Live Activities, Focus status, separate negotiating agents, "move your event" suggestions. A fairness cost *does* exist in `schedule.ts`; it is left out of the copy rather than over-explained.

## Unresolved claims (kept narrow in the copy)
- What family members can see of calendar data beyond availability estimates, and how long the server keeps busy blocks: not audited.
- `GoogleCalendar.swift` implements an optional direct Google Calendar (free/busy) sign-in, but it only appears when a client ID is configured and Settings points users to iOS calendar accounts, so the site doesn't mention it.
- The app is dark-only; `iOS 26` glass vs earlier material both exist. The site approximates the earlier look.

## Deviations and approximations
- The demo's best-time picker (`src/lib/demo.ts`) is a tiny stand-in using the same levels and 45-minute call length, not the app's scheduler. The Insights steps are labelled illustrative.
- The heading is "Kairo insights", not "Kairo AI": the app's scheduler isn't an LLM, so the site avoids the AI label.
- Screenshot sizes/spacing are approximations; glass blur is kept light and the hairline is a flat-colour approximation of the gradient border.
- Sulphur Point ships as TTF (no woff2 conversion tooling was used).
