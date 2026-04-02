# tui.ps1 -- TUI primitives (interactive menus, arrow keys, ANSI)
# Path: lib/setup-ps/tui.ps1
# Dot-sourced by setup-v2.ps1 -- do not execute directly.
#
# PowerShell port of lib/setup/tui.sh
# Uses [Console]::ReadKey() for raw input and ANSI escape codes for rendering.
# Works in Windows Terminal, PowerShell 7+, VS Code integrated terminal.

# --- ANSI Helpers ---

$script:ESC = [char]0x1B
$script:ANSI_REVERSE = "${script:ESC}[7m"
$script:ANSI_BOLD = "${script:ESC}[1m"
$script:ANSI_DIM = "${script:ESC}[2m"
$script:ANSI_RESET = "${script:ESC}[0m"

function Move-CursorUp {
    param([int]$Lines = 1)
    [Console]::Write("${script:ESC}[${Lines}A")
}

function Clear-CurrentLine {
    [Console]::Write("`r${script:ESC}[2K")
}

# --- Key Reading ---

function Read-TuiKey {
    <#
    .SYNOPSIS
    Read a single keypress and return a logical key name.
    Arrow keys are detected via ConsoleKey enum.
    #>
    $key = [Console]::ReadKey($true)

    switch ($key.Key) {
        'UpArrow'    { return 'up' }
        'DownArrow'  { return 'down' }
        'LeftArrow'  { return 'left' }
        'RightArrow' { return 'right' }
        'Enter'      { return 'enter' }
        'Spacebar'   { return 'space' }
        'Escape'     { return 'escape' }
        default {
            $ch = $key.KeyChar
            switch ($ch) {
                'q' { return 'quit' }
                'Q' { return 'quit' }
                'a' { return 'a' }
                'n' { return 'n' }
                'y' { return 'y' }
                'Y' { return 'y' }
                'N' { return 'N' }
                'h' { return 'left' }
                'j' { return 'down' }
                'k' { return 'up' }
                'l' { return 'right' }
                default { return "$ch" }
            }
        }
    }
}

# --- Single Select ---

function Select-TuiItem {
    <#
    .SYNOPSIS
    Arrow-key single-select menu. Returns the selected option string.
    Port of tui_select from lib/setup/tui.sh.

    .PARAMETER Header
    The prompt text shown above the options.

    .PARAMETER Options
    Array of option strings to choose from.

    .EXAMPLE
    $choice = Select-TuiItem -Header "What would you like to do?" -Options @("Proceed", "Customize", "Cancel")
    #>
    param(
        [string]$Header,
        [string[]]$Options
    )

    $count = $Options.Count
    $cur = 0

    # Hide cursor
    [Console]::CursorVisible = $false

    # Print header
    [Console]::WriteLine("")
    [Console]::WriteLine("  ${script:ANSI_BOLD}${Header}${script:ANSI_RESET}")
    [Console]::WriteLine("")

    # Initial draw
    for ($i = 0; $i -lt $count; $i++) {
        if ($i -eq $cur) {
            [Console]::WriteLine("  ${script:ANSI_REVERSE} > $($Options[$i]) ${script:ANSI_RESET}")
        }
        else {
            [Console]::WriteLine("    $($Options[$i])")
        }
    }

    # Input loop
    while ($true) {
        $key = Read-TuiKey

        switch ($key) {
            'up' {
                if ($cur -gt 0) { $cur-- }
            }
            'down' {
                if ($cur -lt ($count - 1)) { $cur++ }
            }
            'enter' {
                [Console]::CursorVisible = $true
                return $Options[$cur]
            }
            { $_ -eq 'quit' -or $_ -eq 'escape' } {
                [Console]::CursorVisible = $true
                return $Options[$cur]
            }
        }

        # Move cursor up to redraw
        Move-CursorUp -Lines $count

        for ($i = 0; $i -lt $count; $i++) {
            Clear-CurrentLine
            if ($i -eq $cur) {
                [Console]::WriteLine("  ${script:ANSI_REVERSE} > $($Options[$i]) ${script:ANSI_RESET}")
            }
            else {
                [Console]::WriteLine("    $($Options[$i])")
            }
        }
    }
}

# --- Multi Select ---

