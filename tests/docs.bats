#!/usr/bin/env bats
# docs.bats -- the README and docs/ describe what the tree holds.
#
# Docs drift silently: a renamed heading breaks every link to it, and an agent
# added without a README row is invisible to whoever reads the catalog.

# bats file_tags=unit,docs

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

# GitHub's heading anchors: lowercase, punctuation dropped, spaces to hyphens.
SLUG='{ s = tolower($0); gsub(/[^a-z0-9 _-]/, "", s); gsub(/ /, "-", s); print s }'

slug() {
    printf '%s\n' "$1" | LC_ALL=C awk "${SLUG}"
}

# The anchors a Markdown file defines, one per line, outside fenced code.
anchors() {
    LC_ALL=C awk '/^[[:space:]]*```/ { code = !code; next } !code && /^##* / { sub(/^##* /, ""); print }' "$1" |
        LC_ALL=C awk "${SLUG}"
}

@test "every relative link in the README and docs resolves" {
    local doc link target file anchor hits=""
    for doc in "$REPO_ROOT"/README.md "$REPO_ROOT"/docs/*.md "$REPO_ROOT"/docs/*/README.md; do
        [[ -f "${doc}" ]] || continue
        while IFS= read -r link; do
            target="${link#*](}"
            target="${target%)}"
            case "${target}" in http://* | https://* | mailto:*) continue ;; esac
            file="${target%%#*}"
            anchor=""
            [[ "${target}" == *'#'* ]] && anchor="${target#*#}"
            if [[ -z "${file}" ]]; then
                file="${doc}"
            else
                file="$(dirname "${doc}")/${file}"
            fi
            if [[ ! -e "${file}" ]]; then
                hits="${hits}${doc#"$REPO_ROOT"/}: ${target} (no such file)"$'\n'
            elif [[ -n "${anchor}" && "${file}" == *.md ]] && ! anchors "${file}" | grep -qxF "${anchor}"; then
                hits="${hits}${doc#"$REPO_ROOT"/}: ${target} (no such heading)"$'\n'
            fi
        # Links inside fenced code are examples, not links.
        done < <(awk '/^[[:space:]]*```/ { code = !code; next } !code' "${doc}" | grep -oE '\]\([^) ]+\)')
    done
    [ -z "${hits}" ] || {
        echo "Broken links:"
        echo "${hits}"
        false
    }
}

@test "the README catalog lists every agent and every skill" {
    local entry name hits=""
    for entry in "$REPO_ROOT"/.claude/agents/*.md "$REPO_ROOT"/.claude/skills/*/SKILL.md; do
        name="${entry%/SKILL.md}"
        name="${name##*/}"
        name="${name%.md}"
        grep -qF "\`${name}\`" "$REPO_ROOT/README.md" || hits="${hits}${name}"$'\n'
    done
    [ -z "${hits}" ] || {
        echo "Missing from the README's agents and skills:"
        echo "${hits}"
        false
    }
}

@test "docs/hooks.md covers every shipped hook" {
    local hook hits=""
    for hook in "$REPO_ROOT"/.claude/hooks/*.sh; do
        grep -qF "\`${hook##*/}\`" "$REPO_ROOT/docs/hooks.md" || hits="${hits}${hook##*/}"$'\n'
    done
    [ -z "${hits}" ] || {
        echo "Hooks missing from docs/hooks.md:"
        echo "${hits}"
        false
    }
}

@test "the slug matches GitHub's anchors for the headings docs link to" {
    [ "$(slug 'Usage for GPT and Muse models')" = "usage-for-gpt-and-muse-models" ]
    [ "$(slug 'Step 3: Set Your API Keys')" = "step-3-set-your-api-keys" ]
    [ "$(slug '4. Add agent-scoped hooks (optional)')" = "4-add-agent-scoped-hooks-optional" ]
    [ "$(slug 'statusline.conf')" = "statuslineconf" ]
    [ "$(slug 'Sharing `~/.claude` with other installers')" = "sharing-claude-with-other-installers" ]
}
