# preview.ps1 -- Statusline preview rendering for setup TUI
# Path: lib/setup-ps/preview.ps1
# Dot-sourced by setup.ps1 -- do not execute directly.
#
# PowerShell port of lib/setup/preview.sh
# Renders live statusline preview with Unicode box drawing.

function Get-BarPreview {
    <#
    .SYNOPSIS
    Render a progress bar preview string for a given style.
    Port of render_bar_preview from lib/setup/preview.sh.
    #>
    param(
        [string]$Style,
        [bool]$PctInside = $false,
        [int]$Pct = 42,
        [int]$Width = 20
    )

    switch ($Style) {
        'text' {
            return "session: ${Pct}% used"
        }
        'block' {
            $filled = [math]::Floor($Pct * $Width / 100)
            $empty = $Width - $filled
            $bar = ([string]::new([char]0x2588, $filled)) + ([string]::new([char]0x00B7, $empty))
            if ($PctInside) { $bar = Merge-PctInside -Bar $bar -Pct $Pct -Width $Width }
            $result = "[${bar}]"
            if (-not $PctInside) { $result += " ${Pct}%" }
            return $result
        }
        'smooth' {
            $partials = @('', [char]0x258F, [char]0x258E, [char]0x258D, [char]0x258C, [char]0x258B, [char]0x258A, [char]0x2589)
            $totalEighths = [math]::Floor($Pct * $Width * 8 / 100)
            $fullBlocks = [math]::Floor($totalEighths / 8)
            $remainder = $totalEighths % 8
            $hasPartial = if ($remainder -gt 0) { 1 } else { 0 }
            $emptyBlocks = $Width - $fullBlocks - $hasPartial
            $bar = ([string]::new([char]0x2588, $fullBlocks))
            if ($remainder -gt 0) { $bar += $partials[$remainder] }
            $bar += ([string]::new([char]0x2591, $emptyBlocks))
            if ($PctInside) { $bar = Merge-PctInside -Bar $bar -Pct $Pct -Width $Width }
            $result = $bar
            if (-not $PctInside) { $result += " ${Pct}%" }
            return $result
        }
        'gradient' {
            $filled = [math]::Floor($Pct * $Width / 100)
            $empty = $Width - $filled
            if ($filled -eq 0) {
                $bar = [string]::new([char]0x2591, $Width)
            }
            elseif ($empty -eq 0) {
                $bar = [string]::new([char]0x2588, $Width)
            }
            else {
                $bar = [string]::new([char]0x2588, $filled)
                $remaining = $empty
                if ($remaining -ge 1) { $bar += [char]0x2593; $remaining-- }
                if ($remaining -ge 1) { $bar += [char]0x2592; $remaining-- }
                $bar += [string]::new([char]0x2591, $remaining)
            }
            if ($PctInside) { $bar = Merge-PctInside -Bar $bar -Pct $Pct -Width $Width }
            $result = $bar
            if (-not $PctInside) { $result += " ${Pct}%" }
            return $result
        }
        'thin' {
            $filled = [math]::Floor($Pct * $Width / 100)
            $empty = $Width - $filled
            $bar = ([string]::new([char]0x2501, $filled)) + ([string]::new([char]0x254C, $empty))
            if ($PctInside) { $bar = Merge-PctInside -Bar $bar -Pct $Pct -Width $Width }
            $result = $bar
            if (-not $PctInside) { $result += " ${Pct}%" }
            return $result
        }
        'spark' {
            $sparkChars = @([char]0x2581, [char]0x2582, [char]0x2583, [char]0x2584,
                [char]0x2585, [char]0x2586, [char]0x2587, [char]0x2588)
            $sw = 5
            $bar = ""
            for ($i = 0; $i -lt $sw; $i++) {
                $segStart = [math]::Floor($i * 100 / $sw)
                $segEnd = [math]::Floor(($i + 1) * 100 / $sw)
                if ($Pct -ge $segEnd) {
                    $bar += [char]0x2588
                }
                elseif ($Pct -le $segStart) {
                    $bar += [char]0x2581
                }
                else {
                    $segRange = $segEnd - $segStart
                    $segFill = $Pct - $segStart
                    $idx = [math]::Min([math]::Floor($segFill * 7 / $segRange), 7)
                    $bar += $sparkChars[$idx]
                }
            }
            return "${bar} ${Pct}%"
        }
        default {
            return "session: ${Pct}% used"
        }
    }
}

