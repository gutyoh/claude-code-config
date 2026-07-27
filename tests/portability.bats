#!/usr/bin/env bats
# portability.bats -- repo-wide guards against machine-specific assumptions.
#
# This repo is installed on other people's machines, so nothing shipped may
# depend on one developer's paths, shell, package manager, or OS. These are
# static guards: they read the tree rather than exercising behaviour, so they
# stay fast and run in the `unit` lane.

bats_require_minimum_version 1.5.0

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_ROOT
}

# Files we ship and therefore must keep portable. Docs prose may legitimately
# name absolute paths as examples, so only executable/config content is scanned.
#
# `--others --exclude-standard` includes new-but-uncommitted files: without it
# a violation stays invisible until the commit that introduces it, which is
# exactly when it is most expensive to notice.
shipped_scripts() {
    git -C "$REPO_ROOT" ls-files -z --cached --others --exclude-standard \
        -- '*.sh' 'bin/*' '.claude/hooks/*' '*.bats' '*.fish' 2>/dev/null |
        tr '\0' '\n' | grep -v '^docs/' | sort -u || true
}

# --- Hardcoded home directories -------------------------------------------

# bats test_tags=unit,portability
@test "no shipped script hardcodes a user home directory" {
    local hits
    hits="$(cd "$REPO_ROOT" && shipped_scripts | while read -r f; do
        [[ -n "$f" ]] || continue
        grep -Hn -E '/(Users|home)/[a-z][a-z0-9_-]*' "$f" 2>/dev/null |
            grep -v -E '(<user>|\$\{?USER|/home/linuxbrew|example|placeholder)' || true
    done)"
    [ -z "$hits" ] || {
        echo "Hardcoded home directories found:"
        echo "$hits"
        false
    }
}

# --- Hardcoded package-manager prefixes ------------------------------------

# bats test_tags=unit,portability
@test "no shipped script assumes a single brew prefix without probing" {
    # /opt/homebrew is Apple-Silicon-only; /usr/local is Intel and Linux.
    # Naming it inside a candidate list that also offers the alternatives is
    # correct — that is how you find the right prefix. Naming it alone is not.
    local hits
    hits="$(cd "$REPO_ROOT" && shipped_scripts | while read -r f; do
        [[ -n "$f" ]] || continue
        grep -q '/opt/homebrew' "$f" 2>/dev/null || continue
        grep -qE '/usr/local|linuxbrew' "$f" 2>/dev/null ||
            echo "$f: /opt/homebrew with no non-Apple-Silicon alternative"
    done)"
    [ -z "$hits" ] || {
        echo "$hits"
        false
    }
}

# bats test_tags=unit,portability
@test "no shipped script defaults to a personal directory layout" {
    # ~/Documents/dev, ~/src, ~/repos are personal conventions, not standards.
    # Naming one inside a probe list that offers alternatives is fine — that is
    # how you find an existing clone. Defaulting to one is not.
    local hits
    hits="$(cd "$REPO_ROOT" && shipped_scripts | while read -r f; do
        [[ -n "$f" ]] || continue
        grep -qE '\$\{?HOME\}?/(Documents|Desktop|Downloads)/' "$f" 2>/dev/null || continue
        # A probe list mentions XDG or several candidates.
        grep -qE 'XDG_DATA_HOME|XDG_CONFIG_HOME|candidate' "$f" 2>/dev/null ||
            echo "$f: personal directory layout with no alternatives"
    done)"
    [ -z "$hits" ] || {
        echo "$hits"
        false
    }
}

# --- Ghostty presets --------------------------------------------------------

# bats test_tags=unit,portability
@test "ghostty presets ship no active absolute command= path" {
    local hits
    hits="$(grep -rn '^command = ' "$REPO_ROOT/docs/ghostty/" 2>/dev/null || true)"
    [ -z "$hits" ] || {
        echo "Active absolute command= in a shipped preset:"
        echo "$hits"
        false
    }
}

# --- XDG Base Directory -----------------------------------------------------

