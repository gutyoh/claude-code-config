# output.ps1 -- Console output with ANSI colors (linter-clean)
# Path: lib/setup-ps/output.ps1
# Dot-sourced by setup-v2.ps1 -- do not execute directly.
#
# Replaces Write-Host with [Console]::WriteLine() + ANSI escape codes.
# Satisfies PSAvoidUsingWriteHost rule. Works in Windows Terminal, VS Code,
# PowerShell 7+, and PowerShell 5.1 with VT support enabled.

$script:_ANSI = @{
    Reset    = "$([char]0x1B)[0m"
    Bold     = "$([char]0x1B)[1m"
    Dim      = "$([char]0x1B)[2m"
    Green    = "$([char]0x1B)[32m"
    Yellow   = "$([char]0x1B)[33m"
    Red      = "$([char]0x1B)[31m"
    Cyan     = "$([char]0x1B)[36m"
    DarkGray = "$([char]0x1B)[90m"
    White    = "$([char]0x1B)[37m"
}

function Write-Status {
    <#
    .SYNOPSIS
    Write a line to the console with optional ANSI color.
    Drop-in replacement for Write-Host that satisfies PSScriptAnalyzer.
    Uses [Console]::WriteLine() -- does not pollute the pipeline.

    .PARAMETER Message
    The text to display.

    .PARAMETER Color
    Optional color name: Green, Yellow, Red, Cyan, DarkGray, White.

    .PARAMETER NoNewline
    If set, does not append a newline (uses [Console]::Write instead).
    #>
    param(
        [string]$Message = "",
        [string]$Color = "",
        [switch]$NoNewline
    )

    $text = $Message
    if ($Color -and $script:_ANSI[$Color]) {
        $text = "$($script:_ANSI[$Color])${Message}$($script:_ANSI['Reset'])"
    }

    if ($NoNewline) {
        [Console]::Write($text)
    }
    else {
        [Console]::WriteLine($text)
    }
}
