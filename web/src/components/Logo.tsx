/**
 * The current app icon (ios/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png): the widget's clock in a
 * night sky with the golden window lit. Resized copies live in /public. The wordmark is plain text.
 */
export function Logo({ size = 32 }: { size?: number }) {
  return (
    <img src={`${import.meta.env.BASE_URL}icon-192.png`} width={size} height={size} alt="" className="logo" style={{ borderRadius: size * 0.2237 }} />
  )
}

export function Wordmark() {
  return (
    <span className="wordmark">
      <Logo />
      <span>Kairo</span>
    </span>
  )
}