# bats test_tags=unit,portability
@test "config paths honour XDG_CONFIG_HOME instead of assuming ~/.config" {
    local hits
    hits="$(cd "$REPO_ROOT" && shipped_scripts | while read -r f; do
        [[ -n "$f" ]] || continue
        grep -Hn -E '\$\{?HOME\}?/\.config' "$f" 2>/dev/null |
            grep -v 'XDG_CONFIG_HOME' || true
    done)"
    [ -z "$hits" ] || {
        echo "\$HOME/.config used without an XDG_CONFIG_HOME fallback:"
        echo "$hits"
        false
    }
}

# bats test_tags=unit,portability
@test "opencode config dir follows XDG_CONFIG_HOME when set" {
    XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/xdg" \
        HOME="$BATS_TEST_TMPDIR/home" \
        run bash -c "source '$REPO_ROOT/lib/setup/opencode.sh'; echo \"\$OPENCODE_CONFIG_DIR\""
    [ "$status" -eq 0 ]
    [[ "$output" == "$BATS_TEST_TMPDIR/xdg/opencode" ]]
}

# bats test_tags=unit,portability
@test "opencode config dir falls back to ~/.config when XDG unset" {
    run env -u XDG_CONFIG_HOME HOME="$BATS_TEST_TMPDIR/home" \
        bash -c "source '$REPO_ROOT/lib/setup/opencode.sh'; echo \"\$OPENCODE_CONFIG_DIR\""
    [ "$status" -eq 0 ]
    [[ "$output" == "$BATS_TEST_TMPDIR/home/.config/opencode" ]]
}

# --- Non-portable sed -------------------------------------------------------

# bats test_tags=unit,portability
@test "no shipped script uses [^\\\\n] in a sed expression" {
    # `[^\n]` is not portable: BSD sed reads it as "not backslash and not the
    # letter n", GNU sed as "not newline". Code relying on it behaves
    # differently on macOS and Linux, usually silently.
    local hits
    hits="$(cd "$REPO_ROOT" && shipped_scripts | while read -r f; do
        [[ -n "$f" ]] || continue
        # Strip comment lines first: this guard and its regression tests both
        # have to name the bad pattern in prose to explain it.
        grep -Hn 'sed' "$f" 2>/dev/null |
            grep -v -E '^[^:]+:[0-9]+:[[:space:]]*#' |
            grep '\[^\\n\]' || true
    done)"
    [ -z "$hits" ] || {
        echo "Non-portable sed bracket expression:"
        echo "$hits"
        false
    }
}

# --- GNU-only tool flags ----------------------------------------------------

# bats test_tags=unit,portability
@test "no shipped script uses GNU-only flags without a BSD path" {
    # `stat -c` and `date -d` are GNU-only. Two shapes make them safe: an
    # explicit platform branch, or a `stat -f … || stat -c …` fallback pair.
    # Anything else breaks on macOS.
    local hits
    hits="$(cd "$REPO_ROOT" && shipped_scripts | while read -r f; do
        [[ -n "$f" ]] || continue
        grep -qE 'stat -c|date -d ' "$f" 2>/dev/null || continue
        grep -qE 'Darwin|darwin|macos|uname|OSTYPE|PLATFORM' "$f" 2>/dev/null && continue
        grep -qE 'stat -f|date -j' "$f" 2>/dev/null && continue
        echo "$f: GNU-only flag with neither platform branch nor BSD fallback"
    done)"
    [ -z "$hits" ] || {
        echo "$hits"
        false
    }
}

