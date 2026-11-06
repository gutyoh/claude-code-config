// Pure forecast math for the 5h and 7d plan limits. No `$` here: tests call it directly.

export type Kind = 'five_hour' | 'seven_day'
export const KINDS: readonly Kind[] = ['five_hour', 'seven_day']

/** [epoch ms, percent used] */
export type Sample = [number, number]
export type Track = { resetsAt: number; samples: Sample[] }

const MIN = 60_000
const HOUR = 60 * MIN
const DAY = 24 * HOUR

export const WINDOW_MS: Record<Kind, number> = { five_hour: 5 * HOUR, seven_day: 7 * DAY }
// 5h only: the slow and fast lookbacks that must both be burning (Google SRE multiwindow).
const SLOW_MS = 45 * MIN
const FAST_MS = 15 * MIN
// The whole-window average counts once this much has passed, or once usage is >= 25%.
const MIN_ELAPSED_MS: Record<Kind, number> = { five_hour: 15 * MIN, seven_day: 6 * HOUR }
// Running out sooner than this is red; later (but before the reset) is orange.
const URGENT_MS: Record<Kind, number> = { five_hour: 30 * MIN, seven_day: 12 * HOUR }
// The service reports resets_at with jitter; closer than this is the same window.
const JITTER_MS = 5 * MIN
const MAX_SAMPLES = 600

/** 0 idle (<25) · 1 notice (25-49) · 2 half (50-74) · 3 slow down (75-89) · 4 stop (90+) */
export type Level = 0 | 1 | 2 | 3 | 4
export function levelFor(pct: number): Level {
  if (pct >= 90) return 4
  if (pct >= 75) return 3
  if (pct >= 50) return 2
  if (pct >= 25) return 1
  return 0
}

export type Recorded = { track: Track; finished?: Track }

/** Adds one reading. A later resets_at starts a new window and hands back the finished one. */
export function record(track: Track | undefined, now: number, pct: number, resetsAt: number): Recorded {
  if (!track) return { track: { resetsAt, samples: [[now, pct]] } }
  if (resetsAt - track.resetsAt > JITTER_MS) {
    return { track: { resetsAt, samples: [[now, pct]] }, finished: track }
  }
  const samples = track.samples.filter(([t]) => t <= now)
  const last = samples[samples.length - 1]
  // Usage never falls inside one window; a drop means the window restarted early.
  if (last && pct < last[1] - 0.5) return { track: { resetsAt, samples: [[now, pct]] }, finished: track }
  if (last && last[1] === pct && now - last[0] < 10 * MIN) return { track: { ...track, resetsAt } }
  samples.push([now, pct])
  return { track: { resetsAt, samples: samples.slice(-MAX_SAMPLES) } }
}

/** Usage at time t: 0 at the window's start, linear between readings, flat after the last one. */
export function pctAt(track: Track, kind: Kind, t: number): number {
  const start = track.resetsAt - WINDOW_MS[kind]
  if (t <= start) return 0
  let prev: Sample = [start, 0]
  for (const s of track.samples) {
    if (s[0] < start) continue
    if (t <= s[0]) {
      const span = s[0] - prev[0]
      return span <= 0 ? s[1] : prev[1] + ((s[1] - prev[1]) * (t - prev[0])) / span
    }
    prev = s
  }
  return prev[1]
}

export type State = 'exhausted' | 'early' | 'idle' | 'ok' | 'hits'
export type Forecast = {
  kind: Kind
  pct: number
  resetInMs: number
  state: State
  /** Percent per ms the forecast uses (5h: slower of last 15 and 45 min; 7d: window average). */
  rate?: number
  /** Average rate against an even spread over the window: 1 = on pace. */
  pace?: number
  fullInMs?: number
  /** Where usage lands at the reset at this rate, capped at 100. */
  atReset?: number
  level: Level
  /** The finished window's usage at this same point of it (weekly "vs last week"). */
  lastTime?: number
}

