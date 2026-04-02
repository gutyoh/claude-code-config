# menu.ps1 -- Interactive installation menu and customization
# Path: lib/setup-ps/menu.ps1
# Dot-sourced by setup.ps1 -- do not execute directly.
#
# PowerShell port of lib/setup/menu.sh
# Uses TUI primitives from tui.ps1 for arrow-key navigation.

function Show-InstallMenu {
    <#
    .SYNOPSIS
    Show current options and let user proceed, customize, or cancel.
    Port of show_install_menu from lib/setup/menu.sh.
    #>
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

    Write-Status "Current installation options:"
    Write-Status "  core (hooks, scripts, commands):  always"
    Write-Status "  agents & skills:                  ${agentsLabel}"
    Write-Status "  MCP search servers:               ${mcpLabel}"
    Write-Status "  agent teams (experimental):       ${teamsLabel}"
    Write-Status "  proxy launcher PATH:              ${proxyLabel}"
    Write-Status "  settings.json:                    ${settingsLabel}"
    Write-Status "  statusline color theme:           $($script:StatuslineTheme)"
    Write-Status "  statusline components:            ${compDisplay}"
    Write-Status "  statusline compact mode:          ${compactLabel}"
    Write-Status "  statusline color scope:           $($script:StatuslineColorScope)"
    Write-Status "  statusline bar style:             $($script:StatuslineBarStyle)"
    Write-Status "  statusline pct inside bar:        ${pctLabel}"
    Write-Status "  statusline icon:                  ${iconLabel}"
    Write-Status "  statusline icon style:            $($script:StatuslineIconStyle)"
    Write-Status "  statusline weekly reset:          ${weeklyResetLabel}"
    if ($script:StatuslineComponents -match "cc_status") {
        Write-Status "  statusline cc status:             $($script:StatuslineCcStatusPosition), $($script:StatuslineCcStatusVisibility), $($script:StatuslineCcStatusColor)"
    }
    Write-Status ""

    $choice = Select-TuiItem -Header "What would you like to do?" -Options @(
        "Proceed with installation",
        "Customize installation",
        "Cancel"
    )

    switch -Wildcard ($choice) {
        "Proceed*" { <# continue #> }
        "Customize*" { Invoke-CustomizeInstallation }
        "Cancel*" {
            Write-Status "Installation cancelled."
            exit 0
        }
    }
}

function Invoke-CustomizeInstallation {
    <#
    .SYNOPSIS
    Walk through customization options using TUI primitives.
    Port of customize_installation from lib/setup/menu.sh.
    #>

    # --- Agents & Skills ---
    $script:InstallAgentsSkills = Confirm-TuiYesNo -Question "Install agents & skills?" `
        -Default $(if ($script:InstallAgentsSkills) { "yes" } else { "no" })

    # --- MCP Servers (multi-select) ---
    $mcpInitSelected = @()
    for ($i = 0; $i -lt $script:McpServerKeys.Count; $i++) {
        if ($script:McpServerKeys[$i] -in $script:InstallMcpServers) {
            $mcpInitSelected += $i
        }
    }

    $mcpDescs = @()
    foreach ($key in $script:McpServerKeys) {
        $mcpDescs += $script:McpServers[$key].desc
    }

    $mcpSelectedIndices = Select-TuiMultiple `
        -Header "MCP search servers (space: toggle, a: all, n: none, enter: confirm):" `
        -OptionKeys $script:McpServerKeys `
        -OptionDescs $mcpDescs `
        -InitialSelected $mcpInitSelected

    $script:InstallMcpServers = @()
    foreach ($i in $mcpSelectedIndices) {
        $script:InstallMcpServers += $script:McpServerKeys[$i]
    }

    # --- Agent Teams ---
    $script:InstallAgentTeamsFlag = Confirm-TuiYesNo -Question "Enable agent teams? (experimental)" `
        -Default $(if ($script:InstallAgentTeamsFlag) { "yes" } else { "no" })

    # --- Proxy Launcher PATH ---
    $script:InstallProxyPath = Confirm-TuiYesNo `
        -Question "Add proxy launcher (bin/) to PATH? (enables 'claude-proxy' from anywhere)" `
        -Default $(if ($script:InstallProxyPath) { "yes" } else { "no" })

    # --- Settings mode ---
    $settingsChoice = Select-TuiItem -Header "Settings.json mode:" -Options @(
        "merge     - Preserve existing settings, add new",
        "overwrite - Replace with repo defaults",
        "skip      - Don't modify settings.json"
    )

    switch -Wildcard ($settingsChoice) {
        "overwrite*" { $script:SettingsMode = "overwrite" }
        "skip*" { $script:SettingsMode = "skip" }
        default { $script:SettingsMode = "merge" }
    }

    # --- Statusline customization with preview loop ---
    Invoke-CustomizeStatuslineWithPreview
    $script:UserCustomizedStatusline = $true
}

function Invoke-CustomizeStatuslineWithPreview {
    <#
    .SYNOPSIS
    Customize statusline with preview loop.
    Port of customize_statusline_with_preview from lib/setup/menu.sh.
    Loops until user confirms the preview looks good.
    #>
    while ($true) {
        # --- Theme ---
        $themeChoice = Select-TuiItem -Header "Statusline color theme:" -Options @(
            "dark       - Yellow/red on dark background",
            "light      - Blue/red on light background",
            "colorblind - Bold yellow/magenta, accessible (no red/green)",
            "none       - No colors"
        )

        switch -Wildcard ($themeChoice) {
            "light*" { $script:StatuslineTheme = "light" }
            "colorblind*" { $script:StatuslineTheme = "colorblind" }
            "none*" { $script:StatuslineTheme = "none" }
            default { $script:StatuslineTheme = "dark" }
        }

        # --- Compact mode ---
        $script:StatuslineCompact = Confirm-TuiYesNo `
            -Question "Compact mode? (no labels, merged tokens -- matches original format)" `
            -Default "yes"

        # --- Color scope ---
        $colorScopeChoice = Select-TuiItem -Header "Color scope (which part gets colored by utilization):" -Options @(
            "percentage - Color only the usage/percentage component",
            "full       - Color the entire statusline"
        )

        $script:StatuslineColorScope = if ($colorScopeChoice -match "^full") { "full" } else { "percentage" }

        # --- Components (multi-select) ---
        $currentComps = $script:StatuslineComponents -split ','
        $initSelected = @()
        for ($j = 0; $j -lt $script:AllComponentKeys.Count; $j++) {
            if ($script:AllComponentKeys[$j] -in $currentComps) {
                $initSelected += $j
            }
        }

        $selectedIndices = Select-TuiMultiple `
            -Header "Statusline components (space: toggle, a: all, n: none, enter: confirm):" `
            -OptionKeys $script:AllComponentKeys `
            -OptionDescs $script:AllComponentDescs `
            -InitialSelected $initSelected

        $newComponents = @()
        foreach ($idx in $selectedIndices) {
            $newComponents += $script:AllComponentKeys[$idx]
        }
        $script:StatuslineComponents = if ($newComponents.Count -gt 0) { $newComponents -join ',' } else { "model" }

        # --- Bar Style ---
        $barChoice = Select-TuiItem -Header "Progress bar style (for 'usage' component, wide mode):" -Options @(
            "text      session: 42% used",
            "block     [$([string]::new([char]0x2588, 8))$([string]::new([char]0x00B7, 12))] 42%",
            "smooth    $([string]::new([char]0x2588, 8))$([char]0x258D)$([string]::new([char]0x2591, 11)) 42%    (1/8th precision)",
            "gradient  $([string]::new([char]0x2588, 8))$([char]0x2593)$([char]0x2592)$([string]::new([char]0x2591, 10)) 42%",
            "thin      $([string]::new([char]0x2501, 8))$([string]::new([char]0x254C, 12)) 42%",
            "spark     $([string]::new([char]0x2588, 2))$([char]0x2581)$([char]0x2581)$([char]0x2581) 42%                   (compact 5-char)"
        )

        $script:StatuslineBarStyle = ($barChoice -split '\s+')[0]

        # --- Pct Inside (only for bar styles that support it) ---
        $script:StatuslineBarPctInside = $false
        if ($script:StatuslineBarStyle -ne "text" -and $script:StatuslineBarStyle -ne "spark") {
            $script:StatuslineBarPctInside = Confirm-TuiYesNo -Question "Show percentage inside the bar?" -Default "no"
        }

        # --- Weekly reset toggle (only if weekly component selected) ---
        if ($script:StatuslineComponents -match "weekly") {
            $script:StatuslineWeeklyShowReset = Confirm-TuiYesNo `
                -Question "Show weekly reset countdown inline? (e.g. 63% (4d2h))" `
                -Default "no"
        }

        # --- CC Status drill-down (only if cc_status selected) ---
        if ($script:StatuslineComponents -match "cc_status") {
            $ccPosChoice = Select-TuiItem -Header "Claude Code status position:" -Options @(
                "inline   - After email on same line (... | email | status)",
                "newline  - Separate second line (cc status <label>)"
            )
            $script:StatuslineCcStatusPosition = if ($ccPosChoice -match "^newline") { "newline" } else { "inline" }

            $ccVisChoice = Select-TuiItem -Header "Claude Code status visibility:" -Options @(
                "always        - Always show status",
                "problem_only  - Only show when there is a problem"
            )
            $script:StatuslineCcStatusVisibility = if ($ccVisChoice -match "^problem") { "problem_only" } else { "always" }

            $ccColorOptions = @("none  - Plain text, no color", "full  - Color the status label")
            if ($script:StatuslineCcStatusPosition -eq "newline") {
                $ccColorOptions += "status_only  - Color only the status label"
            }
            $ccColorChoice = Select-TuiItem -Header "Claude Code status color:" -Options $ccColorOptions

            switch -Wildcard ($ccColorChoice) {
                "full*" { $script:StatuslineCcStatusColor = "full" }
                "status*" { $script:StatuslineCcStatusColor = "status_only" }
                default { $script:StatuslineCcStatusColor = "none" }
            }
        }

        # --- Icon Prefix ---
        $iconChoice = Select-TuiItem -Header "Statusline prefix icon:" -Options @(
            "$([char]0x273B)  Claude spark   (teardrop asterisk -- Claude logo)",
            "A\  Anthropic      (text logo)",
            "$([char]0x274B)  Propeller      (heavy teardrop spokes)",
            "$([char]0x2726)  Star           (four-pointed star)",
            "$([char]0x2747)  Sparkle        (sparkle symbol)",
            "none               (no icon)"
        )

        switch -Wildcard ($iconChoice) {
            "$([char]0x273B)*" { $script:StatuslineIcon = [string][char]0x273B }
            "A\*" { $script:StatuslineIcon = "A\" }
            "$([char]0x274B)*" { $script:StatuslineIcon = [string][char]0x274B }
            "$([char]0x2726)*" { $script:StatuslineIcon = [string][char]0x2726 }
            "$([char]0x2747)*" { $script:StatuslineIcon = [string][char]0x2747 }
            default { $script:StatuslineIcon = "" }
        }

        # --- Icon Style (only if icon selected) ---
        if ($script:StatuslineIcon) {
            $iconStyleChoice = Select-TuiItem -Header "Icon style:" -Options @(
                "plain          $($script:StatuslineIcon)                   (as-is)",
                "bold           $($script:StatuslineIcon)                   (bold weight)",
                "bracketed      [$($script:StatuslineIcon)]                  (square brackets)",
                "rounded        ($($script:StatuslineIcon))                  (parentheses)",
                "reverse        $($script:StatuslineIcon)                   (inverted background)",
                "bold-color     $($script:StatuslineIcon)                   (bold + blue accent)",
                "angle          $([char]0x27E8)$($script:StatuslineIcon)$([char]0x27E9)                  (angle brackets)",
                "double-bracket $([char]0x27E6)$($script:StatuslineIcon)$([char]0x27E7)                  (double brackets)"
            )
            $script:StatuslineIconStyle = ($iconStyleChoice -split '\s+')[0]
        }
        else {
            $script:StatuslineIconStyle = "plain"
        }

        # --- Live Preview + Confirm ---
        Show-PreviewBox

        if (Confirm-TuiYesNo -Question "Look good?" -Default "yes") {
            break
        }

        Write-Status ""
        Write-Status "  Let's try again..."
    }
}
