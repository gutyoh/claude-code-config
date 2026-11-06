import { expect, test } from 'claude-code/testing'

import {
  curve,
  fmtDur,
  forecast,
  levelFor,
  pctAt,
  record,
  warning,
  windowRate,
  type Sample,
  type Track,
} from '../hooks/forecast'

const MIN = 60_000
const HOUR = 60 * MIN
const DAY = 24 * HOUR
const T0 = Date.UTC(2026, 10, 1, 21, 0) // a Sunday 4:00 PM EST: the weekly reset

/** A track whose readings rise in whole points, as the service reports them. */
function linear(resetsAt: number, from: number, to: number, t1: number, p1: number, t2: number, p2: number): Track {
  const samples: Sample[] = []
  for (let p = Math.ceil(p1); p <= p2; p++) {
    const t = t1 + ((t2 - t1) * (p - p1)) / Math.max(1e-9, p2 - p1)
    if (t >= from && t <= to) samples.push([Math.round(t), p])
  }
  return { resetsAt, samples }
}

test('levels follow the v2 bands 25 / 50 / 75 / 90', () => {
  const at = [0, 24, 24.9, 25, 49, 50, 74, 75, 89, 90, 100].map(levelFor)
  expect(at).toEqual([0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4])
})

test('durations read short', () => {
  expect(fmtDur(0)).toBe('0m')
  expect(fmtDur(12 * MIN)).toBe('12m')
  expect(fmtDur(70 * MIN)).toBe('1h10m')
  expect(fmtDur(3 * HOUR)).toBe('3h')
  expect(fmtDur(28 * HOUR)).toBe('1d4h')
  expect(fmtDur(2 * DAY)).toBe('2d')
})

test('record: same window keeps readings, tolerates reset jitter, skips duplicates', () => {
  const reset = T0 + 5 * HOUR
  let r = record(undefined, T0, 3, reset)
  r = record(r.track, T0 + MIN, 3, reset + 1_000) // same point, a second of jitter
  expect(r.track.samples.length).toBe(1)
  r = record(r.track, T0 + 2 * MIN, 4, reset - 30_000)
  expect(r.track.samples).toEqual([[T0, 3], [T0 + 2 * MIN, 4]])
  expect(r.finished).toBeUndefined()
})

test('record: a later reset starts a new window and hands back the finished one', () => {
  const r1 = record(undefined, T0, 80, T0 + HOUR)
  const r2 = record(r1.track, T0 + 2 * HOUR, 2, T0 + 6 * HOUR)
  expect(r2.finished?.samples).toEqual([[T0, 80]])
  expect(r2.track).toEqual({ resetsAt: T0 + 6 * HOUR, samples: [[T0 + 2 * HOUR, 2]] })
})

test('record: a drop inside a window restarts it', () => {
  const r1 = record(undefined, T0, 40, T0 + 3 * HOUR)
  const r2 = record(r1.track, T0 + MIN, 1, T0 + 3 * HOUR)
  expect(r2.finished).toBeDefined()
  expect(r2.track.samples).toEqual([[T0 + MIN, 1]])
})

test('record: keeps at most 600 readings', () => {
  let t: Track | undefined
  for (let i = 0; i < 700; i++) t = record(t, T0 + i * 11 * MIN, i / 7, T0 + 7 * DAY).track
  expect(t?.samples.length).toBe(600)
})

test('pctAt interpolates from 0 at the window start and holds after the last reading', () => {
  const reset = T0 + 5 * HOUR
  const track: Track = { resetsAt: reset, samples: [[T0 + HOUR, 20]] }
  expect(pctAt(track, 'five_hour', T0)).toBe(0)
  expect(pctAt(track, 'five_hour', T0 + 30 * MIN)).toBe(10)
  expect(pctAt(track, 'five_hour', T0 + 3 * HOUR)).toBe(20)
})

test('5h, first minutes: too early to judge, no warning', () => {
  const track: Track = { resetsAt: T0 + 5 * HOUR, samples: [[T0 + 4 * MIN, 3]] }
  const f = forecast('five_hour', track, T0 + 5 * MIN)
  expect(f.state).toBe('early')
  expect(warning(f)).toBeUndefined()
})

test('5h, steady 25%/h: full in 2h with 3h left warns orange', () => {
  const reset = T0 + 5 * HOUR
  const now = T0 + 2 * HOUR
  const track = linear(reset, T0, now, T0, 0, now, 50)
  const f = forecast('five_hour', track, now)
  expect(f.state).toBe('hits')
  expect(Math.abs((f.fullInMs ?? 0) - 2 * HOUR)).toBeLessThan(10 * MIN)
  expect(f.level).toBe(3)
  expect(warning(f)).toMatch(/^Session 50% · full in (1h5\dm|2h\d*m?), resets in 3h$/)
})

test('5h, fast burn with 25 min to full is red', () => {
  const reset = T0 + 5 * HOUR
  const now = T0 + HOUR
  const track = linear(reset, T0, now, T0, 0, now, 70) // 70%/h
  const f = forecast('five_hour', track, now)
  expect(f.state).toBe('hits')
  expect(f.fullInMs).toBeLessThanOrEqual(30 * MIN)
  expect(f.level).toBe(4)
})

