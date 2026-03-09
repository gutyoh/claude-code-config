# setup.ps1
# Path: claude-code-config/setup.ps1
#
# Creates symlinks from this repo to ~/.claude/ for global Claude Code configuration.
# Optionally configures MCP servers, agents, and skills in user scope.
# Run this script from inside the repo directory as Administrator.
# Safe to re-run if you move the repo.
#
# Usage: .\setup.ps1 [options]
#   -Yes                   Accept all defaults without prompting
#   -Mcp LIST              Comma-separated MCP servers to install (brave-search,tavily)
#   -NoMcp                 Skip all MCP server installation
#   -NoAgents              Skip agents & skills installation
#   -AgentTeams            Enable agent teams (experimental)
#   -NoAgentTeams          Disable agent teams
#   -NoProxyPath           Skip proxy launcher PATH setup
#   -Minimal               Core only (no agents, skills, MCP, agent teams, or proxy PATH)
#   -OverwriteSettings     Replace settings.json with repo defaults
#   -SkipSettings          Don't modify settings.json
#   -Theme THEME           Statusline color theme (dark|light|colorblind|none)
#   -Components LIST       Comma-separated statusline components
#   -BarStyle STYLE        Progress bar style (text|block|smooth|gradient|thin|spark)
#   -BarPctInside          Show percentage inside the bar
#   -Compact               Compact mode (no labels, merged tokens - default)
#   -NoCompact             Verbose mode (labels, separate tokens, burn rate)
#   -ColorScope SCOPE      Color scope: percentage or full
#   -Icon ICON             Prefix icon (none|spark|anthropic|sparkle|star|custom)
#   -IconStyle STYLE       Icon style (plain|bold|bracketed|rounded|reverse|bold-color|angle|double-bracket)
#   -WeeklyShowReset       Show weekly reset countdown inline
#   -Help                  Show this help message

