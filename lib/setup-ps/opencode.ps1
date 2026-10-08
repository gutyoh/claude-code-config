# opencode.ps1 -- OpenCode parallel install
# Path: lib/setup-ps/opencode.ps1
# Dot-sourced by setup.ps1 -- do not execute directly.
#
# PowerShell port of lib/setup/opencode.sh. OpenCode reads its global config
# from $XDG_CONFIG_HOME/opencode, else ~/.config/opencode -- on Windows too.

$script:OpenCodeSchemaUrl = "https://opencode.ai/config.json"

# Claude Code named color -> OpenCode theme token. OpenCode accepts a token or
# a #rrggbb hex; anything else fails its config schema, so it is dropped.
$script:OpenCodeColorMap = @{
    red = "error"; green = "success"; yellow = "warning"; orange = "warning"
    blue = "info"; cyan = "info"; purple = "accent"; pink = "accent"
    magenta = "accent"; white = "primary"; black = "secondary"
    gray = "secondary"; grey = "secondary"
}
$script:OpenCodeThemeTokens = @("primary", "secondary", "accent", "success", "warning", "error", "info")

function Get-OpenCodeConfigDir {
    if ($env:OPENCODE_CONFIG_DIR_OVERRIDE) { return $env:OPENCODE_CONFIG_DIR_OVERRIDE }
    $base = $env:XDG_CONFIG_HOME
    if (-not $base) { $base = Join-Path $HOME ".config" }
    return (Join-Path $base "opencode")
}

function Get-OpenCodeConfigPath {
    <#
    .SYNOPSIS
    opencode.jsonc when it exists (never split the config), else opencode.json.
    #>
    $dir = Get-OpenCodeConfigDir
    $jsonc = Join-Path $dir "opencode.jsonc"
    if (Test-Path -LiteralPath $jsonc -PathType Leaf) { return $jsonc }
    return (Join-Path $dir "opencode.json")
}

function Get-OpenCodeForce {
    <#
    .SYNOPSIS
    OPENCODE_FORCE as $true / $false, or $null when unset or unrecognized.
    #>
    $value = $env:OPENCODE_FORCE
    if (-not $value) { return $null }
    if (@("1", "true", "yes", "on") -contains $value) { return $true }
    if (@("0", "false", "no", "off") -contains $value) { return $false }
    return $null
}

function Test-OpenCodeBinary {
    if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) { return $false }
    # On 5.1, redirected native stderr is a terminating error under "Stop".
    $ErrorActionPreference = "Continue"
    & opencode --version 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Test-OpenCodeInstalled {
    <#
    .SYNOPSIS
    Tier 0: OPENCODE_FORCE. Tier 1: a working binary. Tier 2: config dir exists.
    #>
    $force = Get-OpenCodeForce
    if ($null -ne $force) { return $force }
    if (Test-OpenCodeBinary) { return $true }
    return (Test-Path -LiteralPath (Get-OpenCodeConfigDir) -PathType Container)
}

function Get-OpenCodeDetectLabel {
    $force = Get-OpenCodeForce
    if ($true -eq $force) { return "yes (forced)" }
    if ($false -eq $force) { return "no (forced)" }
    if (Test-OpenCodeBinary) { return "yes (binary detected)" }
    if (Test-Path -LiteralPath (Get-OpenCodeConfigDir) -PathType Container) { return "yes (config dir exists)" }
    return "no (not installed)"
}

function Install-OpenCode {
    <#
    .SYNOPSIS
    Mirror skills, agents and MCP servers into OpenCode's config.
    Port of configure_opencode from lib/setup/opencode.sh.
    #>
    if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) {
        Write-Status "  ! opencode CLI not found in PATH" -Color Yellow
        Write-Status "    Install: npm install -g opencode-ai (or: scoop install opencode)" -Color DarkGray
        Write-Status "    OpenCode setup skipped." -Color DarkGray
        return
    }

    New-Item -ItemType Directory -Path (Join-Path (Get-OpenCodeConfigDir) "agents") -Force | Out-Null

    Set-OpenCodeSkillsLink
    Convert-OpenCodeAgentSet
    Update-OpenCodeConfig
    Set-AgentsMdLink
}

