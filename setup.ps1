# setup.ps1
# Path: claude-code-config/setup.ps1
#
# Creates symlinks from this repo to ~/.claude/ for global Claude Code configuration.
# Optionally configures MCP servers in user scope.
# Run this script from inside the repo directory as Administrator.
# Safe to re-run if you move the repo.

$ErrorActionPreference = "Stop"

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Claude Code Config Setup" -ForegroundColor Cyan
Write-Host "========================" -ForegroundColor Cyan
Write-Host "Repo location: $RepoDir"
Write-Host ""

# Create ~/.claude if it doesn't exist
$ClaudeDir = "$env:USERPROFILE\.claude"
if (-not (Test-Path $ClaudeDir)) {
    New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
    Write-Host "Created $ClaudeDir"
}

Write-Host "Step 1: Creating symlinks..." -ForegroundColor Yellow

# Function to safely create symlink without circular references
function Create-SafeSymlink {
    param (
        [string]$Source,
        [string]$Target,
        [string]$Name
    )

    # Resolve real paths to detect if we're IN the repo
    $ClaudeReal = (Resolve-Path $ClaudeDir -ErrorAction SilentlyContinue).Path
    $RepoClaudeReal = (Resolve-Path "$RepoDir\.claude" -ErrorAction SilentlyContinue).Path

    # If ~/.claude IS the repo's .claude directory, skip symlink creation
    if ($ClaudeReal -eq $RepoClaudeReal) {
        Write-Host "  + $ClaudeDir\$Name (same as repo, no symlink needed)" -ForegroundColor Green
        return
    }

    # Check if symlink already exists and points to correct location
    if (Test-Path $Target) {
        $item = Get-Item $Target -Force
        if ($item.LinkType -eq "SymbolicLink") {
            $currentTarget = $item.Target
            if ($currentTarget -eq $Source) {
                Write-Host "  + $ClaudeDir\$Name -> $Source (already configured)" -ForegroundColor Green
                return
            }
        }
        # Remove existing (file, directory, or wrong symlink)
        Remove-Item $Target -Force -Recurse -ErrorAction SilentlyContinue
    }

    # Create fresh symlink
    New-Item -ItemType SymbolicLink -Path $Target -Target $Source -Force | Out-Null
    Write-Host "  + $ClaudeDir\$Name -> $Source" -ForegroundColor Green
}

# Create symlinks
Create-SafeSymlink -Source "$RepoDir\.claude\commands" -Target "$ClaudeDir\commands" -Name "commands"
Create-SafeSymlink -Source "$RepoDir\.claude\skills" -Target "$ClaudeDir\skills" -Name "skills"
Create-SafeSymlink -Source "$RepoDir\.claude\agents" -Target "$ClaudeDir\agents" -Name "agents"
Create-SafeSymlink -Source "$RepoDir\.claude\hooks" -Target "$ClaudeDir\hooks" -Name "hooks"

Write-Host ""
Write-Host "Step 2: Configuring hooks (user scope)..." -ForegroundColor Yellow
Write-Host ""

$SettingsJson = "$env:USERPROFILE\.claude\settings.json"