function Merge-PctInside {
    param(
        [string]$Bar,
        [int]$Pct,
        [int]$Width
    )

    $pctStr = " ${Pct}% "
    $pctLen = $pctStr.Length

    if ($Width -ge ($pctLen + 2)) {
        $start = [math]::Floor(($Width - $pctLen) / 2)
        $chars = $Bar.ToCharArray()
        for ($i = 0; $i -lt $pctLen; $i++) {
            $pos = $start + $i
            if ($pos -lt $chars.Length) {
                $chars[$pos] = $pctStr[$i]
            }
        }
        return [string]::new($chars)
    }
    return $Bar
}

function Get-StatuslinePreview {
    <#
    .SYNOPSIS
    Build the full statusline preview string.
    Port of show_statusline_preview from lib/setup/preview.sh.
    Handles compact token merging, icon styling, etc.
    #>

    $isCompact = $script:StatuslineCompact
    $barStyle = $script:StatuslineBarStyle
    $pctInside = $script:StatuslineBarPctInside

    # Usage string
    if ($isCompact -and $barStyle -eq "text") {
        $usageStr = "42%"
    }
    else {
        $usageStr = Get-BarPreview -Style $barStyle -PctInside $pctInside
    }

    # Icon prefix
    $iconPrefix = ""
    if ($script:StatuslineIcon) {
        switch ($script:StatuslineIconStyle) {
            "bold"           { $iconPrefix = "$($script:StatuslineIcon) " }
            "bracketed"      { $iconPrefix = "[$($script:StatuslineIcon)] " }
            "rounded"        { $iconPrefix = "($($script:StatuslineIcon)) " }
            "reverse"        { $iconPrefix = " $($script:StatuslineIcon)  " }
            "bold-color"     { $iconPrefix = "$($script:StatuslineIcon) " }
            "angle"          { $iconPrefix = "$([char]0x27E8)$($script:StatuslineIcon)$([char]0x27E9) " }
            "double-bracket" { $iconPrefix = "$([char]0x27E6)$($script:StatuslineIcon)$([char]0x27E7) " }
            default          { $iconPrefix = "$($script:StatuslineIcon) " }
        }
    }

    # Build parts from components
    $comps = $script:StatuslineComponents -split ','
    $parts = [System.Collections.ArrayList]::new()
    $partKeys = [System.Collections.ArrayList]::new()

    foreach ($key in $comps) {
        switch ($key) {
            "model"       { [void]$parts.Add("opus-4.5"); [void]$partKeys.Add("model") }
            "usage"       { [void]$parts.Add($usageStr); [void]$partKeys.Add("usage") }
            "weekly" {
                $w = if ($isCompact) { "63%" } else { "weekly: 63%" }
                if ($script:StatuslineWeeklyShowReset) { $w += " (4d2h)" }
                [void]$parts.Add($w); [void]$partKeys.Add("weekly")
            }
            "reset"       { [void]$parts.Add($(if ($isCompact) { "2h15m" } else { "resets: 2h15m" })); [void]$partKeys.Add("reset") }
            "tokens_in"   { [void]$parts.Add($(if ($isCompact) { "15.4k" } else { "in: 15.4k" })); [void]$partKeys.Add("tokens_in") }
            "tokens_out"  { [void]$parts.Add($(if ($isCompact) { "2.1k" } else { "out: 2.1k" })); [void]$partKeys.Add("tokens_out") }
            "tokens_cache" { [void]$parts.Add($(if ($isCompact) { "6.2M" } else { "cache: 6.2M" })); [void]$partKeys.Add("tokens_cache") }
            "cost"        { [void]$parts.Add("`$5.21"); [void]$partKeys.Add("cost") }
            "burn_rate" {
                if (-not $isCompact) { [void]$parts.Add("(`$2.99/hr)"); [void]$partKeys.Add("burn_rate") }
            }
            "email"        { [void]$parts.Add("user@email.com"); [void]$partKeys.Add("email") }
            "cc_status" {
                $label = if ($script:StatuslineCcStatusVisibility -eq "problem_only") { "degraded" } else { "on" }
                [void]$parts.Add($label); [void]$partKeys.Add("cc_status")
            }
            "version"      { [void]$parts.Add("v2.0.37"); [void]$partKeys.Add("version") }
            "lines"        { [void]$parts.Add("+2109 -103"); [void]$partKeys.Add("lines") }
            "session_time" { [void]$parts.Add("37m"); [void]$partKeys.Add("session_time") }
            "cwd"          { [void]$parts.Add("~/project"); [void]$partKeys.Add("cwd") }
        }
    }

    # Join with " | ", merging adjacent tokens with "/" when compact
    $result = ""
    $idx = 0
    $total = $parts.Count

    while ($idx -lt $total) {
        $curKey = $partKeys[$idx]
        $curVal = $parts[$idx]

        # Compact: merge adjacent related components with /
        if ($isCompact) {
            $mergeGroup = ""
            switch ($curKey) {
                { $_ -in @("tokens_in", "tokens_out", "tokens_cache") } { $mergeGroup = "tokens" }
                { $_ -in @("usage", "weekly") } { $mergeGroup = "usage" }
            }

            if ($mergeGroup) {
                $merged = $curVal
                $next = $idx + 1
                while ($next -lt $total) {
                    $nextGroup = ""
                    switch ($partKeys[$next]) {
                        { $_ -in @("tokens_in", "tokens_out", "tokens_cache") } { $nextGroup = "tokens" }
                        { $_ -in @("usage", "weekly") } { $nextGroup = "usage" }
                    }
                    if ($nextGroup -eq $mergeGroup) {
                        $merged += "/$($parts[$next])"
                        $next++
                    }
                    else { break }
                }
                if ($result) { $result += " | " }
                $result += $merged
                $idx = $next
                continue
            }
        }

        if ($result) { $result += " | " }
        $result += $curVal
        $idx++
    }

    return "${iconPrefix}${result}"
}

