# filesystem.ps1 -- Managed entry installation and prerequisite checking
# Path: lib/setup-ps/filesystem.ps1
# Dot-sourced by setup.ps1 -- do not execute directly.
#
# PowerShell port of lib/setup/filesystem.sh: one link per repo entry, so files
# other tools install into the config dir survive (the bash module says why).
# Without symlink privilege, directories become junctions and files become
# copies listed in a manifest, so no Administrator rights are needed.

$script:ManagedManifestName = ".claude-code-config.managed"

function Get-EntryItem {
    <#
    .SYNOPSIS
    The item at a path, dangling links included, or $null.
    #>
    param([string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($item) { return $item }
    # Windows PowerShell 5.1 cannot Get-Item a dangling link; its parent lists it.
    $parent = Split-Path -Parent $Path
    if (-not $parent -or -not (Test-Path -LiteralPath $parent -PathType Container)) { return $null }
    $leaf = Split-Path -Leaf $Path
    return Get-ChildItem -LiteralPath $parent -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq $leaf } | Select-Object -First 1
}

function Test-LinkItem {
    param([object]$Item)
    return ($null -ne $Item) -and (@("SymbolicLink", "Junction") -contains $Item.LinkType)
}

function Get-LinkTargetPath {
    <#
    .SYNOPSIS
    Absolute path a link points to (one hop).
    #>
    param([object]$Item)

    # Target is a string on 7 and a string array on 5.1.
    $target = @($Item.Target)[0]
    if (-not $target) { return $null }
    if (-not [System.IO.Path]::IsPathRooted($target)) {
        $target = Join-Path (Split-Path -Parent $Item.FullName) $target
    }
    return [System.IO.Path]::GetFullPath($target)
}

function Resolve-RealPath {
    <#
    .SYNOPSIS
    Resolve every link along a path, like realpath(1).
    #>
    param([string]$Path)

    $current = [System.IO.Path]::GetFullPath((Get-FullPath $Path))
    for ($hop = 0; $hop -lt 40; $hop++) {
        $root = [System.IO.Path]::GetPathRoot($current)
        $parts = @($current.Substring($root.Length) -split '[\\/]' | Where-Object { $_ })
        $acc = $root
        $followed = $false
        for ($i = 0; $i -lt $parts.Count; $i++) {
            $acc = Join-Path $acc $parts[$i]
            $item = Get-EntryItem $acc
            if (Test-LinkItem $item) {
                $next = Get-LinkTargetPath $item
                if ($i -lt $parts.Count - 1) {
                    $rest = $parts[($i + 1)..($parts.Count - 1)] -join [System.IO.Path]::DirectorySeparatorChar
                    $next = Join-Path $next $rest
                }
                $current = [System.IO.Path]::GetFullPath($next)
                $followed = $true
                break
            }
        }
        if (-not $followed) { break }
    }
    $trimmed = $current.TrimEnd('\', '/')
    if ($trimmed) { return $trimmed }
    return $current
}

function Test-SamePath {
    param(
        [string]$Left,
        [string]$Right
    )

    if (-not $Left -or -not $Right) { return $false }
    $a = ($Left -replace '\\', '/').TrimEnd('/')
    $b = ($Right -replace '\\', '/').TrimEnd('/')
    $comparison = [System.StringComparison]::Ordinal
    if (Test-WindowsHost) { $comparison = [System.StringComparison]::OrdinalIgnoreCase }
    return [string]::Equals($a, $b, $comparison)
}

function Test-ManagedLink {
    <#
    .SYNOPSIS
    True when a link points into the repo directory -- i.e. one of ours.
    #>
    param(
        [object]$Item,
        [string]$SourceDir
    )

    if (-not (Test-LinkItem $Item)) { return $false }
    $dest = (Get-LinkTargetPath $Item) -replace '\\', '/'
    $dir = ($SourceDir -replace '\\', '/').TrimEnd('/') + "/"
    $comparison = [System.StringComparison]::Ordinal
    if (Test-WindowsHost) { $comparison = [System.StringComparison]::OrdinalIgnoreCase }
    return $dest.StartsWith($dir, $comparison)
}

function Test-LinkAlive {
    param([object]$Item)
    return Test-Path -LiteralPath (Resolve-RealPath $Item.FullName)
}

function Remove-LinkItem {
    <#
    .SYNOPSIS
    Delete a link without touching what it points to.
    #>
    param([object]$Item)

    # Remove-Item -Recurse on a 5.1 junction deletes the target's contents.
    if ($Item.PSIsContainer) {
        [System.IO.Directory]::Delete($Item.FullName)
    }
    else {
        [System.IO.File]::Delete($Item.FullName)
    }
}

function Backup-Path {
    <#
    .SYNOPSIS
    Move a path aside to <path>.bak.<timestamp>[.n]; never overwrites a backup.
    Returns the backup's leaf name.
    #>
    param([string]$Path)

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backup = "${Path}.bak.${stamp}"
    $n = 1
    while (Get-EntryItem $backup) {
        $backup = "${Path}.bak.${stamp}.${n}"
        $n++
    }
    Move-Item -LiteralPath $Path -Destination $backup
    return (Split-Path -Leaf $backup)
}

function Invoke-GitQuiet {
    <#
    .SYNOPSIS
    Run git with stderr discarded; true on exit code 0.
    #>
    param([string[]]$Arguments)

    # On 5.1, redirected native stderr is a terminating error under "Stop".
    $ErrorActionPreference = "Continue"
    & git @Arguments 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Test-RepoIsGit {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $false }
    return Invoke-GitQuiet -Arguments @("-C", $script:RepoDir, "rev-parse", "--git-dir")
}

function Test-RepoTrackedPath {
    param([string]$Path)
    return Invoke-GitQuiet -Arguments @("-C", $script:RepoDir, "ls-files", "--error-unmatch", "--", $Path)
}

function Get-ContentFingerprint {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return (Get-FileHash -LiteralPath $Path).Hash
    }
    $prefix = (Get-Item -LiteralPath $Path -Force).FullName.Length
    $files = Get-ChildItem -LiteralPath $Path -Recurse -File -Force | Sort-Object FullName
    return (@($files | ForEach-Object {
                ($_.FullName.Substring($prefix) -replace '\\', '/') + "=" + (Get-FileHash -LiteralPath $_.FullName).Hash
            }) -join "`n")
}

function Test-SameContent {
    param(
        [string]$Source,
        [string]$Target
    )

    $sourceIsDir = Test-Path -LiteralPath $Source -PathType Container
    $targetIsDir = Test-Path -LiteralPath $Target -PathType Container
    if ($sourceIsDir -ne $targetIsDir) { return $false }
    return (Get-ContentFingerprint $Source) -eq (Get-ContentFingerprint $Target)
}

function Read-ManagedManifest {
    <#
    .SYNOPSIS
    Names of the entries this repo installed as copies into a directory.
    #>
    param([string]$TargetDir)

    $names = New-Object System.Collections.Generic.HashSet[string]
    $path = Join-Path $TargetDir $script:ManagedManifestName
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        foreach ($line in ((Read-Utf8Text $path) -split "`r?`n")) {
            if ($line.Trim()) { [void]$names.Add($line.Trim()) }
        }
    }
    return , $names
}

