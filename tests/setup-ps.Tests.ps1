# setup-ps.Tests.ps1
# Path: tests/setup-ps.Tests.ps1
#
# Pester 5 tests for the PowerShell setup modules (lib/setup-ps/).
# Covers: filesystem, settings, statusline-conf, mcp backend detection, preview, CLI parsing.
# TUI tests are limited to non-interactive logic (arrow-key menus require a real console).
#
# Run:  Invoke-Pester tests/setup-ps.Tests.ps1
#       Invoke-Pester tests/setup-ps.Tests.ps1 -Output Detailed

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $setupPsDir = Join-Path (Join-Path $repoRoot "lib") "setup-ps"

    # Silence [Console]::Write/WriteLine during tests so status messages
    # don't leak into Pester output. Restored in AfterAll.
    $script:OriginalConsoleOut = [Console]::Out
    [Console]::SetOut([System.IO.StreamWriter]::Null)

    # Dot-source all modules (same as setup.ps1 does)
    . (Join-Path $setupPsDir "fileio.ps1")
    . (Join-Path $setupPsDir "output.ps1")
    . (Join-Path $setupPsDir "tui.ps1")
    . (Join-Path $setupPsDir "preview.ps1")
    . (Join-Path $setupPsDir "filesystem.ps1")
    . (Join-Path $setupPsDir "settings.ps1")
    . (Join-Path $setupPsDir "statusline-conf.ps1")
    . (Join-Path $setupPsDir "mcp.ps1")
    . (Join-Path $setupPsDir "menu.ps1")

    # Set up script-scope variables that modules expect
    $script:RepoDir = $repoRoot
    $script:StatuslineTheme = "dark"
    $script:StatuslineComponents = "model,usage,weekly,reset,tokens_in,tokens_out,tokens_cache,cost,burn_rate,email"
    $script:StatuslineBarStyle = "text"
    $script:StatuslineBarPctInside = $false
    $script:StatuslineCompact = $true
    $script:StatuslineColorScope = "percentage"
    $script:StatuslineIcon = ""
    $script:StatuslineIconStyle = "plain"
    $script:StatuslineWeeklyShowReset = $false
    $script:StatuslineCcStatusPosition = "inline"
    $script:StatuslineCcStatusVisibility = "always"
    $script:StatuslineCcStatusColor = "full"
    $script:InstallAgentTeamsFlag = $true
    $script:InstallMcpServers = @("brave-search", "tavily")
    $script:InstallAgentsSkills = $true
    $script:InstallProxyPath = $true
    $script:SettingsMode = "merge"
    $script:AllComponentKeys = @(
        "model", "usage", "weekly", "reset", "tokens_in", "tokens_out", "tokens_cache",
        "cost", "burn_rate", "email", "cc_status", "version", "lines", "session_time", "cwd"
    )
    $script:AllComponentDescs = @(
        "Model name (opus-4.5)", "Session utilization (5h)", "Weekly utilization (7d)",
        "Reset countdown timer", "Input tokens count", "Output tokens count",
        "Cache read tokens", "Session cost in USD", "Burn rate (USD/hr)",
        "Account email address", "Claude Code service status", "Claude Code version",
        "Lines added/removed", "Session elapsed time", "Working directory"
    )
}

# ============================================================================
# Preview: Bar rendering
# ============================================================================

Describe "Get-BarPreview" {

    It "renders text style" {
        $result = Get-BarPreview -Style "text"
        $result | Should -Be "session: 42% used"
    }

    It "renders block style with percentage suffix" {
        $result = Get-BarPreview -Style "block"
        $result | Should -Match "^\[.+\] 42%$"
    }

    It "renders block style with pct inside" {
        $result = Get-BarPreview -Style "block" -PctInside $true
        $result | Should -Match "^\[.+\]$"
        $result | Should -Not -Match "42%$"
    }

    It "renders smooth style" {
        $result = Get-BarPreview -Style "smooth"
        $result | Should -Match "42%"
    }

    It "renders gradient style" {
        $result = Get-BarPreview -Style "gradient"
        $result | Should -Match "42%"
    }

    It "renders thin style" {
        $result = Get-BarPreview -Style "thin"
        $result | Should -Match "42%"
    }

    It "renders spark style with 5-char bar" {
        $result = Get-BarPreview -Style "spark"
        $result | Should -Match "42%"
        # Spark has 5 chars + space + percentage
        $result.Length | Should -BeGreaterThan 7
    }

    It "falls back to text for unknown style" {
        $result = Get-BarPreview -Style "nonexistent"
        $result | Should -Be "session: 42% used"
    }

    It "respects custom percentage" {
        $result = Get-BarPreview -Style "text" -Pct 87
        $result | Should -Be "session: 87% used"
    }
}

