#!/usr/bin/env bats
# fish-shell-setup.bats
# Path: tests/fish-shell-setup.bats
#
# fish is not POSIX. `export VAR=x`, `case ... esac` and POSIX function syntax
# are all syntax errors there, so appending the bash shortcut block to a fish
# config would produce a file fish refuses to load. Before this, a fish user
# fell through to `~/.profile` — which fish never reads — and silently got no
# shortcuts at all.
#
# Run: bats tests/fish-shell-setup.bats

bats_require_minimum_version 1.5.0

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    isolate_home
    REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_DIR
    SETTINGS_SH="${REPO_DIR}/lib/setup/settings.sh"

    # Stand-in for "the user's login shell is fish". Set via
    # CLAUDE_CONFIG_SHELL, not SHELL: the login shell now comes from the
    # password database, because $SHELL is inherited from the parent process
    # and does not track the user's actual shell.
    FISH_SHELL="/usr/bin/fish"
    export FISH_SHELL
}

fish_config_dir() {
    printf '%s\n' "${XDG_CONFIG_HOME}/fish"
}

# --- Routing ----------------------------------------------------------------

# bats test_tags=unit,fish
@test "configure_proxy_path routes fish to the fish installer" {
    run bash -c "
        REPO_DIR='$REPO_DIR'
        CLAUDE_CONFIG_SHELL="$FISH_SHELL"
        source '$SETTINGS_SH'
        configure_proxy_path
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"fish/functions"* ]]
}

# bats test_tags=unit,fish
@test "fish install writes nothing to ~/.profile" {
    # The old behaviour: SHELL=fish fell through to the catch-all branch and
    # appended bash syntax to a file fish never reads.
    run bash -c "
        REPO_DIR='$REPO_DIR'
        CLAUDE_CONFIG_SHELL="$FISH_SHELL"
        source '$SETTINGS_SH'
        configure_proxy_path
    "
    [ "$status" -eq 0 ]
    [ ! -f "${HOME}/.profile" ] || ! grep -q 'claude launch shortcuts' "${HOME}/.profile"
}

# --- Generated files --------------------------------------------------------

# bats test_tags=unit,fish
@test "fish install creates claude and clp functions" {
    run bash -c "
        REPO_DIR='$REPO_DIR'
        CLAUDE_CONFIG_SHELL="$FISH_SHELL"
        source '$SETTINGS_SH'
        configure_proxy_path
    "
    [ "$status" -eq 0 ]
    [ -f "$(fish_config_dir)/functions/claude.fish" ]
    [ -f "$(fish_config_dir)/functions/clp.fish" ]
}

# bats test_tags=unit,fish
@test "fish install adds bin/ to PATH via conf.d" {
    run bash -c "
        REPO_DIR='$REPO_DIR'
        CLAUDE_CONFIG_SHELL="$FISH_SHELL"
        source '$SETTINGS_SH'
        configure_proxy_path
    "
    [ "$status" -eq 0 ]
    local path_file="$(fish_config_dir)/conf.d/00-claude-code-config-path.fish"
    [ -f "$path_file" ]
    grep -q "fish_add_path" "$path_file"
    grep -q "${REPO_DIR}/bin" "$path_file"
}

# bats test_tags=unit,fish
@test "fish install honours XDG_CONFIG_HOME" {
    export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/custom-xdg"
    run bash -c "
        REPO_DIR='$REPO_DIR'
        CLAUDE_CONFIG_SHELL="$FISH_SHELL"
        XDG_CONFIG_HOME='$XDG_CONFIG_HOME'
        source '$SETTINGS_SH'
        configure_proxy_path
    "
    [ "$status" -eq 0 ]
    [ -f "${XDG_CONFIG_HOME}/fish/functions/claude.fish" ]
}

# bats test_tags=unit,fish
@test "fish install is idempotent" {
    for _ in 1 2; do
        run bash -c "
            REPO_DIR='$REPO_DIR'
            CLAUDE_CONFIG_SHELL="$FISH_SHELL"
            source '$SETTINGS_SH'
            configure_proxy_path
        "
        [ "$status" -eq 0 ]
    done
    # Exactly one function definition, not two appended copies.
    local count
    count=$(grep -c '^function claude ' "$(fish_config_dir)/functions/claude.fish")
    [ "$count" -eq 1 ]
}

# --- Generated fish actually parses -----------------------------------------