test('5h, a burst that stopped 20 minutes ago does not warn (fast window agrees it stopped)', () => {
  const reset = T0 + 5 * HOUR
  const now = T0 + 3 * HOUR
  // 10% for two hours, then 30 points in 25 minutes, then nothing for 20 minutes.
  const quiet = linear(reset, T0, T0 + 2 * HOUR + 15 * MIN, T0, 0, T0 + 2 * HOUR, 10)
  const burst = linear(reset, T0 + 2 * HOUR + 15 * MIN, now, T0 + 2 * HOUR + 15 * MIN, 10, T0 + 2 * HOUR + 40 * MIN, 40)
  const track: Track = { resetsAt: reset, samples: [...quiet.samples, ...burst.samples] }
  const f = forecast('five_hour', track, now)
  expect(f.state).toBe('idle')
  expect(warning(f)).toBeUndefined()
})

test('5h, an ongoing burst warns even though the window average is low', () => {
  const reset = T0 + 5 * HOUR
  const now = T0 + 3 * HOUR
  const quiet = linear(reset, T0, T0 + 2 * HOUR, T0, 0, T0 + 2 * HOUR, 10)
  const burst = linear(reset, T0 + 2 * HOUR + 1, now, T0 + 2 * HOUR, 10, now, 50) // 40%/h for the last hour
  const track: Track = { resetsAt: reset, samples: [...quiet.samples, ...burst.samples] }
  expect(windowRate('five_hour', track, now, 45 * MIN)).toBeGreaterThan(0)
  const f = forecast('five_hour', track, now)
  expect(f.state).toBe('hits') // 50 left at 40%/h = 1h15m, reset in 2h
  expect(Math.abs((f.fullInMs ?? 0) - 75 * MIN)).toBeLessThan(10 * MIN)
})

test('5h, slow pace lands under the limit: no warning, shows where it ends', () => {
  const reset = T0 + 5 * HOUR
  const now = T0 + 2 * HOUR
  const track = linear(reset, T0, now, T0, 0, now, 20) // 10%/h
  const f = forecast('five_hour', track, now)
  expect(f.state).toBe('ok')
  expect(Math.round(f.atReset ?? 0)).toBe(50)
  expect(warning(f)).toBeUndefined()
})

test('7d, this week: the warning lands on Tuesday, days before Friday', () => {
  // Sun 4 PM reset; Hermann's chart: ~33% by Tue 4 PM, ~50% by Wed noon, 100% Fri noon.
  const reset = T0 + 7 * DAY
  const tue = T0 + 2 * DAY
  const track = linear(reset, T0, tue, T0, 0, tue, 33)
  const f = forecast('seven_day', track, tue)
  expect(f.state).toBe('hits')
  expect(f.pace ?? 0).toBeGreaterThan(1.1)
  // 67 points left at 16.5/day = ~4.06 days, reset in 5 days
  expect(Math.abs((f.fullInMs ?? 0) - 4.06 * DAY)).toBeLessThan(3 * HOUR)
  expect(f.level).toBe(3)
})

test('7d, the night does not cancel the warning: the average spans whole days', () => {
  const reset = T0 + 7 * DAY
  const now = T0 + 3 * DAY
  const track = linear(reset, T0, T0 + 2.6 * DAY, T0, 0, T0 + 2.6 * DAY, 50) // then 10h asleep
  const f = forecast('seven_day', track, now)
  expect(f.state).toBe('hits')
})

test('7d, on pace for the week: no warning', () => {
  const reset = T0 + 7 * DAY
  const now = T0 + 3.5 * DAY
  const track = linear(reset, T0, now, T0, 0, now, 45)
  const f = forecast('seven_day', track, now)
  expect(f.state).toBe('ok')
  expect(warning(f)).toBeUndefined()
})

test('7d, the first hours of a week do not judge pace below 25%', () => {
  const reset = T0 + 7 * DAY
  const track: Track = { resetsAt: reset, samples: [[T0 + HOUR, 4]] }
  expect(forecast('seven_day', track, T0 + 2 * HOUR).state).toBe('early')
})

test('limit reached: red, says when it resets, before any rate math', () => {
  const reset = T0 + 7 * DAY
  const track: Track = { resetsAt: reset, samples: [[T0 + 4.8 * DAY, 100]] }
  const f = forecast('seven_day', track, T0 + 5 * DAY)
  expect(f.state).toBe('exhausted')
  expect(f.level).toBe(4)
  expect(warning(f)).toBe('Week limit reached · resets in 2d')
})

test('last week at this same point is read from the finished window', () => {
  const prev = linear(T0, T0 - 7 * DAY, T0, T0 - 7 * DAY, 0, T0, 70)
  const reset = T0 + 7 * DAY
  const now = T0 + 3.5 * DAY
  const track = linear(reset, T0, now, T0, 0, now, 45)
  expect(forecast('seven_day', track, now, prev).lastTime).toBe(35)
})

test('the curve fills up to now and projects dim after it, capped at full', () => {
  const reset = T0 + 5 * HOUR
  const now = T0 + 2 * HOUR
  const track = linear(reset, T0, now, T0, 0, now, 50)
  const f = forecast('five_hour', track, now)
  const cells = curve(f, track, now, 10)
  expect(cells.filter(c => !c.isFuture).length).toBe(4)
  expect(cells[3]?.ch).toBe('▄')
  expect(cells[9]?.ch).toBe('█')
  expect(cells[9]?.level).toBe(4)
  expect(cells.every(c => c.ch.length === 1)).toBe(true)
})
