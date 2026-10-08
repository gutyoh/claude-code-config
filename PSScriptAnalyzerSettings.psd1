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

    # setup.ps1 must run under the Windows PowerShell 5.1 a stock Windows opens
    # it with, and under PowerShell 7 everywhere. These rules check commands,
    # parameters, types and syntax against both, so a 7-only call fails on any OS.
    Rules = @{
        PSUseCompatibleSyntax   = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }
        PSUseCompatibleCommands = @{
            Enable         = $true
            TargetProfiles = @(
                'win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework'
                'win-4_x64_10.0.18362.0_7.0.0_x64_3.1.2_core'
                'ubuntu_x64_18.04_7.0.0_x64_3.1.2_core'
            )
        }
        PSUseCompatibleTypes    = @{
            Enable         = $true
            TargetProfiles = @(
                'win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework'
                'win-4_x64_10.0.18362.0_7.0.0_x64_3.1.2_core'
                'ubuntu_x64_18.04_7.0.0_x64_3.1.2_core'
            )
        }
    }
}
