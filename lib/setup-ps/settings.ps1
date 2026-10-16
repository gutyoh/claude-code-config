# settings.ps1 -- IDE hook, file suggestion, statusline, and agent teams settings
# Path: lib/setup-ps/settings.ps1
# Dot-sourced by setup.ps1 -- do not execute directly.
#
# PowerShell port of lib/setup/settings.sh
# Uses Update-* verb (approved, no ShouldProcess trigger).

function Update-IdeHook {
    <#
    .SYNOPSIS
    Add the IDE diagnostics hook to settings.json (merge mode).
    #>
    try {
        $settings = Read-Utf8Text $script:SettingsJson | ConvertFrom-Json
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
            Write-Status "  + IDE diagnostics hook already configured" -Color Green
        }
        else {
            Write-Status "  Adding IDE diagnostics hook to existing settings..."

            if (-not $settings.hooks) {
                $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue ([PSCustomObject]@{}) -Force
            }
            if (-not $settings.hooks.PreToolUse) {
                $settings.hooks | Add-Member -NotePropertyName "PreToolUse" -NotePropertyValue @() -Force
            }

            $ideHook = [PSCustomObject]@{
                matcher = "mcp__ide__getDiagnostics"
                hooks   = @(
                    [PSCustomObject]@{
                        type    = "command"
                        command = "$(Get-ClaudeConfigDirRef)/hooks/open-file-in-ide.sh"
                    }
                )
            }

            $preToolUse = [System.Collections.ArrayList]@($settings.hooks.PreToolUse)
            [void]$preToolUse.Add($ideHook)
            $settings.hooks.PreToolUse = @($preToolUse)

            Write-JsonFile -Path $script:SettingsJson -InputObject $settings
            Write-Status "  + IDE diagnostics hook added" -Color Green
        }
    }
    catch {
        Write-Status "  ! Failed to add hook: $_" -Color Yellow
    }
}

function Update-SessionNameHook {
    <#
    .SYNOPSIS
    Add the session naming hooks to settings.json (merge mode); an entry already
    naming hooks/session-name.sh is left as it is.
    #>
    try {
        $settings = Read-Utf8Text $script:SettingsJson | ConvertFrom-Json
        if (-not $settings.hooks) {
            $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue ([PSCustomObject]@{}) -Force
        }

        $added = 0
        foreach ($wanted in @(
                @{ Event = "SessionStart"; Matcher = "startup" },
                @{ Event = "UserPromptSubmit"; Matcher = "" }
            )) {
            $entries = @($settings.hooks.($wanted.Event) | Where-Object { $_ })
            $present = $false
            foreach ($entry in $entries) {
                foreach ($hook in @($entry.hooks)) {
                    if ($hook.command -like "*session-name.sh*") { $present = $true }
                }
            }
            if ($present) { continue }

            $entry = [PSCustomObject]@{
                matcher = $wanted.Matcher
                hooks   = @(
                    [PSCustomObject]@{
                        type    = "command"
                        command = "$(Get-ClaudeConfigDirRef)/hooks/session-name.sh"
                        timeout = 5
                    }
                )
            }
            $list = [System.Collections.ArrayList]@($entries)
            [void]$list.Add($entry)
            $settings.hooks | Add-Member -NotePropertyName $wanted.Event -NotePropertyValue @($list) -Force
            $added++
        }

        if ($added -gt 0) {
            Write-JsonFile -Path $script:SettingsJson -InputObject $settings
            Write-Status "  + Session naming hooks added" -Color Green
        }
        else {
            Write-Status "  + Session naming hooks already configured" -Color Green
        }
    }
    catch {
        Write-Status "  ! Failed to add session naming hooks: $_" -Color Yellow
    }
}

