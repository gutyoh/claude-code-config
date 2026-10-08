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
    . (Join-Path $setupPsDir "paths.ps1")
    . (Join-Path $setupPsDir "output.ps1")
    . (Join-Path $setupPsDir "tui.ps1")
    . (Join-Path $setupPsDir "preview.ps1")
    . (Join-Path $setupPsDir "filesystem.ps1")
    . (Join-Path $setupPsDir "settings.ps1")
    . (Join-Path $setupPsDir "statusline-conf.ps1")
    . (Join-Path $setupPsDir "mcp.ps1")
    . (Join-Path $setupPsDir "opencode.ps1")
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
# Filesystem: per-entry install (parity with install_managed_entries)
# ============================================================================

Describe "Install-ManagedEntry" {
    BeforeAll {
        function New-FakeRepo {
            $root = Join-Path $TestDrive ("repo-" + [guid]::NewGuid().ToString("N"))
            $claude = Join-Path $root ".claude"
            $hooks = Join-Path $claude "hooks"
            $skill = Join-Path (Join-Path $claude "skills") "sample-skill"
            New-Item -ItemType Directory -Path $hooks, $skill -Force | Out-Null
            Write-Utf8Text -Path (Join-Path $hooks "one.sh") -Content "echo one`n"
            Write-Utf8Text -Path (Join-Path $hooks "two.sh") -Content "echo two`n"
            Write-Utf8Text -Path (Join-Path $skill "SKILL.md") -Content "---`nname: sample-skill`n---`n"
            # -c only: a test must never write the developer's git config.
            & git -C $root -c init.defaultBranch=main init -q 2>$null | Out-Null
            & git -C $root add -A 2>$null | Out-Null
            & git -C $root -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false commit -q -m init 2>$null | Out-Null
            return $root
        }

        function Get-Link([string]$Path) {
            $item = Get-EntryItem $Path
            if (Test-LinkItem $item) { return Get-LinkTargetPath $item }
            return $null
        }
    }

    BeforeEach {
        $script:RepoDir = New-FakeRepo
        $script:ClaudeDir = Join-Path $TestDrive ("cfg-" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $script:ClaudeDir | Out-Null
        $script:SourceHooks = Join-Path (Join-Path $script:RepoDir ".claude") "hooks"
        $script:SourceSkills = Join-Path (Join-Path $script:RepoDir ".claude") "skills"
        $script:TargetHooks = Join-Path $script:ClaudeDir "hooks"
        $script:TargetSkills = Join-Path $script:ClaudeDir "skills"
        $script:Messages = New-Object System.Collections.Generic.List[string]
        Mock Write-Status { $script:Messages.Add($Message) }
    }

    It "links each entry individually and is idempotent" {
        Install-ManagedEntry -SourceDir $script:SourceHooks -TargetDir $script:TargetHooks -Name "hooks"
        (Get-Item -LiteralPath $script:TargetHooks -Force).LinkType | Should -BeNullOrEmpty
        Get-Link (Join-Path $script:TargetHooks "one.sh") | Should -Be (Join-Path $script:SourceHooks "one.sh")
        Get-Link (Join-Path $script:TargetHooks "two.sh") | Should -Be (Join-Path $script:SourceHooks "two.sh")

        $script:Messages.Clear()
        Install-ManagedEntry -SourceDir $script:SourceHooks -TargetDir $script:TargetHooks -Name "hooks"
        ($script:Messages -join "`n") | Should -Match "hooks: 2 linked$"
    }

    It "leaves foreign files and foreign links alone" {
        New-Item -ItemType Directory -Path $script:TargetHooks | Out-Null
        Write-Utf8Text -Path (Join-Path $script:TargetHooks "other-tool.sh") -Content "foreign"
        $elsewhere = Join-Path $TestDrive ("elsewhere-" + [guid]::NewGuid().ToString("N"))
        Write-Utf8Text -Path $elsewhere -Content "x"
        New-Item -ItemType SymbolicLink -Path (Join-Path $script:TargetHooks "linked-by-other.sh") -Target $elsewhere | Out-Null

        Install-ManagedEntry -SourceDir $script:SourceHooks -TargetDir $script:TargetHooks -Name "hooks"

        Read-Utf8Text (Join-Path $script:TargetHooks "other-tool.sh") | Should -Be "foreign"
        Get-Link (Join-Path $script:TargetHooks "linked-by-other.sh") | Should -Be $elsewhere
        ($script:Messages -join "`n") | Should -Match "2 left untouched"
    }

    It "skips a foreign link that already uses an entry's name" {
        New-Item -ItemType Directory -Path $script:TargetHooks | Out-Null
        $elsewhere = Join-Path $TestDrive ("elsewhere-" + [guid]::NewGuid().ToString("N"))
        Write-Utf8Text -Path $elsewhere -Content "x"
        New-Item -ItemType SymbolicLink -Path (Join-Path $script:TargetHooks "one.sh") -Target $elsewhere | Out-Null

        Install-ManagedEntry -SourceDir $script:SourceHooks -TargetDir $script:TargetHooks -Name "hooks"

        Get-Link (Join-Path $script:TargetHooks "one.sh") | Should -Be $elsewhere
        ($script:Messages -join "`n") | Should -Match "1 skipped"
    }

    It "keeps a colliding real file as a timestamped backup and never deletes it" {
        New-Item -ItemType Directory -Path $script:TargetHooks | Out-Null
        Write-Utf8Text -Path (Join-Path $script:TargetHooks "one.sh") -Content "mine"

        Install-ManagedEntry -SourceDir $script:SourceHooks -TargetDir $script:TargetHooks -Name "hooks"
        Install-ManagedEntry -SourceDir $script:SourceHooks -TargetDir $script:TargetHooks -Name "hooks"

        Get-Link (Join-Path $script:TargetHooks "one.sh") | Should -Be (Join-Path $script:SourceHooks "one.sh")
        $backups = @(Get-ChildItem -LiteralPath $script:TargetHooks -Force | Where-Object { $_.Name -match '^one\.sh\.bak\.\d{8}-\d{6}(\.\d+)?$' })
        $backups.Count | Should -Be 1
        Read-Utf8Text $backups[0].FullName | Should -Be "mine"
    }

    It "never overwrites an earlier backup" {
        $path = Join-Path $TestDrive ("victim-" + [guid]::NewGuid().ToString("N"))
        Write-Utf8Text -Path $path -Content "first"
        $first = Backup-Path $path
        Write-Utf8Text -Path $path -Content "second"
        $second = Backup-Path $path
        $first | Should -Not -Be $second
        Read-Utf8Text (Join-Path $TestDrive $first) | Should -Be "first"
        Read-Utf8Text (Join-Path $TestDrive $second) | Should -Be "second"
    }

    It "refreshes a stale link of ours" {
        New-Item -ItemType Directory -Path $script:TargetHooks | Out-Null
        New-Item -ItemType SymbolicLink -Path (Join-Path $script:TargetHooks "one.sh") -Target (Join-Path $script:SourceHooks "two.sh") | Out-Null

        Install-ManagedEntry -SourceDir $script:SourceHooks -TargetDir $script:TargetHooks -Name "hooks"

        Get-Link (Join-Path $script:TargetHooks "one.sh") | Should -Be (Join-Path $script:SourceHooks "one.sh")
    }

    It "prunes our links whose repo entry is gone, but not foreign dangling links" {
        Install-ManagedEntry -SourceDir $script:SourceHooks -TargetDir $script:TargetHooks -Name "hooks"
        Remove-Item -LiteralPath (Join-Path $script:SourceHooks "two.sh")
        New-Item -ItemType SymbolicLink -Path (Join-Path $script:TargetHooks "foreign-dangling") -Target (Join-Path $TestDrive "missing-target") | Out-Null

        $script:Messages.Clear()
        Install-ManagedEntry -SourceDir $script:SourceHooks -TargetDir $script:TargetHooks -Name "hooks"

        Get-EntryItem (Join-Path $script:TargetHooks "two.sh") | Should -BeNullOrEmpty
        Get-EntryItem (Join-Path $script:TargetHooks "foreign-dangling") | Should -Not -BeNullOrEmpty
        ($script:Messages -join "`n") | Should -Match "1 pruned"
    }

    It "converts a whole-directory link and rescues untracked files out of the repo" {
        Write-Utf8Text -Path (Join-Path $script:SourceHooks "written-by-other-tool.sh") -Content "rescue me"
        New-Item -ItemType SymbolicLink -Path $script:TargetHooks -Target $script:SourceHooks | Out-Null

        Install-ManagedEntry -SourceDir $script:SourceHooks -TargetDir $script:TargetHooks -Name "hooks"

        Test-LinkItem (Get-EntryItem $script:TargetHooks) | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:SourceHooks "written-by-other-tool.sh") | Should -BeFalse
        Read-Utf8Text (Join-Path $script:TargetHooks "written-by-other-tool.sh") | Should -Be "rescue me"
        Get-Link (Join-Path $script:TargetHooks "one.sh") | Should -Be (Join-Path $script:SourceHooks "one.sh")
        @(Get-ChildItem -LiteralPath $script:ClaudeDir -Force | Where-Object { $_.Name -like "hooks.bak.*" }).Count | Should -Be 0
    }

    It "treats a profile linked to another profile linked to the repo as ours" {
        $profileA = Join-Path $TestDrive ("profile-a-" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $profileA | Out-Null
        New-Item -ItemType SymbolicLink -Path (Join-Path $profileA "skills") -Target $script:SourceSkills | Out-Null
        New-Item -ItemType SymbolicLink -Path $script:TargetSkills -Target (Join-Path $profileA "skills") | Out-Null

        Install-ManagedEntry -SourceDir $script:SourceSkills -TargetDir $script:TargetSkills -Name "skills"

        Test-LinkItem (Get-EntryItem $script:TargetSkills) | Should -BeFalse
        Get-Link (Join-Path $script:TargetSkills "sample-skill") | Should -Be (Join-Path $script:SourceSkills "sample-skill")
        @(Get-ChildItem -LiteralPath $script:ClaudeDir -Force | Where-Object { $_.Name -like "skills.bak.*" }).Count | Should -Be 0
        Get-Link (Join-Path $profileA "skills") | Should -Be $script:SourceSkills
    }

    It "keeps a whole-directory link to somewhere else as a backup" {
        $elsewhere = Join-Path $TestDrive ("other-hooks-" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $elsewhere | Out-Null
        New-Item -ItemType SymbolicLink -Path $script:TargetHooks -Target $elsewhere | Out-Null

        Install-ManagedEntry -SourceDir $script:SourceHooks -TargetDir $script:TargetHooks -Name "hooks"

        Test-LinkItem (Get-EntryItem $script:TargetHooks) | Should -BeFalse
        $backup = @(Get-ChildItem -LiteralPath $script:ClaudeDir -Force | Where-Object { $_.Name -like "hooks.bak.*" })
        $backup.Count | Should -Be 1
        Get-LinkTargetPath $backup[0] | Should -Be $elsewhere
    }

    It "does nothing when the config dir is the repo's .claude" {
        $script:ClaudeDir = Join-Path $script:RepoDir ".claude"
        Install-ManagedEntry -SourceDir $script:SourceHooks -TargetDir (Join-Path $script:ClaudeDir "hooks") -Name "hooks"
        ($script:Messages -join "`n") | Should -Match "same as repo"
    }

    Context "without symlink privilege" {
        BeforeEach {
            Mock New-SymbolicLinkEntry { throw "A required privilege is not held by the client." }
            Mock New-JunctionEntry { New-Item -ItemType SymbolicLink -Path $Path -Target $Target | Out-Null }
        }

        It "uses junctions for directories and manifest-tracked copies for files" {
            Install-ManagedEntry -SourceDir $script:SourceSkills -TargetDir $script:TargetSkills -Name "skills"
            Install-ManagedEntry -SourceDir $script:SourceHooks -TargetDir $script:TargetHooks -Name "hooks"

            Should -Invoke New-JunctionEntry -Times 1 -Exactly
            Get-Link (Join-Path $script:TargetSkills "sample-skill") | Should -Be (Join-Path $script:SourceSkills "sample-skill")
            Test-LinkItem (Get-EntryItem (Join-Path $script:TargetHooks "one.sh")) | Should -BeFalse
            Read-Utf8Text (Join-Path $script:TargetHooks "one.sh") | Should -Be "echo one`n"
            $manifest = Read-ManagedManifest $script:TargetHooks
            $manifest.Contains("one.sh") | Should -BeTrue
            $manifest.Contains("two.sh") | Should -BeTrue
            ($script:Messages -join "`n") | Should -Match "2 as copies"
        }

        It "leaves unchanged copies alone, refreshes changed ones, prunes removed ones" {
            Write-Utf8Text -Path (Join-Path (New-Item -ItemType Directory -Path $script:TargetHooks -Force).FullName "foreign.sh") -Content "foreign"
            Install-ManagedEntry -SourceDir $script:SourceHooks -TargetDir $script:TargetHooks -Name "hooks"
            $copy = Join-Path $script:TargetHooks "one.sh"
            $stamp = (Get-Item -LiteralPath $copy).LastWriteTimeUtc
            Start-Sleep -Milliseconds 50

            Install-ManagedEntry -SourceDir $script:SourceHooks -TargetDir $script:TargetHooks -Name "hooks"
            (Get-Item -LiteralPath $copy).LastWriteTimeUtc | Should -Be $stamp

            Write-Utf8Text -Path (Join-Path $script:SourceHooks "one.sh") -Content "echo changed`n"
            Remove-Item -LiteralPath (Join-Path $script:SourceHooks "two.sh")
            $script:Messages.Clear()
            Install-ManagedEntry -SourceDir $script:SourceHooks -TargetDir $script:TargetHooks -Name "hooks"

            Read-Utf8Text $copy | Should -Be "echo changed`n"
            Test-Path -LiteralPath (Join-Path $script:TargetHooks "two.sh") | Should -BeFalse
            (Read-ManagedManifest $script:TargetHooks).Contains("two.sh") | Should -BeFalse
            Read-Utf8Text (Join-Path $script:TargetHooks "foreign.sh") | Should -Be "foreign"
            ($script:Messages -join "`n") | Should -Match "1 pruned"
            ($script:Messages -join "`n") | Should -Match "1 left untouched"
        }

        It "copies directories too when junctions fail" {
            Mock New-JunctionEntry { throw "junctions unsupported" }
            Install-ManagedEntry -SourceDir $script:SourceSkills -TargetDir $script:TargetSkills -Name "skills"

            $copy = Join-Path $script:TargetSkills "sample-skill"
            Test-LinkItem (Get-EntryItem $copy) | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $copy "SKILL.md") | Should -BeTrue
            (Read-ManagedManifest $script:TargetSkills).Contains("sample-skill") | Should -BeTrue
        }
    }
}

Describe "Link helpers" {
    It "Remove-LinkItem deletes a directory link but not its target" {
        $target = Join-Path $TestDrive "kept-dir"
        New-Item -ItemType Directory -Path $target | Out-Null
        Write-Utf8Text -Path (Join-Path $target "inside.txt") -Content "keep"
        $link = Join-Path $TestDrive "dir-link"
        New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null

        Remove-LinkItem (Get-EntryItem $link)

        Get-EntryItem $link | Should -BeNullOrEmpty
        Read-Utf8Text (Join-Path $target "inside.txt") | Should -Be "keep"
    }

    It "Resolve-RealPath follows relative links and links inside the path" {
        $real = Join-Path $TestDrive "real-root"
        New-Item -ItemType Directory -Path (Join-Path $real "sub") -Force | Out-Null
        Push-Location $TestDrive
        try {
            New-Item -ItemType SymbolicLink -Path (Join-Path $TestDrive "rel-link") -Target "real-root" | Out-Null
        }
        finally {
            Pop-Location
        }
        Resolve-RealPath (Join-Path (Join-Path $TestDrive "rel-link") "sub") |
            Should -Be (Resolve-RealPath (Join-Path $real "sub"))
    }

    It "New-JunctionEntry fails loudly when nothing was created" {
        Mock New-Item { }
        { New-JunctionEntry -Path (Join-Path $TestDrive "no-junction") -Target $TestDrive } | Should -Throw
    }
}

Describe "Find-GitBash" {
    BeforeEach {
        $script:SavedGitBash = $env:CLAUDE_CODE_GIT_BASH_PATH
    }

    AfterEach {
        $env:CLAUDE_CODE_GIT_BASH_PATH = $script:SavedGitBash
    }

    It "prefers CLAUDE_CODE_GIT_BASH_PATH when it exists" {
        $fake = Join-Path $TestDrive "custom-bash.exe"
        Write-Utf8Text -Path $fake -Content ""
        $env:CLAUDE_CODE_GIT_BASH_PATH = $fake
        Find-GitBash | Should -Be $fake
    }

    It "ignores a CLAUDE_CODE_GIT_BASH_PATH that does not exist" {
        $env:CLAUDE_CODE_GIT_BASH_PATH = Join-Path $TestDrive "missing-bash.exe"
        Find-GitBash | Should -Not -Be (Join-Path $TestDrive "missing-bash.exe")
    }

    It "finds bash.exe beside the git on PATH" {
        $env:CLAUDE_CODE_GIT_BASH_PATH = ""
        $gitRoot = Join-Path $TestDrive "PortableGit"
        New-Item -ItemType Directory -Path (Join-Path $gitRoot "cmd"), (Join-Path $gitRoot "bin") -Force | Out-Null
        Write-Utf8Text -Path (Join-Path (Join-Path $gitRoot "bin") "bash.exe") -Content ""
        Mock Get-Command { [PSCustomObject]@{ Source = (Join-Path (Join-Path $gitRoot "cmd") "git.exe") } } -ParameterFilter { $Name -eq "git" }
        Find-GitBash | Should -Be (Join-Path (Join-Path $gitRoot "bin") "bash.exe")
    }

    It "never returns WSL's System32 bash" {
        $env:CLAUDE_CODE_GIT_BASH_PATH = ""
        Mock Get-Command { $null } -ParameterFilter { $Name -eq "git" }
        Mock Get-Command { [PSCustomObject]@{ Source = "C:\Windows\System32\bash.exe" } } -ParameterFilter { $Name -eq "bash" }
        Find-GitBash | Should -Not -Match "System32"
    }
}

Describe "Get-UpdatedUserPath" {
    It "prepends the directory" {
        Get-UpdatedUserPath -CurrentPath "C:\a;C:\b" -Directory "C:\repo\bin" -Separator ";" |
            Should -Be "C:\repo\bin;C:\a;C:\b"
    }

    It "returns null when the directory is already present" {
        Get-UpdatedUserPath -CurrentPath "C:\a;C:\repo\bin" -Directory "C:\repo\bin" -Separator ";" |
            Should -BeNullOrEmpty
    }

    It "handles an empty user PATH without a dangling separator" {
        Get-UpdatedUserPath -CurrentPath "" -Directory "C:\repo\bin" -Separator ";" | Should -Be "C:\repo\bin"
    }
}

Describe "Native commands under the Stop preference" {
    # Only Windows PowerShell 5.1 turns redirected native stderr into a
    # terminating error, so this guards the Windows lane; elsewhere it must pass.
    BeforeAll {
        $script:FakeBin = Join-Path $TestDrive "fake-bin"
        New-Item -ItemType Directory -Path $script:FakeBin | Out-Null
        if (Test-WindowsHost) {
            Write-Utf8Text -Path (Join-Path $script:FakeBin "claude.cmd") -Content "@echo warning: noisy 1>&2`r`n@exit /b 0`r`n"
        }
        else {
            $fake = Join-Path $script:FakeBin "claude"
            Write-Utf8Text -Path $fake -Content "#!/bin/sh`necho 'warning: noisy' >&2`nexit 0`n"
            & chmod +x $fake
        }
        $script:SavedPath = $env:PATH
        $env:PATH = $script:FakeBin + [System.IO.Path]::PathSeparator + $env:PATH
    }

    AfterAll {
        $env:PATH = $script:SavedPath
    }

    It "a warning on stderr does not turn a successful MCP install into a failure" {
        $ErrorActionPreference = "Stop"
        $script:Messages = New-Object System.Collections.Generic.List[string]
        Mock Write-Status { $script:Messages.Add($Message) }
        Install-SingleMcp -Key "tavily" -Backend "doppler"
        ($script:Messages -join "`n") | Should -Match "tavily MCP added"
    }
}

# ============================================================================
# OpenCode parallel install (mirrors tests/opencode-setup.bats)
# ============================================================================

Describe "OpenCode" {
    BeforeAll {
        function New-Agent([string]$Name, [string]$Frontmatter, [string]$Body = "Body text.`n") {
            $src = Join-Path $script:AgentSrcDir "${Name}.md"
            Write-Utf8Text -Path $src -Content ("---`n" + $Frontmatter + "`n---`n" + $Body)
            Convert-OpenCodeAgent -Source $src -Destination (Join-Path $script:AgentDestDir "${Name}.md") | Out-Null
            return Read-Utf8Text (Join-Path $script:AgentDestDir "${Name}.md")
        }
    }

    BeforeEach {
        $script:SavedOverride = $env:OPENCODE_CONFIG_DIR_OVERRIDE
        $script:SavedForce = $env:OPENCODE_FORCE
        $env:OPENCODE_FORCE = ""
        $script:OcRoot = Join-Path $TestDrive ("oc-" + [guid]::NewGuid().ToString("N"))
        $env:OPENCODE_CONFIG_DIR_OVERRIDE = Join-Path $script:OcRoot "opencode"
        $script:RepoDir = Join-Path $script:OcRoot "repo"
        $script:AgentSrcDir = Join-Path $script:OcRoot "agents-src"
        $script:AgentDestDir = Join-Path $env:OPENCODE_CONFIG_DIR_OVERRIDE "agents"
        New-Item -ItemType Directory -Path (Join-Path (Join-Path $script:RepoDir ".claude") "skills"), $script:AgentSrcDir -Force | Out-Null
        $script:InstallMcpServers = @("brave-search", "tavily")
        $script:Messages = New-Object System.Collections.Generic.List[string]
        Mock Write-Status { $script:Messages.Add($Message) }
        Mock Get-McpBackend { "envfile" }
    }

    AfterEach {
        $env:OPENCODE_CONFIG_DIR_OVERRIDE = $script:SavedOverride
        $env:OPENCODE_FORCE = $script:SavedForce
    }

    Context "detection" {
        It "OPENCODE_FORCE=<_> means yes regardless of the binary" -ForEach @("1", "true", "yes", "on", "TRUE") {
            Mock Test-OpenCodeBinary { $false }
            $env:OPENCODE_FORCE = $_
            Test-OpenCodeInstalled | Should -BeTrue
        }

        It "OPENCODE_FORCE=<_> means no regardless of the binary" -ForEach @("0", "false", "no", "off", "OFF") {
            Mock Test-OpenCodeBinary { $true }
            $env:OPENCODE_FORCE = $_
            Test-OpenCodeInstalled | Should -BeFalse
        }

        It "an existing config dir counts as installed without a binary" {
            Mock Test-OpenCodeBinary { $false }
            New-Item -ItemType Directory -Path $env:OPENCODE_CONFIG_DIR_OVERRIDE -Force | Out-Null
            Test-OpenCodeInstalled | Should -BeTrue
            Get-OpenCodeDetectLabel | Should -Match "config dir"
        }

        It "no binary, no dir, no force means not installed" {
            Mock Test-OpenCodeBinary { $false }
            Test-OpenCodeInstalled | Should -BeFalse
            Get-OpenCodeDetectLabel | Should -Be "no (not installed)"
        }

        It "reports forced state" {
            $env:OPENCODE_FORCE = "1"
            Get-OpenCodeDetectLabel | Should -Match "forced"
            $env:OPENCODE_FORCE = "0"
            Get-OpenCodeDetectLabel | Should -Match "forced"
        }

        It "follows XDG_CONFIG_HOME when no override is set" {
            $env:OPENCODE_CONFIG_DIR_OVERRIDE = ""
            $savedXdg = $env:XDG_CONFIG_HOME
            try {
                $env:XDG_CONFIG_HOME = Join-Path $TestDrive "xdg"
                Get-OpenCodeConfigDir | Should -Be (Join-Path (Join-Path $TestDrive "xdg") "opencode")
                $env:XDG_CONFIG_HOME = ""
                Get-OpenCodeConfigDir | Should -Be (Join-Path (Join-Path $HOME ".config") "opencode")
            }
            finally {
                $env:XDG_CONFIG_HOME = $savedXdg
            }
        }
    }

    Context "agent translation" {
        It "drops name: (the file name is the name in OpenCode)" {
            New-Agent "named" "name: named`ndescription: d" | Should -Not -Match "name: named"
        }

        It "drops model: inherit" {
            New-Agent "inheritor" "description: d`nmodel: inherit" | Should -Not -Match "model: inherit"
        }

        It "keeps a concrete model" {
            New-Agent "pinned" "description: d`nmodel: sonnet" | Should -Match "model: sonnet"
        }

        It "drops a hooks: block" {
            $out = New-Agent "hooked" "description: d`nhooks:`n  PreToolUse:`n    - matcher: Bash`n      command: sql-guardrail.sh`nskills:`n  - x" "body`n"
            $out | Should -Not -Match "hooks:"
            $out | Should -Not -Match "sql-guardrail"
            $out | Should -Match "skills:"
            $out | Should -Match "body"
        }

        It "drops tools: as CSV and as a block" {
            New-Agent "tooled" "description: d`ntools: Read, Grep" | Should -Not -Match "tools: Read"
            $out = New-Agent "tooled-block" "description: d`ntools:`n  - Read`n  - Grep`ncolor: red"
            $out | Should -Not -Match "tools:"
            $out | Should -Not -Match "- Read"
            $out | Should -Match "color: error"
        }

        It "adds mode: subagent when absent and keeps an existing mode" {
            New-Agent "modeless" "description: d" | Should -Match "mode: subagent"
            $out = New-Agent "primary" "description: d`nmode: primary"
            $out | Should -Match "mode: primary"
            $out | Should -Not -Match "mode: subagent"
        }

        It "preserves description, skills and the body" {
            $out = New-Agent "preserve" "name: preserve`ndescription: Long description that should survive`nskills:`n  - python-standards`n  - rust-standards" "This is the body.`n`nmultiple paragraphs`n"
            $out | Should -Match "description: Long description that should survive"
            $out | Should -Match "- python-standards"
            $out | Should -Match "- rust-standards"
            $out | Should -Match "This is the body\."
            $out | Should -Match "multiple paragraphs"
        }

        It "maps color <In> to <Out>" -ForEach @(
            @{ In = "red"; Out = "error" }, @{ In = "green"; Out = "success" }, @{ In = "yellow"; Out = "warning" },
            @{ In = "orange"; Out = "warning" }, @{ In = "blue"; Out = "info" }, @{ In = "cyan"; Out = "info" },
            @{ In = "purple"; Out = "accent" }, @{ In = "pink"; Out = "accent" }, @{ In = "success"; Out = "success" },
            @{ In = "'#fab283'"; Out = "#fab283" }, @{ In = '"Blue"'; Out = "info" }
        ) {
            New-Agent ("color-" + [guid]::NewGuid().ToString("N")) "description: d`ncolor: ${In}" | Should -Match "(?m)^color: ${Out}$"
        }

        It "drops an unknown color entirely" {
            New-Agent "mauve" "description: d`ncolor: mauve" | Should -Not -Match "color:"
        }

        It "is case-sensitive like the bash translator (Name: is not name:)" {
            New-Agent "cased" "Name: keep-me`ndescription: d" | Should -Match "Name: keep-me"
        }

        It "every agent in the repo translates to a valid OpenCode color" {
            $repoAgents = Join-Path (Join-Path $repoRoot ".claude") "agents"
            foreach ($agent in Get-ChildItem -LiteralPath $repoAgents -Filter "*.md" -File) {
                $dest = Join-Path $script:AgentDestDir $agent.Name
                Convert-OpenCodeAgent -Source $agent.FullName -Destination $dest | Out-Null
                $colorLine = (Read-Utf8Text $dest) -split "`n" | Where-Object { $_ -match '^color:' } | Select-Object -First 1
                if ($colorLine) {
                    $value = ($colorLine -replace '^color:\s*', '').Trim()
                    ($value -cmatch '^#[0-9a-fA-F]{6}$' -or $script:OpenCodeThemeTokens -contains $value) | Should -BeTrue -Because "$($agent.Name) emitted color '$value'"
                }
            }
        }

        It "produces --- delimited frontmatter" {
            $out = New-Agent "yaml-test" "name: y`ndescription: d"
            ($out -split "`n")[0] | Should -Be "---"
            @(($out -split "`n") | Where-Object { $_ -eq "---" }).Count | Should -BeGreaterOrEqual 2
        }

        It "skips a file without frontmatter but still counts it" {
            $src = Join-Path $script:AgentSrcDir "plain.md"
            Write-Utf8Text -Path $src -Content "no frontmatter here`n"
            Convert-OpenCodeAgent -Source $src -Destination (Join-Path $script:AgentDestDir "plain.md") | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $script:AgentDestDir "plain.md") | Should -BeFalse
        }
    }

    Context "opencode.json" {
        It "writes valid JSON with an mcp section using mcp-env-inject and type local" {
            Update-OpenCodeConfig
            $json = Read-Utf8Text (Get-OpenCodeConfigPath) | ConvertFrom-Json
            $json.mcp."brave-search".command[0] | Should -Be "mcp-env-inject"
            $json.mcp.tavily.type | Should -Be "local"
            $json.mcp.tavily.enabled | Should -BeTrue
            $json.'$schema' | Should -Be "https://opencode.ai/config.json"
        }

        It "preserves existing keys when merging" {
            New-Item -ItemType Directory -Path $env:OPENCODE_CONFIG_DIR_OVERRIDE -Force | Out-Null
            Write-Utf8Text -Path (Join-Path $env:OPENCODE_CONFIG_DIR_OVERRIDE "opencode.json") -Content '{"model": "provider/some-model", "autoupdate": false, "mcp": {"mine": {"type": "remote", "url": "https://example.com/mcp"}}}'
            Update-OpenCodeConfig
            $json = Read-Utf8Text (Get-OpenCodeConfigPath) | ConvertFrom-Json
            $json.model | Should -Be "provider/some-model"
            $json.autoupdate | Should -BeFalse
            $json.mcp.mine.url | Should -Be "https://example.com/mcp"
            $json.mcp.tavily.type | Should -Be "local"
        }

        It "is idempotent" {
            Update-OpenCodeConfig
            $first = Read-Utf8Text (Get-OpenCodeConfigPath)
            Update-OpenCodeConfig
            Read-Utf8Text (Get-OpenCodeConfigPath) | Should -BeExactly $first
        }

        It "emits a doppler run command for the doppler backend" {
            $script:DopplerProject = "claude-code-config"
            $script:DopplerConfig = "dev"
            $entry = Get-OpenCodeMcpEntry -Package "tavily-mcp@0.2.17" -Backend "doppler"
            $entry.command | Should -Be @("doppler", "run", "-p", "claude-code-config", "-c", "dev", "--", "npx", "-y", "tavily-mcp@0.2.17")
            (Get-OpenCodeMcpEntry -Package "pkg" -Backend "envfile").command | Should -Be @("mcp-env-inject", "npx", "-y", "pkg")
        }

        It "follows the active backend" {
            Mock Get-McpBackend { "doppler" }
            Update-OpenCodeConfig
            (Read-Utf8Text (Get-OpenCodeConfigPath) | ConvertFrom-Json).mcp.tavily.command[0] | Should -Be "doppler"
        }

        It "writes into an existing opencode.jsonc instead of splitting the config" {
            New-Item -ItemType Directory -Path $env:OPENCODE_CONFIG_DIR_OVERRIDE -Force | Out-Null
            $jsonc = Join-Path $env:OPENCODE_CONFIG_DIR_OVERRIDE "opencode.jsonc"
            Write-Utf8Text -Path $jsonc -Content "{`n  // comment`n  `"plugin`": [`"@scope/opencode-quota`"],`n  `"share`": `"disabled`", /* block */`n}`n"
            Update-OpenCodeConfig
            Test-Path -LiteralPath (Join-Path $env:OPENCODE_CONFIG_DIR_OVERRIDE "opencode.json") | Should -BeFalse
            $json = Read-Utf8Text $jsonc | ConvertFrom-Json
            @($json.plugin)[0] | Should -Be "@scope/opencode-quota"
            $json.share | Should -Be "disabled"
            $json.mcp.tavily.command[0] | Should -Be "mcp-env-inject"
        }

        It "skips the mcp section when no MCP servers are selected" {
            $script:InstallMcpServers = @()
            Update-OpenCodeConfig
            Test-Path -LiteralPath (Get-OpenCodeConfigPath) | Should -BeFalse
        }

        It "backs up a config it cannot parse and still writes a valid one" {
            New-Item -ItemType Directory -Path $env:OPENCODE_CONFIG_DIR_OVERRIDE -Force | Out-Null
            Write-Utf8Text -Path (Join-Path $env:OPENCODE_CONFIG_DIR_OVERRIDE "opencode.json") -Content "{ not json"
            Update-OpenCodeConfig
            @(Get-ChildItem -LiteralPath $env:OPENCODE_CONFIG_DIR_OVERRIDE -Filter "opencode.json.bak.*").Count | Should -Be 1
            { Read-Utf8Text (Get-OpenCodeConfigPath) | ConvertFrom-Json } | Should -Not -Throw
        }
    }

    Context "JSONC stripping" {
        It "removes line comments" {
            ConvertFrom-Jsonc "{`n  // a comment`n  `"a`": 1`n}" | Should -Not -Match "a comment"
        }

        It "removes block comments" {
            ConvertFrom-Jsonc "{ /* multi`nline */ `"a`": 1 }" | Should -Not -Match "multi"
        }

        It "preserves // inside a schema URL and inside any string" {
            $out = ConvertFrom-Jsonc '{"$schema": "https://opencode.ai/config.json", "x": "a//b"} // trailing'
            ($out | ConvertFrom-Json).'$schema' | Should -Be "https://opencode.ai/config.json"
            ($out | ConvertFrom-Json).x | Should -Be "a//b"
        }

        It "survives a comment containing the letter n" {
            ConvertFrom-Jsonc "{`n  // existing note`n  `"a`": 1`n}" | Should -Not -Match "existing note"
        }

        It "drops trailing commas but not commas inside strings" {
            $out = ConvertFrom-Jsonc '{"a": [1, 2,], "b": "x,}", }'
            $parsed = $out | ConvertFrom-Json
            @($parsed.a).Count | Should -Be 2
            $parsed.b | Should -Be "x,}"
        }

        It "keeps escaped quotes inside strings" {
            (ConvertFrom-Jsonc '{"a": "say \"hi\" // not a comment"}' | ConvertFrom-Json).a | Should -Be 'say "hi" // not a comment'
        }
    }

    Context "skills link" {
        It "links the config skills dir to the repo skills" {
            Set-OpenCodeSkillsLink
            $item = Get-EntryItem (Join-Path $env:OPENCODE_CONFIG_DIR_OVERRIDE "skills")
            Test-LinkItem $item | Should -BeTrue
            Get-LinkTargetPath $item | Should -Be (Join-Path (Join-Path $script:RepoDir ".claude") "skills")
        }

        It "is idempotent" {
            New-Item -ItemType Directory -Path $env:OPENCODE_CONFIG_DIR_OVERRIDE -Force | Out-Null
            Set-OpenCodeSkillsLink
            $script:Messages.Clear()
            Set-OpenCodeSkillsLink
            ($script:Messages -join "`n") | Should -Match "already configured"
        }

        It "replaces a stale link pointing elsewhere" {
            New-Item -ItemType Directory -Path $env:OPENCODE_CONFIG_DIR_OVERRIDE -Force | Out-Null
            $other = Join-Path $script:OcRoot "other-skills"
            New-Item -ItemType Directory -Path $other | Out-Null
            New-Item -ItemType SymbolicLink -Path (Join-Path $env:OPENCODE_CONFIG_DIR_OVERRIDE "skills") -Target $other | Out-Null
            Set-OpenCodeSkillsLink
            Get-LinkTargetPath (Get-EntryItem (Join-Path $env:OPENCODE_CONFIG_DIR_OVERRIDE "skills")) |
                Should -Be (Join-Path (Join-Path $script:RepoDir ".claude") "skills")
            Test-Path -LiteralPath (Join-Path $other ".") | Should -BeTrue
        }

        It "backs up a real directory before linking" {
            $real = Join-Path $env:OPENCODE_CONFIG_DIR_OVERRIDE "skills"
            New-Item -ItemType Directory -Path $real -Force | Out-Null
            Write-Utf8Text -Path (Join-Path $real "mine.txt") -Content "keep"
            Set-OpenCodeSkillsLink
            $backup = @(Get-ChildItem -LiteralPath $env:OPENCODE_CONFIG_DIR_OVERRIDE -Directory | Where-Object { $_.Name -like "skills.bak.*" })
            $backup.Count | Should -Be 1
            Read-Utf8Text (Join-Path $backup[0].FullName "mine.txt") | Should -Be "keep"
        }

        It "falls back to a junction without symlink privilege" {
            Mock New-SymbolicLinkEntry { throw "A required privilege is not held by the client." }
            Mock New-JunctionEntry { New-Item -ItemType SymbolicLink -Path $Path -Target $Target | Out-Null }
            New-Item -ItemType Directory -Path $env:OPENCODE_CONFIG_DIR_OVERRIDE -Force | Out-Null
            Set-OpenCodeSkillsLink
            Should -Invoke New-JunctionEntry -Times 1 -Exactly
        }
    }

    Context "AGENTS.md" {
        BeforeEach {
            Write-Utf8Text -Path (Join-Path $script:RepoDir "CLAUDE.md") -Content "rules"
        }

        It "links AGENTS.md to CLAUDE.md when CLAUDE.md exists" {
            Set-AgentsMdLink
            $item = Get-EntryItem (Join-Path $script:RepoDir "AGENTS.md")
            Test-LinkItem $item | Should -BeTrue
            Get-LinkTargetPath $item | Should -Be (Join-Path $script:RepoDir "CLAUDE.md")
        }

        It "leaves a regular AGENTS.md alone" {
            Write-Utf8Text -Path (Join-Path $script:RepoDir "AGENTS.md") -Content "mine"
            Set-AgentsMdLink
            ($script:Messages -join "`n") | Should -Match "leaving alone"
            Read-Utf8Text (Join-Path $script:RepoDir "AGENTS.md") | Should -Be "mine"
        }

        It "is idempotent" {
            Set-AgentsMdLink
            $script:Messages.Clear()
            Set-AgentsMdLink
            ($script:Messages -join "`n") | Should -Match "already linked"
        }
    }

    Context "full flow" {
        It "mirrors skills, agents, MCP and AGENTS.md when opencode is present" {
            Mock Get-Command { [PSCustomObject]@{ Name = "opencode"; Source = "opencode" } } -ParameterFilter { $Name -eq "opencode" }
            Write-Utf8Text -Path (Join-Path $script:RepoDir "CLAUDE.md") -Content "rules"
            $agents = Join-Path (Join-Path $script:RepoDir ".claude") "agents"
            New-Item -ItemType Directory -Path $agents -Force | Out-Null
            Write-Utf8Text -Path (Join-Path $agents "sample.md") -Content "---`nname: sample`ndescription: d`ncolor: blue`n---`nbody`n"

            Install-OpenCode

            Test-LinkItem (Get-EntryItem (Join-Path $env:OPENCODE_CONFIG_DIR_OVERRIDE "skills")) | Should -BeTrue
            Read-Utf8Text (Join-Path (Join-Path $env:OPENCODE_CONFIG_DIR_OVERRIDE "agents") "sample.md") | Should -Match "color: info"
            (Read-Utf8Text (Get-OpenCodeConfigPath) | ConvertFrom-Json).mcp.tavily.type | Should -Be "local"
            Test-LinkItem (Get-EntryItem (Join-Path $script:RepoDir "AGENTS.md")) | Should -BeTrue
            ($script:Messages -join "`n") | Should -Match "1 agents translated"
        }

        It "skips everything when opencode is not on PATH" {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq "opencode" }
            Install-OpenCode
            ($script:Messages -join "`n") | Should -Match "opencode CLI not found"
            Test-Path -LiteralPath $env:OPENCODE_CONFIG_DIR_OVERRIDE | Should -BeFalse
        }
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
# Paths: CLAUDE_CONFIG_DIR
# ============================================================================

