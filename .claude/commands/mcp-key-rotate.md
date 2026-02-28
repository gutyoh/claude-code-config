# MCP Key Rotate Command

Check quota and rotate API keys for MCP servers (Brave Search, Tavily, etc.).

## Usage

```
/mcp-key-rotate <service> [action]
```

## Description

This command manages API key rotation for MCP servers. It supports checking per-key credit usage, rotating to the next key in the pool, and adding new keys. Auto-detects the secrets backend (Doppler or `.env` file).

## Arguments

- `service` (required): The MCP service name (`brave`, `tavily`)
- `action` (optional): One of `--status`, `--quota`, `--add KEY`. Defaults to rotate.

## Behavior

When invoked, run the appropriate `mcp-key-rotate` command via the Bash tool:

### Default (no action): Rotate to next key
```bash
mcp-key-rotate <service>
```

### `--status`: Show pool without API calls
```bash
mcp-key-rotate <service> --status
```

### `--quota`: Show per-key credit usage (live API check)
```bash
mcp-key-rotate <service> --quota
```

### `--add KEY`: Add a new key to the pool
```bash
mcp-key-rotate <service> --add <KEY>
```

## Examples

```
/mcp-key-rotate brave --quota
/mcp-key-rotate tavily --quota
/mcp-key-rotate brave
/mcp-key-rotate tavily --status
/mcp-key-rotate brave --add BSA_new_key_here
```

## Prerequisites

- `mcp-key-rotate` script on PATH (installed by `setup.sh`)
- Doppler CLI configured (personal computer) OR `.env` file with pool vars (work computer)

## After Rotation

**IMPORTANT:** After rotating a key, tell the user they must restart Claude Code for the MCP server to pick up the new environment variable. The rotation updates the secret store but the running MCP process still has the old key in memory.

## Error Handling

If the script is not found:
1. Check if `mcp-key-rotate` is on PATH: `which mcp-key-rotate`
2. If not, run setup.sh from the claude-code-config repo to install it
3. Or run directly: `<repo-path>/bin/mcp-key-rotate <service> <action>`

## See Also

- `/brave-search` - Search using Brave Search MCP
- `/tavily-search` - Search using Tavily MCP