# ============================================================================
# Preview: Statusline preview string
# ============================================================================

Describe "Get-StatuslinePreview" {

    Context "compact mode (default)" {
        BeforeEach {
            $script:StatuslineCompact = $true
            $script:StatuslineBarStyle = "text"
            $script:StatuslineIcon = ""
            $script:StatuslineWeeklyShowReset = $false
            $script:StatuslineComponents = "model,usage,weekly,reset,tokens_in,tokens_out,tokens_cache,cost,email"
        }

        It "merges usage/weekly with /" {
            $result = Get-StatuslinePreview
            $result | Should -Match "42%/63%"
        }

        It "merges tokens with /" {
            $result = Get-StatuslinePreview
            $result | Should -Match "15\.4k/2\.1k/6\.2M"
        }

        It "does not include burn_rate in compact mode" {
            $script:StatuslineComponents = "model,usage,cost,burn_rate,email"
            $result = Get-StatuslinePreview
            $result | Should -Not -Match "hr\)"
        }

        It "includes icon prefix when set" {
            $script:StatuslineIcon = [string][char]0x273B
            $script:StatuslineIconStyle = "plain"
            $result = Get-StatuslinePreview
            $result | Should -Match "^$([char]0x273B) "
        }

        It "wraps icon in brackets when style is bracketed" {
            $script:StatuslineIcon = [string][char]0x273B
            $script:StatuslineIconStyle = "bracketed"
            $result = Get-StatuslinePreview
            $result | Should -Match "^\[$([char]0x273B)\] "
        }
    }

    Context "verbose mode" {
        BeforeEach {
            $script:StatuslineCompact = $false
            $script:StatuslineBarStyle = "text"
            $script:StatuslineIcon = ""
            $script:StatuslineComponents = "model,usage,weekly,reset,tokens_in,tokens_out,tokens_cache,cost,burn_rate,email"
        }

        It "does not merge components" {
            $result = Get-StatuslinePreview
            $result | Should -Match "session: 42% used"
            $result | Should -Match "weekly: 63%"
            $result | Should -Match "in: 15\.4k"
        }

        It "includes burn_rate in verbose mode" {
            $result = Get-StatuslinePreview
            $result | Should -Match "2\.99/hr"
        }
    }

    Context "weekly reset countdown" {
        It "appends reset when enabled" {
            $script:StatuslineCompact = $true
            $script:StatuslineBarStyle = "text"
            $script:StatuslineIcon = ""
            $script:StatuslineWeeklyShowReset = $true
            $script:StatuslineComponents = "model,usage,weekly,email"
            $result = Get-StatuslinePreview
            $result | Should -Match "63% \(4d2h\)"
        }
    }
}

# ============================================================================
# Statusline Config: Write and compare
# ============================================================================

