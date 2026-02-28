# setup.ps1
# Path: claude-code-config/setup.ps1
#
# Creates symlinks from this repo to ~/.claude/ for global Claude Code configuration.
# Optionally configures MCP servers, agents, and skills in user scope.
# Run this script from inside the repo directory as Administrator.
# Safe to re-run if you move the repo.
#
# Usage: .\setup.ps1 [options]
#   -Yes                 Accept all defaults without prompting
#   -NoMcp               Skip Brave Search MCP server installation
#   -NoAgents            Skip agents & skills installation
#   -Minimal             Core only (no agents, skills, or MCP)
#   -OverwriteSettings   Replace settings.json with repo defaults
#   -SkipSettings        Don't modify settings.json
#   -Help                Show this help message

param(
    [switch]$Yes,
    [switch]$NoMcp,
    [switch]$NoAgents,
    [switch]$Minimal,
    [switch]$OverwriteSettings,
    [switch]$SkipSettings,
    [Alias("h")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# --- Constants ---

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir = "$env:USERPROFILE\.claude"
$SettingsJson = "$env:USERPROFILE\.claude\settings.json"

# --- Installation Options (defaults) ---

$InstallAgentsSkills = $true
$InstallMcp = $true
$SettingsMode = "merge"  # merge | overwrite | skip

# --- Apply flags ---

if ($Minimal) {
    $InstallAgentsSkills = $false
    $InstallMcp = $false
}
if ($NoAgents) {
    $InstallAgentsSkills = $false
}
if ($NoMcp) {
    $InstallMcp = $false
}
if ($OverwriteSettings) {
    $SettingsMode = "overwrite"
}
if ($SkipSettings) {
    $SettingsMode = "skip"
}

# --- Functions ---

function Show-Usage {
    Write-Host "Usage: .\setup.ps1 [options]"
    Write-Host ""
    Write-Host "Creates symlinks from this repo to ~/.claude/ for global Claude Code configuration."
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Yes                 Accept all defaults without prompting"
    Write-Host "  -NoMcp               Skip Brave Search MCP server installation"
    Write-Host "  -NoAgents            Skip agents & skills installation"
    Write-Host "  -Minimal             Core only (no agents, skills, or MCP)"
    Write-Host "  -OverwriteSettings   Replace settings.json with repo defaults"
    Write-Host "  -SkipSettings        Don't modify settings.json"
    Write-Host "  -Help                Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\setup.ps1                     # Interactive mode (recommended)"
    Write-Host "  .\setup.ps1 -Yes                # Full install, no prompts"
    Write-Host "  .\setup.ps1 -Yes -NoMcp         # Full install without Brave Search MCP"
    Write-Host "  .\setup.ps1 -Yes -Minimal       # Core only (hooks, scripts, commands)"
    Write-Host "  .\setup.ps1 -OverwriteSettings  # Interactive, but force-overwrite settings.json"
}

function Show-InstallMenu {
    $agentsLabel = if ($InstallAgentsSkills) { "yes" } else { "no" }
    $mcpLabel = if ($InstallMcp) { "yes" } else { "no" }
    $settingsLabel = switch ($SettingsMode) {
        "overwrite" { "overwrite (replace with repo defaults)" }
        "skip"      { "skip (don't modify)" }
        default     { "merge (preserve existing, add new)" }
    }

    Write-Host "Current installation options:"
    Write-Host "  core (hooks, scripts, commands):  always"
    Write-Host "  agents & skills:                  $agentsLabel"
    Write-Host "  brave search MCP:                 $mcpLabel"
    Write-Host "  settings.json:                    $settingsLabel"
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

    $answer = Read-Host "Install agents & skills? [Y/n]"
    if ($answer -eq "n" -or $answer -eq "N") {
        $script:InstallAgentsSkills = $false
    }

    $answer = Read-Host "Install Brave Search MCP server? [Y/n]"
    if ($answer -eq "n" -or $answer -eq "N") {
        $script:InstallMcp = $false
    }

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
}

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

# --- Main ---

if ($Help) {
    Show-Usage
    exit 0
}

Write-Host "Claude Code Config Setup" -ForegroundColor Cyan
Write-Host "========================" -ForegroundColor Cyan
Write-Host "Repo location: $RepoDir"
Write-Host ""

# Create ~/.claude if it doesn't exist
if (-not (Test-Path $ClaudeDir)) {
    New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
    Write-Host "Created $ClaudeDir"
}

# Show interactive menu (unless -Yes flag was passed)
if (-not $Yes) {
    Show-InstallMenu
}

Write-Host ""

$step = 0

# --- Create symlinks ---
$step++
Write-Host "Step ${step}: Creating symlinks..." -ForegroundColor Yellow

Create-SafeSymlink -Source "$RepoDir\.claude\commands" -Target "$ClaudeDir\commands" -Name "commands"
Create-SafeSymlink -Source "$RepoDir\.claude\hooks" -Target "$ClaudeDir\hooks" -Name "hooks"
Create-SafeSymlink -Source "$RepoDir\.claude\scripts" -Target "$ClaudeDir\scripts" -Name "scripts"

if ($InstallAgentsSkills) {
    Create-SafeSymlink -Source "$RepoDir\.claude\skills" -Target "$ClaudeDir\skills" -Name "skills"
    Create-SafeSymlink -Source "$RepoDir\.claude\agents" -Target "$ClaudeDir\agents" -Name "agents"
} else {
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

    # Add file suggestion on top of overwritten settings (runtime-detected)
    $step++
    Write-Host "Step ${step}: Configuring file suggestion (user scope)..." -ForegroundColor Yellow
    Write-Host ""

    $fdCmd = Get-Command fd -ErrorAction SilentlyContinue
    $fzfCmd = Get-Command fzf -ErrorAction SilentlyContinue

    if ($fdCmd -and $fzfCmd) {
        try {
            $settings = Get-Content $SettingsJson -Raw | ConvertFrom-Json

            if ($settings.fileSuggestion) {
                Write-Host "  + File suggestion already configured" -ForegroundColor Green
            } else {
                Write-Host "  Adding file suggestion to settings..."

                $settings | Add-Member -NotePropertyName "fileSuggestion" -NotePropertyValue @{
                    type = "command"
                    command = "~/.claude/scripts/file-suggestion.ps1"
                } -Force

                $settings | ConvertTo-Json -Depth 10 | Set-Content $SettingsJson -Encoding UTF8
                Write-Host "  + File suggestion configured" -ForegroundColor Green
            }
        } catch {
            Write-Host "  ! Failed to add file suggestion: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ! Skipping file suggestion (fd and fzf not installed)" -ForegroundColor Yellow
        Write-Host "    Install with: scoop install fd fzf"
        Write-Host "    Or: winget install sharkdp.fd junegunn.fzf"
    }

} elseif ($SettingsMode -eq "merge") {
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

    # File suggestion
    $step++
    Write-Host "Step ${step}: Configuring file suggestion (user scope)..." -ForegroundColor Yellow
    Write-Host ""

    $fdCmd = Get-Command fd -ErrorAction SilentlyContinue
    $fzfCmd = Get-Command fzf -ErrorAction SilentlyContinue

    if ($fdCmd -and $fzfCmd) {
        try {
            $settings = Get-Content $SettingsJson -Raw | ConvertFrom-Json

            if ($settings.fileSuggestion) {
                Write-Host "  + File suggestion already configured" -ForegroundColor Green
            } else {
                Write-Host "  Adding file suggestion to settings..."

                $settings | Add-Member -NotePropertyName "fileSuggestion" -NotePropertyValue @{
                    type = "command"
                    command = "~/.claude/scripts/file-suggestion.ps1"
                } -Force

                $settings | ConvertTo-Json -Depth 10 | Set-Content $SettingsJson -Encoding UTF8
                Write-Host "  + File suggestion configured" -ForegroundColor Green
            }
        } catch {
            Write-Host "  ! Failed to add file suggestion: $_" -ForegroundColor Yellow
        }
    } else {
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

    try {
        $settings = Get-Content $SettingsJson -Raw | ConvertFrom-Json

        if ($settings.statusLine) {
            Write-Host "  + Statusline already configured" -ForegroundColor Green
        } else {
            Write-Host "  Adding statusline to settings..."

            $settings | Add-Member -NotePropertyName "statusLine" -NotePropertyValue @{
                type = "command"
                command = "~/.claude/scripts/statusline.sh"
                padding = 0
            } -Force

            $settings | ConvertTo-Json -Depth 10 | Set-Content $SettingsJson -Encoding UTF8
            Write-Host "  + Statusline configured" -ForegroundColor Green

            if (-not $ccusageCmd) {
                Write-Host ""
                Write-Host "  Note: Install ccusage for full statusline functionality:" -ForegroundColor Yellow
                Write-Host "    npm install -g ccusage"
            }

            Write-Host ""
            Write-Host "  Note: Statusline requires bash (via WSL or Git Bash on Windows)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  ! Failed to add statusline: $_" -ForegroundColor Yellow
    }

} else {
    $step++
    Write-Host "Step ${step}: Skipping settings.json configuration (not selected)" -ForegroundColor DarkGray
}

Write-Host ""

# --- Configure MCP servers ---
if ($InstallMcp) {
    $step++
    Write-Host "Step ${step}: Configuring MCP servers (user scope)..." -ForegroundColor Yellow
    Write-Host ""

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
        $mcpList = & claude mcp list 2>$null
        if ($mcpList -match "brave-search") {
            Write-Host "  + brave-search MCP already configured" -ForegroundColor Green
        } else {
            Write-Host "  Adding brave-search MCP server..."
            try {
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

    # Environment variables
    $step++
    Write-Host "Step ${step}: Environment variables" -ForegroundColor Yellow
    Write-Host ""

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
        Write-Host "  Get a free API key (1,000 searches/month, `$5 free credits):"
        Write-Host "    https://api-dashboard.search.brave.com/"
    }
} else {
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

if ($InstallMcp) {
    Write-Host "  > /brave-search   # Test the MCP integration"
    Write-Host ""
    Write-Host "To check MCP server status:"
    Write-Host "  claude mcp list"
}
