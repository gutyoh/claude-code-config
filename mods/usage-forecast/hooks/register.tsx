import type { Color, EngineInterface as Engine, Register, SessionRateLimit } from 'claude-code'

import {
  KINDS,
  curve,
  fmtDur,
  forecast,
  record,
  warning,
  type Forecast,
  type Kind,
  type Level,
  type Track,
} from './forecast'

const PANE = 'usage-forecast'
const MIN = 60_000

// Quiet → loud v2, through theme tokens so light and dark themes both read.
const COLOR: Record<Level, Color> = {
  0: 'inactive',
  1: 'suggestion',
  2: 'warning',
  3: '#ff8700',
  4: 'error',
}

// Mirrors of $.store, refreshed on every reading; $.store is the source of truth.
const tracks: Partial<Record<Kind, Track>> = {}
const previous: Partial<Record<Kind, Track>> = {}

function isKind(kind: string): kind is Kind {
  return kind === 'five_hour' || kind === 'seven_day'
}

async function load($: Engine) {
  for (const kind of KINDS) {
    const t = (await $.store.get('track:' + kind)) as Track | undefined
    const p = (await $.store.get('prev:' + kind)) as Track | undefined
    if (t && Array.isArray(t.samples)) tracks[kind] = t
    if (p && Array.isArray(p.samples)) previous[kind] = p
  }
}

async function ingest($: Engine, limits: readonly SessionRateLimit[]) {
  const now = await $.clock.now()
  for (const limit of limits) {
    if (!isKind(limit.kind) || !limit.resetsAt) continue
    const resetsAt = Date.parse(limit.resetsAt)
    if (!Number.isFinite(resetsAt)) continue
    // Re-read: another session on this machine may have written since we loaded.
    const stored = (await $.store.get('track:' + limit.kind)) as Track | undefined
    const { track, finished } = record(stored ?? tracks[limit.kind], now, limit.percentUsed, resetsAt)
    await $.store.set('track:' + limit.kind, track)
    tracks[limit.kind] = track
    if (finished) {
      await $.store.set('prev:' + limit.kind, finished)
      previous[limit.kind] = finished
    }
    const f = forecast(limit.kind, track, now, previous[limit.kind])
    const line = warning(f)
    // One toast per window and state, shared by every session.
    const mark = `${track.resetsAt}:${f.state}`
    if (line && (await $.store.get('warned:' + limit.kind)) !== mark) {
      await $.store.set('warned:' + limit.kind, mark)
      $.ui.toast(line)
    }
  }
  await handoff($)
  $.ui.invalidate('ui.render')
}

/** Hands the forecast to the statusline script (statusline.sh reads this file). */
async function handoff($: Engine) {
  const now = await $.clock.now()
  const root = (await $.env.get('CLAUDE_CONFIG_DIR')) ?? `${(await $.env.get('HOME')) ?? ''}/.claude`
  const lines = current(now).map(f => {
    const track = tracks[f.kind] as Track
    const full = f.fullInMs === undefined ? '' : String(Math.round(f.fullInMs / 1000))
    return [f.kind, Math.round(track.resetsAt / 1000), f.state, full].join('\t')
  })
  if (lines.length) await $.fs.write(`${root}/cache/usage-forecast.tsv`, lines.join('\n') + '\n')
}

function current(now: number): Forecast[] {
  const out: Forecast[] = []
  for (const kind of KINDS) {
    const track = tracks[kind]
    if (track && track.samples.length) out.push(forecast(kind, track, now, previous[kind]))
  }
  return out
}

function detail(f: Forecast): string {
  const parts: string[] = []
  if (f.state === 'exhausted') parts.push('limit reached')
  else if (f.state === 'hits' && f.fullInMs !== undefined) parts.push(`full in ${fmtDur(f.fullInMs)}`)
  else if (f.state === 'ok' && f.atReset !== undefined) parts.push(`~${Math.round(f.atReset)}% at reset`)
  else if (f.state === 'idle') parts.push('idle')
  else parts.push('learning pace')
  if (f.kind === 'seven_day' && f.pace !== undefined && f.state !== 'exhausted') {
    parts.push(`${f.pace.toFixed(1)}× pace`)
  }
  parts.push(`resets in ${fmtDur(f.resetInMs)}`)
  return parts.join(' · ')
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'usage-forecast',
      description: 'Chart the 5-hour and weekly limits with a run-out forecast',
    })
    await load($)
    const usage = await $.session.usage()
    if (usage.rateLimits.length) await ingest($, usage.rateLimits)
    // Countdowns and idle pace move without readings: refresh once a minute.
    $.clock.every(MIN, () => {
      $.ui.invalidate('ui.render')
      void handoff($).catch(() => undefined)
    })
    return next(e)
  })

  on('session.measure', async ($, e, next) => {
    if (e.changed.includes('rateLimits')) await ingest($, e.rateLimits)
    return next(e)
  })

  on('command.run', { command: 'usage-forecast' }, async $ => {
    try {
      await $.ui.open({ id: PANE, title: 'Usage forecast', closeOnEscape: true })
      return {}
    } catch {
      // No screen to draw on (claude -p, SDK): answer in text instead.
      const list = current(await $.clock.now())
      if (list.length === 0) return { text: 'No plan-limit readings yet.' }
      const name = (f: Forecast) => (f.kind === 'five_hour' ? 'Session' : 'Week')
      return { text: list.map(f => `${name(f)} ${Math.round(f.pct)}% · ${detail(f)}`).join('\n') }
    }
  })

  // The band speaks only when a limit will run out before it resets.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const now = await $.clock.now()
    const lines = current(now)
      .map(f => ({ f, text: warning(f) }))
      .filter((x): x is { f: Forecast; text: string } => x.text !== undefined)
    if (lines.length === 0) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="column">
        {lines.map(({ f, text }) => (
          <Text color={COLOR[f.level]} bold={f.level >= 3} wrap="truncate-end">
            ▲ {text}
          </Text>
        ))}
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const now = await $.clock.now()
    const list = current(now)
    if (list.length === 0) {
      return <Text dimColor>No plan-limit readings yet. They arrive with the next response.</Text>
    }
    const width = Math.max(10, Math.min(48, e.props.bodyColumns - 10))
    return (
      <Box flexDirection="column" rowGap={1}>
        {list.map(f => {
          const track = tracks[f.kind] as Track
          const cells = curve(f, track, now, width)
          return (
            <Box flexDirection="column">
              <Box flexDirection="row" columnGap={1}>
                <Text bold>{f.kind === 'five_hour' ? 'Session' : 'Week   '}</Text>
                <Text color={COLOR[f.level]} bold={f.level >= 3}>
                  {String(Math.round(f.pct)).padStart(3)}%
                </Text>
              </Box>
              <Text>
                {cells.map(c => (
                  <Text color={COLOR[c.level]} dimColor={c.isFuture}>
                    {c.isFuture ? (c.ch === ' ' ? '·' : c.ch) : c.ch}
                  </Text>
                ))}
              </Text>
              <Text color={COLOR[f.level]}>{detail(f)}</Text>
              {f.lastTime !== undefined && (
                <Text dimColor>
                  last window at this point: {f.lastTime}% ({f.pct - f.lastTime >= 0 ? '+' : ''}
                  {Math.round(f.pct - f.lastTime)})
                </Text>
              )}
            </Box>
          )
        })}
        <Text dimColor>solid = used so far · dim = projection at the slower of recent and average pace</Text>
      </Box>
    )
  })
}
