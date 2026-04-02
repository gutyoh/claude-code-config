# setup.ps1
# Path: claude-code-config/setup.ps1
#
# Creates symlinks from this repo to ~/.claude/ for global Claude Code configuration.
# Optionally configures MCP servers, agents, and skills in user scope.
# Run this script from inside the repo directory. Safe to re-run if you move the repo.
#
# Modular architecture: dot-sources modules from lib/setup-ps/ (mirrors setup.sh + lib/setup/).
#
# Usage: .\setup.ps1 [options]
#   -Yes                   Accept all defaults without prompting
#   -Mcp LIST              Comma-separated MCP servers to install (brave-search,tavily)
#   -NoMcp                 Skip all MCP server installation
#   -NoAgents              Skip agents & skills installation
#   -AgentTeams            Enable agent teams (experimental)
#   -NoAgentTeams          Disable agent teams
#   -ProxyPath             Add bin/ to PATH (default)
#   -NoProxyPath           Skip proxy launcher PATH setup
#   -Minimal               Core only (no agents, skills, MCP, agent teams, or proxy PATH)
#   -OverwriteSettings     Replace settings.json with repo defaults
#   -SkipSettings          Don't modify settings.json
#   -Theme THEME           Statusline color theme (dark|light|colorblind|none)
#   -Components LIST       Comma-separated statusline components
#   -BarStyle STYLE        Progress bar style (text|block|smooth|gradient|thin|spark)
#   -BarPctInside          Show percentage inside the bar
#   -Compact               Compact mode (no labels, merged tokens -- default)
#   -NoCompact             Verbose mode (labels, separate tokens, burn rate)
#   -ColorScope SCOPE      Color scope: percentage or full
#   -Icon ICON             Prefix icon (none|spark|anthropic|sparkle|star|custom)
#   -IconStyle STYLE       Icon style (plain|bold|bracketed|rounded|reverse|bold-color|angle|double-bracket)
#   -WeeklyShowReset       Show weekly reset countdown inline
#   -NoWeeklyShowReset     Hide weekly reset countdown (default)
#   -Help                  Show this help message
#
# Platforms: Windows (PowerShell 5.1+, PowerShell 7+ recommended)

