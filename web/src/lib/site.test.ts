import { describe, expect, it } from 'vitest'
import { primaryCta } from './site'

describe('primaryCta', () => {
  it('defaults to the in-page demo when nothing is released', () => {
    expect(primaryCta({})).toEqual({ label: 'Try the demo', href: '#demo', external: false })
  })
  it('offers the waitlist only when the server provides it', () => {
    expect(primaryCta({}, true)).toEqual({ label: 'Join the waitlist', href: '#waitlist', external: false })
    expect(primaryCta({ VITE_APP_STORE_URL: 'https://apps.apple.com/x' }, true).label).toBe('Download on the App Store')
  })
  it('prefers a configured App Store URL, then TestFlight', () => {
    expect(primaryCta({ VITE_APP_STORE_URL: 'https://apps.apple.com/x', VITE_TESTFLIGHT_URL: 'https://testflight.apple.com/y' }).label).toBe('Download on the App Store')
    expect(primaryCta({ VITE_TESTFLIGHT_URL: 'https://testflight.apple.com/y' }).label).toBe('Join the TestFlight')
    expect(primaryCta({ VITE_APP_STORE_URL: '  ' }).href).toBe('#demo')
  })
})