# bats test_tags=unit,portability
@test "no shipped script uses the stat -f || stat -c idiom" {
    # This reads like a BSD-then-GNU fallback but is not. On GNU coreutils `-f`
    # means --file-system, so `stat -f '%Lp' file` SUCCEEDS and prints
    # filesystem info — the `||` never fires and the caller compares against
    # the wrong string. It passes on macOS and fails on Linux for a reason the
    # error message does not reveal. Branch on `uname` instead; tests/helpers.bash
    # provides file_mode() for exactly this.
    local hits
    hits="$(cd "$REPO_ROOT" && shipped_scripts | while read -r f; do
        [[ -n "$f" ]] || continue
        # Drop comments and @test titles: this guard has to name the bad idiom
        # in prose to be readable.
        grep -Hn -E "stat -f.*\|\|.*stat -c" "$f" 2>/dev/null |
            grep -v -E '^[^:]+:[0-9]+:[[:space:]]*(#|@test )' || true
    done)"
    [ -z "$hits" ] || {
        echo "Broken stat fallback (GNU stat -f succeeds, so || never fires):"
        echo "$hits"
        false
    }
}

# bats test_tags=unit,portability
@test "file_mode helper reports octal permissions on this platform" {
    local f="${BATS_TEST_TMPDIR}/perm"
    touch "$f"
    chmod 600 "$f"
    [ "$(file_mode "$f")" = "600" ]
    chmod 644 "$f"
    [ "$(file_mode "$f")" = "644" ]
}

# --- Installed-vs-repo paths ------------------------------------------------

# bats test_tags=unit,portability
@test "repo_hook_path resolves ~/.claude commands without an install" {
    # Hook commands are written as ~/.claude/... because that is where Claude
    # Code loads them. On a machine where setup.sh has never run — every CI
    # runner — that path does not exist, so tests must fall back to the repo
    # copy the symlink would point at.
    HOME="${BATS_TEST_TMPDIR}/empty-home"
    mkdir -p "$HOME"
    local resolved
    resolved="$(repo_hook_path '~/.claude/hooks/enforce-git-pull-rebase.sh' "$REPO_ROOT")"
    [ -f "$resolved" ]
    [ -x "$resolved" ]
}

# bats test_tags=unit,portability
@test "no test pins PLATFORM to a literal platform name" {
    # Sourcing a statusline module means inheriting its stat/date branching.
    # Pinning PLATFORM to one value forces the wrong branch on every other OS —
    # it passes on the platform it names and silently parses garbage elsewhere.
    local hits
    hits="$(cd "$REPO_ROOT" && grep -Hn -E 'PLATFORM=("|\x27)(macos|linux|windows)' tests/*.bats 2>/dev/null || true)"
    [ -z "$hits" ] || {
        echo "PLATFORM pinned to a literal (use detect_test_platform):"
        echo "$hits"
        false
    }
}

# bats test_tags=unit,portability
@test "no shipped script uses date -r on an epoch" {
    # `date -r` is not one flag with one meaning. BSD: format the given epoch.
    # GNU: read the given FILE's mtime. So `date -r 1700000000` prints a date on
    # macOS and fails with "No such file" on Linux.
    local hits
    hits="$(cd "$REPO_ROOT" && shipped_scripts | while read -r f; do
        [[ -n "$f" ]] || continue
        grep -Hn -E 'date -r [^ ]*[0-9]' "$f" 2>/dev/null |
            grep -v -E '^[^:]+:[0-9]+:[[:space:]]*(#|@test )' || true
    done)"
    [ -z "$hits" ] || {
        echo "date -r on an epoch (BSD-only meaning):"
        echo "$hits"
        false
    }
}

# --- CI supply chain ---------------------------------------------------------

# bats test_tags=unit,portability
@test "every GitHub Action is pinned to a full commit SHA" {
    # A tag is mutable. When tj-actions/changed-files was compromised in 2025 the
    # attacker moved 350+ tags to a malicious commit and every repo pinned by tag
    # picked it up. A 40-hex SHA cannot be moved.
    [ -d "$REPO_ROOT/.github/workflows" ] || skip "no workflows"
    local hits
    hits="$(grep -rhn -E '^\s*(-\s*)?uses:' "$REPO_ROOT/.github/workflows/" 2>/dev/null |
        grep -v -E 'uses:\s*\./' |
        grep -v -E 'uses:\s*[^@]+@[0-9a-f]{40}' || true)"
    [ -z "$hits" ] || {
        echo "Action not pinned to a full commit SHA:"
        echo "$hits"
        false
    }
}