param(
    [switch]$Yes,
    [string]$Mcp,
    [switch]$NoMcp,
    [switch]$NoAgents,
    [switch]$AgentTeams,
    [switch]$NoAgentTeams,
    [switch]$ProxyPath,
    [switch]$NoProxyPath,
    [switch]$Minimal,
    [switch]$OverwriteSettings,
    [switch]$SkipSettings,
    [ValidateSet("dark", "light", "colorblind", "none")]
    [string]$Theme,
    [string]$Components,
    [ValidateSet("text", "block", "smooth", "gradient", "thin", "spark")]
    [string]$BarStyle,
    [switch]$BarPctInside,
    [switch]$Compact,
    [switch]$NoCompact,
    [ValidateSet("percentage", "full")]
    [string]$ColorScope,
    [string]$Icon,
    [ValidateSet("plain", "bold", "bracketed", "rounded", "reverse", "bold-color", "angle", "double-bracket")]
    [string]$IconStyle,
    [switch]$WeeklyShowReset,
    [switch]$NoWeeklyShowReset,
    [Alias("h")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# --- Constants ---

$script:RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ClaudeDir = "$env:USERPROFILE\.claude"
$script:SettingsJson = "$env:USERPROFILE\.claude\settings.json"
$script:ClaudeJson = "$env:USERPROFILE\.claude.json"
$script:StatuslineConf = "$env:USERPROFILE\.claude\statusline.conf"

# --- Component Registry ---

$script:AllComponentKeys = @(
    "model", "usage", "weekly", "reset", "tokens_in", "tokens_out", "tokens_cache",
    "cost", "burn_rate", "email", "cc_status", "version", "lines", "session_time", "cwd"
)

$script:AllComponentDescs = @(
    "Model name (opus-4.5)",
    "Session utilization (5h)",
    "Weekly utilization (7d)",
    "Reset countdown timer",
    "Input tokens count",
    "Output tokens count",
    "Cache read tokens",
    "Session cost in USD",
    "Burn rate (USD/hr)",
    "Account email address",
    "Claude Code service status",
    "Claude Code version",
    "Lines added/removed",
    "Session elapsed time",
    "Working directory"
)

$script:DefaultComponentIndices = @(0, 1, 2, 3, 4, 5, 6, 7, 8, 9) # first 10

# --- Installation Options (defaults) ---

$script:InstallAgentsSkills = $true
$script:InstallMcpServers = @("brave-search", "tavily")
$script:SettingsMode = "merge"                          # merge | overwrite | skip
$script:StatuslineTheme = "dark"
$script:StatuslineComponents = "model,usage,weekly,reset,tokens_in,tokens_out,tokens_cache,cost,burn_rate,email"
$script:StatuslineBarStyle = "text"
$script:StatuslineBarPctInside = $false
$script:StatuslineCompact = $true
$script:StatuslineColorScope = "percentage"
$script:StatuslineIcon = ""
$script:StatuslineIconStyle = "plain"
$script:StatuslineWeeklyShowReset = $false
$script:StatuslineCcStatusPosition = "inline"
$script:StatuslineCcStatusVisibility = "always"
$script:StatuslineCcStatusColor = "full"
$script:InstallAgentTeamsFlag = $true
$script:InstallProxyPath = $true
$script:AcceptDefaults = $false
$script:UserCustomizedStatusline = $false

# --- Source Modules ---

$setupPsDir = Join-Path $script:RepoDir "lib" "setup-ps"
. (Join-Path $setupPsDir "output.ps1")
. (Join-Path $setupPsDir "tui.ps1")
. (Join-Path $setupPsDir "preview.ps1")
. (Join-Path $setupPsDir "filesystem.ps1")
. (Join-Path $setupPsDir "settings.ps1")
. (Join-Path $setupPsDir "statusline-conf.ps1")
. (Join-Path $setupPsDir "mcp.ps1")
. (Join-Path $setupPsDir "menu.ps1")

# --- Apply CLI Flags ---

if ($Minimal) {
    $script:InstallAgentsSkills = $false
    $script:InstallMcpServers = @()
    $script:InstallAgentTeamsFlag = $false
    $script:InstallProxyPath = $false
}
if ($NoAgents) { $script:InstallAgentsSkills = $false }
if ($NoMcp) { $script:InstallMcpServers = @() }
if ($Mcp) {
    $script:InstallMcpServers = $Mcp -split ',' | ForEach-Object { $_.Trim() }
    foreach ($m in $script:InstallMcpServers) {
        if ($m -notin $script:McpServerKeys) {
            Write-Status "Error: Unknown MCP server '${m}'. Available: $($script:McpServerKeys -join ', ')" -Color Red
            exit 1
        }
    }
}
if ($AgentTeams) { $script:InstallAgentTeamsFlag = $true }
if ($NoAgentTeams) { $script:InstallAgentTeamsFlag = $false }
if ($ProxyPath) { $script:InstallProxyPath = $true }
if ($NoProxyPath) { $script:InstallProxyPath = $false }
if ($OverwriteSettings) { $script:SettingsMode = "overwrite" }
if ($SkipSettings) { $script:SettingsMode = "skip" }
if ($Yes) { $script:AcceptDefaults = $true }

# Statusline options from CLI
if ($Theme) { $script:StatuslineTheme = $Theme }
if ($Components) { $script:StatuslineComponents = $Components }
if ($BarStyle) { $script:StatuslineBarStyle = $BarStyle }
if ($BarPctInside) { $script:StatuslineBarPctInside = $true }
if ($Compact) { $script:StatuslineCompact = $true }
if ($NoCompact) { $script:StatuslineCompact = $false }
if ($ColorScope) { $script:StatuslineColorScope = $ColorScope }
if ($Icon) {
    switch ($Icon) {
        "none"       { $script:StatuslineIcon = "" }
        "spark"      { $script:StatuslineIcon = [string][char]0x273B }
        "anthropic"  { $script:StatuslineIcon = "A\" }
        "sparkle"    { $script:StatuslineIcon = [string][char]0x2747 }
        "star"       { $script:StatuslineIcon = [string][char]0x2726 }
        default      { $script:StatuslineIcon = $Icon }
    }
}
if ($IconStyle) { $script:StatuslineIconStyle = $IconStyle }
if ($WeeklyShowReset) { $script:StatuslineWeeklyShowReset = $true }
if ($NoWeeklyShowReset) { $script:StatuslineWeeklyShowReset = $false }

# --- Help ---

if ($Help) {
    Write-Status "Usage: .\setup.ps1 [options]"
    Write-Status ""
    Write-Status "Creates symlinks from this repo to ~/.claude/ for global Claude Code configuration."
    Write-Status ""
    Write-Status "Options:"
    Write-Status "  -Yes                   Accept all defaults without prompting"
    Write-Status "  -Mcp LIST              Comma-separated MCP servers to install (brave-search,tavily)"
    Write-Status "  -NoMcp                 Skip all MCP server installation"
    Write-Status "  -NoAgents              Skip agents & skills installation"
    Write-Status "  -AgentTeams            Enable agent teams (experimental)"
    Write-Status "  -NoAgentTeams          Disable agent teams"
    Write-Status "  -ProxyPath             Add bin/ to PATH (default)"
    Write-Status "  -NoProxyPath           Skip proxy launcher PATH setup"
    Write-Status "  -Minimal               Core only (no agents, skills, MCP, agent teams, or proxy PATH)"
    Write-Status "  -OverwriteSettings     Replace settings.json with repo defaults"
    Write-Status "  -SkipSettings          Don't modify settings.json"
    Write-Status "  -Theme THEME           Statusline color theme (dark|light|colorblind|none)"
    Write-Status "  -Components LIST       Comma-separated statusline components"
    Write-Status "  -BarStyle STYLE        Progress bar style (text|block|smooth|gradient|thin|spark)"
    Write-Status "  -BarPctInside          Show percentage inside the bar"
    Write-Status "  -Compact               Compact mode (no labels, merged tokens -- default)"
    Write-Status "  -NoCompact             Verbose mode (labels, separate tokens, burn rate)"
    Write-Status "  -ColorScope SCOPE      Color scope: percentage or full"
    Write-Status "  -Icon ICON             Prefix icon (none|spark|anthropic|sparkle|star|custom)"
    Write-Status "  -IconStyle STYLE       Icon style (plain|bold|bracketed|rounded|reverse|bold-color|angle|double-bracket)"
    Write-Status "  -WeeklyShowReset       Show weekly reset countdown inline"
    Write-Status "  -NoWeeklyShowReset     Hide weekly reset countdown (default)"
    Write-Status "  -Help                  Show this help message"
    Write-Status ""
    Write-Status "Available components:"
    Write-Status "  model, usage, weekly, reset, tokens_in, tokens_out, tokens_cache,"
    Write-Status "  cost, burn_rate, email, cc_status, version, lines, session_time, cwd"
    Write-Status ""
    Write-Status "Available MCP servers:"
    Write-Status "  brave-search, tavily"
    Write-Status ""
    Write-Status "Examples:"
    Write-Status "  .\setup.ps1                     # Interactive mode (recommended)"
    Write-Status "  .\setup.ps1 -Yes                # Full install, no prompts"
    Write-Status "  .\setup.ps1 -Yes -NoMcp         # Full install without MCP servers"
    Write-Status "  .\setup.ps1 -Yes -Mcp brave-search  # Only install Brave Search MCP"
    Write-Status "  .\setup.ps1 -Yes -Minimal       # Core only (hooks, scripts)"
    Write-Status "  .\setup.ps1 -Yes -Theme colorblind  # Full install with colorblind theme"
    Write-Status "  .\setup.ps1 -Yes -BarStyle block -BarPctInside -Components model,usage,cost"
    Write-Status "  .\setup.ps1 -OverwriteSettings  # Interactive, but force-overwrite settings.json"
    exit 0
}

# ============================================================================
# Main
# ============================================================================

Write-Status "Claude Code Config Setup" -Color Cyan
Write-Status "========================" -Color Cyan
Write-Status "Repo location: $($script:RepoDir)"
Write-Status ""

# Check prerequisites
Write-Status "Checking prerequisites..."

Test-Prerequisite "jq" "jq" $false "required for hooks and statusline" | Out-Null
Test-Prerequisite "python" "python3" $false "used by some hooks" | Out-Null
Test-Prerequisite "fd" "fd" $false "optional: for faster file suggestions" | Out-Null
Test-Prerequisite "fzf" "fzf" $false "optional: for faster file suggestions" | Out-Null
Test-Prerequisite "ccusage" "ccusage" $false "optional: for statusline billing tracking" | Out-Null

Write-Status ""

# Create ~/.claude if it doesn't exist
if (-not (Test-Path $script:ClaudeDir)) {
    New-Item -ItemType Directory -Path $script:ClaudeDir -Force | Out-Null
    Write-Status "Created $($script:ClaudeDir)"
}

# Show interactive menu (unless -Yes flag was passed)
if (-not $script:AcceptDefaults) {
    Show-InstallMenu
}

Write-Status ""

$step = 0

# --- Create symlinks ---
$step++
Write-Status "Step ${step}: Creating symlinks..." -Color Yellow

Initialize-Symlink -Source "$($script:RepoDir)\.claude\hooks" -Target "$($script:ClaudeDir)\hooks" -Name "hooks"
Initialize-Symlink -Source "$($script:RepoDir)\.claude\scripts" -Target "$($script:ClaudeDir)\scripts" -Name "scripts"

# --- Install bin/ utilities ---
$binDir = "$env:USERPROFILE\.local\bin"
if (-not (Test-Path $binDir)) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
}

foreach ($util in @("mcp-key-rotate", "mcp-env-inject")) {
    $source = "$($script:RepoDir)\bin\${util}"
    if (Test-Path $source) {
        Copy-Item $source "$binDir\${util}" -Force
        Write-Status "  + ~/.local/bin/${util} -> ${source}" -Color Green
    }
    else {
        Write-Status "  ! bin/${util} not found (skipping)" -Color Yellow
    }
}

if ($script:InstallAgentsSkills) {
    Initialize-Symlink -Source "$($script:RepoDir)\.claude\skills" -Target "$($script:ClaudeDir)\skills" -Name "skills"
    Initialize-Symlink -Source "$($script:RepoDir)\.claude\agents" -Target "$($script:ClaudeDir)\agents" -Name "agents"
}
else {
    Write-Status "  - Skipping agents & skills (not selected)" -Color DarkGray
}

Write-Status ""

# --- Configure settings.json ---
if ($script:SettingsMode -eq "overwrite") {
    $step++
    Write-Status "Step ${step}: Overwriting settings.json with repo defaults..." -Color Yellow
    Write-Status ""

    Copy-Item "$($script:RepoDir)\.claude\settings.json" $script:SettingsJson -Force
    Write-Status "  + settings.json replaced with repo defaults" -Color Green

    Write-Status ""

    $step++
    Write-Status "Step ${step}: Configuring file suggestion (user scope)..." -Color Yellow
    Write-Status ""

    if ((Get-Command fd -ErrorAction SilentlyContinue) -and (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Update-FileSuggestion
    }
    else {
        Write-Status "  ! Skipping file suggestion (fd and fzf not installed)" -Color Yellow
        Write-Status "    Install with: scoop install fd fzf" -Color DarkGray
    }

    Write-Status ""

    $step++
    Write-Status "Step ${step}: Configuring statusline config..." -Color Yellow
    Write-Status ""

    Update-StatuslineConf -Force $true

    Write-Status ""

    $step++
    Write-Status "Step ${step}: Configuring agent teams..." -Color Yellow
    Write-Status ""

    Update-AgentTeam
}
elseif ($script:SettingsMode -eq "merge") {
    $step++
    Write-Status "Step ${step}: Configuring hooks (user scope)..." -Color Yellow
    Write-Status ""

    if (-not (Test-Path $script:SettingsJson)) {
        Write-Status "  Creating ~/.claude/settings.json with default hooks..."
        $hookConfig = [PSCustomObject]@{
            hooks = [PSCustomObject]@{
                PreToolUse = @(
                    [PSCustomObject]@{
                        matcher = "mcp__ide__getDiagnostics"
                        hooks   = @(
                            [PSCustomObject]@{
                                type    = "command"
                                command = "~/.claude/hooks/open-file-in-ide.sh"
                            }
                        )
                    }
                )
            }
        }
        $hookConfig | ConvertTo-Json -Depth 10 | Set-Content $script:SettingsJson -Encoding UTF8
        Write-Status "  + IDE diagnostics hook configured" -Color Green
    }
    else {
        Update-IdeHook
    }

    Write-Status ""

    $step++
    Write-Status "Step ${step}: Configuring file suggestion (user scope)..." -Color Yellow
    Write-Status ""

    if ((Get-Command fd -ErrorAction SilentlyContinue) -and (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Update-FileSuggestion
    }
    else {
        Write-Status "  ! Skipping file suggestion (fd and fzf not installed)" -Color Yellow
        Write-Status "    Install with: scoop install fd fzf" -Color DarkGray
    }

    Write-Status ""

    $step++
    Write-Status "Step ${step}: Configuring statusline (user scope)..." -Color Yellow
    Write-Status ""

    Update-Statusline

    if (-not (Get-Command ccusage -ErrorAction SilentlyContinue)) {
        Write-Status ""
        Write-Status "  Note: Install ccusage for full statusline functionality:" -Color DarkGray
        Write-Status "    npm install -g ccusage" -Color DarkGray
    }

    Write-Status ""

    $step++
    Write-Status "Step ${step}: Configuring statusline config..." -Color Yellow
    Write-Status ""

    Update-StatuslineConf -Force $script:UserCustomizedStatusline

    Write-Status ""

    $step++
    Write-Status "Step ${step}: Configuring agent teams..." -Color Yellow
    Write-Status ""

    Update-AgentTeam
}
else {
    $step++
    Write-Status "Step ${step}: Skipping settings.json configuration (not selected)" -Color DarkGray
}

Write-Status ""

# --- Configure proxy launcher PATH ---
if ($script:InstallProxyPath) {
    $step++
    Write-Status "Step ${step}: Configuring proxy launcher PATH..." -Color Yellow
    Write-Status ""

    Update-ProxyPath
}
else {
    $step++
    Write-Status "Step ${step}: Skipping proxy launcher PATH (not selected)" -Color DarkGray
}

Write-Status ""

# --- Configure MCP servers ---
if ($script:InstallMcpServers.Count -gt 0) {
    $step++
    Write-Status "Step ${step}: Configuring MCP servers (user scope)..." -Color Yellow
    Write-Status ""

    Install-McpServer

    Write-Status ""

    $step++
    Write-Status "Step ${step}: Environment variables" -Color Yellow
    Write-Status ""

    Test-McpEnvVar
}
else {
    $step++
    Write-Status "Step ${step}: Skipping MCP servers (not selected)" -Color DarkGray
}

Write-Status ""
Write-Status "========================================" -Color Cyan
Write-Status "Setup complete!" -Color Green
Write-Status "========================================" -Color Cyan
Write-Status ""
Write-Status "Verify in any project:"
Write-Status "  cd ~\some-project"
Write-Status "  claude"
Write-Status "  > /help           # Should show available skills"

if ($script:InstallMcpServers.Count -gt 0) {
    foreach ($key in $script:InstallMcpServers) {
        switch ($key) {
            "brave-search" { Write-Status "  > /brave-search   # Test Brave Search MCP" }
            "tavily" { Write-Status "  > /tavily-search  # Test Tavily MCP" }
        }
    }
    Write-Status ""
    Write-Status "To check MCP server status:"
    Write-Status "  claude mcp list"
}