function Write-ManagedManifest {
    param(
        [string]$TargetDir,
        [System.Collections.Generic.HashSet[string]]$Names
    )

    $path = Join-Path $TargetDir $script:ManagedManifestName
    if ($Names.Count -eq 0) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        return
    }
    $sorted = @($Names) | Sort-Object
    Write-Utf8Text -Path $path -Content (($sorted -join "`n") + "`n")
}

function New-SymbolicLinkEntry {
    param(
        [string]$Path,
        [string]$Target
    )
    New-Item -ItemType SymbolicLink -Path $Path -Target $Target -ErrorAction Stop | Out-Null
}

function New-JunctionEntry {
    param(
        [string]$Path,
        [string]$Target
    )
    New-Item -ItemType Junction -Path $Path -Target $Target -ErrorAction Stop | Out-Null
    # pwsh off Windows reports success for a junction it never creates.
    if (-not (Test-LinkItem (Get-EntryItem $Path))) { throw "No junction was created at ${Path}" }
}

function Add-ManagedEntry {
    <#
    .SYNOPSIS
    Install one repo entry: symlink, else junction (directories), else copy.
    Returns "link", "junction" or "copy".
    #>
    param(
        [string]$Source,
        [string]$Target
    )

    try {
        New-SymbolicLinkEntry -Path $Target -Target $Source
        return "link"
    }
    catch {
        # Windows without Developer Mode or elevation: fall back below.
        $null = $_
    }

    $isDir = Test-Path -LiteralPath $Source -PathType Container
    if ($isDir) {
        try {
            New-JunctionEntry -Path $Target -Target $Source
            return "junction"
        }
        catch {
            $null = $_
        }
        Copy-Item -LiteralPath $Source -Destination $Target -Recurse -Force
    }
    else {
        Copy-Item -LiteralPath $Source -Destination $Target -Force
    }
    return "copy"
}