function Set-OpenCodeSkillsLink {
    $source = Join-Path (Join-Path $script:RepoDir ".claude") "skills"
    $target = Join-Path (Get-OpenCodeConfigDir) "skills"

    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        Write-Status "  ! ${source} missing. Skipping skills link." -Color Yellow
        return
    }

    $configDir = Get-OpenCodeConfigDir
    if (-not (Test-Path -LiteralPath $configDir -PathType Container)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $existing = Get-EntryItem $target
    if (Test-LinkItem $existing) {
        if (Test-SamePath (Get-LinkTargetPath $existing) $source) {
            Write-Status "  + ${target} -> ${source} (already configured)" -Color Green
            return
        }
        Remove-LinkItem $existing
    }
    elseif ($existing -and $existing.PSIsContainer) {
        $backup = "${target}.bak.$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
        Move-Item -LiteralPath $target -Destination $backup
        Write-Status "  ! ${target} was a real directory -- backed up to ${backup}" -Color Yellow
    }
    elseif ($existing) {
        Remove-Item -LiteralPath $target -Force
    }

    try {
        New-SymbolicLinkEntry -Path $target -Target $source
    }
    catch {
        try {
            New-JunctionEntry -Path $target -Target $source
        }
        catch {
            # No copy: a copied directory would be backed up as "real" on every run.
            Write-Status "  ! Could not link ${target}; OpenCode still reads skills from the Claude config dir" -Color Yellow
            return
        }
    }
    Write-Status "  + ${target} -> ${source}" -Color Green
}

function ConvertTo-OpenCodeColor {
    <#
    .SYNOPSIS
    A theme token or #rrggbb for OpenCode, or $null when there is no mapping.
    #>
    param([string]$Value)

    $v = $Value.Trim().Trim('"').Trim("'").ToLowerInvariant()
    if ($script:OpenCodeThemeTokens -contains $v) { return $v }
    if ($v -cmatch '^#[0-9a-fA-F]{6}$') { return $v }
    if ($script:OpenCodeColorMap.ContainsKey($v)) { return $script:OpenCodeColorMap[$v] }
    return $null
}

function Convert-OpenCodeAgent {
    <#
    .SYNOPSIS
    Translate one Claude Code agent to OpenCode: drop name, model: inherit,
    hooks and tools; map color; add mode: subagent. Returns $true when the
    source was processed (a file without frontmatter is skipped, not failed).
    #>
    param(
        [string]$Source,
        [string]$Destination
    )

    $content = Read-Utf8Text $Source
    $match = [regex]::Match($content, '\A---\n(.*?)\n---\n(.*)\z', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success) { return $true }

    $body = $match.Groups[2].Value
    $kept = New-Object System.Collections.Generic.List[string]
    $inSkipBlock = $false

    foreach ($line in ($match.Groups[1].Value -split "\r\n|\n|\r")) {
        if ($inSkipBlock) {
            if (-not $line.Trim() -or $line.StartsWith(" ") -or $line.StartsWith("`t")) { continue }
            $inSkipBlock = $false
        }

        if ($line -cmatch '^name\s*:') { continue }
        if ($line -cmatch '^model\s*:\s*inherit\s*$') { continue }
        if ($line -cmatch '^hooks\s*:') {
            $inSkipBlock = $true
            continue
        }
        if ($line -cmatch '^tools\s*:') {
            if ($line.TrimEnd().EndsWith(":")) { $inSkipBlock = $true }
            continue
        }

        $color = [regex]::Match($line, '^(color\s*:\s*)(.+?)\s*$')
        if ($color.Success) {
            $translated = ConvertTo-OpenCodeColor $color.Groups[2].Value
            if ($null -eq $translated) { continue }
            $kept.Add($color.Groups[1].Value + $translated)
            continue
        }

        $kept.Add($line)
    }

    $hasMode = @($kept | Where-Object { $_ -cmatch '^mode\s*:' }).Count -gt 0
    if (-not $hasMode) { $kept.Insert(0, "mode: subagent") }

    $translatedContent = "---`n" + ($kept -join "`n").TrimEnd() + "`n---`n" + $body

    $destDir = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $destDir -PathType Container)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    Write-Utf8Text -Path $Destination -Content $translatedContent
    return $true
}

