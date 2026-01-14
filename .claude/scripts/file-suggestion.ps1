# file-suggestion.ps1
# Path: .claude/scripts/file-suggestion.ps1
#
# Custom file suggestion script for Claude Code that provides fast, intelligent
# file discovery using modern CLI tools (fd + fzf) on Windows.
#
# This script leverages:
#   - fd: Fast file finder (Rust-based, replaces 'find')
#   - fzf: Fuzzy finder for filtering results
#
# Benefits over default file suggestion:
#   - 10-100x faster on large codebases (1000+ files)
#   - Respects .gitignore automatically
#   - Follows symlinks correctly
#   - Better fuzzy matching with fzf
#
# Usage: Called automatically by Claude Code when using @ file mentions
# Input: Receives JSON via stdin containing query string
# Output: Returns up to 15 matching file paths (relative to project root)
#
# Prerequisites:
#   - fd (https://github.com/sharkdp/fd)
#   - fzf (https://github.com/junegunn/fzf)
#
# Installation:
#   scoop install fd fzf       (Recommended)
#   winget install sharkdp.fd junegunn.fzf
#   choco install fd fzf

$ErrorActionPreference = "Stop"

try {
    # Read JSON input from stdin
    $InputJson = $input | Out-String

    # Parse JSON to extract query
    $InputData = $InputJson | ConvertFrom-Json
    $Query = if ($InputData.query) { $InputData.query } else { "" }

    # Use project directory from environment variable (provided by Claude Code)
    # Falls back to current directory if not set
    $ProjectDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { Get-Location }

    # Change to project directory
    Set-Location $ProjectDir

    # Check if required tools are available
    if (-not (Get-Command fd -ErrorAction SilentlyContinue)) {
        Write-Error "fd not found. Install with: scoop install fd (or winget install sharkdp.fd)"
        exit 1
    }

    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Error "fzf not found. Install with: scoop install fzf (or winget install junegunn.fzf)"
        exit 1
    }

    # Main file discovery pipeline:
    # 1. fd --type f: Find all files (not directories)
    # 2. --hidden: Include hidden files (like .env, .gitignore)
    # 3. --follow: Follow symlinks
    # 4. --exclude .git: Never include .git directory contents
    # 5. fzf --filter: Fuzzy match against query
    # 6. Select-Object -First 15: Limit to 15 results

    $Results = & fd --type f `
                    --hidden `
                    --follow `
                    --exclude .git `
                    . 2>$null `
              | & fzf --filter $Query `
              | Select-Object -First 15

    # Output results
    if ($Results) {
        $Results | ForEach-Object { Write-Output $_ }
    }

    exit 0
}
catch {
    Write-Error "File suggestion error: $_"
    exit 1
}