Describe "Claude config directory resolution" {
    BeforeAll {
        $script:FakeHome = Join-Path $TestDrive "home"
        $script:OutsideDir = Join-Path $TestDrive "elsewhere"
    }

    Context "Get-ClaudeConfigDir" {
        It "defaults to ~/.claude when CLAUDE_CONFIG_DIR is unset" {
            Get-ClaudeConfigDir -ConfigDir "" -HomeDir $script:FakeHome |
                Should -Be (Join-Path $script:FakeHome ".claude")
        }

        It "uses CLAUDE_CONFIG_DIR without its trailing separators" {
            Get-ClaudeConfigDir -ConfigDir "/opt/cfg/claude//" -HomeDir $script:FakeHome | Should -Be "/opt/cfg/claude"
            Get-ClaudeConfigDir -ConfigDir "C:\cfg\claude\" -HomeDir $script:FakeHome | Should -Be "C:\cfg\claude"
        }
    }

    Context "Get-ClaudeJsonPath" {
        It "sits beside ~/.claude in HOME by default" {
            Get-ClaudeJsonPath -ConfigDir "" -HomeDir $script:FakeHome |
                Should -Be (Join-Path $script:FakeHome ".claude.json")
        }

        It "moves inside CLAUDE_CONFIG_DIR when set" {
            Get-ClaudeJsonPath -ConfigDir $script:OutsideDir -HomeDir $script:FakeHome |
                Should -Be (Join-Path $script:OutsideDir ".claude.json")
        }
    }

    Context "Get-ClaudeConfigDirRef" {
        It "is ~/.claude when unset, so existing settings do not change" {
            Get-ClaudeConfigDirRef -ConfigDir "" -HomeDir "/h/user" | Should -Be "~/.claude"
        }

        It "is ~/<relative> for a directory under HOME" {
            Get-ClaudeConfigDirRef -ConfigDir "/h/user/.claude-work" -HomeDir "/h/user" | Should -Be "~/.claude-work"
            Get-ClaudeConfigDirRef -ConfigDir "/h/user/cfg/claude/" -HomeDir "/h/user/" | Should -Be "~/cfg/claude"
        }

        It "uses forward slashes for Windows paths" {
            Get-ClaudeConfigDirRef -ConfigDir "C:\Users\dev\.claude-work" -HomeDir "C:\Users\dev" |
                Should -Be "~/.claude-work"
            Get-ClaudeConfigDirRef -ConfigDir "D:\cfg\claude" -HomeDir "C:\Users\dev" | Should -Be "D:/cfg/claude"
        }

        It "keeps the absolute path outside HOME" {
            Get-ClaudeConfigDirRef -ConfigDir "/opt/claude" -HomeDir "/h/user" | Should -Be "/opt/claude"
        }

        It "does not treat a sibling with the same prefix as being under HOME" {
            Get-ClaudeConfigDirRef -ConfigDir "/h/user2/claude" -HomeDir "/h/user" | Should -Be "/h/user2/claude"
        }

        It "keeps the absolute path when CLAUDE_CONFIG_DIR is HOME itself" {
            Get-ClaudeConfigDirRef -ConfigDir "/h/user" -HomeDir "/h/user" | Should -Be "/h/user"
        }
    }

    Context "settings.json commands follow the config directory" {
        BeforeEach {
            $script:SavedConfigDir = $env:CLAUDE_CONFIG_DIR
            $script:SettingsJson = Join-Path $TestDrive "settings-ref.json"
            Write-Utf8Text -Path $script:SettingsJson -Content "{}"
        }

        AfterEach {
            $env:CLAUDE_CONFIG_DIR = $script:SavedConfigDir
        }

        It "writes ~/.claude commands when CLAUDE_CONFIG_DIR is unset" {
            $env:CLAUDE_CONFIG_DIR = ""
            Update-IdeHook
            Update-Statusline
            Update-FileSuggestion
            $settings = Read-Utf8Text $script:SettingsJson | ConvertFrom-Json
            $settings.hooks.PreToolUse[0].hooks[0].command | Should -Be "~/.claude/hooks/open-file-in-ide.sh"
            $settings.statusLine.command | Should -Be "~/.claude/scripts/statusline.sh"
            $settings.fileSuggestion.command | Should -Match ([regex]::Escape('"~/.claude/scripts/file-suggestion.ps1"'))
        }

        It "writes the CLAUDE_CONFIG_DIR prefix when set" {
            $env:CLAUDE_CONFIG_DIR = Join-Path $HOME ".claude-alt"
            Update-IdeHook
            Update-Statusline
            Update-FileSuggestion
            $settings = Read-Utf8Text $script:SettingsJson | ConvertFrom-Json
            $settings.hooks.PreToolUse[0].hooks[0].command | Should -Be "~/.claude-alt/hooks/open-file-in-ide.sh"
            $settings.statusLine.command | Should -Be "~/.claude-alt/scripts/statusline.sh"
            $settings.fileSuggestion.command | Should -Match ([regex]::Escape('"~/.claude-alt/scripts/file-suggestion.ps1"'))
        }

        It "Copy-RepoSetting keeps the repo file byte-identical when unset" {
            $env:CLAUDE_CONFIG_DIR = ""
            $script:RepoDir = $repoRoot
            Copy-RepoSetting
            $repoFile = Join-Path (Join-Path $repoRoot ".claude") "settings.json"
            Read-Utf8Text $script:SettingsJson | Should -BeExactly (Read-Utf8Text $repoFile)
        }

        It "Copy-RepoSetting rewrites every command into CLAUDE_CONFIG_DIR when set" {
            $env:CLAUDE_CONFIG_DIR = Join-Path $HOME ".claude-alt"
            $script:RepoDir = $repoRoot
            Copy-RepoSetting
            $text = Read-Utf8Text $script:SettingsJson
            $text | Should -Not -Match ([regex]::Escape("~/.claude/"))
            $text | Should -Match ([regex]::Escape("~/.claude-alt/hooks/"))
            { $text | ConvertFrom-Json } | Should -Not -Throw
        }
    }

    Context "mcp-keys.env follows the config directory" {
        AfterEach {
            Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
            Remove-Item Env:MCP_KEYS_ENV_FILE -ErrorAction SilentlyContinue
            . (Join-Path $setupPsDir "mcp.ps1")
        }

        It "lives under CLAUDE_CONFIG_DIR when set" {
            $env:CLAUDE_CONFIG_DIR = $script:OutsideDir
            . (Join-Path $setupPsDir "mcp.ps1")
            $script:McpKeysEnvFile | Should -Be (Join-Path $script:OutsideDir "mcp-keys.env")
        }

        It "MCP_KEYS_ENV_FILE still wins" {
            $env:CLAUDE_CONFIG_DIR = $script:OutsideDir
            $env:MCP_KEYS_ENV_FILE = Join-Path $TestDrive "keys.env"
            . (Join-Path $setupPsDir "mcp.ps1")
            $script:McpKeysEnvFile | Should -Be (Join-Path $TestDrive "keys.env")
        }
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
    It "lib/setup-ps/<_> exists" -ForEach @("fileio.ps1", "paths.ps1", "output.ps1", "tui.ps1", "preview.ps1",
        "filesystem.ps1", "settings.ps1", "statusline-conf.ps1", "mcp.ps1", "opencode.ps1", "menu.ps1") {
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
