# setup.ps1
# Path: claude-code-config/setup.ps1
#
# Creates symlinks from this repo to ~/.claude/ for global Claude Code configuration.
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

Write-Host "Creating symlinks..."

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
Write-Host "Setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Optional next steps:" -ForegroundColor Yellow
Write-Host "  1. Add Brave Search MCP (user scope):"
Write-Host "     claude mcp add brave-search --scope user ```"
Write-Host "       -e BRAVE_API_KEY='`${BRAVE_API_KEY}' ```"
Write-Host "       -- npx -y @brave/brave-search-mcp-server"
Write-Host ""
Write-Host "  2. Set BRAVE_API_KEY in System Environment Variables"
Write-Host ""
Write-Host "  3. Verify in any project:"
Write-Host "     claude"
Write-Host "     > /help  (should show /web-search, /brave-search, /pr)"
