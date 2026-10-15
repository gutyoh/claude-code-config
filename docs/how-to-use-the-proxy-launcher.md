# How to Use the Proxy Launcher

Route Claude Code through alternative model providers (OpenAI Codex, Google Gemini, Antigravity Cloud Code) using a single unified CLI. The proxy launcher auto-starts the backend, configures environment variables, and launches Claude Code — all in one command.

## How the Proxy Launcher Works

```
┌──────────────┐         ┌──────────────────┐         ┌─────────────────────────┐
│  claude-proxy │────────▶│  Profile Script  │────────▶│  Provider Backend       │
│  (entry point)│         │  proxy-start-*   │         │                         │
│              │         │                  │         │  codex: CLIProxyAPI     │
│  Configures: │         │  Starts the      │         │  antigravity: Cloud Code│
│  • base URL  │         │  proxy server    │         │  custom: your own       │
│  • auth token│         │  in background   │         │                         │
│  • model     │         │                  │         │                         │
└──────┬───────┘         └──────────────────┘         └─────────────────────────┘
       │
       ▼
┌──────────────┐
│  Claude Code  │
│  (exec claude)│
└──────────────┘
```

**How it works step-by-step:**

1. Checks if the proxy is already running (HTTP health check)
2. If not running, launches the profile's start script in the background
3. Waits up to 5 seconds for the proxy to become reachable
4. Sets `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, and model environment variables
5. Runs `claude` with all environment variables injected — your session starts immediately

> **Key design principle:** Profiles only control *how to start the proxy*. Model selection is decoupled — you can use any model string the backend supports.

**PATH and shortcuts setup:** The `setup.sh` script automatically adds `bin/` to your shell PATH and installs shell functions in `~/.zshrc`, `~/.bashrc`, or `~/.profile`:

```bash
claude        # normal Claude Code, with bypassPermissions available in Shift+Tab cycle
claude -a     # start Claude Code directly in bypassPermissions mode
clp           # claude-proxy with gpt-5.5(high), bypassPermissions available in Shift+Tab cycle
clp -a        # claude-proxy with gpt-5.5(high), directly in bypassPermissions mode
```

The proxy shortcut default model can be overridden per shell:

```bash
export CLAUDE_PROXY_MODEL="gpt-5.5(high)"
```

If you skipped this during setup, add PATH manually:

```bash
# Add to ~/.zshrc or ~/.bashrc (use the actual path to your clone):
export PATH="/path/to/claude-code-config/bin:$PATH"
```

Or re-run `./setup.sh` to configure PATH and shortcuts automatically.

## Proxy Quick Start

### Antigravity (Google Cloud Code)

Uses your Google account to access Claude and Gemini models for free via [Antigravity Cloud Code](https://github.com/badrisnarayanan/antigravity-claude-proxy).

**Prerequisites:**

| Tool | Install |
|------|---------|
| Node.js 18+ | `brew install node` |
| Google account | Any Gmail / Google Workspace account |

**First-time setup** (link your Google account):

```bash
# Start the proxy manually
npx antigravity-claude-proxy@latest start

# Open http://localhost:8081 in your browser
# Go to Accounts → Add Account → complete Google OAuth
# Once linked, press Ctrl+C to stop
```

**Run Claude Code:**

```bash
# Claude models via Antigravity
./bin/claude-proxy -p antigravity -m 'claude-sonnet-4-5-thinking'

# Gemini models via Antigravity
./bin/claude-proxy -p antigravity -m 'gemini-3-pro-high[1m]'
```

### Codex (CLIProxyAPI + OpenAI/ChatGPT)

Uses your existing OpenAI Codex/ChatGPT subscription tokens via [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI).

**Prerequisites:**

| Tool | Install |
|------|---------|
| Go 1.21+ | `brew install go` |
| jq | `brew install jq` |
| CLIProxyAPI source | `git clone https://github.com/router-for-me/CLIProxyAPI.git ~/Documents/dev/CLIProxyAPI` |
| Codex CLI auth | Sign in via `codex` CLI (creates `~/.codex/auth.json`) |

**Run Claude Code:**

```bash
# GPT models via CLIProxyAPI (codex is the default profile)
./bin/claude-proxy -m 'gpt-5.3-codex(high)'
```

## Available Profiles