# bats test_tags=unit,fish
@test "generated fish claude function resumes a session as its last account" {
    require_cmd fish
    run bash -c "
        REPO_DIR='$REPO_DIR'
        CLAUDE_CONFIG_SHELL="$FISH_SHELL"
        source '$SETTINGS_SH'
        configure_proxy_path
    "
    [ "$status" -eq 0 ]
    local log="${BATS_TEST_TMPDIR}/calls.log"
    stub_bin claude 'printf "claude:dir=%s:%s\n" "${CLAUDE_CONFIG_DIR-unset}" "$*" >>"$CALL_LOG"'
    stub_bin claude-as 'echo "asked $*" >>"$CALL_LOG"; [ "$1" = --where ] && [ "$3" = known ] && echo /h/.claude-b; exit 0'

    # The stubs first: the repo's own bin/ may be on PATH ahead of them.
    CALL_LOG="$log" run fish -c "
        set -gx PATH '${STUB_DIR}' \$PATH
        source '$(fish_config_dir)/functions/__claude_as_home.fish'
        source '$(fish_config_dir)/functions/claude.fish'
        claude --resume known
        echo \"after=[\$CLAUDE_CONFIG_DIR]\" >>\$CALL_LOG
        claude -a --resume other
        set -lx CLAUDE_CONFIG_DIR /mine
        claude --resume known
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude: as the session last ran, in /h/.claude-b"* ]]
    grep -Fxq 'claude:dir=/h/.claude-b:--allow-dangerously-skip-permissions --resume known' "$log"
    grep -Fxq 'after=[]' "$log"
    grep -Fxq 'claude:dir=unset:--dangerously-skip-permissions --resume other' "$log"
    grep -Fxq 'claude:dir=/mine:--allow-dangerously-skip-permissions --resume known' "$log"
    [ "$(grep -c '^asked --where' "$log")" -eq 2 ]
}

# bats test_tags=unit,fish
@test "generated fish claude function keeps a resumed session's name in Remote Control" {
    require_cmd fish
    run bash -c "
        REPO_DIR='$REPO_DIR'
        CLAUDE_CONFIG_SHELL="$FISH_SHELL"
        source '$SETTINGS_SH'
        configure_proxy_path
    "
    [ "$status" -eq 0 ]
    local log="${BATS_TEST_TMPDIR}/calls.log"
    stub_bin claude 'printf "claude:prefix=%s:%s\n" "${CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX-unset}" "$*" >>"$CALL_LOG"'
    stub_bin claude-as 'case $1 in --rc-name) [ "$3" = known ] && echo "claude-dev-x 1"; ;; --host-alias) echo dev ;; esac; exit 0'
    CALL_LOG="$log" run fish -c "
        set -gx PATH '${STUB_DIR}' \$PATH
        source '$(fish_config_dir)/functions/__claude_as_home.fish'
        source '$(fish_config_dir)/functions/claude.fish'
        claude -a --resume known -- hi
        echo \"after=[\$CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX]\" >>\$CALL_LOG
        claude -p hi
        set -lx CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX mine
        claude -p hi
    "
    [ "$status" -eq 0 ]
    grep -Fxq 'claude:prefix=claude-dev:--dangerously-skip-permissions --remote-control claude-dev-x 1 --resume known -- hi' "$log"
    grep -Fxq 'after=[]' "$log"
    grep -Fxq 'claude:prefix=claude-dev:--allow-dangerously-skip-permissions -p hi' "$log"
    grep -Fxq 'claude:prefix=mine:--allow-dangerously-skip-permissions -p hi' "$log"
}

# bats test_tags=integration,fish
@test "a failing claude-as --where says so and runs as the default account" {
    require_cmd fish
    run bash -c "
        REPO_DIR='$REPO_DIR'
        CLAUDE_CONFIG_SHELL="$FISH_SHELL"
        source '$SETTINGS_SH'
        configure_proxy_path
    "
    [ "$status" -eq 0 ]
    local log="${BATS_TEST_TMPDIR}/calls.log"
    stub_bin claude 'printf "claude:dir=%s:%s\n" "${CLAUDE_CONFIG_DIR-unset}" "$*" >>"$CALL_LOG"'
    stub_bin claude-as 'exit 3'
    CALL_LOG="$log" run fish -c "
        set -gx PATH '${STUB_DIR}' \$PATH
        source '$(fish_config_dir)/functions/__claude_as_home.fish'
        source '$(fish_config_dir)/functions/claude.fish'
        claude --resume known
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude: claude-as --where failed; running as the default account"* ]]
    grep -Fxq 'claude:dir=unset:--allow-dangerously-skip-permissions --resume known' "$log"
}

# bats test_tags=integration,fish
@test "a hand-written claude.fish is told how to route, and routes through the helper" {
    require_cmd fish
    local fdir="${XDG_CONFIG_HOME}/fish/functions"
    mkdir -p "$fdir"
    cat >"$fdir/claude.fish" <<'FISH'
function claude --description 'hand written'
    command claude $argv
end
FISH
    run bash -c "
        REPO_DIR='$REPO_DIR'
        CLAUDE_CONFIG_SHELL='$FISH_SHELL'
        source '$SETTINGS_SH'
        configure_proxy_path
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"does not route a resume to its account"* ]]
    [[ "$output" == *'set -l home (__claude_as_home $argv)'* ]]
    [ -f "$fdir/__claude_as_home.fish" ]

    # The lines the warning names, added by hand, route the resume.
    cat >"$fdir/claude.fish" <<'FISH'
