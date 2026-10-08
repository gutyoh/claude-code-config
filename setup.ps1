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
#   -ProxyPath             Add bin/ to PATH and install claude/clp shortcuts (default)
#   -NoProxyPath           Skip proxy launcher PATH and shortcut setup
#   -Minimal               Core only (no agents, skills, MCP, agent teams, proxy PATH, or OpenCode)
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
#   -WithOpenCode          Force OpenCode parallel install (default: auto-detect)
#   -NoOpenCode            Skip OpenCode setup (default: auto-detect)
#   -Help                  Show this help message
#
# setup.sh's --shell has no counterpart: shortcuts there edit a Unix login
# shell's profile, which Windows does not have.
#
# Platforms: Windows (PowerShell 5.1+, PowerShell 7+ recommended)

#Requires -Version 5.1

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
    [switch]$WithOpenCode,
    [switch]$NoOpenCode,
    [Alias("h")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# --- Constants ---

$script:RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path

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
$script:InstallOpenCode = "auto"                        # auto | yes | no
$script:AcceptDefaults = $false
$script:UserCustomizedStatusline = $false

# --- Source Modules ---

# Two-argument Join-Path only: the -AdditionalChildPath form needs PowerShell 6+.
$setupPsDir = Join-Path (Join-Path $script:RepoDir "lib") "setup-ps"
. (Join-Path $setupPsDir "fileio.ps1")
. (Join-Path $setupPsDir "paths.ps1")
. (Join-Path $setupPsDir "output.ps1")
. (Join-Path $setupPsDir "tui.ps1")
. (Join-Path $setupPsDir "preview.ps1")
. (Join-Path $setupPsDir "filesystem.ps1")
. (Join-Path $setupPsDir "settings.ps1")
. (Join-Path $setupPsDir "statusline-conf.ps1")
. (Join-Path $setupPsDir "mcp.ps1")
. (Join-Path $setupPsDir "opencode.ps1")
. (Join-Path $setupPsDir "menu.ps1")

# --- Paths (CLAUDE_CONFIG_DIR when set, else ~/.claude) ---

$script:ClaudeDir = Get-ClaudeConfigDir
$script:ClaudeDirRef = Get-ClaudeConfigDirRef
$script:SettingsJson = Join-Path $script:ClaudeDir "settings.json"
$script:ClaudeJson = Get-ClaudeJsonPath
$script:StatuslineConf = Join-Path $script:ClaudeDir "statusline.conf"

# --- Apply CLI Flags ---

if ($Minimal) {
    $script:InstallAgentsSkills = $false
    $script:InstallMcpServers = @()
    $script:InstallAgentTeamsFlag = $false
    $script:InstallProxyPath = $false
    $script:InstallOpenCode = "no"
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
if ($WithOpenCode) { $script:InstallOpenCode = "yes" }
if ($NoOpenCode) { $script:InstallOpenCode = "no" }

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
    Write-Status "  -ProxyPath             Add bin/ to PATH and install claude/clp shortcuts (default)"
    Write-Status "  -NoProxyPath           Skip proxy launcher PATH and shortcut setup"
    Write-Status "  -Minimal               Core only (no agents, skills, MCP, agent teams, proxy PATH, or OpenCode)"
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
    Write-Status "  -WithOpenCode          Force OpenCode parallel install (default: auto-detect)"
    Write-Status "  -NoOpenCode            Skip OpenCode setup (default: auto-detect)"
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
    Write-Status "  .\setup.ps1 -Yes -WithOpenCode  # Also set up OpenCode (skills/agents/MCP)"
    Write-Status "  .\setup.ps1 -Yes -NoOpenCode    # Skip OpenCode even if detected"
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

# The hooks and the status line are bash scripts; on Windows Claude Code runs
# them through Git Bash and falls back to PowerShell, which cannot run them.
if (Test-WindowsHost) {
    $gitBash = Find-GitBash
    if ($gitBash) {
        Write-Status "  + Git Bash installed (${gitBash})" -Color Green
    }
    else {
        Write-Status "  ! Git for Windows not found: hooks and the status line will not run without it" -Color Yellow
        Write-Status "    Install with: winget install Git.Git" -Color DarkGray
        Write-Status "    Or point CLAUDE_CODE_GIT_BASH_PATH at an existing bash.exe" -Color DarkGray
    }
}

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

# --- Install managed entries ---
$step++
Write-Status "Step ${step}: Installing managed entries..." -Color Yellow

$repoClaudeDir = Join-Path $script:RepoDir ".claude"
Install-ManagedEntry -SourceDir (Join-Path $repoClaudeDir "hooks") -TargetDir (Join-Path $script:ClaudeDir "hooks") -Name "hooks"
Install-ManagedEntry -SourceDir (Join-Path $repoClaudeDir "scripts") -TargetDir (Join-Path $script:ClaudeDir "scripts") -Name "scripts"

# --- Install bin/ utilities ---
$binDir = Join-Path (Join-Path $HOME ".local") "bin"
if (-not (Test-Path $binDir)) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
}

foreach ($util in @("mcp-key-rotate", "mcp-env-inject")) {
    $source = Join-Path (Join-Path $script:RepoDir "bin") $util
    if (Test-Path $source) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $binDir $util) -Force
        Write-Status "  + ~/.local/bin/${util} -> ${source}" -Color Green
    }
    else {
        Write-Status "  ! bin/${util} not found (skipping)" -Color Yellow
    }
}