function Convert-OpenCodeAgentSet {
    $sourceDir = Join-Path (Join-Path $script:RepoDir ".claude") "agents"
    if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
        Write-Status "  ! ${sourceDir} missing. Skipping agent translation." -Color Yellow
        return
    }

    $agentsDir = Join-Path (Get-OpenCodeConfigDir) "agents"
    $count = 0
    foreach ($agent in @(Get-ChildItem -LiteralPath $sourceDir -Filter "*.md" -File)) {
        if (Convert-OpenCodeAgent -Source $agent.FullName -Destination (Join-Path $agentsDir $agent.Name)) {
            $count++
        }
    }
    Write-Status "  + ${agentsDir} (${count} agents translated)" -Color Green
}

function ConvertFrom-Jsonc {
    <#
    .SYNOPSIS
    Strip // and /* */ comments and trailing commas from JSONC, leaving string
    contents alone (a schema URL contains "//"), so ConvertFrom-Json accepts it.
    #>
    param([string]$Text)

    $noComments = New-Object System.Text.StringBuilder
    $i = 0
    $n = $Text.Length
    $inString = $false
    $escaped = $false
    while ($i -lt $n) {
        $ch = $Text[$i]
        if ($inString) {
            [void]$noComments.Append($ch)
            if ($escaped) { $escaped = $false }
            elseif ($ch -eq [char]'\') { $escaped = $true }
            elseif ($ch -eq [char]'"') { $inString = $false }
            $i++
            continue
        }
        if ($ch -eq [char]'"') {
            $inString = $true
            [void]$noComments.Append($ch)
            $i++
            continue
        }
        if ($ch -eq [char]'/' -and ($i + 1) -lt $n) {
            $next = $Text[$i + 1]
            if ($next -eq [char]'/') {
                while ($i -lt $n -and $Text[$i] -ne [char]"`n") { $i++ }
                continue
            }
            if ($next -eq [char]'*') {
                $i += 2
                while (($i + 1) -lt $n -and -not ($Text[$i] -eq [char]'*' -and $Text[$i + 1] -eq [char]'/')) { $i++ }
                $i += 2
                continue
            }
        }
        [void]$noComments.Append($ch)
        $i++
    }

    # Trailing commas are legal JSONC but not JSON; drop one only when the next
    # non-blank character outside a string closes the container.
    $stripped = $noComments.ToString()
    $result = New-Object System.Text.StringBuilder
    $inString = $false
    $escaped = $false
    for ($j = 0; $j -lt $stripped.Length; $j++) {
        $ch = $stripped[$j]
        if ($inString) {
            if ($escaped) { $escaped = $false }
            elseif ($ch -eq [char]'\') { $escaped = $true }
            elseif ($ch -eq [char]'"') { $inString = $false }
        }
        elseif ($ch -eq [char]'"') {
            $inString = $true
        }
        elseif ($ch -eq [char]',') {
            $k = $j + 1
            while ($k -lt $stripped.Length -and [char]::IsWhiteSpace($stripped[$k])) { $k++ }
            if ($k -lt $stripped.Length -and ($stripped[$k] -eq [char]'}' -or $stripped[$k] -eq [char]']')) { continue }
        }
        [void]$result.Append($ch)
    }
    return $result.ToString()
}

function Get-OpenCodeMcpEntry {
    <#
    .SYNOPSIS
    OpenCode MCP entry; the wrapper must match the backend or no keys reach
    the server (MCP -32000 "Connection closed").
    #>
    param(
        [string]$Package,
        [string]$Backend
    )

    if ($Backend -eq "doppler") {
        $command = @("doppler", "run", "-p", $script:DopplerProject, "-c", $script:DopplerConfig, "--", "npx", "-y", $Package)
    }
    else {
        $command = @("mcp-env-inject", "npx", "-y", $Package)
    }
    return [ordered]@{ type = "local"; command = $command; enabled = $true }
}

function ConvertFrom-JsonOrNull {
    param([string]$Text)

    if (-not $Text -or -not $Text.Trim()) { return $null }
    try {
        return (ConvertFrom-Json -InputObject $Text -ErrorAction Stop)
    }
    catch {
        $null = $_
        return $null
    }
}

function Update-OpenCodeConfig {
    <#
    .SYNOPSIS
    Merge the MCP section into opencode.{json,jsonc}, preserving user keys.
    #>
    if ($script:InstallMcpServers.Count -eq 0) {
        Write-Status "  - MCP servers not selected. Skipping opencode.json mcp section." -Color DarkGray
        return
    }

    $path = Get-OpenCodeConfigPath
    $backend = Get-McpBackend

    $ours = [ordered]@{}
    foreach ($key in $script:InstallMcpServers) {
        $server = $script:McpServers[$key]
        if (-not $server -or -not $server.package) { continue }
        $ours[$key] = Get-OpenCodeMcpEntry -Package $server.package -Backend $backend
    }

    $existing = $null
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $text = Read-Utf8Text $path
        $existing = ConvertFrom-JsonOrNull $text
        if ($null -eq $existing) { $existing = ConvertFrom-JsonOrNull (ConvertFrom-Jsonc $text) }
        if ($null -eq $existing) {
            $backup = "${path}.bak.$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
            Copy-Item -LiteralPath $path -Destination $backup -Force
            Write-Status "  ! Could not parse ${path}; backed up to ${backup}" -Color Yellow
        }
    }

    $merged = [ordered]@{}
    if ($existing) {
        foreach ($prop in $existing.PSObject.Properties) { $merged[$prop.Name] = $prop.Value }
    }
    $merged['$schema'] = $script:OpenCodeSchemaUrl

    $mcp = [ordered]@{}
    if ($merged.Contains("mcp") -and $merged["mcp"]) {
        foreach ($prop in $merged["mcp"].PSObject.Properties) { $mcp[$prop.Name] = $prop.Value }
    }
    foreach ($key in $ours.Keys) { $mcp[$key] = $ours[$key] }
    $merged["mcp"] = $mcp

    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Write-JsonFile -Path $path -InputObject $merged
    Write-Status "  + ${path} (${backend} backend)" -Color Green
}

function Set-AgentsMdLink {
    <#
    .SYNOPSIS
    Link the repo's AGENTS.md to CLAUDE.md so OpenCode reads the same rules.
    #>
    $repoClaude = Join-Path $script:RepoDir "CLAUDE.md"
    $repoAgents = Join-Path $script:RepoDir "AGENTS.md"

    if (-not (Test-Path -LiteralPath $repoClaude -PathType Leaf)) { return }

    $existing = Get-EntryItem $repoAgents
    if (Test-LinkItem $existing) {
        if (@($existing.Target)[0] -eq "CLAUDE.md" -or (Test-SamePath (Get-LinkTargetPath $existing) $repoClaude)) {
            Write-Status "  + AGENTS.md -> CLAUDE.md (already linked)" -Color Green
            return
        }
        Remove-LinkItem $existing
    }
    elseif ($existing) {
        Write-Status "  - AGENTS.md exists as a regular file -- leaving alone" -Color DarkGray
        return
    }

    Push-Location $script:RepoDir
    try {
        New-SymbolicLinkEntry -Path $repoAgents -Target "CLAUDE.md"
        Write-Status "  + ${repoAgents} -> CLAUDE.md" -Color Green
    }
    catch {
        Write-Status "  ! Could not link AGENTS.md (symlinks need Developer Mode); OpenCode falls back to CLAUDE.md" -Color Yellow
    }
    finally {
        Pop-Location
    }
}