export function forecast(kind: Kind, track: Track, now: number, previous?: Track): Forecast {
  const win = WINDOW_MS[kind]
  const start = track.resetsAt - win
  const elapsed = Math.max(0, Math.min(win, now - start))
  const pct = track.samples[track.samples.length - 1]?.[1] ?? 0
  const resetInMs = Math.max(0, track.resetsAt - now)
  const base: Forecast = { kind, pct, resetInMs, state: 'early', level: levelFor(pct) }

  if (previous) {
    const prevStart = previous.resetsAt - win
    base.lastTime = Math.round(pctAt(previous, kind, prevStart + elapsed))
  }
  if (pct >= 100) return { ...base, state: 'exhausted', level: 4, fullInMs: 0, atReset: 100 }

  const avg = elapsed >= MIN_ELAPSED_MS[kind] || pct >= 25 ? pct / Math.max(elapsed, MIN) : undefined
  let rate = avg
  if (kind === 'five_hour') {
    const slow = windowRate(kind, track, now, SLOW_MS)
    const fast = windowRate(kind, track, now, FAST_MS)
    if (slow !== undefined && fast !== undefined) rate = Math.min(slow, fast)
  }
  if (rate === undefined) return base
  const pace = avg === undefined ? undefined : (avg * win) / 100
  if (rate <= 0) return { ...base, state: 'idle', rate: 0, pace, atReset: pct }

  const fullInMs = (100 - pct) / rate
  const atReset = Math.min(100, pct + rate * resetInMs)
  const hits = fullInMs < resetInMs
  const projected: Level = hits ? (fullInMs <= URGENT_MS[kind] ? 4 : 3) : 0
  const level = Math.max(base.level, projected) as Level
  return { ...base, state: hits ? 'hits' : 'ok', rate, pace, fullInMs, atReset, level }
}

/** Percent per ms over the last `lookback`, ending now; undefined without history that far back. */
export function windowRate(kind: Kind, track: Track, now: number, lookback: number): number | undefined {
  const start = track.resetsAt - WINDOW_MS[kind]
  const first = track.samples.find(([t]) => t >= start)
  if (!first) return undefined
  let from = now - lookback
  if (from <= start) {
    // The window began inside the lookback: usage was 0 at its start.
    from = start
    if (now - start < lookback / 3) return undefined
  } else if (first[0] > from) {
    return undefined
  }
  return Math.max(0, (pctAt(track, kind, now) - pctAt(track, kind, from)) / (now - from))
}

export function fmtDur(ms: number): string {
  const m = Math.max(0, Math.round(ms / MIN))
  if (m < 60) return `${m}m`
  const h = Math.floor(m / 60)
  if (h < 24) return m % 60 ? `${h}h${m % 60}m` : `${h}h`
  const d = Math.floor(h / 24)
  return h % 24 ? `${d}d${h % 24}h` : `${d}d`
}

/** One line per window that needs attention; empty when everything is calm. */
export function warning(f: Forecast): string | undefined {
  const name = f.kind === 'five_hour' ? 'Session' : 'Week'
  if (f.state === 'exhausted') return `${name} limit reached · resets in ${fmtDur(f.resetInMs)}`
  if (f.state === 'hits' && f.fullInMs !== undefined) {
    return `${name} ${Math.round(f.pct)}% · full in ${fmtDur(f.fullInMs)}, resets in ${fmtDur(f.resetInMs)}`
  }
  return undefined
}

const BLOCKS = ' ▁▂▃▄▅▆▇█'
export type Cell = { ch: string; level: Level; isFuture: boolean }

/** The window as `cells` time slots: real usage up to now, the projection (dim) after it. */
export function curve(f: Forecast, track: Track, now: number, cells: number): Cell[] {
  const win = WINDOW_MS[f.kind]
  const start = track.resetsAt - win
  const out: Cell[] = []
  for (let i = 0; i < cells; i++) {
    const t = start + ((i + 1) * win) / cells
    const isFuture = t > now
    const v = isFuture
      ? Math.min(100, f.pct + (f.rate ?? 0) * (t - now))
      : pctAt(track, f.kind, t)
    const idx = Math.max(v > 0 ? 1 : 0, Math.min(8, Math.round((v / 100) * 8)))
    out.push({ ch: BLOCKS[idx] ?? ' ', level: levelFor(v), isFuture })
  }
  return out
}
