#!/usr/bin/env bats
# login-shell-detection.bats
# Path: tests/login-shell-detection.bats
#
# setup.sh has to write the shortcuts into the rc file the user's shell
# actually reads. Getting that wrong is silent: the install reports success and
# the user never sees a `claude` function.
#
# $SHELL is the obvious source and the wrong one. It is an ordinary environment
# variable inherited from whatever spawned the process, and no shell corrects it
# on startup:
#
#     $ SHELL=/bin/made-up fish -c 'echo $SHELL'
#     /bin/made-up
#
# So a fish user whose terminal was launched with SHELL=zsh had their shortcuts
# written to ~/.zshrc, which fish never reads. detect_login_shell consults the
# password database instead, which is authoritative.
#
# Run: bats tests/login-shell-detection.bats

bats_require_minimum_version 1.5.0

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    isolate_home
    REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_DIR
    SETTINGS_SH="${REPO_DIR}/lib/setup/settings.sh"
}

# --- Precedence -------------------------------------------------------------

# bats test_tags=unit,portability
@test "explicit override wins over everything" {
    run bash -c "
        CLAUDE_CONFIG_SHELL=/usr/bin/ksh
        SHELL=/bin/zsh
        source '$SETTINGS_SH'
        detect_login_shell
    "
    [ "$status" -eq 0 ]
    [ "$output" = "/usr/bin/ksh" ]
}

# bats test_tags=unit,portability
@test "the password database beats a misleading \$SHELL" {
    # The regression: $SHELL says zsh while the user's login shell is fish.
    # A stub dscl/getent stands in for the real user database.
    # Synthetic passwd fields. Deliberately not a realistic /home/<name> or a
    # single brew prefix: the portability guards scan test files too, and a
    # lifelike fixture is indistinguishable from a real hardcode.
    stub_bin dscl 'echo "UserShell: /PLACEHOLDER/bin/fish"'
    stub_bin getent 'echo "u:x:1:1::/PLACEHOLDER/u:/PLACEHOLDER/bin/fish"'

    # stub_bin already prepended STUB_DIR to PATH in this shell; export it so
    # the child sees the stubs *and* keeps the real awk/cut.
    export PATH
    run bash -c "
        SHELL=/bin/zsh
        USER=u
        source '$SETTINGS_SH'
        detect_login_shell
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *fish ]] || {
        echo "expected the database value (fish), got: $output"
        false
    }
}

# bats test_tags=unit,portability
@test "falls back to \$SHELL when no database lookup is available" {
    # env -i plus a PATH with no dscl/getent: the fallback is all that is left.
    local empty="${BATS_TEST_TMPDIR}/emptybin"
    mkdir -p "$empty"
    for b in bash awk cut head printf; do
        src="$(command -v "$b" 2>/dev/null)" && ln -sf "$src" "$empty/$b"
    done

    run env -i PATH="$empty" SHELL=/bin/zsh USER=nobodyxyz HOME="$HOME" \
        bash -c "source '$SETTINGS_SH'; detect_login_shell"
    [ "$status" -eq 0 ]
    [ "$output" = "/bin/zsh" ]
}

# --- Routing ----------------------------------------------------------------

route_for() {
    CLAUDE_CONFIG_SHELL="$1" bash -c "
        REPO_DIR='$REPO_DIR'
        source '$SETTINGS_SH'
        configure_proxy_path
    " 2>&1
}

# bats test_tags=integration,portability
@test "a fish login shell gets fish files, not a profile" {
    run route_for /opt/homebrew/bin/fish
    [ "$status" -eq 0 ]
    [[ "$output" == *"Detected login shell: /opt/homebrew/bin/fish"* ]]
    [ -f "${XDG_CONFIG_HOME}/fish/functions/claude.fish" ]
    [ -f "${XDG_CONFIG_HOME}/fish/functions/clp.fish" ]
    [ ! -f "${HOME}/.zshrc" ]
    [ ! -f "${HOME}/.bashrc" ]
}

# bats test_tags=integration,portability
@test "a zsh login shell gets ~/.zshrc" {
    run route_for /bin/zsh
    [ "$status" -eq 0 ]
    grep -Fq 'claude-code-config: claude launch shortcuts' "${HOME}/.zshrc"
    [ ! -d "${XDG_CONFIG_HOME}/fish/functions" ]
}

# bats test_tags=integration,portability
@test "a bash login shell gets ~/.bashrc" {
    run route_for /bin/bash
    [ "$status" -eq 0 ]
    grep -Fq 'claude-code-config: claude launch shortcuts' "${HOME}/.bashrc"
}

# bats test_tags=integration,portability
@test "an unrecognised login shell falls back to ~/.profile" {
    run route_for /usr/bin/somethingelse
    [ "$status" -eq 0 ]
    grep -Fq 'claude-code-config: claude launch shortcuts' "${HOME}/.profile"
}