# Check if settings.json exists
if (-not (Test-Path $SettingsJson)) {
    Write-Host "  Creating settings.json with default hooks..."
    $hookConfig = @{
        hooks = @{
            PreToolUse = @(
                @{
                    matcher = "mcp__ide__getDiagnostics"
                    hooks = @(
                        @{
                            type = "command"
                            command = "~/.claude/hooks/open-file-in-ide.sh"
                        }
                    )
                }
            )
        }
    }
    $hookConfig | ConvertTo-Json -Depth 10 | Set-Content $SettingsJson -Encoding UTF8
    Write-Host "  + IDE diagnostics hook configured" -ForegroundColor Green
} else {
    # Check if IDE diagnostics hook is already configured
    try {
        $settings = Get-Content $SettingsJson -Raw | ConvertFrom-Json
        $hookExists = $false

        if ($settings.hooks -and $settings.hooks.PreToolUse) {
            foreach ($hook in $settings.hooks.PreToolUse) {
                if ($hook.matcher -eq "mcp__ide__getDiagnostics") {
                    $hookExists = $true
                    break
                }
            }
        }

        if ($hookExists) {
            Write-Host "  + IDE diagnostics hook already configured" -ForegroundColor Green
        } else {
            Write-Host "  Adding IDE diagnostics hook to existing settings..."

            # Ensure hooks structure exists
            if (-not $settings.hooks) {
                $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue @{} -Force
            }
            if (-not $settings.hooks.PreToolUse) {
                $settings.hooks | Add-Member -NotePropertyName "PreToolUse" -NotePropertyValue @() -Force
            }

            # Add IDE diagnostics hook
            $ideHook = @{
                matcher = "mcp__ide__getDiagnostics"
                hooks = @(
                    @{
                        type = "command"
                        command = "~/.claude/hooks/open-file-in-ide.sh"
                    }
                )
            }

            # Convert PreToolUse to ArrayList to add items
            $preToolUse = [System.Collections.ArrayList]@($settings.hooks.PreToolUse)
            $preToolUse.Add($ideHook) | Out-Null
            $settings.hooks.PreToolUse = $preToolUse

            # Save back
            $settings | ConvertTo-Json -Depth 10 | Set-Content $SettingsJson -Encoding UTF8
            Write-Host "  + IDE diagnostics hook added" -ForegroundColor Green
        }
    } catch {
        Write-Host "  ! Failed to add hook: $_" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Step 3: Configuring MCP servers (user scope)..." -ForegroundColor Yellow
Write-Host ""

# Check if claude CLI is available
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-Host "  ! Claude Code CLI not found. Install it first:" -ForegroundColor Yellow
    Write-Host "    irm https://claude.ai/install.ps1 | iex"
    Write-Host ""
    Write-Host "  After installing, re-run this script or manually add MCP servers:"
    Write-Host "    claude mcp add brave-search --scope user ``"
    Write-Host "      -e BRAVE_API_KEY='`${BRAVE_API_KEY}' ``"
    Write-Host "      -- npx -y @brave/brave-search-mcp-server"
    Write-Host ""
} else {
    # Check if brave-search MCP is already configured
    $mcpList = & claude mcp list 2>$null
    if ($mcpList -match "brave-search") {
        Write-Host "  + brave-search MCP already configured" -ForegroundColor Green
    } else {
        Write-Host "  Adding brave-search MCP server..."
        try {
            # Add Brave Search MCP to user scope
            # Note: On Windows, we need to use cmd /c wrapper for npx
            & claude mcp add brave-search --scope user `
                -e BRAVE_API_KEY='${BRAVE_API_KEY}' `
                -- cmd /c npx -y @brave/brave-search-mcp-server 2>$null
            Write-Host "  + brave-search MCP added to user scope" -ForegroundColor Green
        } catch {
            Write-Host "  ! Failed to add brave-search MCP. You can add it manually:" -ForegroundColor Yellow
            Write-Host "    claude mcp add brave-search --scope user ``"
            Write-Host "      -e BRAVE_API_KEY='`${BRAVE_API_KEY}' ``"
            Write-Host "      -- cmd /c npx -y @brave/brave-search-mcp-server"
        }
    }
}

Write-Host ""
Write-Host "Step 4: Environment variables" -ForegroundColor Yellow
Write-Host ""

# Check if BRAVE_API_KEY is set
if ($env:BRAVE_API_KEY) {
    Write-Host "  + BRAVE_API_KEY is set ($($env:BRAVE_API_KEY.Length) chars)" -ForegroundColor Green
} else {
    Write-Host "  ! BRAVE_API_KEY not set." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Set it in System Environment Variables:"
    Write-Host "    1. Open System Properties > Advanced > Environment Variables"
    Write-Host "    2. Under User variables, click New"
    Write-Host "    3. Set BRAVE_API_KEY with your API key value"
    Write-Host ""
    Write-Host "  Get a free API key (2,000 searches/month):"
    Write-Host "    https://api-dashboard.search.brave.com/"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Setup complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Verify in any project:"
Write-Host "  cd ~\some-project"
Write-Host "  claude"
Write-Host "  > /help           # Should show /web-search, /brave-search, /pr"
Write-Host "  > /brave-search   # Test the MCP integration"
Write-Host ""
Write-Host "To check MCP server status:"
Write-Host "  claude mcp list"
