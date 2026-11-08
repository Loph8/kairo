import { PICKUP_LABEL, countOf, localDay, type Context, type Member, type Pickup, type Suggestion } from '../lib/demo'
import { formatRange } from '../lib/time'

const SIZE = 250
const RING = SIZE * 0.13
const R = SIZE / 2 - RING / 2 - 10
const C = SIZE / 2

const pt = (slot: number, r = R) => {
  const a = (slot / 48) * 2 * Math.PI - Math.PI / 2
  return { x: C + r * Math.cos(a), y: C + r * Math.sin(a) }
}

function arc(a: number, b: number): string {
  const s = pt(a)
  const e = pt(b)
  return `M ${s.x.toFixed(2)} ${s.y.toFixed(2)} A ${R} ${R} 0 ${b - a > 24 ? 1 : 0} 1 ${e.x.toFixed(2)} ${e.y.toFixed(2)}`
}

function runs(cells: Pickup[]) {
  const out: { a: number; b: number; level: Pickup }[] = []
  cells.forEach((c, i) => {
    const last = out[out.length - 1]
    if (last && last.level === c) last.b = i + 1
    else out.push({ a: i, b: i + 1, level: c })
  })
  return out
}

const STROKE: Record<Pickup, string> = { G: 'var(--gold)', Y: 'rgb(200 186 221 / 0.85)', R: 'rgb(81 65 110 / 0.8)' }
const LABELS: [number, string][] = [[0, '12a'], [12, '6a'], [24, '12p'], [36, '6p']]

interface Props {
  member: Member
  ctx: Context
  suggestion: Suggestion | null
}

/** A member's own local day as a 24-hour dial: midnight at the top, noon at the bottom. */
export function AvailabilityClock({ member, ctx, suggestion }: Props) {
  const { cells, nowSlot } = localDay(member, ctx)
  const now = cells[nowSlot]
  const hours = countOf(cells, 'G') / 2
  const dot = pt(nowSlot + 0.5)
  const bestLocal = suggestion ? formatRange(suggestion.start, suggestion.end, member.timeZone) : null
  const summary = `${member.name}'s day in ${member.city}: likely free about ${hours} hours, ${PICKUP_LABEL[now].toLowerCase()} right now.${bestLocal ? ` Suggested call: ${bestLocal} in ${member.city}.` : ''}`

  return (
    <div className="clock">
      <svg viewBox={`0 0 ${SIZE} ${SIZE}`} role="img" aria-label={summary} className="clock__svg">
        <defs>
          <filter id="gold-glow" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="4" /></filter>
        </defs>
        {(['R', 'Y'] as const).map((lvl) =>
          runs(cells).filter((r) => r.level === lvl).map((r) =>
            r.b - r.a === 48
              ? <circle key={`${lvl}${r.a}`} cx={C} cy={C} r={R} fill="none" stroke={STROKE[lvl]} strokeWidth={RING} />
              : <path key={`${lvl}${r.a}`} d={arc(r.a, r.b)} fill="none" stroke={STROKE[lvl]} strokeWidth={RING} />,
          ),
        )}
        {runs(cells).filter((r) => r.level === 'G').map((r) => (
          <g key={`G${r.a}`}>
            <path d={arc(r.a, r.b)} fill="none" stroke="var(--gold)" strokeWidth={RING} opacity="0.55" filter="url(#gold-glow)" />
            <path d={arc(r.a, r.b)} fill="none" stroke="var(--gold)" strokeWidth={RING} />
          </g>
        ))}
        {LABELS.map(([slot, text]) => {
          const p = pt(slot, R - RING / 2 - 14)
          return <text key={text} x={p.x} y={p.y} textAnchor="middle" dominantBaseline="middle" className="clock__tick">{text}</text>
        })}
        <circle cx={dot.x} cy={dot.y} r={RING * 0.4} fill="var(--text)" stroke="rgb(42 33 64 / 0.6)" strokeWidth="2" style={{ filter: 'drop-shadow(0 0 5px rgb(255 255 255 / 0.8))' }} />
        <text x={C} y={C - 12} textAnchor="middle" className="clock__tick">now</text>
        <text x={C} y={C + 12} textAnchor="middle" className={`clock__now clock__now--${now}`}>{PICKUP_LABEL[now]}</text>
      </svg>
      <p className="clock__summary soft">{summary}</p>
    </div>
  )
}