function Convert-DirectoryLink {
    <#
    .SYNOPSIS
    Turn a legacy whole-directory link into a real directory, lifting files
    that foreign installers wrote through it back out of the repo.
    #>
    param(
        [string]$SourceDir,
        [string]$TargetDir,
        [string]$Label
    )

    $item = Get-EntryItem $TargetDir
    # Fully resolved, so a profile dir linked to another profile still counts.
    if (-not (Test-SamePath (Resolve-RealPath $TargetDir) (Resolve-RealPath $SourceDir))) {
        $dest = Get-LinkTargetPath $item
        $moved = Backup-Path $TargetDir
        Write-Status "  ! ${Label} pointed at ${dest} -- link kept as ${moved}" -Color Yellow
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
        return
    }

    Remove-LinkItem $item
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    Write-Status "  ! ${Label} was a whole-directory link -- converting to per-entry links" -Color Yellow

    if (-not (Test-RepoIsGit)) { return }

    # Untracked files there were written through the old link by another tool;
    # the next branch switch would delete them.
    $entries = Get-ChildItem -LiteralPath $SourceDir -Force | Where-Object { -not $_.Name.StartsWith(".") }
    foreach ($entry in $entries) {
        if (Test-RepoTrackedPath $entry.FullName) { continue }
        Move-Item -LiteralPath $entry.FullName -Destination (Join-Path $TargetDir $entry.Name)
        Write-Status "    <- rescued $(Split-Path -Leaf $TargetDir)/$($entry.Name) out of the repo working tree" -Color Yellow
    }
}