# claude-proxy is a bash script that must resolve its real repo location to
# locate sibling files (lib/proxy/preflight.sh, bin/proxy-start-*.sh). A
# plain Copy-Item would break that. We install TWO shims:
#   1. A bash shim at ~/.local/bin/claude-proxy (for Git Bash, MSYS2, WSL)
#   2. A PowerShell companion at ~/.local/bin/claude-proxy.ps1 (so native
#      PowerShell / pwsh users can type `claude-proxy` and have it dispatch
#      to bash automatically)
# Neither requires admin -- same pattern Scoop uses for its shim system.
$claudeProxySource = Join-Path (Join-Path $script:RepoDir "bin") "claude-proxy"
if (Test-Path $claudeProxySource) {
    $shimPath = Join-Path $binDir "claude-proxy"
    # Convert Windows path to the forward-slash form bash accepts
    $bashPath = ($claudeProxySource -replace '\\', '/')
    $shimBody = @"
#!/usr/bin/env bash
# Auto-generated by setup.ps1 -- do not edit. Rerun setup.ps1 to update.
exec "$bashPath" "`$@"
"@
    # LF line endings -- bash chokes on CRLF
    Write-Utf8Text -Path $shimPath -Content ($shimBody -replace "`r`n", "`n")
    Write-Status "  + ~/.local/bin/claude-proxy (bash shim -> ${claudeProxySource})" -Color Green

    # PowerShell companion -- enables `claude-proxy` from PowerShell itself.
    # Locates bash (PATH first, then common Git Bash install dirs) and
    # forwards all args to the bash shim.
    $ps1Path = Join-Path $binDir "claude-proxy.ps1"
    $ps1Body = Get-ClaudeProxyCompanion
    Write-Utf8Text -Path $ps1Path -Content $ps1Body
    Write-Status "  + ~/.local/bin/claude-proxy.ps1 (PowerShell companion)" -Color Green
}
else {
    Write-Status "  ! bin/claude-proxy not found (skipping)" -Color Yellow
}

if ($script:InstallAgentsSkills) {
    Install-ManagedEntry -SourceDir (Join-Path $repoClaudeDir "skills") -TargetDir (Join-Path $script:ClaudeDir "skills") -Name "skills"
    Install-ManagedEntry -SourceDir (Join-Path $repoClaudeDir "agents") -TargetDir (Join-Path $script:ClaudeDir "agents") -Name "agents"
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

    Copy-RepoSetting
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
        Write-Status "  Creating $($script:ClaudeDirRef)/settings.json with default hooks..."
        $hookConfig = [PSCustomObject]@{
            hooks = [PSCustomObject]@{
                PreToolUse = @(
                    [PSCustomObject]@{
                        matcher = "mcp__ide__getDiagnostics"
                        hooks   = @(
                            [PSCustomObject]@{
                                type    = "command"
                                command = "$($script:ClaudeDirRef)/hooks/open-file-in-ide.sh"
                            }
                        )
                    }
                )
            }
        }
        Write-JsonFile -Path $script:SettingsJson -InputObject $hookConfig
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
    Write-Status "Step ${step}: Configuring proxy launcher PATH and shortcuts..." -Color Yellow
    Write-Status ""

    Update-ProxyPath
    Update-ClaudeShortcut -ProfilePath $PROFILE.CurrentUserAllHosts
    Write-Status ""
    Write-Status "  Open a new PowerShell window, then:"
    Write-Status "    claude --help"
    Write-Status "    claude -a"
    Write-Status "    clp -a"
}
else {
    $step++
    Write-Status "Step ${step}: Skipping proxy launcher PATH and shortcuts (not selected)" -Color DarkGray
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

# --- Configure OpenCode parallel install ---
$openCodeResolved = $false
switch ($script:InstallOpenCode) {
    "yes" { $openCodeResolved = $true }
    "no" { $openCodeResolved = $false }
    default { $openCodeResolved = Test-OpenCodeInstalled }
}

$step++
if ($openCodeResolved) {
    Write-Status "Step ${step}: Configuring OpenCode (parallel install)..." -Color Yellow
    Write-Status ""
    Install-OpenCode
}
else {
    Write-Status "Step ${step}: Skipping OpenCode setup ($(Get-OpenCodeDetectLabel))" -Color DarkGray
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

if ($openCodeResolved) {
    Write-Status ""
    Write-Status "OpenCode verify:"
    Write-Status "  cd ~\some-project"
    Write-Status "  opencode"
    Write-Status "  Tab to switch agents -- translated subagents available via @"
    Write-Status "  Config: $(Get-OpenCodeConfigPath)"
}
