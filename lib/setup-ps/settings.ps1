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

        if ($settings.statusLine) {
            Write-Status "  + Statusline already configured" -Color Green
        }
        else {
            Write-Status "  Adding statusline to settings..."

            $settings | Add-Member -NotePropertyName "statusLine" -NotePropertyValue ([PSCustomObject]@{
                    type    = "command"
                    command = "$(Get-ClaudeConfigDirRef)/scripts/statusline.sh"
                    padding = 0
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
