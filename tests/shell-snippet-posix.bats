#!/usr/bin/env bats
# shell-snippet-posix.bats
# Path: tests/shell-snippet-posix.bats
#
# configure_claude_shortcuts writes a managed block into the user's shell
# profile. For anything that is not bash or zsh that profile is ~/.profile,
# which is read by POSIX shells — so the generated snippet has to BE POSIX, not
# merely "works on my machine".
#
# `local` is the trap: it is a near-universal extension, not part of POSIX, and
# on macOS /bin/sh is bash in sh-mode, so testing there proves nothing. These
# tests check the emitted text with shellcheck's POSIX mode and then actually
# execute it under every POSIX-ish shell present.
#
# Run: bats tests/shell-snippet-posix.bats

bats_require_minimum_version 1.5.0

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    isolate_home
    REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_DIR
    PROFILE="${BATS_TEST_TMPDIR}/profile"
    : >"$PROFILE"
    # shellcheck disable=SC1090
    source "${REPO_DIR}/lib/setup/settings.sh"
    configure_claude_shortcuts "$PROFILE" >/dev/null 2>&1
}

# Just the managed block, with a POSIX shebang so shellcheck judges it as sh.
extract_snippet() {
    local out="${BATS_TEST_TMPDIR}/snippet.sh"
    {
        printf '#!/bin/sh\n'
        sed -n '/# claude-code-config: claude launch shortcuts/,/# claude-code-config: end/p' "$PROFILE"
    } >"$out"
    printf '%s\n' "$out"
}

# Every POSIX-ish shell installed here. bash and zsh are included because the
# snippet must keep working there too.
available_shells() {
    local sh p
    for sh in /bin/sh dash ksh mksh zsh bash; do
        p="$(command -v "$sh" 2>/dev/null)" || continue
        printf '%s\n' "$p"
    done | sort -u
}

# --- Static: the emitted text ------------------------------------------------

# bats test_tags=unit,portability
@test "generated snippet contains no 'local' keyword" {
    # `local` is not in POSIX. It happens to work in dash and in bash's sh-mode,
    # which is exactly why testing on macOS gives a false pass.
    run grep -nE '^[[:space:]]*local[[:space:]]' "$PROFILE"
    [ "$status" -ne 0 ] || {
        echo "non-POSIX 'local' in a profile snippet:"
        echo "$output"
        false
    }
}

# bats test_tags=unit,portability
@test "generated snippet passes shellcheck in POSIX sh mode" {
    require_cmd shellcheck
    local snippet
    snippet="$(extract_snippet)"
    run shellcheck -s sh "$snippet"
    [ "$status" -eq 0 ] || {
        echo "$output"
        false
    }
}

# bats test_tags=unit,portability
@test "generated snippet declares both managed markers" {
    grep -Fq '# claude-code-config: claude launch shortcuts' "$PROFILE"
    grep -Fq '# claude-code-config: end claude launch shortcuts' "$PROFILE"
}

# --- Parse: every shell present ---------------------------------------------

# bats test_tags=integration,portability
@test "generated snippet parses under every installed POSIX shell" {
    local p failed=0
    while read -r p; do
        [[ -n "$p" ]] || continue
        if ! "$p" -n "$PROFILE" 2>/dev/null; then
            echo "parse FAILED under $p"
            failed=1
        fi
    done < <(available_shells)
    [ "$failed" -eq 0 ]
}

# --- Behaviour: run it -------------------------------------------------------

stub_proxy() {
    stub_bin claude-proxy 'printf "proxy:%s\n" "$*"'
    stub_bin claude 'printf "claude:%s\n" "$*"'
}

# bats test_tags=integration,portability
@test "clp forwards the default model under every installed shell" {
    stub_proxy
    local p out
    while read -r p; do
        [[ -n "$p" ]] || continue
        out="$("$p" -c ". '$PROFILE'; clp --continue" 2>&1 | tail -1)"
        [[ "$out" == *"-m gpt-5.5(high)"* ]] || {
            echo "$p produced: $out"
            false
        }
        [[ "$out" == *"--allow-dangerously-skip-permissions --continue"* ]] || {
            echo "$p produced: $out"
            false
        }
    done < <(available_shells)
}

# bats test_tags=integration,portability
@test "clp -a switches to the bypass flag under every installed shell" {
    stub_proxy
    local p out
    while read -r p; do
        [[ -n "$p" ]] || continue
        out="$("$p" -c ". '$PROFILE'; clp -a --resume" 2>&1 | tail -1)"
        [[ "$out" == *"-- --dangerously-skip-permissions --resume"* ]] || {
            echo "$p produced: $out"
            false
        }
    done < <(available_shells)
}

# bats test_tags=integration,portability
@test "CLAUDE_PROXY_MODEL overrides the default under every installed shell" {
    stub_proxy
    local p out
    while read -r p; do
        [[ -n "$p" ]] || continue
        out="$(CLAUDE_PROXY_MODEL=custom-model "$p" -c ". '$PROFILE'; clp" 2>&1 | tail -1)"
        [[ "$out" == *"-m custom-model"* ]] || {
            echo "$p produced: $out"
            false
        }
    done < <(available_shells)
}

# bats test_tags=integration,portability
@test "claude forwards arguments under every installed shell" {
    stub_proxy
    local p out
    while read -r p; do
        [[ -n "$p" ]] || continue
        out="$("$p" -c ". '$PROFILE'; claude --resume" 2>&1 | tail -1)"
        [[ "$out" == *"claude:--allow-dangerously-skip-permissions --resume"* ]] || {
            echo "$p produced: $out"
            false
        }
        out="$("$p" -c ". '$PROFILE'; claude -a --resume" 2>&1 | tail -1)"
        [[ "$out" == *"claude:--dangerously-skip-permissions --resume"* ]] || {
            echo "$p produced: $out"
            false
        }
    done < <(available_shells)
}

# bats test_tags=integration,portability
@test "sourcing the snippet leaks no variables into the caller" {
    # The old version used `local model=...`; dropping `local` without also
    # dropping the variable would have leaked `model` into the user's shell.
    stub_proxy
    local out
    out="$(dash -c ". '$PROFILE'; clp >/dev/null 2>&1; echo \"model=[\${model:-}]\"" 2>&1 | tail -1)" ||
        skip "dash not available"
    [[ "$out" == "model=[]" ]]
}

# --- Smoke: the real installer path -----------------------------------------

# bats test_tags=smoke
@test "setup.sh writes a POSIX-clean profile snippet end to end" {
    require_cmd python3
    require_cmd jq
    require_cmd shellcheck

    # --shell, not SHELL: the login shell now comes from the password database,
    # because $SHELL is inherited from the parent process and lies. This test
    # wants the POSIX-profile branch specifically, so it asks for it.
    run env HOME="${BATS_TEST_TMPDIR}/smokehome" \
        bash "${REPO_DIR}/setup.sh" -y --no-agents --no-mcp \
        --no-claude-sync --no-opencode --shell /bin/sh
    [ "$status" -eq 0 ] || {
        echo "$output"
        false
    }

    local prof="${BATS_TEST_TMPDIR}/smokehome/.profile"
    [ -f "$prof" ]
    ! grep -qE '^[[:space:]]*local[[:space:]]' "$prof"

    local snippet="${BATS_TEST_TMPDIR}/smoke-snippet.sh"
    {
        printf '#!/bin/sh\n'
        sed -n '/# claude-code-config: claude launch shortcuts/,/# claude-code-config: end/p' "$prof"
    } >"$snippet"
    run shellcheck -s sh "$snippet"
    [ "$status" -eq 0 ] || {
        echo "$output"
        false
    }
}