param(
    [switch]$Yes,
    [string]$Mcp,
    [switch]$NoMcp,
    [switch]$NoAgents,
    [switch]$AgentTeams,
    [switch]$NoAgentTeams,
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
    [Alias("h")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# --- Constants ---

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir = "$env:USERPROFILE\.claude"
$SettingsJson = "$env:USERPROFILE\.claude\settings.json"
$ClaudeJson = "$env:USERPROFILE\.claude.json"
$StatuslineConf = "$env:USERPROFILE\.claude\statusline.conf"
$McpKeysEnvFile = "$env:USERPROFILE\.claude\mcp-keys.env"

# --- MCP Server Registry ---

$McpServers = @{
    "brave-search" = @{
        label      = "brave-search"
        desc       = "Web, image, video, news, local search (1,000/mo free)"
        env_var    = "BRAVE_API_KEY"
        package    = "@brave/brave-search-mcp-server"
        signup_url = "https://api-dashboard.search.brave.com/"
        free_limit = "1,000 searches/month (`$5 free credits)"
    }
    "tavily"       = @{
        label      = "tavily"
        desc       = "AI-native search, extract, crawl, map, research (1,000/mo free)"
        env_var    = "TAVILY_API_KEY"
        package    = "tavily-mcp@0.2.17"
        signup_url = "https://tavily.com"
        free_limit = "1,000 credits/month"
    }
}

$McpServerKeys = @("brave-search", "tavily")

# --- Component Registry ---

$AllComponentKeys = @(
    "model", "usage", "weekly", "reset", "tokens_in", "tokens_out", "tokens_cache",
    "cost", "burn_rate", "email", "cc_status", "version", "lines", "session_time", "cwd"
)

$AllComponentDescs = @(
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

# --- Installation Options (defaults) ---

$InstallAgentsSkills = $true
$InstallMcpServers = @("brave-search", "tavily")
$SettingsMode = "merge"  # merge | overwrite | skip
$StatuslineTheme = "dark"
$StatuslineComponents = "model,usage,weekly,reset,tokens_in,tokens_out,tokens_cache,cost,burn_rate,email"
$StatuslineBarStyle = "text"
$StatuslineBarPctInside = $false
$StatuslineCompact = $true
$StatuslineColorScope = "percentage"
$StatuslineIcon = ""
$StatuslineIconStyle = "plain"
$StatuslineWeeklyShowReset = $false
$StatuslineCcStatusPosition = "inline"
$StatuslineCcStatusVisibility = "always"
$StatuslineCcStatusColor = "full"
$InstallAgentTeamsFlag = $true
$InstallProxyPath = $true
$AcceptDefaults = $false
$UserCustomizedStatusline = $false

# --- Apply flags ---

if ($Minimal) {
    $InstallAgentsSkills = $false
    $InstallMcpServers = @()
    $InstallAgentTeamsFlag = $false
    $InstallProxyPath = $false
}
if ($NoAgents) {
    $InstallAgentsSkills = $false
}
if ($NoMcp) {
    $InstallMcpServers = @()
}
if ($Mcp) {
    $InstallMcpServers = $Mcp -split ',' | ForEach-Object { $_.Trim() }
    foreach ($m in $InstallMcpServers) {
        if ($m -notin $McpServerKeys) {
            Write-Host "Error: Unknown MCP server '$m'. Available: $($McpServerKeys -join ', ')" -ForegroundColor Red
            exit 1
        }
    }
}
if ($AgentTeams) {
    $InstallAgentTeamsFlag = $true
}
if ($NoAgentTeams) {
    $InstallAgentTeamsFlag = $false
}
if ($NoProxyPath) {
    $InstallProxyPath = $false
}
if ($OverwriteSettings) {
    $SettingsMode = "overwrite"
}
if ($SkipSettings) {
    $SettingsMode = "skip"
}
if ($Yes) {
    $AcceptDefaults = $true
}

# Statusline options from CLI
if ($Theme) { $StatuslineTheme = $Theme }
if ($Components) { $StatuslineComponents = $Components }
if ($BarStyle) { $StatuslineBarStyle = $BarStyle }
if ($BarPctInside) { $StatuslineBarPctInside = $true }
if ($Compact) { $StatuslineCompact = $true }
if ($NoCompact) { $StatuslineCompact = $false }
if ($ColorScope) { $StatuslineColorScope = $ColorScope }
if ($Icon) {
    switch ($Icon) {
        "none" { $StatuslineIcon = "" }
        "spark" { $StatuslineIcon = [char]0x273B }  # heavy teardrop spoked asterisk
        "anthropic" { $StatuslineIcon = "A\" }
        "sparkle" { $StatuslineIcon = [char]0x2747 }
        "star" { $StatuslineIcon = [char]0x2726 }
        default { $StatuslineIcon = $Icon }
    }
}
if ($IconStyle) { $StatuslineIconStyle = $IconStyle }
if ($WeeklyShowReset) { $StatuslineWeeklyShowReset = $true }

# --- Functions ---

function Show-Usage {
    Write-Host "Usage: .\setup.ps1 [options]"
    Write-Host ""
    Write-Host "Creates symlinks from this repo to ~/.claude/ for global Claude Code configuration."
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Yes                   Accept all defaults without prompting"
    Write-Host "  -Mcp LIST              Comma-separated MCP servers to install (brave-search,tavily)"
    Write-Host "  -NoMcp                 Skip all MCP server installation"
    Write-Host "  -NoAgents              Skip agents & skills installation"
    Write-Host "  -AgentTeams            Enable agent teams (experimental)"
    Write-Host "  -NoAgentTeams          Disable agent teams"
    Write-Host "  -NoProxyPath           Skip proxy launcher PATH setup"
    Write-Host "  -Minimal               Core only (no agents, skills, MCP, agent teams, or proxy PATH)"
    Write-Host "  -OverwriteSettings     Replace settings.json with repo defaults"
    Write-Host "  -SkipSettings          Don't modify settings.json"
    Write-Host "  -Theme THEME           Statusline color theme (dark|light|colorblind|none)"
    Write-Host "  -Components LIST       Comma-separated statusline components"
    Write-Host "  -BarStyle STYLE        Progress bar style (text|block|smooth|gradient|thin|spark)"
    Write-Host "  -BarPctInside          Show percentage inside the bar"
    Write-Host "  -Compact               Compact mode (no labels, merged tokens - default)"
    Write-Host "  -NoCompact             Verbose mode (labels, separate tokens, burn rate)"
    Write-Host "  -ColorScope SCOPE      Color scope: percentage or full"
    Write-Host "  -Icon ICON             Prefix icon (none|spark|anthropic|sparkle|star|custom)"
    Write-Host "  -IconStyle STYLE       Icon style (plain|bold|bracketed|rounded|reverse|bold-color|angle|double-bracket)"
    Write-Host "  -WeeklyShowReset       Show weekly reset countdown inline"
    Write-Host "  -Help                  Show this help message"
    Write-Host ""
    Write-Host "Available components:"
    Write-Host "  model, usage, weekly, reset, tokens_in, tokens_out, tokens_cache,"
    Write-Host "  cost, burn_rate, email, cc_status, version, lines, session_time, cwd"
    Write-Host ""
    Write-Host "Available MCP servers:"
    Write-Host "  brave-search, tavily"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\setup.ps1                     # Interactive mode (recommended)"
    Write-Host "  .\setup.ps1 -Yes                # Full install, no prompts"
    Write-Host "  .\setup.ps1 -Yes -NoMcp         # Full install without MCP servers"
    Write-Host "  .\setup.ps1 -Yes -Mcp brave-search  # Only install Brave Search MCP"
    Write-Host "  .\setup.ps1 -Yes -Minimal       # Core only (hooks, scripts)"
    Write-Host "  .\setup.ps1 -Yes -Theme colorblind  # Full install with colorblind theme"
    Write-Host "  .\setup.ps1 -OverwriteSettings  # Interactive, but force-overwrite settings.json"
}

function Check-Prerequisite {
    param(
        [string]$Cmd,
        [string]$Label,
        [bool]$Required = $false,
        [string]$InstallHint = ""
    )

    $cmdPath = Get-Command $Cmd -ErrorAction SilentlyContinue
    if (-not $cmdPath) {
        $msg = "  ! $Label not found"
        if ($InstallHint) { $msg += " ($InstallHint)" }
        Write-Host $msg -ForegroundColor Yellow
        if ($InstallHint) {
            Write-Host "    Install with: scoop install $Cmd"
            Write-Host "    Or: winget install $Cmd"
        }
        if ($Required) {
            Write-Host "    Setup cannot continue without $Cmd." -ForegroundColor Red
            exit 1
        }
        Write-Host ""
        return $false
    }
    else {
        Write-Host "  + $Label installed" -ForegroundColor Green
        return $true
    }
}

function Show-InstallMenu {
    $agentsLabel = if ($script:InstallAgentsSkills) { "yes" } else { "no" }
    $settingsLabel = switch ($script:SettingsMode) {
        "overwrite" { "overwrite (replace with repo defaults)" }
        "skip" { "skip (don't modify)" }
        default { "merge (preserve existing, add new)" }
    }
    $mcpLabel = if ($script:InstallMcpServers.Count -gt 0) { $script:InstallMcpServers -join ", " } else { "none" }
    $teamsLabel = if ($script:InstallAgentTeamsFlag) { "yes" } else { "no" }
    $proxyLabel = if ($script:InstallProxyPath) { "yes" } else { "no" }
    $compactLabel = if ($script:StatuslineCompact) { "yes" } else { "no" }
    $pctLabel = if ($script:StatuslineBarPctInside) { "yes" } else { "no" }
    $iconLabel = if ($script:StatuslineIcon) { $script:StatuslineIcon } else { "none" }
    $weeklyResetLabel = if ($script:StatuslineWeeklyShowReset) { "yes" } else { "no" }

    $compDisplay = $script:StatuslineComponents -replace ',', ', '
    if ($compDisplay.Length -gt 50) { $compDisplay = $compDisplay.Substring(0, 47) + "..." }

    Write-Host "Current installation options:"
    Write-Host "  core (hooks, scripts):            always"
    Write-Host "  agents & skills:                  $agentsLabel"
    Write-Host "  MCP search servers:               $mcpLabel"
    Write-Host "  agent teams (experimental):       $teamsLabel"
    Write-Host "  proxy launcher PATH:              $proxyLabel"
    Write-Host "  settings.json:                    $settingsLabel"
    Write-Host "  statusline color theme:           $($script:StatuslineTheme)"
    Write-Host "  statusline components:            $compDisplay"
    Write-Host "  statusline compact mode:          $compactLabel"
    Write-Host "  statusline color scope:           $($script:StatuslineColorScope)"
    Write-Host "  statusline bar style:             $($script:StatuslineBarStyle)"
    Write-Host "  statusline pct inside bar:        $pctLabel"
    Write-Host "  statusline icon:                  $iconLabel"
    Write-Host "  statusline icon style:            $($script:StatuslineIconStyle)"
    Write-Host "  statusline weekly reset:          $weeklyResetLabel"
    Write-Host ""
    Write-Host "1) Proceed with installation (default - just press enter)"
    Write-Host "2) Customize installation"
    Write-Host "3) Cancel installation"
    Write-Host ""

    $choice = Read-Host ">"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }

    switch ($choice) {
        "1" {
            # Use current options
        }
        "2" {
            Invoke-CustomizeInstallation
        }
        "3" {
            Write-Host "Installation cancelled."
            exit 0
        }
        default {
            Write-Host "Invalid option. Using current options."
        }
    }
}

function Invoke-CustomizeInstallation {
    Write-Host ""

    # Agents & Skills
    $answer = Read-Host "Install agents & skills? [Y/n]"
    if ($answer -eq "n" -or $answer -eq "N") {
        $script:InstallAgentsSkills = $false
    }
    else {
        $script:InstallAgentsSkills = $true
    }

    # MCP Servers (multi-select)
    Write-Host ""
    Write-Host "MCP search servers (enter numbers separated by comma, or 'none'):"
    for ($i = 0; $i -lt $McpServerKeys.Count; $i++) {
        $key = $McpServerKeys[$i]
        $desc = $McpServers[$key].desc
        $selected = if ($key -in $script:InstallMcpServers) { "[x]" } else { "[ ]" }
        Write-Host "  $($i + 1). $selected $key - $desc"
    }
    Write-Host ""
    $answer = Read-Host "Enter selection (e.g., '1,2' or 'all' or 'none') [default: all]"
    if ([string]::IsNullOrWhiteSpace($answer) -or $answer -eq "all") {
        $script:InstallMcpServers = $McpServerKeys.Clone()
    }
    elseif ($answer -eq "none") {
        $script:InstallMcpServers = @()
    }
    else {
        $script:InstallMcpServers = @()
        $nums = $answer -split ',' | ForEach-Object { $_.Trim() }
        foreach ($n in $nums) {
            $idx = [int]$n - 1
            if ($idx -ge 0 -and $idx -lt $McpServerKeys.Count) {
                $script:InstallMcpServers += $McpServerKeys[$idx]
            }
        }
    }

    # Agent Teams
    $answer = Read-Host "Enable agent teams? (experimental) [Y/n]"
    if ($answer -eq "n" -or $answer -eq "N") {
        $script:InstallAgentTeamsFlag = $false
    }
    else {
        $script:InstallAgentTeamsFlag = $true
    }

    # Proxy PATH
    $answer = Read-Host "Add proxy launcher (bin/) to PATH? [Y/n]"
    if ($answer -eq "n" -or $answer -eq "N") {
        $script:InstallProxyPath = $false
    }
    else {
        $script:InstallProxyPath = $true
    }

    # Settings mode
    Write-Host ""
    Write-Host "Settings.json mode:"
    Write-Host "  [m]erge     - Preserve existing settings, add new (default)"
    Write-Host "  [o]verwrite - Replace with repo defaults"
    Write-Host "  [s]kip      - Don't modify settings.json"
    Write-Host ""
    $answer = Read-Host "Settings mode [m/o/s] (default: m)"
    if ([string]::IsNullOrWhiteSpace($answer)) { $answer = "m" }

    switch ($answer.ToLower()) {
        "o" { $script:SettingsMode = "overwrite" }
        "s" { $script:SettingsMode = "skip" }
        default { $script:SettingsMode = "merge" }
    }

    # Statusline customization
    Invoke-CustomizeStatusline
    $script:UserCustomizedStatusline = $true
}

function Invoke-CustomizeStatusline {
    Write-Host ""
    Write-Host "=== Statusline Customization ===" -ForegroundColor Cyan
    Write-Host ""

    # Theme
    Write-Host "Statusline color theme:"
    Write-Host "  1. dark       - Yellow/red on dark background (default)"
    Write-Host "  2. light      - Blue/red on light background"
    Write-Host "  3. colorblind - Bold yellow/magenta, accessible (no red/green)"
    Write-Host "  4. none       - No colors"
    $answer = Read-Host "Select [1-4] (default: 1)"
    switch ($answer) {
        "2" { $script:StatuslineTheme = "light" }
        "3" { $script:StatuslineTheme = "colorblind" }
        "4" { $script:StatuslineTheme = "none" }
        default { $script:StatuslineTheme = "dark" }
    }

    # Compact mode
    $answer = Read-Host "Compact mode? (no labels, merged tokens) [Y/n]"
    if ($answer -eq "n" -or $answer -eq "N") {
        $script:StatuslineCompact = $false
    }
    else {
        $script:StatuslineCompact = $true
    }

    # Color scope
    Write-Host ""
    Write-Host "Color scope (which part gets colored by utilization):"
    Write-Host "  1. percentage - Color only the usage/percentage component (default)"
    Write-Host "  2. full       - Color the entire statusline"
    $answer = Read-Host "Select [1-2] (default: 1)"
    if ($answer -eq "2") {
        $script:StatuslineColorScope = "full"
    }
    else {
        $script:StatuslineColorScope = "percentage"
    }

    # Components (multi-select)
    Write-Host ""
    Write-Host "Statusline components (enter numbers separated by comma):"
    $currentComps = $script:StatuslineComponents -split ','
    for ($i = 0; $i -lt $AllComponentKeys.Count; $i++) {
        $key = $AllComponentKeys[$i]
        $desc = $AllComponentDescs[$i]
        $selected = if ($key -in $currentComps) { "[x]" } else { "[ ]" }
        Write-Host "  $($i + 1). $selected $key - $desc"
    }
    Write-Host ""
    $answer = Read-Host "Enter selection (e.g., '1,2,3,4,5,6,7,8,9,10' or 'all') [default: keep current]"
    if (-not [string]::IsNullOrWhiteSpace($answer)) {
        if ($answer -eq "all") {
            $script:StatuslineComponents = $AllComponentKeys -join ','
        }
        else {
            $selectedComps = @()
            $nums = $answer -split ',' | ForEach-Object { $_.Trim() }
            foreach ($n in $nums) {
                $idx = [int]$n - 1
                if ($idx -ge 0 -and $idx -lt $AllComponentKeys.Count) {
                    $selectedComps += $AllComponentKeys[$idx]
                }
            }
            if ($selectedComps.Count -gt 0) {
                $script:StatuslineComponents = $selectedComps -join ','
            }
        }
    }

    # Bar Style
    Write-Host ""
    Write-Host "Progress bar style:"
    Write-Host "  1. text      session: 42% used (default)"
    Write-Host "  2. block     [########............] 42%"
    Write-Host "  3. smooth    ########.            42% (1/8th precision)"
    Write-Host "  4. gradient  ########..           42%"
    Write-Host "  5. thin      --------....         42%"
    Write-Host "  6. spark     ##... 42%            (compact 5-char)"
    $answer = Read-Host "Select [1-6] (default: 1)"
    switch ($answer) {
        "2" { $script:StatuslineBarStyle = "block" }
        "3" { $script:StatuslineBarStyle = "smooth" }
        "4" { $script:StatuslineBarStyle = "gradient" }
        "5" { $script:StatuslineBarStyle = "thin" }
        "6" { $script:StatuslineBarStyle = "spark" }
        default { $script:StatuslineBarStyle = "text" }
    }

    # Pct inside bar (only for styles that support it)
    if ($script:StatuslineBarStyle -ne "text" -and $script:StatuslineBarStyle -ne "spark") {
        $answer = Read-Host "Show percentage inside the bar? [y/N]"
        if ($answer -eq "y" -or $answer -eq "Y") {
            $script:StatuslineBarPctInside = $true
        }
        else {
            $script:StatuslineBarPctInside = $false
        }
    }

    # Weekly reset (only if weekly component selected)
    if ($script:StatuslineComponents -match "weekly") {
        $answer = Read-Host "Show weekly reset countdown inline? (e.g. 63% (4d2h)) [y/N]"
        if ($answer -eq "y" -or $answer -eq "Y") {
            $script:StatuslineWeeklyShowReset = $true
        }
        else {
            $script:StatuslineWeeklyShowReset = $false
        }
    }

    # CC Status config (only if cc_status selected)
    if ($script:StatuslineComponents -match "cc_status") {
        Write-Host ""
        Write-Host "Claude Code status position:"
        Write-Host "  1. inline   - After email on same line (default)"
        Write-Host "  2. newline  - Separate second line"
        $answer = Read-Host "Select [1-2] (default: 1)"
        if ($answer -eq "2") {
            $script:StatuslineCcStatusPosition = "newline"
        }
        else {
            $script:StatuslineCcStatusPosition = "inline"
        }

        Write-Host ""
        Write-Host "Claude Code status visibility:"
        Write-Host "  1. always        - Always show status (default)"
        Write-Host "  2. problem_only  - Only show when there is a problem"
        $answer = Read-Host "Select [1-2] (default: 1)"
        if ($answer -eq "2") {
            $script:StatuslineCcStatusVisibility = "problem_only"
        }
        else {
            $script:StatuslineCcStatusVisibility = "always"
        }

        Write-Host ""
        Write-Host "Claude Code status color:"
        Write-Host "  1. none        - Plain text, no color"
        Write-Host "  2. full        - Color the status label (default)"
        if ($script:StatuslineCcStatusPosition -eq "newline") {
            Write-Host "  3. status_only - Color only the status label"
        }
        $answer = Read-Host "Select (default: 2)"
        switch ($answer) {
            "1" { $script:StatuslineCcStatusColor = "none" }
            "3" {
                if ($script:StatuslineCcStatusPosition -eq "newline") {
                    $script:StatuslineCcStatusColor = "status_only"
                }
                else { $script:StatuslineCcStatusColor = "full" }
            }
            default { $script:StatuslineCcStatusColor = "full" }
        }
    }

    # Icon
    Write-Host ""
    Write-Host "Statusline prefix icon:"
    Write-Host "  1. none        (no icon - default)"
    Write-Host "  2. spark       Claude spark teardrop asterisk"
    Write-Host "  3. anthropic   A\ (text logo)"
    Write-Host "  4. sparkle     sparkle symbol"
    Write-Host "  5. star        four-pointed star"
    $answer = Read-Host "Select [1-5] (default: 1)"
    switch ($answer) {
        "2" { $script:StatuslineIcon = [char]0x273B }
        "3" { $script:StatuslineIcon = "A\" }
        "4" { $script:StatuslineIcon = [char]0x2747 }
        "5" { $script:StatuslineIcon = [char]0x2726 }
        default { $script:StatuslineIcon = "" }
    }

    # Icon Style (only if icon selected)
    if ($script:StatuslineIcon) {
        Write-Host ""
        Write-Host "Icon style:"
        Write-Host "  1. plain          (as-is - default)"
        Write-Host "  2. bold           (bold weight)"
        Write-Host "  3. bracketed      [icon]"
        Write-Host "  4. rounded        (icon)"
        Write-Host "  5. reverse        (inverted background)"
        Write-Host "  6. bold-color     (bold + blue accent)"
        Write-Host "  7. angle          <icon>"
        Write-Host "  8. double-bracket [[icon]]"
        $answer = Read-Host "Select [1-8] (default: 1)"
        switch ($answer) {
            "2" { $script:StatuslineIconStyle = "bold" }
            "3" { $script:StatuslineIconStyle = "bracketed" }
            "4" { $script:StatuslineIconStyle = "rounded" }
            "5" { $script:StatuslineIconStyle = "reverse" }
            "6" { $script:StatuslineIconStyle = "bold-color" }
            "7" { $script:StatuslineIconStyle = "angle" }
            "8" { $script:StatuslineIconStyle = "double-bracket" }
            default { $script:StatuslineIconStyle = "plain" }
        }
    }

    # Show preview
    Show-StatuslinePreview
}

function Show-StatuslinePreview {
    Write-Host ""
    Write-Host "--- Statusline Preview ---" -ForegroundColor Cyan

    $iconPrefix = ""
    if ($script:StatuslineIcon) {
        switch ($script:StatuslineIconStyle) {
            "bracketed" { $iconPrefix = "[$($script:StatuslineIcon)] " }
            "rounded" { $iconPrefix = "($($script:StatuslineIcon)) " }
            "angle" { $iconPrefix = "<$($script:StatuslineIcon)> " }
            "double-bracket" { $iconPrefix = "[[$($script:StatuslineIcon)]] " }
            default { $iconPrefix = "$($script:StatuslineIcon) " }
        }
    }

    $parts = @()
    $comps = $script:StatuslineComponents -split ','
    $isCompact = $script:StatuslineCompact

    foreach ($key in $comps) {
        switch ($key) {
            "model" { $parts += "opus-4.5" }
            "usage" {
                if ($isCompact -and $script:StatuslineBarStyle -eq "text") {
                    $parts += "42%"
                }
                else {
                    $parts += "session: 42% used"
                }
            }
            "weekly" {
                $w = if ($isCompact) { "63%" } else { "weekly: 63%" }
                if ($script:StatuslineWeeklyShowReset) { $w += " (4d2h)" }
                $parts += $w
            }
            "reset" { $parts += if ($isCompact) { "2h15m" } else { "resets: 2h15m" } }
            "tokens_in" { $parts += if ($isCompact) { "15.4k" } else { "in: 15.4k" } }
            "tokens_out" { $parts += if ($isCompact) { "2.1k" } else { "out: 2.1k" } }
            "tokens_cache" { $parts += if ($isCompact) { "6.2M" } else { "cache: 6.2M" } }
            "cost" { $parts += "`$5.21" }
            "burn_rate" { if (-not $isCompact) { $parts += "(`$2.99/hr)" } }
            "email" { $parts += "user@email.com" }
            "cc_status" { $parts += "on" }
            "version" { $parts += "v2.0.37" }
            "lines" { $parts += "+2109 -103" }
            "session_time" { $parts += "37m" }
            "cwd" { $parts += "~/project" }
        }
    }

    $preview = $iconPrefix + ($parts -join " | ")
    Write-Host "  $preview" -ForegroundColor White
    Write-Host ""
}

function Create-SafeSymlink {
    param(
        [string]$Source,
        [string]$Target,
        [string]$Name
    )

    # Resolve real paths to detect if we're IN the repo
    $ClaudeReal = (Resolve-Path $ClaudeDir -ErrorAction SilentlyContinue).Path
    $RepoClaudeReal = (Resolve-Path "$RepoDir\.claude" -ErrorAction SilentlyContinue).Path

    # If ~/.claude IS the repo's .claude directory, skip symlink creation
    if ($ClaudeReal -eq $RepoClaudeReal) {
        Write-Host "  + $Name (same as repo, no symlink needed)" -ForegroundColor Green
        return
    }

    # Check if symlink already exists and points to correct location
    if (Test-Path $Target) {
        $item = Get-Item $Target -Force
        if ($item.LinkType -eq "SymbolicLink") {
            $currentTarget = $item.Target
            if ($currentTarget -eq $Source) {
                Write-Host "  + $Name -> $Source (already configured)" -ForegroundColor Green
                return
            }
        }
        # Remove existing (file, directory, or wrong symlink)
        Remove-Item $Target -Force -Recurse -ErrorAction SilentlyContinue
    }

    # Create fresh symlink
    try {
        New-Item -ItemType SymbolicLink -Path $Target -Target $Source -Force | Out-Null
        Write-Host "  + $Name -> $Source" -ForegroundColor Green
    }
    catch {
        Write-Host "  ! Failed to create symlink for $Name. Run as Administrator." -ForegroundColor Red
        Write-Host "    Error: $_" -ForegroundColor Yellow
    }
}

function Configure-IdeHook {
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
        }
        else {
            Write-Host "  Adding IDE diagnostics hook to existing settings..."

            if (-not $settings.hooks) {
                $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue @{ } -Force
            }
            if (-not $settings.hooks.PreToolUse) {
                $settings.hooks | Add-Member -NotePropertyName "PreToolUse" -NotePropertyValue @() -Force
            }

            $ideHook = @{
                matcher = "mcp__ide__getDiagnostics"
                hooks   = @(
                    @{
                        type    = "command"
                        command = "~/.claude/hooks/open-file-in-ide.sh"
                    }
                )
            }

            $preToolUse = [System.Collections.ArrayList]@($settings.hooks.PreToolUse)
            $preToolUse.Add($ideHook) | Out-Null
            $settings.hooks.PreToolUse = $preToolUse

            $settings | ConvertTo-Json -Depth 10 | Set-Content $SettingsJson -Encoding UTF8
            Write-Host "  + IDE diagnostics hook added" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "  ! Failed to add hook: $_" -ForegroundColor Yellow
    }
}

function Configure-FileSuggestion {
    try {
        $settings = Get-Content $SettingsJson -Raw | ConvertFrom-Json

        if ($settings.fileSuggestion) {
            Write-Host "  + File suggestion already configured" -ForegroundColor Green
        }
        else {
            Write-Host "  Adding file suggestion to settings..."

            $settings | Add-Member -NotePropertyName "fileSuggestion" -NotePropertyValue @{
                type    = "command"
                command = "~/.claude/scripts/file-suggestion.ps1"
            } -Force

            $settings | ConvertTo-Json -Depth 10 | Set-Content $SettingsJson -Encoding UTF8
            Write-Host "  + File suggestion configured" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "  ! Failed to add file suggestion: $_" -ForegroundColor Yellow
    }
}

function Configure-Statusline {
    try {
        $settings = Get-Content $SettingsJson -Raw | ConvertFrom-Json

        if ($settings.statusLine) {
            Write-Host "  + Statusline already configured" -ForegroundColor Green
        }
        else {
            Write-Host "  Adding statusline to settings..."

            $settings | Add-Member -NotePropertyName "statusLine" -NotePropertyValue @{
                type    = "command"
                command = "~/.claude/scripts/statusline.sh"
                padding = 0
            } -Force

            $settings | ConvertTo-Json -Depth 10 | Set-Content $SettingsJson -Encoding UTF8
            Write-Host "  + Statusline configured" -ForegroundColor Green

            Write-Host ""
            Write-Host "  Note: Statusline requires bash (via WSL or Git Bash on Windows)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  ! Failed to add statusline: $_" -ForegroundColor Yellow
    }
}

function Configure-StatuslineConf {
    param([bool]$Force = $false)

    if (Test-Path $StatuslineConf) {
        if (-not $Force) {
            Write-Host "  + Statusline config already exists (preserved)" -ForegroundColor Green
            return
        }
    }

    $content = @"
theme=$StatuslineTheme
components=$StatuslineComponents
bar_style=$StatuslineBarStyle
bar_pct_inside=$($StatuslineBarPctInside.ToString().ToLower())
compact=$($StatuslineCompact.ToString().ToLower())
color_scope=$StatuslineColorScope
icon=$StatuslineIcon
icon_style=$StatuslineIconStyle
weekly_show_reset=$($StatuslineWeeklyShowReset.ToString().ToLower())
cc_status_position=$StatuslineCcStatusPosition
cc_status_visibility=$StatuslineCcStatusVisibility
cc_status_color=$StatuslineCcStatusColor
"@

    $content | Set-Content $StatuslineConf -Encoding UTF8
    Write-Host "  + Statusline config written (theme=$StatuslineTheme, bar=$StatuslineBarStyle)" -ForegroundColor Green
}

function Configure-AgentTeams {
    try {
        $settings = Get-Content $SettingsJson -Raw | ConvertFrom-Json

        if ($script:InstallAgentTeamsFlag) {
            $currentValue = $null
            if ($settings.env) {
                $currentValue = $settings.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
            }

            if ($currentValue -eq "1") {
                Write-Host "  + Agent teams already enabled" -ForegroundColor Green
            }
            else {
                Write-Host "  Adding agent teams env to settings..."

                if (-not $settings.env) {
                    $settings | Add-Member -NotePropertyName "env" -NotePropertyValue @{ } -Force
                }
                $settings.env | Add-Member -NotePropertyName "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" -NotePropertyValue "1" -Force

                $settings | ConvertTo-Json -Depth 10 | Set-Content $SettingsJson -Encoding UTF8
                Write-Host "  + Agent teams enabled" -ForegroundColor Green
            }
        }
        else {
            if ($settings.env -and $settings.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS) {
                $settings.env.PSObject.Properties.Remove("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS")
                if ($settings.env.PSObject.Properties.Count -eq 0) {
                    $settings.PSObject.Properties.Remove("env")
                }
                $settings | ConvertTo-Json -Depth 10 | Set-Content $SettingsJson -Encoding UTF8
                Write-Host "  + Agent teams disabled (removed from settings)" -ForegroundColor Green
            }
            else {
                Write-Host "  - Agent teams not enabled (nothing to remove)" -ForegroundColor DarkGray
            }
        }
    }
    catch {
        Write-Host "  ! Failed to configure agent teams: $_" -ForegroundColor Yellow
    }
}

function Configure-ProxyPath {
    $binDir = "$RepoDir\bin"

    # Get current user PATH
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")

    if ($currentPath -split ';' -contains $binDir) {
        Write-Host "  + Proxy launcher PATH already configured" -ForegroundColor Green
    }
    else {
        Write-Host "  Adding $binDir to user PATH..."
        $newPath = "$binDir;$currentPath"
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        Write-Host "  + Proxy launcher PATH added to user environment" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Open a new terminal, then run:" -ForegroundColor Yellow
        Write-Host "    claude-proxy --help"
    }
}

function Configure-McpServers {
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claudeCmd) {
        Write-Host "  ! Claude Code CLI not found. Install it first:" -ForegroundColor Yellow
        Write-Host "    irm https://claude.ai/install.ps1 | iex"
        Write-Host ""
        Write-Host "  After installing, re-run this script or manually add MCP servers."
        return
    }

    foreach ($key in $script:InstallMcpServers) {
        $server = $McpServers[$key]
        $envVar = $server.env_var
        $package = $server.package

        # Check if already configured
        $mcpList = & claude mcp list 2>$null
        if ($mcpList -match $key) {
            Write-Host "  + $key MCP already configured" -ForegroundColor Green
        }
        else {
            Write-Host "  Adding $key MCP server..."
            try {
                # Use cmd wrapper for npx on Windows
                & claude mcp add $key --scope user `
                    -e "$envVar=`${$envVar}" `
                    -- cmd /c npx -y $package 2>$null
                Write-Host "  + $key MCP added to user scope" -ForegroundColor Green
            }
            catch {
                Write-Host "  ! Failed to add $key MCP. You can add it manually:" -ForegroundColor Yellow
                Write-Host "    claude mcp add $key --scope user ``"
                Write-Host "      -e $envVar='`${$envVar}' ``"
                Write-Host "      -- cmd /c npx -y $package"
            }
        }
    }

    # Create mcp-keys.env file
    Create-McpKeysEnv
}

function Create-McpKeysEnv {
    Write-Host ""
    Write-Host "  Creating $McpKeysEnvFile..."

    $keysWritten = 0
    $envContent = ""

    foreach ($key in $script:InstallMcpServers) {
        $server = $McpServers[$key]
        $envVar = $server.env_var
        $envVal = [Environment]::GetEnvironmentVariable($envVar)

        # Also check process environment
        if (-not $envVal) {
            $envVal = (Get-Item "Env:$envVar" -ErrorAction SilentlyContinue).Value
        }

        if ($envVal) {
            $envContent += "$envVar=$envVal`n"
            $keysWritten++
            Write-Host "  + $envVar written ($($envVal.Length) chars)" -ForegroundColor Green
        }
        else {
            Write-Host "  ! $envVar not found - add it later with:" -ForegroundColor Yellow
            Write-Host "    Add-Content $McpKeysEnvFile '$envVar=YOUR_KEY'"
            Write-Host "    Get a key: $($server.signup_url)"
        }
    }

    if ($keysWritten -gt 0) {
        $envContent | Set-Content $McpKeysEnvFile -Encoding UTF8
        Write-Host ""
        Write-Host "  + $McpKeysEnvFile created ($keysWritten keys)" -ForegroundColor Green
    }
    else {
        Write-Host ""
        Write-Host "  ! No MCP keys found. Add them to $McpKeysEnvFile before using MCP servers." -ForegroundColor Yellow
    }
}

function Check-McpEnvVars {
    if (Test-Path $McpKeysEnvFile) {
        foreach ($key in $script:InstallMcpServers) {
            $server = $McpServers[$key]
            $envVar = $server.env_var

            $content = Get-Content $McpKeysEnvFile -Raw
            if ($content -match "^$envVar=") {
                Write-Host "  + $envVar found in $McpKeysEnvFile" -ForegroundColor Green
            }
            else {
                Write-Host "  ! $envVar missing from $McpKeysEnvFile" -ForegroundColor Yellow
                Write-Host "    Add-Content $McpKeysEnvFile '$envVar=YOUR_KEY'"
                Write-Host "    Get a free API key ($($server.free_limit)): $($server.signup_url)"
            }
        }
    }
    else {
        # Check environment variables directly
        foreach ($key in $script:InstallMcpServers) {
            $server = $McpServers[$key]
            $envVar = $server.env_var
            $envVal = [Environment]::GetEnvironmentVariable($envVar)

            if ($envVal) {
                Write-Host "  + $envVar is set ($($envVal.Length) chars)" -ForegroundColor Green
            }
            else {
                Write-Host "  ! $envVar not set." -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  Set it in System Environment Variables:"
                Write-Host "    1. Open System Properties > Advanced > Environment Variables"
                Write-Host "    2. Under User variables, click New"
                Write-Host "    3. Set $envVar with your API key value"
                Write-Host ""
                Write-Host "  Get a free API key ($($server.free_limit)):"
                Write-Host "    $($server.signup_url)"
            }
        }
    }
}

function Install-BinUtilities {
    $binDir = "$env:USERPROFILE\.local\bin"
    if (-not (Test-Path $binDir)) {
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    }

    $utilities = @("mcp-key-rotate", "mcp-env-inject")

    foreach ($util in $utilities) {
        $source = "$RepoDir\bin\$util"
        $target = "$binDir\$util"

        if (Test-Path $source) {
            Copy-Item $source $target -Force
            Write-Host "  + $util -> $target" -ForegroundColor Green
        }
        else {
            Write-Host "  ! $util not found in repo bin/ (skipping)" -ForegroundColor Yellow
        }
    }
}

# --- Main ---

if ($Help) {
    Show-Usage
    exit 0
}

Write-Host "Claude Code Config Setup" -ForegroundColor Cyan
Write-Host "========================" -ForegroundColor Cyan
Write-Host "Repo location: $RepoDir"
Write-Host ""

# Check prerequisites
Write-Host "Checking prerequisites..."

Check-Prerequisite "python" "python3" $false "required for settings configuration"
Check-Prerequisite "fd" "fd" $false "optional: for faster file suggestions"
Check-Prerequisite "fzf" "fzf" $false "optional: for faster file suggestions"
Check-Prerequisite "ccusage" "ccusage" $false "optional: for statusline billing tracking"

Write-Host ""

# Create ~/.claude if it doesn't exist
if (-not (Test-Path $ClaudeDir)) {
    New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
    Write-Host "Created $ClaudeDir"
}

# Show interactive menu (unless -Yes flag was passed)
if (-not $AcceptDefaults) {
    Show-InstallMenu
}

Write-Host ""

$step = 0

# --- Create symlinks ---
$step++
Write-Host "Step ${step}: Creating symlinks..." -ForegroundColor Yellow

Create-SafeSymlink -Source "$RepoDir\.claude\hooks" -Target "$ClaudeDir\hooks" -Name "hooks"
Create-SafeSymlink -Source "$RepoDir\.claude\scripts" -Target "$ClaudeDir\scripts" -Name "scripts"

# Install bin utilities
$binDir = "$env:USERPROFILE\.local\bin"
if (-not (Test-Path $binDir)) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
}

$utilities = @("mcp-key-rotate", "mcp-env-inject")
foreach ($util in $utilities) {
    $source = "$RepoDir\bin\$util"
    if (Test-Path $source) {
        Copy-Item $source "$binDir\$util" -Force
        Write-Host "  + ~/.local/bin/$util -> $source" -ForegroundColor Green
    }
    else {
        Write-Host "  ! bin/$util not found (skipping)" -ForegroundColor Yellow
    }
}

if ($InstallAgentsSkills) {
    Create-SafeSymlink -Source "$RepoDir\.claude\skills" -Target "$ClaudeDir\skills" -Name "skills"
    Create-SafeSymlink -Source "$RepoDir\.claude\agents" -Target "$ClaudeDir\agents" -Name "agents"
}
else {
    Write-Host "  - Skipping agents & skills (not selected)" -ForegroundColor DarkGray
}

Write-Host ""

# --- Configure settings.json ---
if ($SettingsMode -eq "overwrite") {
    $step++
    Write-Host "Step ${step}: Overwriting settings.json with repo defaults..." -ForegroundColor Yellow
    Write-Host ""

    Copy-Item "$RepoDir\.claude\settings.json" $SettingsJson -Force
    Write-Host "  + settings.json replaced with repo defaults" -ForegroundColor Green

    Write-Host ""

    # File suggestion
    $step++
    Write-Host "Step ${step}: Configuring file suggestion (user scope)..." -ForegroundColor Yellow
    Write-Host ""

    $fdCmd = Get-Command fd -ErrorAction SilentlyContinue
    $fzfCmd = Get-Command fzf -ErrorAction SilentlyContinue

    if ($fdCmd -and $fzfCmd) {
        Configure-FileSuggestion
    }
    else {
        Write-Host "  ! Skipping file suggestion (fd and fzf not installed)" -ForegroundColor Yellow
        Write-Host "    Install with: scoop install fd fzf"
        Write-Host "    Or: winget install sharkdp.fd junegunn.fzf"
    }

    Write-Host ""

    # Statusline config
    $step++
    Write-Host "Step ${step}: Configuring statusline config..." -ForegroundColor Yellow
    Write-Host ""

    Configure-StatuslineConf -Force $true

    Write-Host ""

    # Agent teams
    $step++
    Write-Host "Step ${step}: Configuring agent teams..." -ForegroundColor Yellow
    Write-Host ""

    Configure-AgentTeams

}
elseif ($SettingsMode -eq "merge") {
    # Hooks
    $step++
    Write-Host "Step ${step}: Configuring hooks (user scope)..." -ForegroundColor Yellow
    Write-Host ""

    if (-not (Test-Path $SettingsJson)) {
        Write-Host "  Creating settings.json with default hooks..."
        $hookConfig = @{
            hooks = @{
                PreToolUse = @(
                    @{
                        matcher = "mcp__ide__getDiagnostics"
                        hooks   = @(
                            @{
                                type    = "command"
                                command = "~/.claude/hooks/open-file-in-ide.sh"
                            }
                        )
                    }
                )
            }
        }
        $hookConfig | ConvertTo-Json -Depth 10 | Set-Content $SettingsJson -Encoding UTF8
        Write-Host "  + IDE diagnostics hook configured" -ForegroundColor Green
    }
    else {
        Configure-IdeHook
    }

    Write-Host ""

    # File suggestion
    $step++
    Write-Host "Step ${step}: Configuring file suggestion (user scope)..." -ForegroundColor Yellow
    Write-Host ""

    $fdCmd = Get-Command fd -ErrorAction SilentlyContinue
    $fzfCmd = Get-Command fzf -ErrorAction SilentlyContinue

    if ($fdCmd -and $fzfCmd) {
        Configure-FileSuggestion
    }
    else {
        Write-Host "  ! Skipping file suggestion (fd and fzf not installed)" -ForegroundColor Yellow
        Write-Host "    Install with: scoop install fd fzf"
        Write-Host "    Or: winget install sharkdp.fd junegunn.fzf"
    }

    Write-Host ""

    # Statusline
    $step++
    Write-Host "Step ${step}: Configuring statusline (user scope)..." -ForegroundColor Yellow
    Write-Host ""

    $ccusageCmd = Get-Command ccusage -ErrorAction SilentlyContinue
    if (-not $ccusageCmd) {
        Write-Host "  ! ccusage not found (optional: for statusline billing tracking)" -ForegroundColor Yellow
        Write-Host "    Install with: npm install -g ccusage"
        Write-Host ""
    }

    Configure-Statusline

    Write-Host ""

    # Statusline config
    $step++
    Write-Host "Step ${step}: Configuring statusline config..." -ForegroundColor Yellow
    Write-Host ""

    Configure-StatuslineConf -Force $UserCustomizedStatusline

    Write-Host ""

    # Agent teams
    $step++
    Write-Host "Step ${step}: Configuring agent teams..." -ForegroundColor Yellow
    Write-Host ""

    Configure-AgentTeams

}
else {
    $step++
    Write-Host "Step ${step}: Skipping settings.json configuration (not selected)" -ForegroundColor DarkGray
}

Write-Host ""

# --- Configure proxy launcher PATH ---
if ($InstallProxyPath) {
    $step++
    Write-Host "Step ${step}: Configuring proxy launcher PATH..." -ForegroundColor Yellow
    Write-Host ""

    Configure-ProxyPath
}
else {
    $step++
    Write-Host "Step ${step}: Skipping proxy launcher PATH (not selected)" -ForegroundColor DarkGray
}

Write-Host ""

# --- Configure MCP servers ---
if ($InstallMcpServers.Count -gt 0) {
    $step++
    Write-Host "Step ${step}: Configuring MCP servers (user scope)..." -ForegroundColor Yellow
    Write-Host ""

    Configure-McpServers

    Write-Host ""

    $step++
    Write-Host "Step ${step}: Environment variables" -ForegroundColor Yellow
    Write-Host ""

    Check-McpEnvVars
}
else {
    $step++
    Write-Host "Step ${step}: Skipping MCP servers (not selected)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Setup complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Verify in any project:"
Write-Host "  cd ~\some-project"
Write-Host "  claude"
Write-Host "  > /help           # Should show available skills"

if ($InstallMcpServers.Count -gt 0) {
    foreach ($key in $InstallMcpServers) {
        switch ($key) {
            "brave-search" { Write-Host "  > /brave-search   # Test Brave Search MCP" }
            "tavily" { Write-Host "  > /tavily-search  # Test Tavily MCP" }
        }
    }
    Write-Host ""
    Write-Host "To check MCP server status:"
    Write-Host "  claude mcp list"
}