function claude --description 'hand written'
    set -l home (__claude_as_home $argv)
    test -n "$home"; and set -lx CLAUDE_CONFIG_DIR $home
    command claude $argv
end
FISH
    local log="${BATS_TEST_TMPDIR}/calls.log"
    stub_bin claude 'printf "claude:dir=%s:%s\n" "${CLAUDE_CONFIG_DIR-unset}" "$*" >>"$CALL_LOG"'
    stub_bin claude-as '[ "$1" = --where ] && [ "$3" = known ] && echo /h/.claude-b; exit 0'
    CALL_LOG="$log" run fish -c "
        set -gx PATH '${STUB_DIR}' \$PATH
        source '$fdir/__claude_as_home.fish'
        source '$fdir/claude.fish'
        claude --resume known
    "
    [ "$status" -eq 0 ]
    grep -Fxq 'claude:dir=/h/.claude-b:--resume known' "$log"

    run bash -c "
        REPO_DIR='$REPO_DIR'
        CLAUDE_CONFIG_SHELL='$FISH_SHELL'
        source '$SETTINGS_SH'
        configure_proxy_path
    "
    [ "$status" -eq 0 ]
    [[ "$output" != *"does not route a resume to its account"* ]]
}

# bats test_tags=integration,fish
@test "generated fish functions parse under fish -n" {
    require_cmd fish
    run bash -c "
        REPO_DIR='$REPO_DIR'
        CLAUDE_CONFIG_SHELL="$FISH_SHELL"
        source '$SETTINGS_SH'
        configure_proxy_path
    "
    [ "$status" -eq 0 ]

    run fish -n "$(fish_config_dir)/functions/claude.fish"
    [ "$status" -eq 0 ]
    run fish -n "$(fish_config_dir)/functions/clp.fish"
    [ "$status" -eq 0 ]
    run fish -n "$(fish_config_dir)/conf.d/00-claude-code-config-path.fish"
    [ "$status" -eq 0 ]
}

# bats test_tags=integration,fish
@test "generated fish claude function forwards arguments correctly" {
    require_cmd fish
    run bash -c "
        REPO_DIR='$REPO_DIR'
        CLAUDE_CONFIG_SHELL="$FISH_SHELL"
        source '$SETTINGS_SH'
        configure_proxy_path
    "
    [ "$status" -eq 0 ]

    local log="${BATS_TEST_TMPDIR}/calls.log"
    stub_bin claude 'printf "claude:%s\n" "$*" >>"$CALL_LOG"'

    CALL_LOG="$log" run fish -c "
        source '$(fish_config_dir)/functions/claude.fish'
        claude --resume
        claude -a --resume
    "
    [ "$status" -eq 0 ]
    grep -Fq 'claude:--allow-dangerously-skip-permissions --resume' "$log"
    grep -Fq 'claude:--dangerously-skip-permissions --resume' "$log"
}

# bats test_tags=unit,fish
@test "fish routing is independent of the install prefix" {
    # fish lives at a different path on Apple Silicon, Intel macOS, Linux brew
    # and distro packages. Routing must key off the */fish glob, not one prefix.
    local candidate
    for candidate in \
        /opt/homebrew/bin/fish \
        /usr/local/bin/fish \
        /home/linuxbrew/.linuxbrew/bin/fish \
        /usr/bin/fish; do
        rm -rf "${XDG_CONFIG_HOME:?}/fish"
        run bash -c "
            REPO_DIR='$REPO_DIR'
            CLAUDE_CONFIG_SHELL='$candidate'
            source '$SETTINGS_SH'
            configure_proxy_path
        "
        [ "$status" -eq 0 ] || {
            echo "routing failed for $candidate"
            false
        }
        [ -f "${XDG_CONFIG_HOME}/fish/functions/claude.fish" ] || {
            echo "no fish function written for $candidate"
            false
        }
    done
}

