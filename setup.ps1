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

# Create symlinks
New-Item -ItemType SymbolicLink -Path "$ClaudeDir\commands" -Target "$RepoDir\.claude\commands" -Force | Out-Null
Write-Host "  + $ClaudeDir\commands -> $RepoDir\.claude\commands" -ForegroundColor Green

New-Item -ItemType SymbolicLink -Path "$ClaudeDir\skills" -Target "$RepoDir\.claude\skills" -Force | Out-Null
Write-Host "  + $ClaudeDir\skills -> $RepoDir\.claude\skills" -ForegroundColor Green

New-Item -ItemType SymbolicLink -Path "$ClaudeDir\agents" -Target "$RepoDir\.claude\agents" -Force | Out-Null
Write-Host "  + $ClaudeDir\agents -> $RepoDir\.claude\agents" -ForegroundColor Green

New-Item -ItemType SymbolicLink -Path "$ClaudeDir\hooks" -Target "$RepoDir\.claude\hooks" -Force | Out-Null
Write-Host "  + $ClaudeDir\hooks -> $RepoDir\.claude\hooks" -ForegroundColor Green

Write-Host ""
Write-Host "Step 2: Configuring MCP servers (user scope)..." -ForegroundColor Yellow
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
Write-Host "Step 3: Environment variables" -ForegroundColor Yellow
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
