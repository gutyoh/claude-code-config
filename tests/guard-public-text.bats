#!/usr/bin/env bats
# guard-public-text.bats
# Path: tests/guard-public-text.bats
#
# The guard stops text bound for a public repository when the scanner in
# CLAUDE_LEAK_GUARD flags it, and stays out of the way everywhere else.

HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/guard-public-text.sh"

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    command -v jq >/dev/null 2>&1 || skip "jq is required"
    isolate_home
    export XDG_CACHE_HOME="$HOME/.cache" TMPDIR="$BATS_TEST_TMPDIR"
    # The scanner flags any file that holds the word SECRETNAME.
    SCANNER="$BATS_TEST_TMPDIR/scanner"
    printf '#!/usr/bin/env bash\nif grep -l SECRETNAME "$@"; then exit 1; fi\nexit 0\n' >"$SCANNER"
    chmod +x "$SCANNER"
    export CLAUDE_LEAK_GUARD="$SCANNER"
    visibility PUBLIC
    REPO="$BATS_TEST_TMPDIR/repo"
    git init -q "$REPO"
    git -C "$REPO" remote add origin https://github.com/acme/widgets.git
    cd "$REPO"
}

# gh answers every visibility query with $1 and counts the calls.
visibility() {
    stub_bin gh "echo gh >>\"$BATS_TEST_TMPDIR/gh-calls\"; echo $1"
}

guard() {
    run bash "$HOOK" < <(jq -n --arg c "$1" '{tool_input: {command: $c}}')
}

# bats test_tags=unit
@test "a command that publishes nothing passes without a scan" {
    guard 'ls -la && echo SECRETNAME'
    [ "$status" -eq 0 ]
    [ ! -f "$BATS_TEST_TMPDIR/gh-calls" ]
}

# bats test_tags=unit
@test "a pull request body naming a secret is blocked in a public repo" {
    guard 'gh pr create --title t --body "hello SECRETNAME"'
    [ "$status" -eq 2 ]
    [[ "$output" == *"acme/widgets"* ]]
}

# bats test_tags=unit
@test "the same body passes in a private repo" {
    visibility PRIVATE
    guard 'gh pr create --title t --body "hello SECRETNAME"'
    [ "$status" -eq 0 ]
}

# bats test_tags=unit
@test "a clean body passes in a public repo" {
    guard 'gh pr create --title t --body "hello world"'
    [ "$status" -eq 0 ]
}

# bats test_tags=unit
@test "a body file is read and checked" {
    printf 'body with SECRETNAME\n' >"$BATS_TEST_TMPDIR/body.md"
    guard "gh pr edit 7 --body-file $BATS_TEST_TMPDIR/body.md"
    [ "$status" -eq 2 ]
    printf 'clean body\n' >"$BATS_TEST_TMPDIR/body.md"
    guard "gh pr edit 7 --body-file $BATS_TEST_TMPDIR/body.md"
    [ "$status" -eq 0 ]
}

# bats test_tags=unit
@test "a body file followed by an operator is still read and checked" {
    printf 'body with SECRETNAME\n' >"$BATS_TEST_TMPDIR/body.md"
    for op in '; echo done' '&& echo done' '|| echo failed' '| cat'; do
        guard "gh pr edit 7 --body-file $BATS_TEST_TMPDIR/body.md$op"
        [ "$status" -eq 2 ]
        [[ "$output" == *"leak guard flags"* ]]
    done
    printf 'clean body\n' >"$BATS_TEST_TMPDIR/body.md"
    guard "gh pr edit 7 --body-file $BATS_TEST_TMPDIR/body.md; echo done"
    [ "$status" -eq 0 ]
}

# bats test_tags=unit
@test "a gh api field file followed by an operator is still read and checked" {
    printf 'SECRETNAME\n' >"$BATS_TEST_TMPDIR/field.txt"
    guard "gh api repos/acme/widgets/issues -F body=@$BATS_TEST_TMPDIR/field.txt; echo done"
    [ "$status" -eq 2 ]
    [[ "$output" == *"leak guard flags"* ]]
}

# bats test_tags=unit
@test "a body file named through a variable is refused, since it cannot be read" {
    guard 'F=/tmp/x.md; gh pr create --body-file "$F"'
    [ "$status" -eq 2 ]
    [[ "$output" == *"literal path"* ]]
}

# bats test_tags=unit
@test "a heredoc body is part of the command and is checked" {
    guard $'gh issue comment 3 --body-file - <<EOF\nsee SECRETNAME\nEOF'
    [ "$status" -eq 2 ]
}

# bats test_tags=unit
@test "-R names the repository whose visibility counts" {
    stub_bin gh 'case "$*" in *acme/private*) echo PRIVATE ;; *) echo PUBLIC ;; esac'
    guard 'gh pr create -R acme/private --body "SECRETNAME"'
    [ "$status" -eq 0 ]
    guard 'gh pr create --repo acme/open --body "SECRETNAME"'
    [ "$status" -eq 2 ]
}

