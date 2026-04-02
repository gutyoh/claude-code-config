# mcp.ps1 -- MCP server configuration with backend detection
# Path: lib/setup-ps/mcp.ps1
# Dot-sourced by setup.ps1 -- do not execute directly.
#
# PowerShell port of lib/setup/mcp.sh
# Adds Doppler vs envfile backend detection (missing from old setup.ps1).

# --- MCP Server Registry ---

$script:McpServers = @{
    "brave-search" = @{
        label      = "brave-search"
        desc       = "Web, image, video, news, local search (1,000/mo free)"
        env_var    = "BRAVE_API_KEY"
        package    = "@brave/brave-search-mcp-server"
        signup_url = "https://api-dashboard.search.brave.com/"
        free_limit = "1,000 searches/month (`$5 free credits)"
    }
    "tavily"       = @{
        label      = "tavily"
        desc       = "AI-native search, extract, crawl, map, research (1,000/mo free)"
        env_var    = "TAVILY_API_KEY"
        package    = "tavily-mcp@0.2.17"
        signup_url = "https://tavily.com"
        free_limit = "1,000 credits/month"
    }
}

$script:McpServerKeys = @("brave-search", "tavily")

$script:DopplerProject = if ($env:MCP_DOPPLER_PROJECT) { $env:MCP_DOPPLER_PROJECT } else { "claude-code-config" }
$script:DopplerConfig = if ($env:MCP_DOPPLER_CONFIG) { $env:MCP_DOPPLER_CONFIG } else { "dev" }
$script:McpKeysEnvFile = if ($env:MCP_KEYS_ENV_FILE) { $env:MCP_KEYS_ENV_FILE } else { "$env:USERPROFILE\.claude\mcp-keys.env" }

# --- Backend Detection ---

