# How to Add an MCP Server

Register a new MCP server so it is available in all Claude Code sessions.

## Prerequisites

- Claude Code installed
- This repo's global config installed via `setup.sh`

## 1. Add the server via CLI

```bash
claude mcp add <server-name> --scope user -- npx -y @org/mcp-server-package
```

For servers that need environment variables:

```bash
claude mcp add <server-name> --scope user \
  -e API_KEY='${API_KEY}' \
  -- npx -y @org/mcp-server-package
```

The `${VAR}` syntax means Claude Code reads the value from your environment at runtime. No secrets are stored in config files.

## 2. Add the API key

### Envfile backend (default)

Add the key to `~/.claude/mcp-keys.env`:

```bash
echo 'MY_API_KEY=your-key-here' >> ~/.claude/mcp-keys.env
```

### Doppler backend (enterprise)

If using Doppler for secrets management:

```bash
doppler secrets set MY_API_KEY --project claude-code-config --config dev
```

The setup script auto-detects which backend to use.

## 3. Verify the server

```bash
claude mcp list
```

Your server should appear with scope `user`:

```
  my-server: npx ... (user)
```

Start a Claude Code session and test the server's tools.

## Add the server to setup.sh (optional)

To include the server in automated setup for new machines, add it to the MCP registry in `lib/setup/mcp.sh`:

1. Add the server key to `MCP_SERVER_KEYS`:

```bash
MCP_SERVER_KEYS=("brave-search" "tavily" "my-server")
```

2. Add the metadata lookup in `mcp_get()`:

```bash
my-server)
    case "$field" in
        label)     echo "My Server" ;;
        desc)      echo "Description of what it does" ;;
        env_var)   echo "MY_API_KEY" ;;
        package)   echo "@org/mcp-server-package" ;;
        signup_url) echo "https://example.com" ;;
        free_limit) echo "1,000/mo" ;;
    esac
    ;;
```

## Set up key rotation (optional)

If your server supports multiple API keys, add a key pool for rotation:

1. Add multiple keys to `.env` or Doppler:

```bash
MY_API_KEY=key1
MY_API_KEY_POOL=key1,key2,key3
```

2. Rotate keys:

```bash
mcp-key-rotate my-server
```

3. Check quota per key:

```bash
mcp-key-rotate my-server --quota
```

Key rotation requires adding quota-checking logic to `bin/mcp-key-rotate` for the new service.

## Add rate limiting (optional)

If the server has strict rate limits, create a rate-limiting hook:

1. Copy the existing Brave Search rate limiter:

```bash
cp .claude/hooks/rate-limit-brave-search.sh .claude/hooks/rate-limit-my-server.sh
chmod +x .claude/hooks/rate-limit-my-server.sh
```

2. Edit the lock file path and rate limit in the new script.

3. Register the hook in `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "mcp__my-server__.*",
        "hooks": [
          {
            "type": "command",
            "command": "./.claude/hooks/rate-limit-my-server.sh"
          }
        ]
      }
    ]
  }
}
```

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Server not in `claude mcp list` | Wrong scope or failed registration | Re-run `claude mcp add` with `--scope user` |
| Server tools not available in session | Session started before server was added | Restart Claude Code |
| API key not found at runtime | Key not in `~/.claude/mcp-keys.env` or environment | Add the key and restart |
| 429 quota errors | API quota exhausted | Run `mcp-key-rotate <server> --quota` to check, rotate if pool available |
| Server crashes on startup | Package version issue | Pin the version: `npx -y @org/mcp-server@1.0.0` |

## See also

- [Configuration](configuration.md): full reference for .mcp.json format and environment variables
- [Architecture](architecture.md): how MCP key management and rotation works
- [Project Structure](project-structure.md): MCP-related files (bin/mcp-key-rotate, hooks/rate-limit-brave-search)