# bats test_tags=unit
@test "a commit message is checked, inline or from a file" {
    guard 'git commit -m "add SECRETNAME"'
    [ "$status" -eq 2 ]
    printf 'msg SECRETNAME\n' >"$BATS_TEST_TMPDIR/msg"
    guard "git commit -q -F $BATS_TEST_TMPDIR/msg"
    [ "$status" -eq 2 ]
}

# bats test_tags=unit
@test "a push is checked against the messages of every commit it sends" {
    git -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m "first"
    guard 'git push origin HEAD'
    [ "$status" -eq 0 ]
    git -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m "names SECRETNAME"
    guard 'git push origin HEAD'
    [ "$status" -eq 2 ]
}

# bats test_tags=unit
@test "a repository outside GitHub is never treated as public" {
    git remote set-url origin https://dev.azure.com/acme/_git/widgets
    guard 'git commit -m "add SECRETNAME"'
    [ "$status" -eq 0 ]
}

# bats test_tags=unit
@test "cd before the command picks the repository" {
    local other="$BATS_TEST_TMPDIR/other"
    git init -q "$other"
    git -C "$other" remote add origin git@github.com:acme/private.git
    stub_bin gh 'case "$*" in *acme/private*) echo PRIVATE ;; *) echo PUBLIC ;; esac'
    cd /
    guard "cd $other && git commit -m 'SECRETNAME'"
    [ "$status" -eq 0 ]
}

# bats test_tags=unit
@test "visibility is asked once a day per repository" {
    guard 'gh pr create --body "clean"'
    guard 'gh pr create --body "clean"'
    [ "$(wc -l <"$BATS_TEST_TMPDIR/gh-calls")" -eq 1 ]
}

# bats test_tags=unit
@test "an unknown visibility is checked as public" {
    stub_bin gh 'exit 1'
    guard 'gh pr create --body "SECRETNAME"'
    [ "$status" -eq 2 ]
}

# bats test_tags=unit
@test "a scanner that cannot run blocks rather than letting text out" {
    export CLAUDE_LEAK_GUARD="$BATS_TEST_TMPDIR/no-such-scanner --flag"
    guard 'gh pr create --body "clean"'
    [ "$status" -eq 2 ]
}

# bats test_tags=unit
@test "without a scanner configured the hook does nothing" {
    unset CLAUDE_LEAK_GUARD
    guard 'gh pr create --body "SECRETNAME"'
    [ "$status" -eq 0 ]
}

# bats test_tags=unit
@test "a scanner path with ~ and its own arguments works" {
    mkdir -p "$HOME/bin"
    cp "$SCANNER" "$HOME/bin/scan"
    export CLAUDE_LEAK_GUARD="~/bin/scan --mode strict"
    printf '#!/usr/bin/env bash\nshift 2\nif grep -l SECRETNAME "$@"; then exit 1; fi\n' >"$HOME/bin/scan"
    guard 'gh release create v1 --notes "SECRETNAME"'
    [ "$status" -eq 2 ]
    guard 'gh release create v1 --notes "fine"'
    [ "$status" -eq 0 ]
}

# bats test_tags=unit
@test "gh api writes are checked, fields read from files included" {
    guard 'gh api -X PATCH repos/acme/widgets/pulls/1 -f body="SECRETNAME"'
    [ "$status" -eq 2 ]
    printf 'SECRETNAME\n' >"$BATS_TEST_TMPDIR/field.txt"
    guard "gh api repos/acme/widgets/issues -F body=@$BATS_TEST_TMPDIR/field.txt"
    [ "$status" -eq 2 ]
}

# bats test_tags=unit
@test "local paths in the command are not scanned, only what gets published" {
    local dir="$BATS_TEST_TMPDIR/SECRETNAME-dir"
    mkdir -p "$dir"
    printf 'clean body\n' >"$dir/body.md"
    guard "cd $REPO && gh pr create --title fine --body-file $dir/body.md"
    [ "$status" -eq 0 ]
    guard "git -C $dir commit -q -F $dir/body.md"
    [ "$status" -eq 0 ]
    guard "gh pr create --title 'SECRETNAME in the title' --body-file $dir/body.md"
    [ "$status" -eq 2 ]
}

# bats test_tags=unit
@test "setup adds the guard to user settings once, beside the hooks already there" {
    source "$BATS_TEST_DIRNAME/../lib/setup/settings.sh"
    export SETTINGS_JSON="$BATS_TEST_TMPDIR/settings.json"
    printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"other.sh"}]}]}}' >"$SETTINGS_JSON"
    run configure_public_text_guard_hook
    [ "$status" -eq 0 ]
    run configure_public_text_guard_hook
    [ "$status" -eq 0 ]
    [ "$(jq '.hooks.PreToolUse | length' "$SETTINGS_JSON")" -eq 2 ]
    [ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$SETTINGS_JSON")" = "other.sh" ]
    [ "$(jq -r '.hooks.PreToolUse[1].matcher' "$SETTINGS_JSON")" = "Bash" ]
    [ "$(jq -r '.hooks.PreToolUse[1].hooks[0].command' "$SETTINGS_JSON")" = "~/.claude/hooks/guard-public-text.sh" ]
}