Describe "Update-StatuslineConf" {
    BeforeEach {
        $script:StatuslineConf = Join-Path $TestDrive "statusline.conf"
        $script:StatuslineTheme = "dark"
        $script:StatuslineComponents = "model,usage"
        $script:StatuslineBarStyle = "block"
        $script:StatuslineBarPctInside = $false
        $script:StatuslineCompact = $true
        $script:StatuslineColorScope = "percentage"
        $script:StatuslineIcon = ""
        $script:StatuslineIconStyle = "plain"
        $script:StatuslineWeeklyShowReset = $false
        $script:StatuslineCcStatusPosition = "inline"
        $script:StatuslineCcStatusVisibility = "always"
        $script:StatuslineCcStatusColor = "full"
    }

    It "creates new config file" {
        Update-StatuslineConf -Force $true
        Test-Path $script:StatuslineConf | Should -BeTrue
        $content = Get-Content $script:StatuslineConf -Raw
        $content | Should -Match "theme=dark"
        $content | Should -Match "bar_style=block"
        $content | Should -Match "components=model,usage"
    }

    It "preserves existing config in non-force mode" {
        "theme=light" | Set-Content $script:StatuslineConf
        Update-StatuslineConf -Force $false
        $content = Get-Content $script:StatuslineConf -Raw
        $content | Should -Match "theme=light"
        $content | Should -Not -Match "theme=dark"
    }

    It "overwrites existing config in force mode" {
        "theme=light" | Set-Content $script:StatuslineConf
        Update-StatuslineConf -Force $true
        $content = Get-Content $script:StatuslineConf -Raw
        $content | Should -Match "theme=dark"
    }

    It "writes boolean values as lowercase" {
        $script:StatuslineCompact = $true
        $script:StatuslineBarPctInside = $false
        Update-StatuslineConf -Force $true
        $content = Get-Content $script:StatuslineConf -Raw
        $content | Should -Match "compact=true"
        $content | Should -Match "bar_pct_inside=false"
    }
}

# ============================================================================
# Settings: JSON manipulation
# ============================================================================

Describe "Settings JSON manipulation" {
    BeforeEach {
        $script:SettingsJson = Join-Path $TestDrive "settings.json"
        @{ hooks = @{ PreToolUse = @() } } | ConvertTo-Json -Depth 5 | Set-Content $script:SettingsJson
    }

    Context "Update-IdeHook" {
        It "adds IDE hook when not present" {
            Update-IdeHook
            $settings = Get-Content $script:SettingsJson -Raw | ConvertFrom-Json
            $matchers = $settings.hooks.PreToolUse | ForEach-Object { $_.matcher }
            $matchers | Should -Contain "mcp__ide__getDiagnostics"
        }

        It "does not duplicate IDE hook" {
            Update-IdeHook
            Update-IdeHook
            $settings = Get-Content $script:SettingsJson -Raw | ConvertFrom-Json
            $count = ($settings.hooks.PreToolUse | Where-Object { $_.matcher -eq "mcp__ide__getDiagnostics" }).Count
            $count | Should -Be 1
        }
    }

    Context "Update-FileSuggestion" {
        It "adds file suggestion when not present" {
            Update-FileSuggestion
            $settings = Get-Content $script:SettingsJson -Raw | ConvertFrom-Json
            $settings.fileSuggestion | Should -Not -BeNullOrEmpty
            $settings.fileSuggestion.type | Should -Be "command"
        }

        It "does not overwrite existing file suggestion" {
            $settings = Get-Content $script:SettingsJson -Raw | ConvertFrom-Json
            $settings | Add-Member -NotePropertyName "fileSuggestion" -NotePropertyValue @{
                type    = "command"
                command = "custom-script.ps1"
            } -Force
            $settings | ConvertTo-Json -Depth 10 | Set-Content $script:SettingsJson
            Update-FileSuggestion
            $settings2 = Get-Content $script:SettingsJson -Raw | ConvertFrom-Json
            $settings2.fileSuggestion.command | Should -Be "custom-script.ps1"
        }
    }

    Context "Update-AgentTeam" {
        It "enables agent teams" {
            $script:InstallAgentTeamsFlag = $true
            Update-AgentTeam
            $settings = Get-Content $script:SettingsJson -Raw | ConvertFrom-Json
            $settings.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS | Should -Be "1"
        }

        It "disables agent teams" {
            # First enable
            $script:InstallAgentTeamsFlag = $true
            Update-AgentTeam
            # Then disable
            $script:InstallAgentTeamsFlag = $false
            Update-AgentTeam
            $settings = Get-Content $script:SettingsJson -Raw | ConvertFrom-Json
            $settings.env | Should -BeNullOrEmpty
        }
    }
}

# ============================================================================
# MCP: Backend detection and registry
# ============================================================================

