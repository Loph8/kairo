/** Release state and public destinations. Everything the primary CTA can point at lives here. */
export const REPO_URL = 'https://github.com/Loph8/kairo'

export interface Cta {
  label: string
  href: string
  external: boolean
}

/**
 * Picks the primary CTA from what actually exists.
 * App Store / TestFlight only when a URL is configured at build time (see .env.example).
 * The waitlist CTA appears only when the Node server (server/index.mjs) served the page, because only
 * then does /api/waitlist exist. Otherwise: the in-page demo.
 */
type Runtime = { __KAIRO__?: { waitlist?: boolean } }
/** True when the page was served by server/index.mjs, which provides the waitlist API. */
export const waitlistEnabled = (rt: Runtime = globalThis as Runtime) => rt.__KAIRO__?.waitlist === true

export function primaryCta(env: Record<string, string | undefined> = import.meta.env, waitlist = waitlistEnabled()): Cta {
  const store = env.VITE_APP_STORE_URL?.trim()
  if (store) return { label: 'Download on the App Store', href: store, external: true }
  const tf = env.VITE_TESTFLIGHT_URL?.trim()
  if (tf) return { label: 'Join the TestFlight', href: tf, external: true }
  if (waitlist) return { label: 'Join the waitlist', href: '#waitlist', external: false }
  return { label: 'Try the demo', href: '#demo', external: false }
}
