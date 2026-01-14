#!/bin/bash
# file-suggestion.sh
# Path: .claude/scripts/file-suggestion.sh
#
# Custom file suggestion script for Claude Code that provides fast, intelligent
# file discovery using modern CLI tools (fd + fzf).
#
# This script leverages:
#   - fd: Fast file finder (Rust-based, replaces 'find')
#   - fzf: Fuzzy finder for filtering results
#   - jq: JSON parser for handling Claude Code's input format
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
#   - fd-find (https://github.com/sharkdp/fd)
#   - fzf (https://github.com/junegunn/fzf)
#   - jq (https://stedolan.github.io/jq/)
#
# Installation:
#   macOS:   brew install fd fzf jq
#   Ubuntu:  apt install fd-find fzf jq
#   Fedora:  dnf install fd-find fzf jq
#   Windows: scoop install fd fzf jq

set -e

# Parse JSON input to extract query string
QUERY=$(jq -r '.query // ""')

# Use project directory from environment variable (provided by Claude Code)
# Falls back to current directory if not set
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# Change to project directory so fd outputs relative paths
cd "$PROJECT_DIR" || exit 1

# Check if required tools are available
if ! command -v fd &> /dev/null; then
    echo "Error: fd not found. Install with: brew install fd (macOS) or apt install fd-find (Linux)" >&2
    exit 1
fi

if ! command -v fzf &> /dev/null; then
    echo "Error: fzf not found. Install with: brew install fzf (macOS) or apt install fzf (Linux)" >&2
    exit 1
fi

# Main file discovery pipeline:
# 1. fd --type f: Find all files (not directories)
# 2. --hidden: Include hidden files (like .env, .gitignore)
# 3. --follow: Follow symlinks (important for node_modules, etc.)
# 4. --exclude .git: Never include .git directory contents
# 5. fzf --filter: Fuzzy match against query
# 6. head -15: Limit to 15 results (prevents overwhelming Claude's context)
fd --type f \
   --hidden \
   --follow \
   --exclude .git \
   . 2>/dev/null \
  | fzf --filter "$QUERY" \
  | head -15

# Exit successfully
exit 0