# bats test_tags=integration,portability
@test "the fish branch never writes a POSIX profile" {
    # The bug this guards: fish config is not POSIX, and a profile written for
    # fish would either be ignored or error on load.
    run route_for /usr/local/bin/fish
    [ "$status" -eq 0 ]
    [ ! -f "${HOME}/.profile" ]
    [ ! -f "${HOME}/.zshrc" ]
    [ ! -f "${HOME}/.bashrc" ]
}

# --- CLI flag ---------------------------------------------------------------

# bats test_tags=unit,portability
@test "--shell sets the override" {
    run bash -c "
        source '${REPO_DIR}/lib/setup/cli.sh'
        parse_arguments --shell /opt/homebrew/bin/fish
        echo \"\$CLAUDE_CONFIG_SHELL\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"/opt/homebrew/bin/fish"* ]]
}

# bats test_tags=unit,portability
@test "--shell without a value is rejected" {
    run bash -c "
        source '${REPO_DIR}/lib/setup/cli.sh'
        parse_arguments --shell
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires a path"* ]]
}

# bats test_tags=unit,portability
@test "--shell is documented in --help" {
    run bash "${REPO_DIR}/setup.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--shell"* ]]
}

# --- bash login vs non-login rc files ---------------------------------------
#
# bash reads ~/.bashrc for non-login interactive shells and ~/.bash_profile for
# login shells. Linux terminal emulators open the former; macOS Terminal.app and
# iTerm2 open the LATTER. Demonstrated:
#
#     bash -l -i  ->  BASH_PROFILE loaded
#     bash    -i  ->  BASHRC loaded
#
# So a block written only to ~/.bashrc is invisible on macOS. Same silent
# failure as picking the wrong shell entirely: install succeeds, user gets
# nothing.

# bats test_tags=integration,portability
@test "a bash login shell reads .bash_profile, not .bashrc" {
    # Pins the premise. If this ever stops being true the bridge is unnecessary.
    local h="${BATS_TEST_TMPDIR}/bashhome"
    mkdir -p "$h"
    echo 'echo BASHRC' >"$h/.bashrc"
    echo 'echo BASHPROFILE' >"$h/.bash_profile"

    run env HOME="$h" bash -l -i -c true
    [[ "$output" == *"BASHPROFILE"* ]]
    [[ "$output" != *"BASHRC"* ]]

    run env HOME="$h" bash -i -c true
    [[ "$output" == *"BASHRC"* ]]
}

# bats test_tags=integration,portability
@test "installing for bash bridges .bash_profile to .bashrc" {
    run bash -c "
        REPO_DIR='$REPO_DIR'
        CLAUDE_CONFIG_SHELL=/bin/bash
        source '$SETTINGS_SH'
        configure_proxy_path
    "
    [ "$status" -eq 0 ]

    grep -Fq 'claude-code-config: claude launch shortcuts' "${HOME}/.bashrc"
    [ -f "${HOME}/.bash_profile" ]
    grep -qE '(\.|source)[[:space:]]+.*\.bashrc' "${HOME}/.bash_profile"
}

# bats test_tags=integration,portability
@test "the bash bridge actually makes a login shell load the shortcuts" {
    # End to end: install, then start a real login shell and check the function
    # is defined. This is the behaviour the bridge exists for.
    run bash -c "
        REPO_DIR='$REPO_DIR'
        CLAUDE_CONFIG_SHELL=/bin/bash
        source '$SETTINGS_SH'
        configure_proxy_path
    "
    [ "$status" -eq 0 ]

    run env HOME="$HOME" bash -l -i -c 'type -t clp'
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

# bats test_tags=unit,portability
@test "the bash bridge is idempotent" {
    for _ in 1 2 3; do
        run bash -c "
            REPO_DIR='$REPO_DIR'
            CLAUDE_CONFIG_SHELL=/bin/bash
            source '$SETTINGS_SH'
            configure_proxy_path
        "
        [ "$status" -eq 0 ]
    done
    [ "$(grep -c 'load .bashrc for login shells' "${HOME}/.bash_profile")" -eq 1 ]
}

# bats test_tags=unit,portability
@test "the bash bridge leaves an existing source line alone" {
    # A .bash_profile that already pulls in .bashrc by any spelling needs no
    # help, and appending a second one would be noise.
    printf 'source ~/.bashrc\n' >"${HOME}/.bash_profile"
    run bash -c "
        REPO_DIR='$REPO_DIR'
        CLAUDE_CONFIG_SHELL=/bin/bash
        source '$SETTINGS_SH'
        configure_proxy_path
    "
    [ "$status" -eq 0 ]
    [ "$(grep -c 'load .bashrc for login shells' "${HOME}/.bash_profile")" -eq 0 ]
}

# bats test_tags=unit,portability
@test "non-bash shells get no .bash_profile bridge" {
    run bash -c "
        REPO_DIR='$REPO_DIR'
        CLAUDE_CONFIG_SHELL=/bin/zsh
        source '$SETTINGS_SH'
        configure_proxy_path
    "
    [ "$status" -eq 0 ]
    [ ! -f "${HOME}/.bash_profile" ]
}