function Select-TuiMultiple {
    <#
    .SYNOPSIS
    Arrow-key multi-select menu with space toggle. Returns array of selected indices.
    Port of tui_multiselect from lib/setup/tui.sh.

    .PARAMETER Header
    The prompt text shown above the options.

    .PARAMETER OptionKeys
    Array of short key names (displayed in the checkbox list).

    .PARAMETER OptionDescs
    Array of descriptions (shown dimmed next to each key).

    .PARAMETER InitialSelected
    Array of indices that should be pre-selected.

    .EXAMPLE
    $selected = Select-TuiMultiple -Header "Components:" -OptionKeys @("model","usage") -OptionDescs @("Model name","Session %") -InitialSelected @(0,1)
    #>
    param(
        [string]$Header,
        [string[]]$OptionKeys,
        [string[]]$OptionDescs,
        [int[]]$InitialSelected = @()
    )

    $count = $OptionKeys.Count
    $cur = 0
    $checked = [bool[]]::new($count)

    foreach ($idx in $InitialSelected) {
        if ($idx -ge 0 -and $idx -lt $count) {
            $checked[$idx] = $true
        }
    }

    [Console]::CursorVisible = $false

    [Console]::WriteLine("")
    [Console]::WriteLine("  ${script:ANSI_BOLD}${Header}${script:ANSI_RESET}")
    [Console]::WriteLine("  ${script:ANSI_DIM}(arrow keys: navigate, space: toggle, a: all, n: none, enter: confirm)${script:ANSI_RESET}")
    [Console]::WriteLine("")

    # Capture for scriptblock scope (satisfies PSReviewUnusedParameter)
    $descs = $OptionDescs

    # Draw function
    $drawMenu = {
        for ($i = 0; $i -lt $count; $i++) {
            Clear-CurrentLine
            $checkbox = if ($checked[$i]) { "[x]" } else { "[ ]" }
            $desc = ""
            if ($descs.Count -gt $i -and $descs[$i]) {
                $desc = " ${script:ANSI_DIM}$($descs[$i])${script:ANSI_RESET}"
            }

            if ($i -eq $cur) {
                [Console]::WriteLine("  ${script:ANSI_REVERSE} $checkbox $($OptionKeys[$i]) ${script:ANSI_RESET}${desc}")
            }
            else {
                [Console]::WriteLine("   $checkbox $($OptionKeys[$i])${desc}")
            }
        }
    }

    & $drawMenu

    while ($true) {
        $key = Read-TuiKey

        switch ($key) {
            'up' {
                if ($cur -gt 0) { $cur-- }
            }
            'down' {
                if ($cur -lt ($count - 1)) { $cur++ }
            }
            'space' {
                $checked[$cur] = -not $checked[$cur]
            }
            'a' {
                for ($i = 0; $i -lt $count; $i++) { $checked[$i] = $true }
            }
            'n' {
                for ($i = 0; $i -lt $count; $i++) { $checked[$i] = $false }
            }
            'enter' {
                [Console]::CursorVisible = $true
                $result = @()
                for ($i = 0; $i -lt $count; $i++) {
                    if ($checked[$i]) { $result += $i }
                }
                return $result
            }
            { $_ -eq 'quit' -or $_ -eq 'escape' } {
                [Console]::CursorVisible = $true
                $result = @()
                for ($i = 0; $i -lt $count; $i++) {
                    if ($checked[$i]) { $result += $i }
                }
                return $result
            }
        }

        Move-CursorUp -Lines $count
        & $drawMenu
    }
}

# --- Yes/No Confirm ---

function Confirm-TuiYesNo {
    <#
    .SYNOPSIS
    Arrow-key yes/no toggle. Returns $true for Yes, $false for No.
    Port of tui_confirm from lib/setup/tui.sh.

    .PARAMETER Question
    The question to ask.

    .PARAMETER Default
    Default selection: "yes" or "no".

    .EXAMPLE
    if (Confirm-TuiYesNo -Question "Install agents?" -Default "yes") { ... }
    #>
    param(
        [string]$Question,
        [string]$Default = "no"
    )

    $selected = if ($Default -eq "yes") { 0 } else { 1 } # 0=yes, 1=no

    [Console]::CursorVisible = $false

    [Console]::WriteLine("")

    # Capture for scriptblock scope (satisfies PSReviewUnusedParameter)
    $prompt = $Question

    $drawConfirm = {
        Clear-CurrentLine
        $yesStyle = if ($selected -eq 0) { "${script:ANSI_REVERSE} Yes ${script:ANSI_RESET}" } else { "Yes" }
        $noStyle = if ($selected -eq 1) { "${script:ANSI_REVERSE} No ${script:ANSI_RESET}" } else { "No" }
        [Console]::Write("  ${prompt}  ${yesStyle}  ${noStyle}")
    }

    & $drawConfirm

    while ($true) {
        $key = Read-TuiKey

        switch ($key) {
            { $_ -eq 'left' -or $_ -eq 'up' -or $_ -eq 'y' } {
                $selected = 0
            }
            { $_ -eq 'right' -or $_ -eq 'down' -or $_ -eq 'N' } {
                $selected = 1
            }
            'enter' {
                [Console]::WriteLine("")
                [Console]::CursorVisible = $true
                return ($selected -eq 0)
            }
            { $_ -eq 'quit' -or $_ -eq 'escape' } {
                [Console]::WriteLine("")
                [Console]::CursorVisible = $true
                return ($selected -eq 1) # escape = no
            }
        }

        & $drawConfirm
    }
}
