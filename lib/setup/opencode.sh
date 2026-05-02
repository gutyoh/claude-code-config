# opencode.sh -- OpenCode parallel install
# Path: lib/setup/opencode.sh
# Sourced by setup.sh — do not execute directly.

OPENCODE_CONFIG_DIR_DEFAULT="${HOME}/.config/opencode"
OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR_OVERRIDE:-${OPENCODE_CONFIG_DIR_DEFAULT}}"
OPENCODE_AGENTS_DIR="${OPENCODE_CONFIG_DIR}/agents"
OPENCODE_SKILLS_DIR="${OPENCODE_CONFIG_DIR}/skills"

_opencode_resolve_config_path() {
    if [[ -f "${OPENCODE_CONFIG_DIR}/opencode.jsonc" ]]; then
        echo "${OPENCODE_CONFIG_DIR}/opencode.jsonc"
    else
        echo "${OPENCODE_CONFIG_DIR}/opencode.json"
    fi
}
OPENCODE_JSON="$(_opencode_resolve_config_path)"

# Tier 0: OPENCODE_FORCE env. Tier 1: binary + --version. Tier 2: config dir exists.
detect_opencode() {
    if [[ -n "${OPENCODE_FORCE:-}" ]]; then
        case "${OPENCODE_FORCE}" in
            1 | true | yes | on | TRUE | YES | ON) return 0 ;;
            0 | false | no | off | FALSE | NO | OFF) return 1 ;;
        esac
    fi
    if command -v opencode &>/dev/null && opencode --version &>/dev/null; then
        return 0
    fi
    if [[ -d "${OPENCODE_CONFIG_DIR}" ]]; then
        return 0
    fi
    return 1
}

opencode_detect_label() {
    if [[ -n "${OPENCODE_FORCE:-}" ]]; then
        case "${OPENCODE_FORCE}" in
            1 | true | yes | on | TRUE | YES | ON) echo "yes (forced)"; return ;;
            0 | false | no | off | FALSE | NO | OFF) echo "no (forced)"; return ;;
        esac
    fi
    if command -v opencode &>/dev/null && opencode --version &>/dev/null; then
        echo "yes (binary detected)"
        return
    fi
    if [[ -d "${OPENCODE_CONFIG_DIR}" ]]; then
        echo "yes (config dir exists)"
        return
    fi
    echo "no (not installed)"
}

configure_opencode() {
    if ! command -v opencode &>/dev/null; then
        echo "  ⚠ opencode CLI not found in PATH"
        echo "    Install: brew install opencode"
        echo "    OpenCode setup skipped."
        return
    fi
    if ! command -v jq &>/dev/null; then
        echo "  ⚠ jq required. Skipping."
        return
    fi
    if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
        echo "  ⚠ python3 required. Skipping."
        return
    fi

    mkdir -p "${OPENCODE_CONFIG_DIR}" "${OPENCODE_AGENTS_DIR}"

    _opencode_link_skills
    _opencode_translate_agents
    _opencode_generate_json
    _opencode_link_agents_md
}

_opencode_link_skills() {
    local source="${REPO_DIR}/.claude/skills"
    local target="${OPENCODE_SKILLS_DIR}"

    if [[ ! -d "${source}" ]]; then
        echo "  ⚠ ${source} missing. Skipping skills symlink."
        return
    fi

    if [[ -L "${target}" ]]; then
        local current
        current="$(readlink "${target}")"
        if [[ "${current}" == "${source}" ]]; then
            echo "  ✓ ${target} -> ${source} (already configured)"
            return
        fi
        rm -f "${target}"
    elif [[ -d "${target}" ]]; then
        local backup_ts
        backup_ts="$(date +%s)"
        local backup="${target}.bak.${backup_ts}"
        mv "${target}" "${backup}"
        echo "  ⚠ ${target} was a real directory — backed up to ${backup}"
    elif [[ -e "${target}" ]]; then
        rm -f "${target}"
    fi

    ln -sfn "${source}" "${target}"
    echo "  ✓ ${target} -> ${source}"
}

