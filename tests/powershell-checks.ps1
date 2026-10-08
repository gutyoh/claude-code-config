# powershell-checks.ps1 -- PSScriptAnalyzer and Pester, one definition for
# `just ps-check` and every CI lane.
# Path: tests/powershell-checks.ps1
#
# Runs under Windows PowerShell 5.1 and PowerShell 7 on any OS. Exits non-zero
# on any analyzer finding or failed test.

#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$SkipAnalyzer
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

# Pinned so a module release cannot turn the gate red on an unchanged tree.
$modules = @(
    @{ Name = 'Pester'; Version = '6.2.0' },
    @{ Name = 'PSScriptAnalyzer'; Version = '1.25.0' }
)

if ($PSVersionTable.PSVersion.Major -lt 6) {
    # Windows PowerShell 5.1 defaults to TLS 1.0 and ships without the NuGet
    # provider, so PSGallery downloads fail before they start.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
    }
}

foreach ($m in $modules) {
    $have = Get-Module -ListAvailable -Name $m.Name |
        Where-Object { $_.Version -eq [version]$m.Version }
    if ($have) { continue }
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Install-Module -Name $m.Name -RequiredVersion $m.Version -Repository PSGallery `
                -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
            break
        } catch {
            if ($attempt -eq 3) { throw }
            Start-Sleep -Seconds (5 * $attempt)
        }
    }
}

if (-not $SkipAnalyzer) {
    Import-Module PSScriptAnalyzer -RequiredVersion 1.25.0
    $settings = Import-PowerShellDataFile (Join-Path $repo 'PSScriptAnalyzerSettings.psd1')
    # Pester's DSL is not "available by default" in any profile, so the
    # compatibility rules only judge what ships; tests get every other rule.
    $testSettings = $settings.Clone()
    $testSettings.Remove('Rules')

    $findings = @()
    $shipped = @(
        (Join-Path $repo 'setup.ps1'),
        (Join-Path $repo 'lib'),
        (Join-Path $repo '.claude')
    )
    foreach ($path in $shipped) {
        $findings += @(Invoke-ScriptAnalyzer -Path $path -Recurse -Settings $settings)
    }
    $findings += @(Invoke-ScriptAnalyzer -Path (Join-Path $repo 'tests') -Recurse -Settings $testSettings)
    $findings += @(Invoke-ScriptAnalyzer -Path (Join-Path $repo 'PSScriptAnalyzerSettings.psd1') -Settings $testSettings)
    if ($findings.Count -gt 0) {
        $findings | Format-Table -AutoSize RuleName, Severity, ScriptName, Line, Message |
            Out-String -Width 200 | Write-Host
        throw "PSScriptAnalyzer: $($findings.Count) finding(s)"
    }
    Write-Host 'PSScriptAnalyzer: clean'
}

# Pester 3.4 ships inside Windows PowerShell; load the pinned one explicitly.
Remove-Module Pester -ErrorAction SilentlyContinue
Import-Module Pester -RequiredVersion 6.2.0
$config = New-PesterConfiguration
$config.Run.Path = Join-Path $repo 'tests'
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
$result = Invoke-Pester -Configuration $config
$analyzer = 'clean'
if ($SkipAnalyzer) { $analyzer = 'skipped' }

if ($env:GITHUB_STEP_SUMMARY) {
    $edition = "PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
    $line = "| $edition | analyzer $analyzer | $($result.PassedCount) passed | $($result.FailedCount) failed | $($result.SkippedCount) skipped |"
    $text = "| Host | Analyzer | Passed | Failed | Skipped |`n|---|---|---|---|---|`n$line`n"
    [System.IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, $text, (New-Object System.Text.UTF8Encoding $false))
}
if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') { exit 1 }
