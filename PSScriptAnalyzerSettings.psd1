# PSScriptAnalyzerSettings.psd1
# Path: claude-code-config/PSScriptAnalyzerSettings.psd1
#
# PSScriptAnalyzer configuration for the project.
# See: https://github.com/PowerShell/PSScriptAnalyzer
#
# Equivalent of .shellcheckrc for PowerShell scripts.

@{
    # Severity levels to report (Error + Warning; skip Information)
    Severity = @('Error', 'Warning')

    # Rules to exclude (documented false positives for this project type):
    #
    #   PSAvoidUsingWriteHost (includes [Console]::Write/WriteLine):
    #     This is an interactive TUI setup script with arrow-key menus, cursor
    #     control, and colored output. [Console]::Write() is the ONLY way to do
    #     in-place cursor redraws for the TUI. Write-Output would pollute the
    #     pipeline; Write-Information cannot do cursor positioning.
    #     See: https://github.com/PowerShell/PSScriptAnalyzer/issues/1118
    #          https://github.com/PowerShell/PSScriptAnalyzer/issues/267
    #
    #   PSUseShouldProcessForStateChangingFunctions:
    #     The rule fires purely on verb name (Update-, Set-, New-), not on
    #     whether the function actually changes system state. Our functions are
    #     internal helpers called from an interactive TUI that already confirms
    #     actions. Adding ShouldProcess to every internal helper adds ceremony
    #     without value.
    #     See: https://github.com/PowerShell/PSScriptAnalyzer/issues/206
    #          https://github.com/PowerShell/PSScriptAnalyzer/issues/283
    #
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