function Install-ManagedEntry {
    <#
    .SYNOPSIS
    Install every entry of a repo .claude subdirectory into the config dir.
    Port of install_managed_entries from lib/setup/filesystem.sh.
    #>
    param(
        [string]$SourceDir,
        [string]$TargetDir,
        [string]$Name
    )

    $label = "$(Get-ClaudeConfigDirRef)/${Name}"

    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) {
        Write-Status "  - ${label} -- repo has no .claude/${Name}, skipping" -Color DarkGray
        return
    }

    $repoClaude = Join-Path $script:RepoDir ".claude"
    if ((Test-Path -LiteralPath $script:ClaudeDir) -and
        (Test-SamePath (Resolve-RealPath $script:ClaudeDir) (Resolve-RealPath $repoClaude))) {
        Write-Status "  + ${label} (same as repo, no install needed)" -Color Green
        return
    }

    $existingDir = Get-EntryItem $TargetDir
    if (Test-LinkItem $existingDir) {
        Convert-DirectoryLink -SourceDir $SourceDir -TargetDir $TargetDir -Label $label
    }
    elseif ($existingDir -and -not $existingDir.PSIsContainer) {
        $moved = Backup-Path $TargetDir
        Write-Status "  ! ${label} was a file -- kept as ${moved}" -Color Yellow
    }
    if (-not (Test-Path -LiteralPath $TargetDir -PathType Container)) {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    }

    $copies = Read-ManagedManifest $TargetDir
    $linked = 0
    $replaced = 0
    $skipped = 0
    $pruned = 0
    $copied = 0

    $entries = Get-ChildItem -LiteralPath $SourceDir -Force | Where-Object { -not $_.Name.StartsWith(".") }
    foreach ($entry in $entries) {
        $base = $entry.Name
        $target = Join-Path $TargetDir $base
        $existing = Get-EntryItem $target

        if (Test-LinkItem $existing) {
            if (Test-SamePath (Get-LinkTargetPath $existing) $entry.FullName) {
                [void]$copies.Remove($base)
                $linked++
                continue
            }
            if (Test-ManagedLink $existing $SourceDir) {
                Remove-LinkItem $existing
            }
            else {
                Write-Status "  - ${label}/${base} -- foreign link, left as-is" -Color DarkGray
                $skipped++
                continue
            }
        }
        elseif ($existing) {
            if ($copies.Contains($base)) {
                if (Test-SameContent $entry.FullName $target) {
                    $linked++
                    $copied++
                    continue
                }
                Remove-Item -LiteralPath $target -Recurse -Force
            }
            else {
                $moved = Backup-Path $target
                Write-Status "  ! ${label}/${base} existed -- kept as ${moved}" -Color Yellow
                $replaced++
            }
        }

        $mode = Add-ManagedEntry -Source $entry.FullName -Target $target
        if ($mode -eq "copy") {
            [void]$copies.Add($base)
            $copied++
        }
        else {
            [void]$copies.Remove($base)
        }
        $linked++
    }

    # Drop what we installed whose repo entry has since gone.
    foreach ($child in @(Get-ChildItem -LiteralPath $TargetDir -Force)) {
        if ($child.Name -eq $script:ManagedManifestName) { continue }
        if (Test-LinkItem $child) {
            if ((Test-ManagedLink $child $SourceDir) -and -not (Test-LinkAlive $child)) {
                Remove-LinkItem $child
                $pruned++
            }
        }
        elseif ($copies.Contains($child.Name) -and
            -not (Test-Path -LiteralPath (Join-Path $SourceDir $child.Name))) {
            Remove-Item -LiteralPath $child.FullName -Recurse -Force
            [void]$copies.Remove($child.Name)
            $pruned++
        }
    }

    # A manifest name with nothing behind it any more is not ours to track.
    foreach ($nameInManifest in @($copies)) {
        if (-not (Get-EntryItem (Join-Path $TargetDir $nameInManifest))) { [void]$copies.Remove($nameInManifest) }
    }
    Write-ManagedManifest -TargetDir $TargetDir -Names $copies

    # Everything else belongs to another installer.
    $foreign = 0
    foreach ($child in @(Get-ChildItem -LiteralPath $TargetDir -Force)) {
        if ($child.Name -eq $script:ManagedManifestName) { continue }
        if (Test-ManagedLink $child $SourceDir) { continue }
        if ($copies.Contains($child.Name)) { continue }
        $foreign++
    }

    $summary = "${linked} linked"
    if ($copied -gt 0) { $summary += " (${copied} as copies: symlinks need Developer Mode)" }
    if ($replaced -gt 0) { $summary += ", ${replaced} replaced" }
    if ($pruned -gt 0) { $summary += ", ${pruned} pruned" }
    if ($skipped -gt 0) { $summary += ", ${skipped} skipped" }
    if ($foreign -gt 0) { $summary += ", ${foreign} left untouched" }
    Write-Status "  + ${label}: ${summary}" -Color Green
}

function Find-GitBash {
    <#
    .SYNOPSIS
    Path to Git for Windows' bash.exe, or $null. Claude Code runs hooks and the
    status line through it; WSL's System32\bash.exe is a different bash.
    #>
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($env:CLAUDE_CODE_GIT_BASH_PATH) { $candidates.Add($env:CLAUDE_CODE_GIT_BASH_PATH) }

    # <Git>\cmd\git.exe and <Git>\bin\git.exe both sit beside <Git>\bin\bash.exe.
    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($git -and $git.Source) {
        $gitRoot = Split-Path -Parent (Split-Path -Parent $git.Source)
        if ($gitRoot) { $candidates.Add((Join-Path (Join-Path $gitRoot "bin") "bash.exe")) }
    }
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($root) { $candidates.Add((Join-Path (Join-Path (Join-Path $root "Git") "bin") "bash.exe")) }
    }
    if ($env:LOCALAPPDATA) {
        $candidates.Add((Join-Path (Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA "Programs") "Git") "bin") "bash.exe"))
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }

    $onPath = Get-Command bash -CommandType Application -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notmatch '[\\/]System32[\\/]' } | Select-Object -First 1
    if ($onPath) { return $onPath.Source }
    return $null
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
