# fileio.ps1 -- UTF-8 reads and writes that behave the same on every edition
# Path: lib/setup-ps/fileio.ps1
# Dot-sourced by setup.ps1 -- do not execute directly.
#
# Windows PowerShell 5.1 reads BOM-less files as ANSI and writes UTF-8 with a
# BOM, so every config file goes through these helpers instead of
# Get-Content/Set-Content.

function Get-FullPath {
    <#
    .SYNOPSIS
    Resolve a path against the PowerShell location, as .NET would not.
    #>
    param([string]$Path)

    # .NET file APIs resolve relative paths against the process directory,
    # which is not $PWD once the script has changed location.
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Read-Utf8Text {
    <#
    .SYNOPSIS
    Read a whole file as UTF-8, dropping a byte order mark if present.
    #>
    param([string]$Path)

    return [System.IO.File]::ReadAllText((Get-FullPath $Path), [System.Text.Encoding]::UTF8)
}

function Write-Utf8Text {
    <#
    .SYNOPSIS
    Write a whole file as UTF-8 without a byte order mark.
    Writes through a symlink rather than replacing it.
    #>
    param(
        [string]$Path,
        [string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Get-FullPath $Path), $Content, $encoding)
}

function Write-JsonFile {
    <#
    .SYNOPSIS
    Serialize an object to a JSON file with LF line endings.
    #>
    param(
        [string]$Path,
        [object]$InputObject
    )

    # Windows PowerShell 5.1's type data gives arrays an extra Count property,
    # so an array attached with Add-Member serializes as {"value":[],"Count":n}.
    if ($PSVersionTable.PSEdition -ne "Core") {
        Remove-TypeData -TypeName System.Array -ErrorAction SilentlyContinue
    }
    $json = ConvertTo-Json -InputObject $InputObject -Depth 100
    Write-Utf8Text -Path $Path -Content (($json -replace "`r`n", "`n") + "`n")
}
