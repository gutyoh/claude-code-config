# statusline-conf.ps1 -- Statusline config file (statusline.conf) management
# Path: lib/setup-ps/statusline-conf.ps1
# Dot-sourced by setup-v2.ps1 -- do not execute directly.
#
# PowerShell port of lib/setup/statusline-conf.sh

function Update-StatuslineConf {
    <#
    .SYNOPSIS
    Write or update ~/.claude/statusline.conf.

    .PARAMETER Force
    When $true, overwrite existing config (user explicitly customized via TUI).
    When $false, preserve existing config (merge mode).
    #>
    param([bool]$Force = $false)

    $confFile = $script:StatuslineConf

    if (Test-Path $confFile) {
        if (-not $Force) {
            Write-Status "  + Statusline config already exists (preserved)" -Color Green
            return
        }

        # Check if current config matches what we'd write
        $isMatch = $true
        $existing = @{}

        Get-Content $confFile | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith('#')) {
                $eqIdx = $line.IndexOf('=')
                if ($eqIdx -gt 0) {
                    $k = $line.Substring(0, $eqIdx).Trim()
                    $v = $line.Substring($eqIdx + 1).Trim()
                    $existing[$k] = $v
                }
            }
        }

        # Compare all keys
        $expected = @{
            theme                = $script:StatuslineTheme
            components           = $script:StatuslineComponents
            bar_style            = $script:StatuslineBarStyle
            bar_pct_inside       = $script:StatuslineBarPctInside.ToString().ToLower()
            compact              = $script:StatuslineCompact.ToString().ToLower()
            color_scope          = $script:StatuslineColorScope
            icon                 = $script:StatuslineIcon
            icon_style           = $script:StatuslineIconStyle
            weekly_show_reset    = $script:StatuslineWeeklyShowReset.ToString().ToLower()
            cc_status_position   = $script:StatuslineCcStatusPosition
            cc_status_visibility = $script:StatuslineCcStatusVisibility
            cc_status_color      = $script:StatuslineCcStatusColor
        }

        foreach ($k in $expected.Keys) {
            if ($existing[$k] -ne $expected[$k]) {
                $isMatch = $false
                break
            }
        }

        if ($isMatch) {
            Write-Status "  + Statusline config already up to date" -Color Green
            return
        }
    }

    # Write the config file (LF line endings for cross-platform compat)
    $content = @(
        "theme=$($script:StatuslineTheme)"
        "components=$($script:StatuslineComponents)"
        "bar_style=$($script:StatuslineBarStyle)"
        "bar_pct_inside=$($script:StatuslineBarPctInside.ToString().ToLower())"
        "compact=$($script:StatuslineCompact.ToString().ToLower())"
        "color_scope=$($script:StatuslineColorScope)"
        "icon=$($script:StatuslineIcon)"
        "icon_style=$($script:StatuslineIconStyle)"
        "weekly_show_reset=$($script:StatuslineWeeklyShowReset.ToString().ToLower())"
        "cc_status_position=$($script:StatuslineCcStatusPosition)"
        "cc_status_visibility=$($script:StatuslineCcStatusVisibility)"
        "cc_status_color=$($script:StatuslineCcStatusColor)"
    ) -join "`n"

    [System.IO.File]::WriteAllText($confFile, $content + "`n", [System.Text.UTF8Encoding]::new($false))
    Write-Status "  + Statusline config written (theme=$($script:StatuslineTheme), bar=$($script:StatuslineBarStyle))" -Color Green
}