function Get-McpBackend {
    <#
    .SYNOPSIS
    Detect whether to use Doppler or envfile backend.
    Returns "doppler" or "envfile".
    #>

    # Tier 1: Doppler CLI available and project accessible
    $dopplerCmd = Get-Command doppler -ErrorAction SilentlyContinue
    if ($dopplerCmd) {
        $testVar = $script:McpServers["brave-search"].env_var
        try {
            $null = & doppler secrets get $testVar --plain `
                -p $script:DopplerProject -c $script:DopplerConfig 2>$null
            if ($LASTEXITCODE -eq 0) {
                return "doppler"
            }
        }
        catch {
            # Doppler not configured for this project -- fall through
            $null = $_  # Acknowledge the error to satisfy linter
        }
    }

    # Tier 2: Fall back to env file wrapper
    return "envfile"
}

# --- MCP Server Configuration ---

function Install-McpServer {
    <#
    .SYNOPSIS
    Register MCP servers in user scope via `claude mcp add`.
    #>
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claudeCmd) {
        Write-Status "  ! Claude Code CLI not found. Install it first:" -Color Yellow
        Write-Status "    irm https://claude.ai/install.ps1 | iex"
        Write-Status ""
        Write-Status "  After installing, re-run this script or manually add MCP servers."
        return
    }

    $backend = Get-McpBackend
    Write-Status "  MCP backend: ${backend}"
    Write-Status ""

    foreach ($key in $script:InstallMcpServers) {
        Install-SingleMcp -Key $key -Backend $backend
    }

    # For envfile backend: create the keys env file
    if ($backend -eq "envfile") {
        Initialize-McpKeysEnv
    }
}

function Install-SingleMcp {
    param(
        [string]$Key,
        [string]$Backend
    )

    $server = $script:McpServers[$Key]
    $package = $server.package

    # Remove existing config to re-register with correct backend
    $claudeJsonPath = "$env:USERPROFILE\.claude.json"
    if (Test-Path $claudeJsonPath) {
        try {
            $claudeJson = Get-Content $claudeJsonPath -Raw | ConvertFrom-Json
            if ($claudeJson.mcpServers.PSObject.Properties[$Key]) {
                & claude mcp remove $Key --scope user 2>$null
            }
        }
        catch {
            # JSON parse error or missing mcpServers -- safe to ignore
            $null = $_
        }
    }

    Write-Status "  Adding ${Key} MCP server (${Backend} backend)..."

    if ($Backend -eq "doppler") {
        try {
            & claude mcp add $Key --scope user `
                -- doppler run `
                -p $script:DopplerProject -c $script:DopplerConfig `
                -- npx -y $package 2>$null

            if ($LASTEXITCODE -eq 0) {
                Write-Status "  + ${Key} MCP added (doppler wrapper)" -Color Green
            }
            else { throw "exit code $LASTEXITCODE" }
        }
        catch {
            Write-Status "  ! Failed to add ${Key} MCP with doppler wrapper." -Color Yellow
            Write-Status "    Manual: claude mcp add ${Key} --scope user ``" -Color DarkGray
            Write-Status "      -- doppler run -p $($script:DopplerProject) -c $($script:DopplerConfig) -- npx -y ${package}" -Color DarkGray
        }
    }
    else {
        # envfile backend: use mcp-env-inject wrapper
        try {
            & claude mcp add $Key --scope user `
                -- mcp-env-inject npx -y $package 2>$null

            if ($LASTEXITCODE -eq 0) {
                Write-Status "  + ${Key} MCP added (mcp-env-inject wrapper)" -Color Green
            }
            else { throw "exit code $LASTEXITCODE" }
        }
        catch {
            Write-Status "  ! Failed to add ${Key} MCP with env-inject wrapper." -Color Yellow
            Write-Status "    Manual: claude mcp add ${Key} --scope user ``" -Color DarkGray
            Write-Status "      -- mcp-env-inject npx -y ${package}" -Color DarkGray
        }
    }
}

function Initialize-McpKeysEnv {
    <#
    .SYNOPSIS
    Create ~/.claude/mcp-keys.env from available sources.
    #>
    Write-Status ""
    Write-Status "  Creating $($script:McpKeysEnvFile)..."

    $keysWritten = 0
    $envContent = ""

    foreach ($key in $script:InstallMcpServers) {
        $server = $script:McpServers[$key]
        $varName = $server.env_var

        # Try current process environment
        $envVal = [Environment]::GetEnvironmentVariable($varName)
        if (-not $envVal) {
            $envVal = (Get-Item "Env:${varName}" -ErrorAction SilentlyContinue).Value
        }

        # Fall back to repo .env file
        if (-not $envVal -and (Test-Path "$($script:RepoDir)\.env")) {
            $found = Select-String -Path "$($script:RepoDir)\.env" -Pattern "^${varName}=" -ErrorAction SilentlyContinue
            if ($found) {
                $envVal = $found.Line.Substring($varName.Length + 1)
            }
        }

        if ($envVal) {
            $envContent += "${varName}=${envVal}`n"
            $keysWritten++
            Write-Status "  + ${varName} written ($($envVal.Length) chars)" -Color Green
        }
        else {
            Write-Status "  ! ${varName} not found -- add it later with:" -Color Yellow
            Write-Status "    Add-Content '$($script:McpKeysEnvFile)' '${varName}=YOUR_KEY'" -Color DarkGray
            Write-Status "    Get a key: $($server.signup_url)" -Color DarkGray
        }
    }

    if ($keysWritten -gt 0) {
        $dir = Split-Path $script:McpKeysEnvFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        [System.IO.File]::WriteAllText($script:McpKeysEnvFile, $envContent, [System.Text.UTF8Encoding]::new($false))
        Write-Status ""
        Write-Status "  + $($script:McpKeysEnvFile) created (${keysWritten} keys)" -Color Green
    }
    else {
        Write-Status ""
        Write-Status "  ! No MCP keys found. Add them to $($script:McpKeysEnvFile) before using MCP servers." -Color Yellow
    }
}

function Test-McpEnvVar {
    <#
    .SYNOPSIS
    Check if MCP environment variables are set.
    #>
    $backend = Get-McpBackend

    if ($backend -eq "doppler") {
        Write-Status "  + Doppler backend active -- keys injected at MCP server launch" -Color Green
        return
    }

    if (Test-Path $script:McpKeysEnvFile) {
        $content = Get-Content $script:McpKeysEnvFile -Raw
        foreach ($key in $script:InstallMcpServers) {
            $server = $script:McpServers[$key]
            $varName = $server.env_var

            if ($content -match "(?m)^${varName}=") {
                Write-Status "  + ${varName} found in $($script:McpKeysEnvFile)" -Color Green
            }
            else {
                Write-Status "  ! ${varName} missing from $($script:McpKeysEnvFile)" -Color Yellow
                Write-Status "    Add-Content '$($script:McpKeysEnvFile)' '${varName}=YOUR_KEY'" -Color DarkGray
                Write-Status "    Get a free API key ($($server.free_limit)): $($server.signup_url)" -Color DarkGray
            }
        }
    }
    else {
        Write-Status "  ! $($script:McpKeysEnvFile) not found." -Color Yellow
        Write-Status "    Re-run setup or create it manually with your MCP API keys." -Color DarkGray
    }
}