function Update-PublicTextGuardHook {
    <#
    .SYNOPSIS
    Add hooks/guard-public-text.sh on Bash calls (merge mode); it acts only once
    CLAUDE_LEAK_GUARD names a scanner. An entry already naming it stays as it is.
    #>
    try {
        $settings = Read-Utf8Text $script:SettingsJson | ConvertFrom-Json
        if (-not $settings.hooks) {
            $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        $entries = @($settings.hooks.PreToolUse | Where-Object { $_ })
        foreach ($entry in $entries) {
            foreach ($hook in @($entry.hooks)) {
                if ($hook.command -like "*guard-public-text.sh*") {
                    Write-Status "  + Public text guard hook already configured" -Color Green
                    return
                }
            }
        }
        $entry = [PSCustomObject]@{
            matcher = "Bash"
            hooks   = @(
                [PSCustomObject]@{
                    type    = "command"
                    command = "$(Get-ClaudeConfigDirRef)/hooks/guard-public-text.sh"
                    timeout = 30
                }
            )
        }
        $list = [System.Collections.ArrayList]@($entries)
        [void]$list.Add($entry)
        $settings.hooks | Add-Member -NotePropertyName "PreToolUse" -NotePropertyValue @($list) -Force
        Write-JsonFile -Path $script:SettingsJson -InputObject $settings
        Write-Status "  + Public text guard hook added" -Color Green
    }
    catch {
        Write-Status "  ! Failed to add the public text guard hook: $_" -Color Yellow
    }
}

function Update-TranscriptRetention {
    <#
    .SYNOPSIS
    Keep session transcripts for a century unless the user chose a period.
    Claude Code otherwise deletes them after 30 days, and --resume with them.
    #>
    try {
        $settings = Read-Utf8Text $script:SettingsJson | ConvertFrom-Json
        if ($null -ne $settings.PSObject.Properties['cleanupPeriodDays']) {
            Write-Status "  + Transcript retention already set ($($settings.cleanupPeriodDays) days)" -Color Green
        }
        else {
            $settings | Add-Member -NotePropertyName "cleanupPeriodDays" -NotePropertyValue 36500 -Force
            Write-JsonFile -Path $script:SettingsJson -InputObject $settings
            Write-Status "  + Transcripts kept for 36500 days" -Color Green
        }
    }
    catch {
        Write-Status "  ! Failed to set transcript retention: $_" -Color Yellow
    }
}

function Update-SessionPrivacy {
    <#
    .SYNOPSIS
    Commits and pull requests name no claude.ai session link unless the user
    set sessionUrl, and a hand-registered stop-nudge hook, which the
    config-hooks plugin now runs, is removed so it never runs twice.
    #>
    try {
        $settings = Read-Utf8Text $script:SettingsJson | ConvertFrom-Json
        if ($null -eq $settings.PSObject.Properties['attribution']) {
            $settings | Add-Member -NotePropertyName "attribution" -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        if ($null -ne $settings.attribution.PSObject.Properties['sessionUrl']) {
            Write-Status "  + Session links already set (sessionUrl $($settings.attribution.sessionUrl))" -Color Green
        }
        else {
            $settings.attribution | Add-Member -NotePropertyName "sessionUrl" -NotePropertyValue $false -Force
            Write-Status "  + Commits and pull requests name no session link" -Color Green
        }
        $hooks = $settings.PSObject.Properties['hooks']
        if ($null -ne $hooks -and $null -ne $settings.hooks.PSObject.Properties['Stop']) {
            $kept = @()
            $removed = $false
            foreach ($group in @($settings.hooks.Stop)) {
                $rest = @(@($group.hooks) | Where-Object { -not ([string]$_.command).EndsWith('hooks/stop-nudge.sh') })
                if ($rest.Count -ne @($group.hooks).Count) { $removed = $true }
                if ($rest.Count -gt 0) {
                    $group.hooks = $rest
                    $kept += $group
                }
            }
            if ($removed) {
                if ($kept.Count -gt 0) { $settings.hooks.Stop = $kept }
                else { $settings.hooks.PSObject.Properties.Remove('Stop') }
                Write-Status "  + Removed a hand-registered stop-nudge hook; the config-hooks plugin runs it" -Color Green
            }
        }
        Write-JsonFile -Path $script:SettingsJson -InputObject $settings
    }
    catch {
        Write-Status "  ! Failed to set session privacy: $_" -Color Yellow
    }
}

function Update-FileSuggestion {
    <#
    .SYNOPSIS
    Add file suggestion configuration to settings.json.
    #>
    try {
        $settings = Read-Utf8Text $script:SettingsJson | ConvertFrom-Json

        if ($settings.fileSuggestion) {
            Write-Status "  + File suggestion already configured" -Color Green
        }
        else {
            Write-Status "  Adding file suggestion to settings..."

            # Windows always has powershell.exe; elsewhere only pwsh exists.
            $shell = "pwsh"
            if (Test-WindowsHost) { $shell = "powershell.exe" }

            $settings | Add-Member -NotePropertyName "fileSuggestion" -NotePropertyValue ([PSCustomObject]@{
                    type    = "command"
                    command = "${shell} -NoProfile -File `"$(Get-ClaudeConfigDirRef)/scripts/file-suggestion.ps1`""
                }) -Force

            Write-JsonFile -Path $script:SettingsJson -InputObject $settings
            Write-Status "  + File suggestion configured (PowerShell)" -Color Green
        }
    }
    catch {
        Write-Status "  ! Failed to add file suggestion: $_" -Color Yellow
    }
}

function Update-Statusline {
    <#
    .SYNOPSIS
    Add statusline configuration to settings.json.
    #>
    try {
        $settings = Read-Utf8Text $script:SettingsJson | ConvertFrom-Json

        # Redraws on a timer too, so an idle session keeps its countdowns moving
        # and picks up usage other sessions spent. Another statusline is left alone.
        if ($settings.statusLine) {
            $line = $settings.statusLine
            if ($null -eq $line.PSObject.Properties['refreshInterval'] -and "$($line.command)" -like '*/scripts/statusline.sh') {
                $line | Add-Member -NotePropertyName "refreshInterval" -NotePropertyValue 60 -Force
                Write-JsonFile -Path $script:SettingsJson -InputObject $settings
                Write-Status "  + Statusline refreshes every 60s" -Color Green
            }
            else {
                Write-Status "  + Statusline already configured" -Color Green
            }
        }
        else {
            Write-Status "  Adding statusline to settings..."

            $settings | Add-Member -NotePropertyName "statusLine" -NotePropertyValue ([PSCustomObject]@{
                    type    = "command"
                    command         = "$(Get-ClaudeConfigDirRef)/scripts/statusline.sh"
                    padding         = 0
                    refreshInterval = 60
                }) -Force

            Write-JsonFile -Path $script:SettingsJson -InputObject $settings
            Write-Status "  + Statusline configured" -Color Green
        }
    }
    catch {
        Write-Status "  ! Failed to add statusline: $_" -Color Yellow
    }
}

function Update-AgentTeam {
    <#
    .SYNOPSIS
    Enable or disable agent teams in settings.json env block.
    #>
    try {
        $settings = Read-Utf8Text $script:SettingsJson | ConvertFrom-Json

        if ($script:InstallAgentTeamsFlag) {
            $currentValue = $null
            if ($settings.env) {
                $currentValue = $settings.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
            }

            if ($currentValue -eq "1") {
                Write-Status "  + Agent teams already enabled" -Color Green
            }
            else {
                Write-Status "  Adding agent teams env to settings..."

                if (-not $settings.env) {
                    $settings | Add-Member -NotePropertyName "env" -NotePropertyValue ([PSCustomObject]@{}) -Force
                }
                $settings.env | Add-Member -NotePropertyName "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" -NotePropertyValue "1" -Force

                Write-JsonFile -Path $script:SettingsJson -InputObject $settings
                Write-Status "  + Agent teams enabled" -Color Green
            }
        }
        else {
            if ($settings.env -and $settings.env.PSObject.Properties['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS']) {
                $settings.env.PSObject.Properties.Remove("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS")
                if ($settings.env.PSObject.Properties.Count -eq 0) {
                    $settings.PSObject.Properties.Remove("env")
                }
                Write-JsonFile -Path $script:SettingsJson -InputObject $settings
                Write-Status "  + Agent teams disabled (removed from settings)" -Color Green
            }
            else {
                Write-Status "  - Agent teams not enabled (nothing to remove)" -Color DarkGray
            }
        }
    }
    catch {
        Write-Status "  ! Failed to configure agent teams: $_" -Color Yellow
    }
}

function Copy-RepoSetting {
    <#
    .SYNOPSIS
    Replace settings.json with the repo defaults (overwrite mode).
    Command paths are rewritten when CLAUDE_CONFIG_DIR moves the config dir.
    #>
    $text = Read-Utf8Text (Join-Path (Join-Path $script:RepoDir ".claude") "settings.json")
    $ref = Get-ClaudeConfigDirRef
    if ($ref -ne "~/.claude") {
        $text = $text.Replace("~/.claude/", "${ref}/")
    }
    Write-Utf8Text -Path $script:SettingsJson -Content $text
}

function Get-ClaudeProxyCompanion {
    <#
    .SYNOPSIS
    Text of ~/.local/bin/claude-proxy.ps1, which forwards to the bash shim.
    #>
    return @'
<#
.SYNOPSIS
  PowerShell companion shim for claude-proxy. Auto-generated by setup.ps1.
#>
# No param block: bound parameters would capture claude-proxy's own -p and -m.

$bashShim = Join-Path $PSScriptRoot 'claude-proxy'
if (-not (Test-Path -LiteralPath $bashShim)) {
    Write-Error "claude-proxy bash shim not found at $bashShim. Run setup.ps1 first."
    exit 1
}

# Git Bash first: WSL's System32\bash.exe cannot see C:/ paths.
$bash = $null
foreach ($candidate in @(
        $env:CLAUDE_CODE_GIT_BASH_PATH,
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        $bash = $candidate
        break
    }
}
if (-not $bash) {
    $found = Get-Command bash -CommandType Application -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notmatch '[\\/]System32[\\/]' } | Select-Object -First 1
    if ($found) { $bash = $found.Source }
}
if (-not $bash) {
    Write-Error "bash not found. Install Git for Windows (https://git-scm.com/download/win)."
    exit 1
}

& $bash $bashShim @args
exit $LASTEXITCODE
'@
}

$script:ShortcutBeginMarker = "# claude-code-config: claude launch shortcuts"
$script:ShortcutEndMarker = "# claude-code-config: end claude launch shortcuts"

function Get-ClaudeShortcutBlock {
    <#
    .SYNOPSIS
    The claude / clp functions written into the PowerShell profile.
    Port of the block configure_claude_shortcuts writes in lib/setup/settings.sh.
    #>
    return @'
# claude-code-config: claude launch shortcuts
# claude: bypass offered; claude -a (or --unsafe, --bypass, -adskp): bypass now.
function claude {
    $mode = "--allow-dangerously-skip-permissions"
    $rest = @($args)
    if ($rest.Count -gt 0 -and @("-a", "--unsafe", "--bypass", "-adskp") -ccontains [string]$rest[0]) {
        $mode = "--dangerously-skip-permissions"
        $rest = @($rest | Select-Object -Skip 1)
    }
    $exe = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exe) {
        Write-Error "claude not found on PATH. Install: irm https://claude.ai/install.ps1 | iex"
        return
    }
    & $exe.Source $mode @rest
}

# clp: the same through claude-proxy; CLAUDE_PROXY_MODEL picks the model.
# clp is also a built-in alias of Clear-ItemProperty, and aliases win over
# functions, so the alias goes first.
Remove-Item -Path Alias:clp -Force -ErrorAction SilentlyContinue
function clp {
    $model = $env:CLAUDE_PROXY_MODEL
    if (-not $model) { $model = "gpt-6.1-sol(high)" }
    $mode = "--allow-dangerously-skip-permissions"
    $rest = @($args)
    if ($rest.Count -gt 0 -and @("-a", "--unsafe", "--bypass", "-adskp") -ccontains [string]$rest[0]) {
        $mode = "--dangerously-skip-permissions"
        $rest = @($rest | Select-Object -Skip 1)
    }
    $proxy = Join-Path (Join-Path (Join-Path $HOME ".local") "bin") "claude-proxy.ps1"
    if (-not (Test-Path -LiteralPath $proxy)) { $proxy = "claude-proxy" }
    # Quoted: a bare -- is consumed by PowerShell instead of reaching claude-proxy.
    & $proxy --no-validate -m $model '--' $mode @rest
}
# claude-code-config: end claude launch shortcuts
'@
}

function Update-ClaudeShortcut {
    <#
    .SYNOPSIS
    Write the claude / clp shortcuts into a PowerShell profile, between markers.
    Port of configure_claude_shortcuts from lib/setup/settings.sh.
    #>
    param([string]$ProfilePath)

    if (-not $ProfilePath) {
        Write-Status "  ! No PowerShell profile path in this host; shortcuts skipped" -Color Yellow
        return
    }

    $dir = Split-Path -Parent $ProfilePath
    if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # Latin-1 maps every byte to one char, so the user's lines round-trip byte
    # for byte whatever their encoding; only the ASCII block is edited.
    $latin1 = [System.Text.Encoding]::GetEncoding(28591)
    $full = Get-FullPath $ProfilePath
    $text = ""
    if (Test-Path -LiteralPath $full -PathType Leaf) {
        $text = [System.IO.File]::ReadAllText($full, $latin1)
    }
    $newline = "`n"
    if ($text.Contains("`r`n")) { $newline = "`r`n" }

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($piece in [regex]::Split($text, '(?<=\n)')) {
        if ($piece -ne "") { $lines.Add($piece) }
    }
    $begin = -1
    $end = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $bare = $lines[$i].TrimEnd("`r", "`n")
        if ($begin -lt 0 -and $bare -eq $script:ShortcutBeginMarker) { $begin = $i }
        elseif ($begin -ge 0 -and $bare -eq $script:ShortcutEndMarker) {
            $end = $i
            break
        }
    }

    if ($begin -ge 0) {
        # A begin marker with no end marker (a hand edit, a partial paste)
        # would make the removal run to the end of the user's profile.
        if ($end -lt 0) {
            $backup = "${ProfilePath}.claude-code-config.bak"
            Copy-Item -LiteralPath $full -Destination $backup -Force
            Write-Status "  ! ${ProfilePath} has the shortcuts begin marker but no end marker." -Color Yellow
            Write-Status "    Refusing to rewrite it -- that would delete everything after the marker." -Color Yellow
            Write-Status "    Backup: ${backup}" -Color DarkGray
            Write-Status "    Remove the stale block by hand, then re-run setup." -Color DarkGray
            return
        }
        $start = $begin
        # The blank line written before the block goes with it, or every run adds one.
        if ($start -gt 0 -and $lines[$start - 1].Trim() -eq "") { $start-- }
        $lines.RemoveRange($start, $end - $start + 1)
        $text = $lines -join ""
    }

    if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += $newline }
    $block = (Get-ClaudeShortcutBlock) -replace "`r?`n", $newline
    $text += $newline + $block + $newline

    # WriteAllText writes through a symlinked profile instead of replacing it.
    [System.IO.File]::WriteAllText($full, $text, $latin1)
    Write-Status "  + claude / clp shortcuts configured in ${ProfilePath}" -Color Green
}

function Get-UpdatedUserPath {
    <#
    .SYNOPSIS
    The user PATH with a directory prepended, or $null if already present.
    #>
    param(
        [string]$CurrentPath,
        [string]$Directory,
        [string]$Separator = [string][System.IO.Path]::PathSeparator
    )

    $entries = @($CurrentPath -split [regex]::Escape($Separator) | Where-Object { $_ })
    foreach ($entry in $entries) {
        if (Test-SamePath $entry $Directory) { return $null }
    }
    if ($entries.Count -eq 0) { return $Directory }
    return "${Directory}${Separator}${CurrentPath}"
}

function Update-ProxyPath {
    <#
    .SYNOPSIS
    Add bin/ directory to user PATH environment variable.
    #>
    $binDir = Join-Path $script:RepoDir "bin"

    # A persistent user PATH is a Windows registry setting; .NET ignores it
    # elsewhere, where setup.sh edits the shell profile instead.
    if (-not (Test-WindowsHost)) {
        Write-Status "  - User PATH is Windows-only; on this platform run setup.sh for shell shortcuts" -Color DarkGray
        return
    }

    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $newPath = Get-UpdatedUserPath -CurrentPath $currentPath -Directory $binDir

    if ($null -eq $newPath) {
        Write-Status "  + Proxy launcher PATH already configured" -Color Green
    }
    else {
        Write-Status "  Adding ${binDir} to user PATH..."
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        Write-Status "  + Proxy launcher PATH added to user environment" -Color Green
        Write-Status ""
        Write-Status "  Open a new terminal, then run:" -Color Yellow
        Write-Status "    claude-proxy --help"
    }
}