Describe "MCP module" {

    Context "Server registry" {
        It "has brave-search and tavily keys" {
            $script:McpServerKeys | Should -Contain "brave-search"
            $script:McpServerKeys | Should -Contain "tavily"
        }

        It "brave-search has required fields" {
            $server = $script:McpServers["brave-search"]
            $server.env_var | Should -Be "BRAVE_API_KEY"
            $server.package | Should -Be "@brave/brave-search-mcp-server"
            $server.signup_url | Should -Not -BeNullOrEmpty
        }

        It "tavily has required fields" {
            $server = $script:McpServers["tavily"]
            $server.env_var | Should -Be "TAVILY_API_KEY"
            $server.package | Should -Match "tavily-mcp"
            $server.signup_url | Should -Not -BeNullOrEmpty
        }
    }

    Context "Backend detection" {
        It "falls back to envfile when doppler is not available" {
            # In test environment, doppler is unlikely to be configured
            $backend = Get-McpBackend
            $backend | Should -BeIn @("doppler", "envfile")
        }
    }
}

# ============================================================================
# Filesystem: Prerequisite checking
# ============================================================================

Describe "Test-Prerequisite" {

    It "returns true for an installed command" {
        $result = Test-Prerequisite -Cmd "powershell" -Label "PowerShell" -Required $false
        $result | Should -BeTrue
    }

    It "returns false for a missing command" {
        $result = Test-Prerequisite -Cmd "nonexistent_command_xyz" -Label "Missing Tool" -Required $false
        $result | Should -BeFalse
    }
}

# ============================================================================
# Overlay: Percentage inside bar
# ============================================================================

Describe "Merge-PctInside" {

    It "overlays percentage at center of bar" {
        $bar = [string]::new([char]0x2588, 20)  # 20 full blocks
        $result = Merge-PctInside -Bar $bar -Pct 42 -Width 20
        $result | Should -Match "42%"
        $result.Length | Should -Be 20
    }

    It "returns bar unchanged when too narrow" {
        $bar = "XX"
        $result = Merge-PctInside -Bar $bar -Pct 42 -Width 2
        $result | Should -Be "XX"
    }
}

# ============================================================================
# File I/O: UTF-8 without a byte order mark on every edition
# ============================================================================