# Translate Claude Code agent frontmatter to OpenCode-compatible:
#   drop name/model:inherit/hooks/tools, map color, add mode:subagent.
_opencode_translate_agents() {
    local source_dir="${REPO_DIR}/.claude/agents"
    if [[ ! -d "${source_dir}" ]]; then
        echo "  ⚠ ${source_dir} missing. Skipping agent translation."
        return
    fi

    local count=0
    local src
    for src in "${source_dir}"/*.md; do
        [[ -f "${src}" ]] || continue
        local name
        name="$(basename "${src}" .md)"
        local dest="${OPENCODE_AGENTS_DIR}/${name}.md"
        if _opencode_translate_one "${src}" "${dest}"; then
            count=$((count + 1))
        fi
    done

    echo "  ✓ ${OPENCODE_AGENTS_DIR}/ (${count} agents translated)"
}

_opencode_translate_one() {
    local src="$1" dest="$2"
    local py_cmd
    if command -v python3 &>/dev/null; then
        py_cmd="python3"
    else
        py_cmd="python"
    fi

    "${py_cmd}" - "${src}" "${dest}" <<'PYTHON_TRANSLATE'
import os
import re
import sys

src_path, dest_path = sys.argv[1], sys.argv[2]

# Claude Code named color → OpenCode theme token (zod regex ^#[0-9a-fA-F]{6}$
# OR enum primary|secondary|accent|success|warning|error|info).
COLOR_MAP = {
    "red": "error", "green": "success", "yellow": "warning", "orange": "warning",
    "blue": "info", "cyan": "info", "purple": "accent", "pink": "accent",
    "magenta": "accent", "white": "primary", "black": "secondary",
    "gray": "secondary", "grey": "secondary",
}
VALID_THEME_TOKENS = {
    "primary", "secondary", "accent", "success", "warning", "error", "info",
}
HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")


def translate_color(value: str) -> str | None:
    v = value.strip().strip('"').strip("'").lower()
    if v in VALID_THEME_TOKENS:
        return v
    if HEX_RE.match(v):
        return v
    if v in COLOR_MAP:
        return COLOR_MAP[v]
    return None


with open(src_path, "r", encoding="utf-8") as fh:
    content = fh.read()

m = re.match(r"^---\n(.*?)\n---\n(.*)$", content, re.DOTALL)
if not m:
    sys.exit(0)

frontmatter, body = m.group(1), m.group(2)
fm_lines = frontmatter.splitlines()

new_lines = []
in_skip_block = False

for line in fm_lines:
    if in_skip_block:
        if not line.strip() or line.startswith((" ", "\t")):
            continue
        in_skip_block = False

    if re.match(r"^name\s*:", line):
        continue
    if re.match(r"^model\s*:\s*inherit\s*$", line):
        continue
    if re.match(r"^hooks\s*:", line):
        in_skip_block = True
        continue
    if re.match(r"^tools\s*:", line):
        if line.rstrip().endswith(":"):
            in_skip_block = True
        continue

    cm = re.match(r"^(color\s*:\s*)(.+?)\s*$", line)
    if cm:
        translated = translate_color(cm.group(2))
        if translated is None:
            continue
        new_lines.append(f"{cm.group(1)}{translated}")
        continue

    new_lines.append(line)

if not any(re.match(r"^mode\s*:", line) for line in new_lines):
    new_lines.insert(0, "mode: subagent")

translated_content = "---\n" + "\n".join(new_lines).rstrip() + "\n---\n" + body

os.makedirs(os.path.dirname(dest_path), exist_ok=True)
with open(dest_path, "w", encoding="utf-8") as fh:
    fh.write(translated_content)
PYTHON_TRANSLATE
}

# backend = "doppler" → `doppler run -p PROJ -c CONF -- npx -y PKG`
# backend = "envfile" → `mcp-env-inject npx -y PKG`
# Wrong wrapper = MCP -32000 "Connection closed" (no keys reach server).
_opencode_build_mcp_entry() {
    local pkg="$1" backend="$2"
    if [[ "${backend}" == "doppler" ]]; then
        jq -n -c \
            --arg project "${DOPPLER_PROJECT}" \
            --arg config "${DOPPLER_CONFIG}" \
            --arg pkg "${pkg}" \
            '{
                type: "local",
                command: ["doppler", "run", "-p", $project, "-c", $config, "--", "npx", "-y", $pkg],
                enabled: true
            }'
    else
        jq -n -c --arg pkg "${pkg}" '{
            type: "local",
            command: ["mcp-env-inject", "npx", "-y", $pkg],
            enabled: true
        }'
    fi
}

# Merge MCP section into opencode.{json,jsonc}, preserving user keys.
_opencode_generate_json() {
    if [[ ${#INSTALL_MCP_SERVERS[@]} -eq 0 ]]; then
        echo "  ⊘ MCP servers not selected. Skipping opencode.json mcp section."
        return
    fi

    OPENCODE_JSON="$(_opencode_resolve_config_path)"

    local backend
    backend="$(detect_mcp_backend)"

    local mcp_section="{}"
    local key
    for key in "${INSTALL_MCP_SERVERS[@]}"; do
        local pkg
        pkg="$(mcp_get "${key}" package)"
        if [[ -z "${pkg}" ]]; then
            continue
        fi
        local entry
        entry="$(_opencode_build_mcp_entry "${pkg}" "${backend}")"
        mcp_section="$(printf '%s' "${mcp_section}" | jq -c \
            --arg name "${key}" \
            --argjson entry "${entry}" \
            '. + {($name): $entry}')"
    done

    local existing="{}"
    if [[ -f "${OPENCODE_JSON}" ]]; then
        if existing="$(jq -c '.' "${OPENCODE_JSON}" 2>/dev/null)"; then
            :
        else
            existing="$(sed -E 's://[^\n]*$::g; s/,(\s*[}\]])/\1/g' "${OPENCODE_JSON}" | jq -c '.' 2>/dev/null || echo '{}')"
            if [[ "${existing}" == "{}" ]]; then
                local backup_ts
                backup_ts="$(date +%s)"
                local backup="${OPENCODE_JSON}.bak.${backup_ts}"
                cp "${OPENCODE_JSON}" "${backup}" 2>/dev/null || true
                echo "  ⚠ Could not parse ${OPENCODE_JSON}; backed up to ${backup}"
            fi
        fi
    fi

    local merged
    merged="$(printf '%s' "${existing}" | jq \
        --argjson mcp "${mcp_section}" \
        '. + {"$schema": "https://opencode.ai/config.json"} + {mcp: ((.mcp // {}) + $mcp)}')"

    printf '%s\n' "${merged}" | jq '.' > "${OPENCODE_JSON}"
    echo "  ✓ ${OPENCODE_JSON} (${backend} backend)"
}

_opencode_link_agents_md() {
    local repo_claude="${REPO_DIR}/CLAUDE.md"
    local repo_agents="${REPO_DIR}/AGENTS.md"

    if [[ ! -f "${repo_claude}" ]]; then
        return
    fi

    if [[ -L "${repo_agents}" ]]; then
        local current
        current="$(readlink "${repo_agents}")"
        if [[ "${current}" == "CLAUDE.md" || "${current}" == "${repo_claude}" ]]; then
            echo "  ✓ AGENTS.md -> CLAUDE.md (already linked)"
            return
        fi
        rm -f "${repo_agents}"
    elif [[ -f "${repo_agents}" ]]; then
        echo "  ⊘ AGENTS.md exists as a regular file — leaving alone"
        return
    fi

    (cd "${REPO_DIR}" && ln -sfn "CLAUDE.md" "AGENTS.md")
    echo "  ✓ ${repo_agents} -> CLAUDE.md"
}