function Show-PreviewBox {
    <#
    .SYNOPSIS
    Show a Unicode box around the statusline preview.
    Port of show_preview_box from lib/setup/preview.sh.
    #>

    $preview = Get-StatuslinePreview
    $modeLabel = if ($script:StatuslineCompact) { "wide, compact" } else { "wide, verbose" }

    # Dynamic box width: content + 2 padding chars, min 66
    $contentLen = $preview.Length
    $boxInner = [math]::Max($contentLen + 2, 66)

    # Top border
    $header = [char]0x2500 + " Preview (${modeLabel} mode, 42% usage) "
    $headerLen = $header.Length
    $topPad = [math]::Max($boxInner - $headerLen, 0)
    $topBorder = "  $([char]0x250C)${header}$([string]::new([char]0x2500, $topPad))$([char]0x2510)"

    # Content line
    $pad = [math]::Max($boxInner - $contentLen, 0)
    $contentLine = "  $([char]0x2502) ${preview}$([string]::new(' ', $pad))$([char]0x2502)"

    # Bottom border
    $bottomBorder = "  $([char]0x2514)$([string]::new([char]0x2500, $boxInner))$([char]0x2518)"

    Write-Status ""
    Write-Status $topBorder
    Write-Status $contentLine
    Write-Status $bottomBorder
    Write-Status ""

    # Settings summary
    $iconDisplay = if ($script:StatuslineIcon) { $script:StatuslineIcon } else { "none" }
    $compactDisplay = if ($script:StatuslineCompact) { "yes" } else { "no" }
    $styleDisplay = if ($script:StatuslineIcon) { $script:StatuslineIconStyle } else { "n/a" }

    Write-Status "  Settings:"
    Write-Status "    theme: $($script:StatuslineTheme) | compact: ${compactDisplay} | color: $($script:StatuslineColorScope) | bar: $($script:StatuslineBarStyle) | icon: ${iconDisplay} (${styleDisplay})"

    $compDisplay = $script:StatuslineComponents -replace ',', ', '
    if ($compDisplay.Length -gt 60) { $compDisplay = $compDisplay.Substring(0, 57) + "..." }
    Write-Status "    components: ${compDisplay}"

    if ($script:StatuslineComponents -match "cc_status") {
        Write-Status "    cc status: $($script:StatuslineCcStatusPosition), $($script:StatuslineCcStatusVisibility), $($script:StatuslineCcStatusColor)"
    }
}