# bats test_tags=unit,fish
@test "docs fish presets stay in sync with what the installer generates" {
    # docs/fish/.../functions/*.fish is the reference for a manual install, and
    # lib/setup/settings.sh generates the same functions for an automated one.
    # Two copies of the same code drift silently; compare the executable parts.
    run bash -c "
        REPO_DIR='$REPO_DIR'
        CLAUDE_CONFIG_SHELL=/usr/bin/fish
        source '$SETTINGS_SH'
        configure_proxy_path
    "
    [ "$status" -eq 0 ]

    local f
    for f in claude clp __claude_as_home; do
        local doc gen
        doc="$(grep -vE '^[[:space:]]*#' "${REPO_DIR}/docs/fish/config-power-user/functions/${f}.fish" | grep -v '^[[:space:]]*$')"
        gen="$(grep -vE '^[[:space:]]*#' "${XDG_CONFIG_HOME}/fish/functions/${f}.fish" | grep -v '^[[:space:]]*$')"
        [ "$doc" = "$gen" ] || {
            echo "${f}.fish drifted between docs/ and the installer:"
            diff <(printf '%s\n' "$doc") <(printf '%s\n' "$gen") || true
            false
        }
    done
}

# bats test_tags=integration,fish
@test "the fish PATH entry survives a repo path containing a space" {
    # Unquoted, `fish_add_path -ga /a/b c/bin` is two arguments; fish_add_path
    # skips missing directories silently, so the entry vanishes with no error.
    require_cmd fish
    local spaced="${BATS_TEST_TMPDIR}/has space/repo"
    mkdir -p "${spaced}/bin"

    run bash -c "
        REPO_DIR='$spaced'
        CLAUDE_CONFIG_SHELL=/usr/bin/fish
        source '$SETTINGS_SH'
        configure_proxy_path
    "
    [ "$status" -eq 0 ]

    local path_file="$(fish_config_dir)/conf.d/00-claude-code-config-path.fish"
    run fish -n "$path_file"
    [ "$status" -eq 0 ]

    run fish -c "source '$path_file'; contains '${spaced}/bin' \$PATH; and echo PRESENT"
    [[ "$output" == *"PRESENT"* ]] || {
        echo "PATH entry was dropped for a spaced path:"
        cat "$path_file"
        false
    }
}

# --- The installer must not clobber a hand-owned function -------------------
#
# The POSIX branch delimits its block with markers and refuses to rewrite when
# they are not intact. The fish branch wrote each function with `cat >`, so a
# customised claude.fish was replaced with no warning — the same silent
# destruction the markers exist to prevent. fish users are the likeliest to have
# customised these, because until recently setup.sh never installed them.

# bats test_tags=integration,fish
@test "an unmanaged claude.fish is preserved, not overwritten" {
    local fdir="${XDG_CONFIG_HOME}/fish/functions"
    mkdir -p "$fdir"
    cat >"$fdir/claude.fish" <<'FISH'
function claude --description 'hand written, do not clobber'
    set -l sentinel PRESERVE_ME
    command claude $argv
end
FISH
    local before
    before="$(cat "$fdir/claude.fish")"

    run bash -c "
        REPO_DIR='$REPO_DIR'
        CLAUDE_CONFIG_SHELL='$FISH_SHELL'
        source '$SETTINGS_SH'
        configure_proxy_path
    "
    [ "$status" -eq 0 ]

    [ "$(cat "$fdir/claude.fish")" = "$before" ] || {
        echo "the installer overwrote a file it did not write"
        false
    }
    grep -q 'PRESERVE_ME' "$fdir/claude.fish"
    [[ "$output" == *"was not written by setup.sh"* ]]
    ls "$fdir"/claude.fish.bak.* >/dev/null 2>&1
}

# bats test_tags=integration,fish
@test "a managed claude.fish is regenerated on re-run" {
    run bash -c "
        REPO_DIR='$REPO_DIR'
        CLAUDE_CONFIG_SHELL='$FISH_SHELL'
        source '$SETTINGS_SH'
        configure_proxy_path
    "
    [ "$status" -eq 0 ]
    grep -q 'Managed by claude-code-config setup.sh' "$(fish_config_dir)/functions/claude.fish"

    # Second run must update it in place rather than refuse.
    run bash -c "
        REPO_DIR='$REPO_DIR'
        CLAUDE_CONFIG_SHELL='$FISH_SHELL'
        source '$SETTINGS_SH'
        configure_proxy_path
    "
    [ "$status" -eq 0 ]
    [[ "$output" != *"was not written by setup.sh"* ]]
    [ "$(grep -c '^function claude ' "$(fish_config_dir)/functions/claude.fish")" -eq 1 ]
}

# bats test_tags=integration,fish
@test "the generated PATH file is recognised as managed on re-run" {
    for _ in 1 2; do
        run bash -c "
            REPO_DIR='$REPO_DIR'
            CLAUDE_CONFIG_SHELL='$FISH_SHELL'
            source '$SETTINGS_SH'
            configure_proxy_path
        "
        [ "$status" -eq 0 ]
    done
    [[ "$output" != *"was not written by setup.sh"* ]]
    local pf="$(fish_config_dir)/conf.d/00-claude-code-config-path.fish"
    [ "$(grep -c '^fish_add_path ' "$pf")" -eq 1 ]
}
