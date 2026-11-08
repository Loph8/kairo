/**
 * The app's deterministic star field (ios/Widget/SyncClockWidget.swift NightSkyBackground):
 * 38 stars from a fixed 64-bit LCG seeded with 11, so every load looks the same.
 */
const stars = (() => {
  let seed = 11n
  const MASK = (1n << 64n) - 1n
  const rnd = () => {
    seed = (seed * 6364136223846793005n + 1442695040888963407n) & MASK
    return Number(seed >> 33n) / 2 ** 31
  }
  return Array.from({ length: 38 }, () => {
    const s = rnd()
    return { x: rnd() * 100, y: rnd() * 100, r: s < 0.15 ? 1.3 : s < 0.5 ? 0.8 : 0.5, o: 0.25 + rnd() * 0.6 }
  })
})()

export function Starfield() {
  return (
    <svg className="starfield" aria-hidden focusable="false">
      {stars.map((s, i) => (
        <circle key={i} cx={`${s.x}%`} cy={`${s.y}%`} r={s.r} fill="#f8f9f4" opacity={s.o} />
      ))}
    </svg>
  )
}