| Profile | Backend | Port | Auth Token | Models |
|---------|---------|------|------------|--------|
| `codex` (default) | [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) | 8317 | `sk-dummy` | GPT / Codex |
| `antigravity` | [Antigravity Claude Proxy](https://github.com/badrisnarayanan/antigravity-claude-proxy) | 8081 | `test` | Claude / Gemini |
| `none` | (external) | 8317 | `sk-dummy` | Any (proxy must be pre-started) |

Port and auth token are per-profile defaults — override them with `--port` and `--api-key` if needed.

## CLI Reference

```
Usage:
  ./bin/claude-proxy [options] [--] [claude args...]

Options:
  -m, --model MODEL        Model string (validated per profile; uses profile default if omitted)
  -p, --profile PROFILE    Proxy profile: codex | antigravity | none (default: codex)
  --models                 List available models for the selected profile and exit
  --host HOST              Proxy bind address (default: 127.0.0.1)
  --port PORT              Proxy port (auto-set per profile if omitted)
  --api-key KEY            Proxy auth key (auto-set per profile if omitted)
  --no-start               Require proxy to be already running (skip auto-start)
  --no-validate            Skip model validation
  -h, --help               Show help
```

**Examples:**

```bash
# Use profile defaults (codex + gpt-5.3-codex(high))
./bin/claude-proxy

# Antigravity with its default (claude-opus-4-6-thinking)
./bin/claude-proxy -p antigravity

# Codex with medium effort
./bin/claude-proxy -m 'gpt-5.3-codex(medium)'

# Antigravity with Gemini + 1M context
./bin/claude-proxy -p antigravity -m 'gemini-3-pro-high[1m]'

# List available models per profile
./bin/claude-proxy --models                   # codex models
./bin/claude-proxy -p antigravity --models    # antigravity models

# Use a proxy that's already running on a custom port
./bin/claude-proxy --no-start --port 3001 --no-validate -m 'custom-model'

# Pass extra arguments to Claude Code (after --)
./bin/claude-proxy -p antigravity -- --verbose

# Installed shell shortcut: proxy + allow switching to bypassPermissions
clp

# Installed shell shortcut: proxy + start directly in bypassPermissions
clp -a
```

## Creating Custom Profiles

Add support for any proxy backend by creating a start script:

1. Create `bin/proxy-start-<name>.sh` (must be executable)
2. The script receives environment variables: `HOST`, `PORT`, `API_KEY`, `MODEL`
3. The script should start the proxy in the foreground (the launcher handles backgrounding)

**Example:** Create a profile for a hypothetical `my-proxy` backend:

```bash
#!/usr/bin/env bash
set -euo pipefail

# bin/proxy-start-myproxy.sh
# Called by: ./bin/claude-proxy -p myproxy

PORT="${PORT:-9090}" exec my-proxy-server --port "${PORT}"
```

```bash
chmod +x bin/proxy-start-myproxy.sh
./bin/claude-proxy -p myproxy -m 'my-custom-model'
```

To set per-profile defaults (port, API key), add a case to the defaults block in `bin/claude-proxy`.

## Proxy Troubleshooting

<details>
<summary><strong>Proxy not reachable after startup</strong></summary>

Check the proxy log for errors:

```bash
cat ~/.cli-proxy-api/cli-proxy-api.log
```

Common causes:
- **Port conflict:** Another service is using the port. Override with `--port 8081`
- **Missing dependencies:** Codex profile requires `go` and `jq`; Antigravity requires `node` and `npx`
- **No auth configured:** Antigravity requires linking a Google account first (see Quick Start above)

</details>

<details>
<summary><strong>Antigravity shows "No accounts in config"</strong></summary>

The proxy is running but no Google account is linked. Open `http://localhost:8081`, go to **Accounts**, and click **Add Account** to complete OAuth.

</details>

<details>
<summary><strong>Codex profile fails to build</strong></summary>

The CLIProxyAPI source must be cloned locally:

```bash
git clone https://github.com/router-for-me/CLIProxyAPI.git ~/Documents/dev/CLIProxyAPI
```

You also need Go installed: `brew install go`

Override the source location:

```bash
CLI_PROXY_DIR=~/path/to/CLIProxyAPI ./bin/claude-proxy -m 'gpt-5.3-codex(high)'
```

</details>

<details>
<summary><strong>Running both profiles simultaneously</strong></summary>

Since each profile uses a different port, you can run them side-by-side:

```bash
# Terminal 1: Antigravity on :8081
./bin/claude-proxy -p antigravity -m 'claude-sonnet-4-5-thinking'

# Terminal 2: Codex on :8317
./bin/claude-proxy -m 'gpt-5.3-codex(high)'
```

</details>

<details>
<summary><strong>Environment variables vs. proxy launcher</strong></summary>

The proxy launcher is an alternative to manually setting environment variables. These two approaches are equivalent:

```bash
# Option A: Proxy launcher (recommended)
./bin/claude-proxy -p antigravity -m 'claude-sonnet-4-5-thinking'

# Option B: Manual environment variables
export ANTHROPIC_BASE_URL="http://localhost:8081"
export ANTHROPIC_AUTH_TOKEN="test"
export ANTHROPIC_DEFAULT_OPUS_MODEL="claude-opus-4-5-thinking"
export ANTHROPIC_DEFAULT_SONNET_MODEL="claude-sonnet-4-5-thinking"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-sonnet-4-5-thinking"
claude
```

The launcher adds auto-start and per-profile defaults so you don't have to remember ports and tokens.

</details>

## See also

- [Configuration](configuration.md#environment-variables): `CODEX_TOKEN_MAX_AGE_HOURS` and the other variables
- [How to configure the status line](how-to-configure-statusline.md#usage-for-gpt-and-muse-models): usage for GPT and Muse models
