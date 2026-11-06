import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

const MIN = 60_000
const HOUR = 60 * MIN
const T0 = Date.UTC(2026, 10, 6, 15, 0)

const BAND = {
  plugin: 'usage-forecast',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 100, scroll: { offset: 0, bodyRows: 10 }, view: {} },
} as const

const PANE = {
  plugin: 'usage-forecast',
  component: 'Pane',
  requestId: 'usage-forecast',
  props: { title: 'Usage forecast', isFocused: false, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 30 }, view: {} },
} as const

const iso = (ms: number) => new Date(ms).toISOString()

/** The engine beneath the mod: store and clock in memory, everything else answered. */
function engine(on: On, usage: { kind: string; percentUsed: number; resetsAt?: string }[] = [], opened: string[] = []) {
  const clock = mock.clock(on, { now: T0 })
  mock.store(on)
  mock.env(on, { HOME: '/home/user' })
  const files: Record<string, string> = {}
  on('fs.write', (_, e) => {
    const [path, text] = (e as { args?: [string, string] }).args ?? [(e as any).path, (e as any).text]
    files[String(path)] = String(text)
    return { value: undefined }
  })
  const toasts: string[] = []
  on('command.register', () => ({ value: { command: 'usage-forecast' } }))
  on('ui.open', (_, e) => {
    opened.push((e as { id: string }).id)
    return { value: { isPlaced: true } }
  })
  on('ui.toast', (_, e) => {
    toasts.push(String((e as { text?: string }).text ?? JSON.stringify(e)))
    return { value: undefined }
  })
  on('session.usage', () => ({ value: { startedAt: T0, context: { tokens: 0, window: 200000, percent: 0 }, rateLimits: usage } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.measure', (_, e) => ({ changed: e.changed }))
  return { clock, toasts, files }
}

test('calm usage: the band stays empty and the pane shows both windows', async ($, on) => {
  const { clock } = engine(on, [
    { kind: 'five_hour', percentUsed: 10, resetsAt: iso(T0 + 3 * HOUR) },
    { kind: 'seven_day', percentUsed: 20, resetsAt: iso(T0 + 4 * 24 * HOUR) },
  ])
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await clock.settle()

  for (const surface of ['terminal', 'desktop'] as const) {
    const band = await $.ui.mount({ ...BAND, surface })
    expect((await band.find({ type: 'Text', text: /▲/ }))).toBeUndefined()
    // Calm: the mod passes the band on untouched (here the stub engine draws it).
    expect((await band.find({ type: 'Text', text: /^engine$/ }))?.text).toBe('engine')
    await band.unmount()

    const pane = await $.ui.mount({ ...PANE, surface })
    expect(await pane.find({ type: 'Text', text: /^Session$/ })).toBeDefined()
    expect(await pane.find({ type: 'Text', text: /resets in 3h/ })).toBeDefined()
    expect(await pane.find({ type: 'Text', text: /resets in 4d/ })).toBeDefined()
    await pane.unmount()
  }
})

test('a burning session: readings arrive, the band warns once and a toast fires once', async ($, on) => {
  const { clock, toasts } = engine(on)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const reset = T0 + 3 * HOUR // window began 2h ago
  // 30 points in the last hour, one reading per point.
  await $.session.measure({ context: { tokens: 0, window: 200000, percent: 0 } as never, changed: ['rateLimits'], rateLimits: [{ kind: 'five_hour', percentUsed: 20, resetsAt: iso(reset) }] })
  for (let p = 21; p <= 50; p++) {
    await clock.advance(2 * MIN)
    await $.session.measure({ context: { tokens: 0, window: 200000, percent: 0 } as never, changed: ['rateLimits'], rateLimits: [{ kind: 'five_hour', percentUsed: p, resetsAt: iso(reset) }] })
  }
  // Orange: the statusline shows it, the band stays quiet, one toast fires.
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  for (const surface of ['terminal', 'desktop'] as const) {
    const band = await $.ui.mount({ ...BAND, surface })
    expect(await band.find({ type: 'Text', text: /▲/ })).toBeUndefined()
    await band.unmount()
  }
  expect(toasts.length).toBe(1)
  expect(toasts[0]).toMatch(/^Session 50% · full in \d+h?\d*m?, resets in 2h$/)
})

test('readings are shared through the store across sessions and survive a restart', async ($, on) => {
  const reset = T0 + 2 * 24 * HOUR
  const clock = mock.clock(on, { now: T0 })
  mock.store(on, {
    'track:seven_day': { resetsAt: reset, samples: [[T0 - 5 * 24 * HOUR + HOUR, 1], [T0 - HOUR, 100]] },
  })
  on('command.register', () => ({ value: { command: 'usage-forecast' } }))
  on('ui.toast', () => ({ value: undefined }))
  on('session.usage', () => ({ value: { startedAt: T0, context: { tokens: 0, window: 200000, percent: 0 }, rateLimits: [] } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await band.find({ type: 'Text', text: /Week limit reached/ }))?.text).toBe('▲ Week limit reached · resets in 2d')
  await band.unmount()
})

test('the command opens the pane', async ($, on) => {
  const opened: string[] = []
  engine(on, [], opened)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.command.run({ command: 'usage-forecast', args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 160 } })
  expect(opened).toEqual(['usage-forecast'])
})

test('no readings yet: the pane says so instead of drawing empty rows', async ($, on) => {
  engine(on)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await pane.find({ type: 'Text', text: /No plan-limit readings/ }))).toBeDefined()
  await pane.unmount()
})

test('a survey in the band wins over a warning', async ($, on) => {
  engine(on, [{ kind: 'seven_day', percentUsed: 100, resetsAt: iso(T0 + 24 * HOUR) }])
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const band = await $.ui.mount({ ...BAND, props: { ...BAND.props, hasSurvey: true }, surface: 'terminal' })
  expect(await band.find({ type: 'Text', text: /▲/ })).toBeUndefined()
  expect((await band.find({ type: 'Text', text: /^engine$/ }))?.text).toBe('engine')
  await band.unmount()
})

test('headless: with no screen the command answers in text', async ($, on) => {
  const clock = mock.clock(on, { now: T0 })
  mock.store(on, {
    'track:seven_day': { resetsAt: T0 + 24 * HOUR, samples: [[T0 - HOUR, 100]] },
  })
  on('command.register', () => ({ value: { command: 'usage-forecast' } }))
  on('ui.open', () => ({ deny: 'no-surface: no surface is attached' }))
  on('session.usage', () => ({ value: { startedAt: T0, context: { tokens: 0, window: 200000, percent: 0 }, rateLimits: [] } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: false })
  await clock.settle()
  const answer = await $.command.run({ command: 'usage-forecast', args: '', origin: { kind: 'sdk' } as never, presentation: { isFullscreen: false, columns: 80 } })
  expect(answer.text).toBe('Week 100% · limit reached · resets in 1d')
})

test('hands the forecast to statusline.sh as one tab-separated line per window', async ($, on) => {
  const { clock, files } = engine(on)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const reset = T0 + 3 * HOUR
  const ctx = { tokens: 0, window: 200000, percent: 0 } as never
  await $.session.measure({ context: ctx, changed: ['rateLimits'], rateLimits: [{ kind: 'five_hour', percentUsed: 20, resetsAt: iso(reset) }] })
  for (let p = 21; p <= 50; p++) {
    await clock.advance(2 * MIN)
    await $.session.measure({ context: ctx, changed: ['rateLimits'], rateLimits: [{ kind: 'five_hour', percentUsed: p, resetsAt: iso(reset) }, { kind: 'seven_day', percentUsed: 10, resetsAt: iso(T0 + 4 * 24 * HOUR) }] })
  }
  const text = files['/home/user/.claude/cache/usage-forecast.tsv'] ?? ''
  const [five, week] = text.trim().split('\n')
  const f = (five ?? '').split('\t')
  expect(f[0]).toBe('five_hour')
  expect(f[1]).toBe(String(Math.round(reset / 1000)))
  expect(f[2]).toBe('hits')
  expect(Number(f[3])).toBeGreaterThan(0)
  expect(Number(f[3])).toBeLessThan(2 * 3600)
  expect((week ?? '').split('\t').slice(0, 3)).toEqual(['seven_day', String(Math.round((T0 + 4 * 24 * HOUR) / 1000)), 'ok'])
})