# --- Shebangs ---------------------------------------------------------------

# bats test_tags=unit,portability
@test "every shipped script uses env-based shebang" {
    local hits
    hits="$(cd "$REPO_ROOT" && shipped_scripts | while read -r f; do
        [[ -n "$f" ]] || continue
        head -1 "$f" 2>/dev/null | grep -q '^#!' || continue
        head -1 "$f" | grep -qE '^#!/usr/bin/env ' || echo "$f: $(head -1 "$f")"
    done)"
    [ -z "$hits" ] || {
        echo "Non-portable shebang (hardcodes an interpreter path):"
        echo "$hits"
        false
    }
}

# --- bash version guard -----------------------------------------------------

# --- bash 3.2 support --------------------------------------------------------

# bats test_tags=unit,portability
@test "no script uses bash 4+ namerefs" {
    # macOS ships bash 3.2.57 as /bin/bash and cannot ship newer for licensing
    # reasons, so `#!/usr/bin/env bash` lands on 3.2 whenever no newer bash is
    # ahead of it on PATH — the default state on a clean Mac. `local -n` is a
    # 4.3 feature and fails there at RUNTIME, which `bash -n` does not catch.
    # Assign by name with `printf -v` (bash 3.1+) or eval instead.
    local hits
    hits="$(cd "$REPO_ROOT" && shipped_scripts | while read -r f; do
        [[ -n "$f" ]] || continue
        grep -Hn -E '(local|declare) -n ' "$f" 2>/dev/null |
            grep -v -E '^[^:]+:[0-9]+:[[:space:]]*(#|@test )' |
            grep -v -E 'grep -' || true
    done)"
    [ -z "$hits" ] || {
        echo "bash 4.3+ nameref found (breaks on stock macOS bash 3.2):"
        echo "$hits"
        false
    }
}

# bats test_tags=unit,portability
@test "no script uses other bash 4+ only features" {
    local hits
    hits="$(cd "$REPO_ROOT" && shipped_scripts | while read -r f; do
        [[ -n "$f" ]] || continue
        grep -Hn -E '(declare|local) -A |mapfile |readarray ' "$f" 2>/dev/null |
            grep -v -E '^[^:]+:[0-9]+:[[:space:]]*(#|@test )' |
            grep -v -E 'grep -' || true
    done)"
    [ -z "$hits" ] || {
        echo "bash 4+ feature found (breaks on stock macOS bash 3.2):"
        echo "$hits"
        false
    }
}

# bats test_tags=integration,portability
@test "setup.sh --help runs under stock macOS bash 3.2" {
    [ -x /bin/bash ] || skip "no /bin/bash on this platform"
    run /bin/bash "$REPO_ROOT/setup.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: setup.sh"* ]]
}

# bats test_tags=integration,portability
@test "setup.sh --minimal completes under stock macOS bash 3.2" {
    [ -x /bin/bash ] || skip "no /bin/bash on this platform"
    require_cmd python3
    require_cmd jq
    run env HOME="${BATS_TEST_TMPDIR}/h32" /bin/bash "$REPO_ROOT/setup.sh" \
        -y --minimal --no-claude-sync --no-opencode
    [ "$status" -eq 0 ] || {
        echo "setup.sh exited $status under bash 3.2"
        echo "$output"
        false
    }
    [[ "$output" == *"Setup complete!"* ]]
}

# bats test_tags=integration,portability
@test "the statusline bar overlay works under stock macOS bash 3.2" {
    [ -x /bin/bash ] || skip "no /bin/bash on this platform"
    run /bin/bash -c "
        set -euo pipefail
        PLATFORM=macos
        source '$REPO_ROOT/.claude/scripts/lib/statusline/bar.sh'
        b='....................'
        _overlay_pct_inside b 42 20 '#' '.'
        printf '%s' \"\$b\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"42%"* ]]
}

