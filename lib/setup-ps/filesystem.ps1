# filesystem.ps1 -- Symlink creation and prerequisite checking
# Path: lib/setup-ps/filesystem.ps1
# Dot-sourced by setup.ps1 -- do not execute directly.
#
# PowerShell port of lib/setup/filesystem.sh

function Initialize-Symlink {
    <#
    .SYNOPSIS
    Create a symlink with conflict handling.
    Port of create_symlink from lib/setup/filesystem.sh.
    #>
    param(
        [string]$Source,
        [string]$Target,
        [string]$Name
    )

    # Resolve real paths to detect if we're IN the repo
    $claudeReal = if (Test-Path $script:ClaudeDir) { (Resolve-Path $script:ClaudeDir).Path } else { "" }
    $repoClaudeReal = if (Test-Path "$($script:RepoDir)\.claude") { (Resolve-Path "$($script:RepoDir)\.claude").Path } else { "" }

    if ($claudeReal -and $repoClaudeReal -and ($claudeReal -eq $repoClaudeReal)) {
        Write-Status "  + ~/.claude/${Name} (same as repo, no symlink needed)" -Color Green
        return
    }

    if (Test-Path $Target) {
        $item = Get-Item $Target -Force
        if ($item.LinkType -eq "SymbolicLink") {
            $currentTarget = $item.Target
            if ($currentTarget -eq $Source) {
                Write-Status "  + ~/.claude/${Name} -> ${Source} (already configured)" -Color Green
                return
            }
            # Wrong symlink target -- remove it
            Remove-Item $Target -Force -ErrorAction SilentlyContinue
        }
        elseif ($item.PSIsContainer) {
            # Real directory -- back it up
            $backup = "${Target}.bak"
            if (Test-Path $backup) { Remove-Item $backup -Force -Recurse }
            Move-Item $Target $backup
            Write-Status "  ! ~/.claude/${Name} was a directory -- backed up to ${Name}.bak" -Color Yellow
        }
        else {
            Remove-Item $Target -Force -ErrorAction SilentlyContinue
        }
    }

    try {
        New-Item -ItemType SymbolicLink -Path $Target -Target $Source -Force | Out-Null
        Write-Status "  + ~/.claude/${Name} -> ${Source}" -Color Green
    }
    catch {
        Write-Status "  ! Failed to create symlink for ${Name}. Run as Administrator." -Color Red
        Write-Status "    Error: $_" -Color Yellow
    }
}

function Test-Prerequisite {
    <#
    .SYNOPSIS
    Check if a command exists. Returns $true/$false.
    Port of check_prerequisite from lib/setup/filesystem.sh.
    #>
    param(
        [string]$Cmd,
        [string]$Label,
        [bool]$Required = $false,
        [string]$Hint = ""
    )

    $found = Get-Command $Cmd -ErrorAction SilentlyContinue
    if (-not $found) {
        $msg = "  ! ${Label} not found"
        if ($Hint) { $msg += " (${Hint})" }
        Write-Status $msg -Color Yellow
        if ($Hint) {
            Write-Status "    Install with: scoop install ${Cmd}" -Color DarkGray
            Write-Status "    Or: winget install ${Cmd}" -Color DarkGray
        }
        if ($Required) {
            Write-Status "    Setup cannot continue without ${Cmd}." -Color Red
            exit 1
        }
        Write-Status ""
        return $false
    }

    Write-Status "  + ${Label} installed" -Color Green
    return $true
}