Describe "UTF-8 file helpers" {

    It "writes no byte order mark" {
        $path = Join-Path $TestDrive "plain.json"
        Write-Utf8Text -Path $path -Content '{"a":1}'
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $bytes[0] | Should -Be ([byte][char]'{')
    }

    It "round-trips non-ASCII text" {
        $path = Join-Path $TestDrive "icon.conf"
        $icon = [string][char]0x273B
        Write-Utf8Text -Path $path -Content "icon=${icon}"
        Read-Utf8Text $path | Should -Be "icon=${icon}"
    }

    It "drops a byte order mark when reading" {
        $path = Join-Path $TestDrive "bom.json"
        [System.IO.File]::WriteAllBytes($path, [byte[]](0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::ASCII.GetBytes('{"a":1}'))
        (Read-Utf8Text $path | ConvertFrom-Json).a | Should -Be 1
    }

    It "writes JSON with LF line endings and a final newline" {
        $path = Join-Path $TestDrive "obj.json"
        Write-JsonFile -Path $path -InputObject ([PSCustomObject]@{ a = @(1, 2); b = "x" })
        $text = Read-Utf8Text $path
        $text | Should -Not -Match "`r"
        $text.EndsWith("`n") | Should -BeTrue
        ($text | ConvertFrom-Json).b | Should -Be "x"
    }

    It "resolves relative paths against the PowerShell location" {
        Push-Location $TestDrive
        try {
            Write-Utf8Text -Path "relative.txt" -Content "here"
            Test-Path (Join-Path $TestDrive "relative.txt") | Should -BeTrue
        }
        finally {
            Pop-Location
        }
    }
}

# ============================================================================
# Windows PowerShell 5.1 compatibility (static checks on every script)
# ============================================================================

Describe "Windows PowerShell 5.1 compatibility" {
    BeforeAll {
        $script:PsSources = @(
            Get-Item (Join-Path $repoRoot "setup.ps1")
            Get-ChildItem $setupPsDir -Filter "*.ps1"
            Get-ChildItem (Join-Path (Join-Path $repoRoot ".claude") "scripts") -Filter "*.ps1"
            Get-ChildItem (Join-Path $repoRoot "tests") -Filter "*.ps1"
        )
        $script:ParsedSources = foreach ($file in $script:PsSources) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            [PSCustomObject]@{ Name = $file.Name; Ast = $ast; Errors = $errors }
        }
    }

    It "every script is ASCII-only (5.1 reads BOM-less files as ANSI)" {
        $offenders = foreach ($file in $script:PsSources) {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            if (@($bytes | Where-Object { $_ -gt 0x7F }).Count -gt 0) { $file.Name }
        }
        $offenders | Should -BeNullOrEmpty
    }

    It "every script parses" {
        $broken = $script:ParsedSources | Where-Object { $_.Errors.Count -gt 0 } | ForEach-Object { $_.Name }
        $broken | Should -BeNullOrEmpty
    }

    It "no Join-Path call passes more than two positional paths" {
        $offenders = foreach ($parsed in $script:ParsedSources) {
            $calls = $parsed.Ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq "Join-Path"
                }, $true)
            foreach ($call in $calls) {
                $positional = @($call.CommandElements | Select-Object -Skip 1 |
                        Where-Object { $_ -isnot [System.Management.Automation.Language.CommandParameterAst] })
                if ($positional.Count -gt 2) { "$($parsed.Name):$($call.Extent.StartLineNumber)" }
            }
        }
        $offenders | Should -BeNullOrEmpty
    }

    It "no PowerShell 7-only operators (&&, ||, ternary, ??, ?., ?[])" {
        $sevenOnly = @("PipelineChainAst", "TernaryExpressionAst")
        $offenders = foreach ($parsed in $script:ParsedSources) {
            $nodes = $parsed.Ast.FindAll({
                    param($node)
                    $sevenOnly -contains $node.GetType().Name -or
                    ($node -is [System.Management.Automation.Language.BinaryExpressionAst] -and
                        $node.Operator.ToString() -eq "QuestionQuestion") -or
                    ($node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                        $node.Operator.ToString() -eq "QuestionQuestionEquals") -or
                    (@("MemberExpressionAst", "InvokeMemberExpressionAst", "IndexExpressionAst") -contains $node.GetType().Name -and
                        $node.PSObject.Properties["NullConditional"] -and $node.NullConditional)
                }, $true)
            foreach ($node in $nodes) { "$($parsed.Name):$($node.Extent.StartLineNumber)" }
        }
        $offenders | Should -BeNullOrEmpty
    }

    It "setup.ps1 declares #Requires -Version 5.1" {
        $setup = $script:ParsedSources | Where-Object { $_.Name -eq "setup.ps1" }
        $setup.Ast.ScriptRequirements.RequiredPSVersion | Should -Be ([version]"5.1")
    }

    It "no module writes with Set-Content or Out-File (both add a BOM on 5.1)" {
        $offenders = foreach ($parsed in $script:ParsedSources | Where-Object { $_.Name -notlike "*.Tests.ps1" }) {
            $calls = $parsed.Ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    @("Set-Content", "Out-File", "Add-Content") -contains $node.GetCommandName()
                }, $true)
            foreach ($call in $calls) { "$($parsed.Name):$($call.Extent.StartLineNumber)" }
        }
        $offenders | Should -BeNullOrEmpty
    }
}

# ============================================================================
# Module file existence
# ============================================================================

Describe "Module files exist" {
    # -ForEach, not a foreach loop: discovery-time variables do not reach It blocks.
    It "lib/setup-ps/<_> exists" -ForEach @("fileio.ps1", "output.ps1", "tui.ps1", "preview.ps1",
        "filesystem.ps1", "settings.ps1", "statusline-conf.ps1", "mcp.ps1", "menu.ps1") {
        Test-Path (Join-Path $setupPsDir $_) | Should -BeTrue
    }
}

Describe "setup.ps1 exists" {
    It "entry point script exists" {
        Test-Path (Join-Path $repoRoot "setup.ps1") | Should -BeTrue
    }
}

AfterAll {
    # Restore [Console]::Out so Pester summary renders correctly
    if ($script:OriginalConsoleOut) {
        [Console]::SetOut($script:OriginalConsoleOut)
    }
}
