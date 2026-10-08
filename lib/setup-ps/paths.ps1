# paths.ps1 -- Where Claude Code keeps its configuration on this machine
# Path: lib/setup-ps/paths.ps1
# Dot-sourced by setup.ps1 -- do not execute directly.
#
# Claude Code moves everything under CLAUDE_CONFIG_DIR when it is set,
# .claude.json included, which otherwise sits beside ~/.claude in $HOME.

function Test-WindowsHost {
    <#
    .SYNOPSIS
    True on Windows under both Windows PowerShell 5.1 and PowerShell 7.
    #>
    # $IsWindows does not exist on 5.1.
    return [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

function Get-ClaudeConfigDir {
    <#
    .SYNOPSIS
    The Claude Code config directory: CLAUDE_CONFIG_DIR, else ~/.claude.
    #>
    param(
        [string]$ConfigDir = $env:CLAUDE_CONFIG_DIR,
        [string]$HomeDir = $HOME
    )

    if ($ConfigDir) {
        $trimmed = $ConfigDir.TrimEnd('\', '/')
        if ($trimmed) { return $trimmed }
        return $ConfigDir
    }
    return (Join-Path $HomeDir ".claude")
}

function Get-ClaudeJsonPath {
    <#
    .SYNOPSIS
    Where Claude Code keeps .claude.json (user-scope MCP servers, state).
    #>
    param(
        [string]$ConfigDir = $env:CLAUDE_CONFIG_DIR,
        [string]$HomeDir = $HOME
    )

    if ($ConfigDir) {
        return (Join-Path (Get-ClaudeConfigDir -ConfigDir $ConfigDir -HomeDir $HomeDir) ".claude.json")
    }
    return (Join-Path $HomeDir ".claude.json")
}

function Get-ClaudeConfigDirRef {
    <#
    .SYNOPSIS
    The config dir as written into settings.json commands, forward slashes:
    "~/.claude" when unset (existing settings stay byte-identical), "~/<rel>"
    under $HOME, else the absolute path.
    #>
    param(
        [string]$ConfigDir = $env:CLAUDE_CONFIG_DIR,
        [string]$HomeDir = $HOME
    )

    if (-not $ConfigDir) { return "~/.claude" }

    $dir = (Get-ClaudeConfigDir -ConfigDir $ConfigDir -HomeDir $HomeDir) -replace '\\', '/'
    $homeNorm = ($HomeDir.TrimEnd('\', '/')) -replace '\\', '/'
    $comparison = [System.StringComparison]::Ordinal
    if (Test-WindowsHost) { $comparison = [System.StringComparison]::OrdinalIgnoreCase }

    if ($homeNorm -and $dir.StartsWith("${homeNorm}/", $comparison)) {
        return "~/" + $dir.Substring($homeNorm.Length + 1)
    }
    return $dir
}
