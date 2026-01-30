#!/usr/bin/env bash
# setup.sh
# Path: claude-code-config/setup.sh
#
# Creates symlinks from this repo to ~/.claude/ for global Claude Code configuration.
# Optionally configures MCP servers, agents, and skills in user scope.
# Run this script from inside the repo directory. Safe to re-run if you move the repo.
#
# Usage: ./setup.sh [options]
#   -y, --yes              Accept all defaults without prompting
#   --no-mcp               Skip Brave Search MCP server installation
#   --no-agents            Skip agents & skills installation
#   --minimal              Core only (no agents, skills, or MCP)
#   --overwrite-settings   Replace settings.json with repo defaults
#   --skip-settings        Don't modify settings.json
#   --theme THEME          Statusline color theme (dark|light|colorblind|none)
#   --components LIST      Comma-separated statusline components
#   --bar-style STYLE      Progress bar style (text|block|smooth|gradient|thin|spark)
#   --bar-pct-inside       Show percentage inside the bar
#   --compact              Compact mode (no labels, merged tokens)
#   --no-compact           Verbose mode (labels, separate tokens)
#   --color-scope SCOPE    Color scope: percentage or full
#   --icon-style STYLE     Icon style (plain|bold|bracketed|rounded|reverse|bold-color|angle|double-bracket)
#   --weekly-show-reset    Show weekly reset countdown inline
#   -h, --help             Show this help message
#
# Platforms: macOS, Linux

set -euo pipefail

# --- Constants ---

readonly REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly CLAUDE_DIR="${HOME}/.claude"
readonly SETTINGS_JSON="${CLAUDE_DIR}/settings.json"
readonly CLAUDE_JSON="${HOME}/.claude.json"

# --- Installation Options (defaults) ---

INSTALL_AGENTS_SKILLS="true"
INSTALL_MCP="true"
SETTINGS_MODE="merge"  # merge | overwrite | skip
STATUSLINE_THEME="dark"  # dark | light | colorblind | none
STATUSLINE_COMPONENTS="model,usage,weekly,reset,tokens_in,tokens_out,tokens_cache,cost,burn_rate,email"
STATUSLINE_BAR_STYLE="text"
STATUSLINE_BAR_PCT_INSIDE="false"
STATUSLINE_COMPACT="true"  # Compact: no labels, merged tokens, no burn_rate in wide mode
STATUSLINE_COLOR_SCOPE="percentage"  # "percentage" = color usage only, "full" = color entire line
STATUSLINE_ICON=""  # Prefix icon: "✻", "A\", "❋", etc. or "" for none
STATUSLINE_ICON_STYLE="plain"  # plain|bold|bracketed|rounded|reverse|bold-color|angle|double-bracket
STATUSLINE_WEEKLY_SHOW_RESET="false"  # Show weekly reset countdown inline
ACCEPT_DEFAULTS="false"

# --- Component Registry ---

readonly ALL_COMPONENT_KEYS=(
    "model" "usage" "weekly" "reset" "tokens_in" "tokens_out" "tokens_cache"
    "cost" "burn_rate" "email" "version" "lines" "session_time" "cwd"
)

readonly ALL_COMPONENT_DESCS=(
    "Model name (opus-4.5)"
    "Session utilization (5h)"
    "Weekly utilization (7d)"
    "Reset countdown timer"
    "Input tokens count"
    "Output tokens count"
    "Cache read tokens"
    "Session cost in USD"
    "Burn rate (USD/hr)"
    "Account email address"
    "Claude Code version"
    "Lines added/removed"
    "Session elapsed time"
    "Working directory"
)

readonly DEFAULT_COMPONENT_INDICES=(0 1 2 3 4 5 6 7 8 9)  # first 10

# ============================================================================
# TUI Primitives — Pure Bash Interactive Menus (arrow keys + ANSI)
# ============================================================================

# Read a single keypress and return a logical key name.
# Arrow keys are multi-byte: ESC [ A/B/C/D
tui_readkey() {
    local key
    IFS= read -rsn1 key </dev/tty

    case "${key}" in
        $'\x1b')
            # Escape sequence — read 2 more chars (arrow keys: [A [B etc)
            local seq
            IFS= read -rsn2 -t 0.1 seq </dev/tty || true
            case "${seq}" in
                '[A') echo "up" ;;
                '[B') echo "down" ;;
                '[C') echo "right" ;;
                '[D') echo "left" ;;
                *)    echo "escape" ;;
            esac
            ;;
        '')    echo "enter" ;;   # Enter key
        ' ')   echo "space" ;;   # Space bar
        [qQ])  echo "quit" ;;
        *)     echo "${key}" ;;
    esac
}

# Single-select menu: arrow keys to navigate, enter to confirm.
# Usage: tui_select RESULT_VAR "header" "opt1" "opt2" ...
# Sets RESULT_VAR to the selected option string.
tui_select() {
    local -n _result_var="$1"
    local header="$2"
    shift 2
    local options=("$@")
    local count=${#options[@]}
    local cur=0

    # Save cursor and hide it
    tput civis 2>/dev/null || true

    # Print header
    echo ""
    printf "  \033[1m%s\033[0m\n" "${header}"
    echo ""

    # Initial draw
    local i
    for ((i = 0; i < count; i++)); do
        if [[ ${i} -eq ${cur} ]]; then
            printf "  \033[7m > %s \033[0m\n" "${options[$i]}"
        else
            printf "    %s\n" "${options[$i]}"
        fi
    done

    # Input loop
    while true; do
        local key
        key=$(tui_readkey)

        case "${key}" in
            up)
                [[ ${cur} -gt 0 ]] && cur=$((cur - 1))
                ;;
            down)
                [[ ${cur} -lt $((count - 1)) ]] && cur=$((cur + 1))
                ;;
            enter)
                break
                ;;
            quit|escape)
                break
                ;;
        esac

        # Move cursor up to redraw
        printf "\033[%dA" "${count}"

        for ((i = 0; i < count; i++)); do
            printf "\r\033[2K"
            if [[ ${i} -eq ${cur} ]]; then
                printf "  \033[7m > %s \033[0m\n" "${options[$i]}"
            else
                printf "    %s\n" "${options[$i]}"
            fi
        done
    done

    # Restore cursor
    tput cnorm 2>/dev/null || true

    _result_var="${options[$cur]}"
}

# Multi-select menu: arrow keys to navigate, space to toggle, enter to confirm.
# Usage: tui_multiselect RESULT_ARRAY_VAR "header" SELECTED_ARRAY OPTIONS_ARRAY DESCS_ARRAY
# Sets RESULT_ARRAY_VAR to array of selected indices.
tui_multiselect() {
    local -n _ms_result="$1"
    local header="$2"
    local -n _ms_selected="$3"
    local -n _ms_options="$4"
    local -n _ms_descs="$5"
    local count=${#_ms_options[@]}
    local cur=0

    # Build checked state from initial selection
    local checked=()
    for ((i = 0; i < count; i++)); do
        checked+=("false")
    done
    for idx in "${_ms_selected[@]}"; do
        if [[ ${idx} -ge 0 && ${idx} -lt ${count} ]]; then
            checked[${idx}]="true"
        fi
    done

    tput civis 2>/dev/null || true

    echo ""
    printf "  \033[1m%s\033[0m\n" "${header}"
    printf "  \033[2m(arrow keys: navigate, space: toggle, enter: confirm)\033[0m\n"
    echo ""

    # Draw function
    _ms_draw() {
        local i
        for ((i = 0; i < count; i++)); do
            local checkbox="[ ]"
            [[ "${checked[$i]}" == "true" ]] && checkbox="[x]"

            local desc=""
            if [[ ${#_ms_descs[@]} -gt ${i} && -n "${_ms_descs[$i]}" ]]; then
                desc=" \033[2m${_ms_descs[$i]}\033[0m"
            fi

            printf "\r\033[2K"
            if [[ ${i} -eq ${cur} ]]; then
                printf "  \033[7m %s %s \033[0m%b\n" "${checkbox}" "${_ms_options[$i]}" "${desc}"
            else
                printf "   %s %s%b\n" "${checkbox}" "${_ms_options[$i]}" "${desc}"
            fi
        done
    }

    _ms_draw

    while true; do
        local key
        key=$(tui_readkey)

        case "${key}" in
            up)
                [[ ${cur} -gt 0 ]] && cur=$((cur - 1))
                ;;
            down)
                [[ ${cur} -lt $((count - 1)) ]] && cur=$((cur + 1))
                ;;
            space)
                if [[ "${checked[$cur]}" == "true" ]]; then
                    checked[$cur]="false"
                else
                    checked[$cur]="true"
                fi
                ;;
            enter)
                break
                ;;
            a)
                # Select all
                for ((i = 0; i < count; i++)); do
                    checked[$i]="true"
                done
                ;;
            n)
                # Select none
                for ((i = 0; i < count; i++)); do
                    checked[$i]="false"
                done
                ;;
            quit|escape)
                break
                ;;
        esac

        printf "\033[%dA" "${count}"
        _ms_draw
    done

    tput cnorm 2>/dev/null || true

    # Collect selected indices
    _ms_result=()
    for ((i = 0; i < count; i++)); do
        if [[ "${checked[$i]}" == "true" ]]; then
            _ms_result+=("${i}")
        fi
    done
}

# Yes/No confirm: arrow keys to toggle, enter to confirm.
# Usage: tui_confirm "question" [default_yes]
# Returns 0 for yes, 1 for no.
tui_confirm() {
    local question="$1"
    local default="${2:-no}"  # "yes" or "no"
    local selected=1  # 0=yes, 1=no
    [[ "${default}" == "yes" ]] && selected=0

    tput civis 2>/dev/null || true

    echo ""

    _cf_draw() {
        printf "\r\033[2K"
        printf "  %s  " "${question}"
        if [[ ${selected} -eq 0 ]]; then
            printf "\033[7m Yes \033[0m  No"
        else
            printf "Yes  \033[7m No \033[0m"
        fi
    }

    _cf_draw

    while true; do
        local key
        key=$(tui_readkey)

        case "${key}" in
            left|up|h|y|Y)
                selected=0
                ;;
            right|down|l|n|N)
                selected=1
                ;;
            enter)
                echo ""
                tput cnorm 2>/dev/null || true
                return ${selected}
                ;;
            quit|escape)
                echo ""
                tput cnorm 2>/dev/null || true
                return 1
                ;;
        esac

        _cf_draw
    done
}

# ============================================================================
# Statusline Preview — renders mock statusline with current settings
# ============================================================================

_preview_overlay_pct() {
    # Overlay " NN% " at center of a bar string
    # Usage: _preview_overlay_pct BAR_VAR pct width
    local -n _pbar="$1"
    local pct="$2"
    local width="$3"
    local pstr=" ${pct}% "
    local plen=${#pstr}

    if [[ ${width} -ge $((plen + 2)) ]]; then
        local start=$(( (width - plen) / 2 ))
        local after=$((start + plen))
        local new_bar="${_pbar:0:${start}}${pstr}${_pbar:${after}}"
        _pbar="${new_bar:0:${width}}"
    fi
}

render_bar_preview() {
    local style="$1"
    local pct_inside="$2"
    local pct=42
    local width=20

    case "${style}" in
        text)
            printf "session: %d%% used" ${pct}
            ;;
        block)
            local filled=$(( pct * width / 100 ))
            local empty=$(( width - filled ))
            local bar=""
            for ((i = 0; i < filled; i++)); do bar+="█"; done
            for ((i = 0; i < empty; i++)); do bar+="·"; done
            [[ "${pct_inside}" == "true" ]] && _preview_overlay_pct bar ${pct} ${width}
            printf "[%s]" "${bar}"
            [[ "${pct_inside}" != "true" ]] && printf " %d%%" ${pct}
            ;;
        smooth)
            local partials=("" "▏" "▎" "▍" "▌" "▋" "▊" "▉")
            local total_eighths=$(( pct * width * 8 / 100 ))
            local full_blocks=$(( total_eighths / 8 ))
            local remainder=$(( total_eighths % 8 ))
            local has_partial=0
            [[ ${remainder} -gt 0 ]] && has_partial=1
            local empty_blocks=$(( width - full_blocks - has_partial ))
            local bar=""
            for ((i = 0; i < full_blocks; i++)); do bar+="█"; done
            [[ ${remainder} -gt 0 ]] && bar+="${partials[${remainder}]}"
            for ((i = 0; i < empty_blocks; i++)); do bar+="░"; done
            [[ "${pct_inside}" == "true" ]] && _preview_overlay_pct bar ${pct} ${width}
            printf "%s" "${bar}"
            [[ "${pct_inside}" != "true" ]] && printf " %d%%" ${pct}
            ;;
        gradient)
            local filled=$(( pct * width / 100 ))
            local empty=$(( width - filled ))
            local bar=""
            if [[ ${filled} -eq 0 ]]; then
                for ((i = 0; i < width; i++)); do bar+="░"; done
            elif [[ ${empty} -eq 0 ]]; then
                for ((i = 0; i < width; i++)); do bar+="█"; done
            else
                for ((i = 0; i < filled; i++)); do bar+="█"; done
                local remaining=$((empty))
                if [[ ${remaining} -ge 1 ]]; then bar+="▓"; remaining=$((remaining - 1)); fi
                if [[ ${remaining} -ge 1 ]]; then bar+="▒"; remaining=$((remaining - 1)); fi
                for ((i = 0; i < remaining; i++)); do bar+="░"; done
            fi
            [[ "${pct_inside}" == "true" ]] && _preview_overlay_pct bar ${pct} ${width}
            printf "%s" "${bar}"
            [[ "${pct_inside}" != "true" ]] && printf " %d%%" ${pct}
            ;;
        thin)
            local filled=$(( pct * width / 100 ))
            local empty=$(( width - filled ))
            local bar=""
            for ((i = 0; i < filled; i++)); do bar+="━"; done
            for ((i = 0; i < empty; i++)); do bar+="╌"; done
            [[ "${pct_inside}" == "true" ]] && _preview_overlay_pct bar ${pct} ${width}
            printf "%s" "${bar}"
            [[ "${pct_inside}" != "true" ]] && printf " %d%%" ${pct}
            ;;
        spark)
            local spark_chars=("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")
            local sw=5
            local bar=""
            for ((i = 0; i < sw; i++)); do
                local seg_start=$(( i * 100 / sw ))
                local seg_end=$(( (i + 1) * 100 / sw ))
                if [[ ${pct} -ge ${seg_end} ]]; then
                    bar+="█"
                elif [[ ${pct} -le ${seg_start} ]]; then
                    bar+="▁"
                else
                    local seg_range=$((seg_end - seg_start))
                    local seg_fill=$((pct - seg_start))
                    local idx=$(( seg_fill * 7 / seg_range ))
                    (( idx > 7 )) && idx=7
                    bar+="${spark_chars[${idx}]}"
                fi
            done
            printf "%s %d%%" "${bar}" ${pct}
            ;;
    esac
}

show_statusline_preview() {
    local is_compact="${STATUSLINE_COMPACT}"
    local bar_style="${STATUSLINE_BAR_STYLE}"
    local pct_inside="${STATUSLINE_BAR_PCT_INSIDE}"

    # In compact + text mode, usage is just plain percentage
    local usage_str
    if [[ "${is_compact}" == "true" && "${bar_style}" == "text" ]]; then
        usage_str="42%"
    else
        usage_str=$(render_bar_preview "${bar_style}" "${pct_inside}")
    fi

    # Icon prefix (styled)
    local icon_prefix=""
    if [[ -n "${STATUSLINE_ICON}" ]]; then
        case "${STATUSLINE_ICON_STYLE}" in
            bold)            icon_prefix="${STATUSLINE_ICON} " ;;
            bracketed)       icon_prefix="[${STATUSLINE_ICON}] " ;;
            rounded)         icon_prefix="(${STATUSLINE_ICON}) " ;;
            reverse)         icon_prefix=" ${STATUSLINE_ICON}  " ;;
            bold-color)      icon_prefix="${STATUSLINE_ICON} " ;;
            angle)           icon_prefix="⟨${STATUSLINE_ICON}⟩ " ;;
            double-bracket)  icon_prefix="⟦${STATUSLINE_ICON}⟧ " ;;
            *)               icon_prefix="${STATUSLINE_ICON} " ;;
        esac
    fi

    # Build wide-mode preview from components
    local IFS=','
    local comp_arr=(${STATUSLINE_COMPONENTS})
    unset IFS

    local parts=()
    local part_keys=()

    for key in "${comp_arr[@]}"; do
        case "${key}" in
            model)        parts+=("opus-4.5"); part_keys+=("model") ;;
            usage)        parts+=("${usage_str}"); part_keys+=("usage") ;;
            weekly)
                if [[ "${is_compact}" == "true" ]]; then
                    local weekly_str="63%"
                else
                    local weekly_str="weekly: 63%"
                fi
                if [[ "${STATUSLINE_WEEKLY_SHOW_RESET}" == "true" ]]; then
                    weekly_str+=" (4d2h)"
                fi
                parts+=("${weekly_str}")
                part_keys+=("weekly")
                ;;
            reset)
                if [[ "${is_compact}" == "true" ]]; then
                    parts+=("2h15m")
                else
                    parts+=("resets: 2h15m")
                fi
                part_keys+=("reset")
                ;;
            tokens_in)
                if [[ "${is_compact}" == "true" ]]; then
                    parts+=("15.4k")
                else
                    parts+=("in: 15.4k")
                fi
                part_keys+=("tokens_in")
                ;;
            tokens_out)
                if [[ "${is_compact}" == "true" ]]; then
                    parts+=("2.1k")
                else
                    parts+=("out: 2.1k")
                fi
                part_keys+=("tokens_out")
                ;;
            tokens_cache)
                if [[ "${is_compact}" == "true" ]]; then
                    parts+=("6.2M")
                else
                    parts+=("cache: 6.2M")
                fi
                part_keys+=("tokens_cache")
                ;;
            cost)         parts+=("\$5.21"); part_keys+=("cost") ;;
            burn_rate)
                # Hidden in compact mode
                if [[ "${is_compact}" != "true" ]]; then
                    parts+=("(\$2.99/hr)")
                    part_keys+=("burn_rate")
                fi
                ;;
            email)        parts+=("user@email.com"); part_keys+=("email") ;;
            version)      parts+=("v2.0.37"); part_keys+=("version") ;;
            lines)        parts+=("+2109 -103"); part_keys+=("lines") ;;
            session_time) parts+=("37m"); part_keys+=("session_time") ;;
            cwd)          parts+=("~/project"); part_keys+=("cwd") ;;
        esac
    done

    # Join with " | ", merging adjacent tokens with "/" when compact
    local result=""
    local idx=0
    local total=${#parts[@]}

    while [[ ${idx} -lt ${total} ]]; do
        local cur_key="${part_keys[${idx}]}"
        local cur_val="${parts[${idx}]}"

        # Compact: merge adjacent related components with /
        # Groups: tokens (tokens_in/out/cache), usage (usage/weekly)
        if [[ "${is_compact}" == "true" ]]; then
            local merge_group=""
            case "${cur_key}" in
                tokens_in|tokens_out|tokens_cache) merge_group="tokens" ;;
                usage|weekly) merge_group="usage" ;;
            esac

            if [[ -n "${merge_group}" ]]; then
                local merged="${cur_val}"
                local next=$((idx + 1))
                while [[ ${next} -lt ${total} ]]; do
                    local next_group=""
                    case "${part_keys[${next}]}" in
                        tokens_in|tokens_out|tokens_cache) next_group="tokens" ;;
                        usage|weekly) next_group="usage" ;;
                    esac
                    if [[ "${next_group}" == "${merge_group}" ]]; then
                        merged+="/${parts[${next}]}"
                        next=$((next + 1))
                    else
                        break
                    fi
                done
                [[ -n "${result}" ]] && result+=" | "
                result+="${merged}"
                idx=${next}
                continue
            fi
        fi

        [[ -n "${result}" ]] && result+=" | "
        result+="${cur_val}"
        idx=$((idx + 1))
    done

    printf "%s%s" "${icon_prefix}" "${result}"
}

show_preview_box() {
    local preview
    preview=$(show_statusline_preview)

    echo ""
    local mode_label="wide, compact"
    [[ "${STATUSLINE_COMPACT}" != "true" ]] && mode_label="wide, verbose"

    # Dynamic box width: content + 2 padding chars, min 66
    local content_len=${#preview}
    local box_inner=$((content_len + 2))
    [[ ${box_inner} -lt 66 ]] && box_inner=66

    # Top border
    local header="─ Preview (${mode_label} mode, 42% usage) "
    local header_len=${#header}
    local top_pad=$((box_inner - header_len))
    [[ ${top_pad} -lt 0 ]] && top_pad=0
    printf "  ┌%s" "${header}"
    for ((i = 0; i < top_pad; i++)); do printf "─"; done
    printf "┐\n"

    # Content line
    printf "  │ %s" "${preview}"
    local pad=$((box_inner - content_len))
    [[ ${pad} -lt 0 ]] && pad=0
    printf "%*s│\n" "${pad}" ""

    # Bottom border
    printf "  └"
    for ((i = 0; i < box_inner; i++)); do printf "─"; done
    printf "┘\n"
    echo ""
    echo "  Settings:"
    local icon_display="${STATUSLINE_ICON:-none}"
    local compact_display="no"
    [[ "${STATUSLINE_COMPACT}" == "true" ]] && compact_display="yes"
    local style_display="${STATUSLINE_ICON_STYLE}"
    [[ -z "${STATUSLINE_ICON}" ]] && style_display="n/a"
    echo "    theme: ${STATUSLINE_THEME} | compact: ${compact_display} | color: ${STATUSLINE_COLOR_SCOPE} | bar: ${STATUSLINE_BAR_STYLE} | icon: ${icon_display} (${style_display})"
    local comp_display="${STATUSLINE_COMPONENTS//,/, }"
    if [[ ${#comp_display} -gt 60 ]]; then
        comp_display="${comp_display:0:57}..."
    fi
    echo "    components: ${comp_display}"
}

# ============================================================================
# Setup Functions
# ============================================================================

create_symlink() {
    local source="$1"
    local target="$2"
    local name="$3"

    local claude_real
    claude_real=$(cd "${CLAUDE_DIR}" && pwd -P)
    local repo_claude_real
    repo_claude_real=$(cd "${REPO_DIR}/.claude" && pwd -P)

    if [[ "${claude_real}" == "${repo_claude_real}" ]]; then
        echo "  ✓ ~/.claude/${name} (same as repo, no symlink needed)"
        return 0
    fi

    if [[ -L "${target}" ]]; then
        local current_target
        current_target=$(readlink "${target}")
        if [[ "${current_target}" == "${source}" ]]; then
            echo "  ✓ ~/.claude/${name} -> ${source} (already configured)"
            return 0
        fi
    fi

    rm -rf "${target}"
    ln -s "${source}" "${target}"
    echo "  ✓ ~/.claude/${name} -> ${source}"
}

check_prerequisite() {
    local cmd="$1"
    local label="$2"
    local required="${3:-false}"
    local install_hint="${4:-}"

    if ! command -v "${cmd}" &>/dev/null; then
        echo "  ⚠ ${label} not found${install_hint:+ (${install_hint})}"
        if [[ -n "${install_hint}" ]]; then
            echo "    Install with: brew install ${cmd}  # macOS"
            echo "                  sudo apt-get install ${cmd}  # Ubuntu/Debian"
        fi
        if [[ "${required}" == "true" ]]; then
            echo "    Setup cannot continue without ${cmd}."
            exit 1
        fi
        echo ""
        return 1
    else
        echo "  ✓ ${label} installed"
        return 0
    fi
}

configure_ide_hook() {
    if python3 -c "
import json
import sys
try:
    with open('${SETTINGS_JSON}') as f:
        data = json.load(f)
    hooks = data.get('hooks', {}).get('PreToolUse', [])
    for hook in hooks:
        if hook.get('matcher') == 'mcp__ide__getDiagnostics':
            sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
        echo "  ✓ IDE diagnostics hook already configured"
    else
        echo "  Adding IDE diagnostics hook to existing settings..."
        python3 <<PYTHON_SCRIPT
import json
import sys

settings_file = "${SETTINGS_JSON}"

try:
    with open(settings_file) as f:
        data = json.load(f)

    if 'hooks' not in data:
        data['hooks'] = {}
    if 'PreToolUse' not in data['hooks']:
        data['hooks']['PreToolUse'] = []

    ide_hook = {
        "matcher": "mcp__ide__getDiagnostics",
        "hooks": [
            {
                "type": "command",
                "command": "~/.claude/hooks/open-file-in-ide.sh"
            }
        ]
    }

    existing = False
    for hook in data['hooks']['PreToolUse']:
        if hook.get('matcher') == 'mcp__ide__getDiagnostics':
            existing = True
            break

    if not existing:
        data['hooks']['PreToolUse'].append(ide_hook)

    with open(settings_file, 'w') as f:
        json.dump(data, f, indent=2)

    print("  ✓ IDE diagnostics hook added")
    sys.exit(0)
except Exception as e:
    print(f"  ⚠ Failed to add hook: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    fi
}

configure_file_suggestion() {
    if python3 -c "
import json
import sys
try:
    with open('${SETTINGS_JSON}') as f:
        data = json.load(f)
    if 'fileSuggestion' in data:
        sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
        echo "  ✓ File suggestion already configured"
    else
        echo "  Adding file suggestion to settings..."
        python3 <<PYTHON_SCRIPT
import json
import sys

settings_file = "${SETTINGS_JSON}"

try:
    with open(settings_file) as f:
        data = json.load(f)

    data['fileSuggestion'] = {
        "type": "command",
        "command": "~/.claude/scripts/file-suggestion.sh"
    }

    with open(settings_file, 'w') as f:
        json.dump(data, f, indent=2)

    print("  ✓ File suggestion configured")
    sys.exit(0)
except Exception as e:
    print(f"  ⚠ Failed to add file suggestion: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    fi
}

configure_statusline() {
    if python3 -c "
import json
import sys
try:
    with open('${SETTINGS_JSON}') as f:
        data = json.load(f)
    if 'statusLine' in data:
        sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
        echo "  ✓ Statusline already configured"
    else
        echo "  Adding statusline to settings..."
        python3 <<PYTHON_SCRIPT
import json
import sys

settings_file = "${SETTINGS_JSON}"

try:
    with open(settings_file) as f:
        data = json.load(f)

    data['statusLine'] = {
        "type": "command",
        "command": "~/.claude/scripts/statusline.sh",
        "padding": 0
    }

    with open(settings_file, 'w') as f:
        json.dump(data, f, indent=2)

    print("  ✓ Statusline configured")
    sys.exit(0)
except Exception as e:
    print(f"  ⚠ Failed to add statusline: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    fi
}

configure_statusline_conf() {
    local conf_file="${CLAUDE_DIR}/statusline.conf"

    if [[ -f "${conf_file}" ]]; then
        local matches="true"

        local cur_theme="" cur_components="" cur_bar_style="" cur_pct_inside="" cur_compact="" cur_color_scope="" cur_icon="" cur_icon_style="" cur_weekly_show_reset=""

        local first_line
        first_line=$(head -n1 "${conf_file}" 2>/dev/null | tr -d '[:space:]')

        if [[ -n "${first_line}" && "${first_line}" != *"="* ]]; then
            matches="false"
        else
            while IFS='=' read -r key value; do
                [[ -z "${key}" || "${key}" == \#* ]] && continue
                key=$(echo "${key}" | tr -d '[:space:]')
                # Don't strip spaces from value for icon (it could be "A\")
                value=$(echo "${value}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                case "${key}" in
                    theme)           cur_theme="${value}" ;;
                    components)      cur_components="${value}" ;;
                    bar_style)       cur_bar_style="${value}" ;;
                    bar_pct_inside)  cur_pct_inside="${value}" ;;
                    compact)         cur_compact="${value}" ;;
                    color_scope)     cur_color_scope="${value}" ;;
                    icon)            cur_icon="${value}" ;;
                    icon_style)      cur_icon_style="${value}" ;;
                    weekly_show_reset) cur_weekly_show_reset="${value}" ;;
                esac
            done < "${conf_file}"

            [[ "${cur_theme}" != "${STATUSLINE_THEME}" ]] && matches="false"
            [[ "${cur_components}" != "${STATUSLINE_COMPONENTS}" ]] && matches="false"
            [[ "${cur_bar_style}" != "${STATUSLINE_BAR_STYLE}" ]] && matches="false"
            [[ "${cur_pct_inside}" != "${STATUSLINE_BAR_PCT_INSIDE}" ]] && matches="false"
            [[ "${cur_compact}" != "${STATUSLINE_COMPACT}" ]] && matches="false"
            [[ "${cur_color_scope}" != "${STATUSLINE_COLOR_SCOPE}" ]] && matches="false"
            [[ "${cur_icon}" != "${STATUSLINE_ICON}" ]] && matches="false"
            [[ "${cur_icon_style}" != "${STATUSLINE_ICON_STYLE}" ]] && matches="false"
            [[ "${cur_weekly_show_reset}" != "${STATUSLINE_WEEKLY_SHOW_RESET}" ]] && matches="false"
        fi

        if [[ "${matches}" == "true" ]]; then
            echo "  ✓ Statusline config already up to date"
            return
        fi
    fi

    cat > "${conf_file}" <<EOF
theme=${STATUSLINE_THEME}
components=${STATUSLINE_COMPONENTS}
bar_style=${STATUSLINE_BAR_STYLE}
bar_pct_inside=${STATUSLINE_BAR_PCT_INSIDE}
compact=${STATUSLINE_COMPACT}
color_scope=${STATUSLINE_COLOR_SCOPE}
icon=${STATUSLINE_ICON}
icon_style=${STATUSLINE_ICON_STYLE}
weekly_show_reset=${STATUSLINE_WEEKLY_SHOW_RESET}
EOF
    echo "  ✓ Statusline config written (theme=${STATUSLINE_THEME}, bar=${STATUSLINE_BAR_STYLE})"
}

configure_mcp_servers() {
    if ! command -v claude &>/dev/null; then
        echo "  ⚠ Claude Code CLI not found. Install it first:"
        echo "    curl -fsSL https://claude.ai/install.sh | bash"
        echo ""
        echo "  After installing, re-run this script or manually add MCP servers:"
        echo "    claude mcp add brave-search --scope user \\"
        echo "      -e BRAVE_API_KEY='\${BRAVE_API_KEY}' \\"
        echo "      -- npx -y @brave/brave-search-mcp-server"
        echo ""
        return
    fi

    local user_scope_configured=false

    if [[ -f "${CLAUDE_JSON}" ]]; then
        if python3 -c "
import json
import sys
try:
    with open('${CLAUDE_JSON}') as f:
        data = json.load(f)
    if 'brave-search' in data.get('mcpServers', {}):
        sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
            user_scope_configured=true
        fi
    fi

    if [[ "${user_scope_configured}" == "true" ]]; then
        echo "  ✓ brave-search MCP already configured (user scope)"
    else
        echo "  Adding brave-search MCP server to user scope..."
        if claude mcp add brave-search --scope user \
            -e BRAVE_API_KEY='${BRAVE_API_KEY}' \
            -- npx -y @brave/brave-search-mcp-server 2>/dev/null; then
            echo "  ✓ brave-search MCP added to user scope"
        else
            echo "  ⚠ Failed to add brave-search MCP. You can add it manually:"
            echo "    claude mcp add brave-search --scope user \\"
            echo "      -e BRAVE_API_KEY='\${BRAVE_API_KEY}' \\"
            echo "      -- npx -y @brave/brave-search-mcp-server"
        fi
    fi
}

# ============================================================================
# CLI Argument Parsing & Help
# ============================================================================

show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Creates symlinks from this repo to ~/.claude/ for global Claude Code configuration."
    echo ""
    echo "Options:"
    echo "  -y, --yes              Accept all defaults without prompting"
    echo "  --no-mcp               Skip Brave Search MCP server installation"
    echo "  --no-agents            Skip agents & skills installation"
    echo "  --minimal              Core only (no agents, skills, or MCP)"
    echo "  --overwrite-settings   Replace settings.json with repo defaults"
    echo "  --skip-settings        Don't modify settings.json"
    echo "  --theme THEME          Statusline color theme (dark|light|colorblind|none)"
    echo "  --components LIST      Comma-separated statusline components"
    echo "  --bar-style STYLE      Progress bar style (text|block|smooth|gradient|thin|spark)"
    echo "  --bar-pct-inside       Show percentage inside the bar"
    echo "  --compact              Compact mode (no labels, merged tokens — default)"
    echo "  --no-compact           Verbose mode (labels, separate tokens, burn rate)"
    echo "  --color-scope SCOPE    Color scope: percentage (usage only) or full (entire line)"
    echo "  --icon ICON            Prefix icon (none|spark|anthropic|sparkle|star|custom)"
    echo "  --icon-style STYLE     Icon style (plain|bold|bracketed|rounded|reverse|bold-color|angle|double-bracket)"
    echo "  --weekly-show-reset    Show weekly reset countdown inline"
    echo "  --no-weekly-show-reset Hide weekly reset countdown (default)"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Available components:"
    echo "  model, usage, weekly, reset, tokens_in, tokens_out, tokens_cache,"
    echo "  cost, burn_rate, email, version, lines, session_time, cwd"
    echo ""
    echo "Examples:"
    echo "  ./setup.sh                     # Interactive mode (recommended)"
    echo "  ./setup.sh -y                  # Full install, no prompts"
    echo "  ./setup.sh -y --no-mcp         # Full install without Brave Search MCP"
    echo "  ./setup.sh -y --minimal        # Core only (hooks, scripts, commands)"
    echo "  ./setup.sh -y --theme colorblind  # Full install with colorblind theme"
    echo "  ./setup.sh -y --bar-style block --bar-pct-inside --components model,usage,cost"
    echo "  ./setup.sh --overwrite-settings # Interactive, but force-overwrite settings.json"
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes)
                ACCEPT_DEFAULTS="true"
                shift
                ;;
            --no-mcp)
                INSTALL_MCP="false"
                shift
                ;;
            --no-agents)
                INSTALL_AGENTS_SKILLS="false"
                shift
                ;;
            --minimal)
                INSTALL_AGENTS_SKILLS="false"
                INSTALL_MCP="false"
                shift
                ;;
            --overwrite-settings)
                SETTINGS_MODE="overwrite"
                shift
                ;;
            --skip-settings)
                SETTINGS_MODE="skip"
                shift
                ;;
            --theme)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --theme requires a value (dark|light|colorblind|none)"
                    exit 1
                fi
                case "$2" in
                    dark|light|colorblind|none)
                        STATUSLINE_THEME="$2"
                        ;;
                    *)
                        echo "Error: Invalid theme '$2'. Choose: dark, light, colorblind, none"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            --components)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --components requires a comma-separated list"
                    exit 1
                fi
                STATUSLINE_COMPONENTS="$2"
                shift 2
                ;;
            --bar-style)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --bar-style requires a value (text|block|smooth|gradient|thin|spark)"
                    exit 1
                fi
                case "$2" in
                    text|block|smooth|gradient|thin|spark)
                        STATUSLINE_BAR_STYLE="$2"
                        ;;
                    *)
                        echo "Error: Invalid bar style '$2'. Choose: text, block, smooth, gradient, thin, spark"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            --bar-pct-inside)
                STATUSLINE_BAR_PCT_INSIDE="true"
                shift
                ;;
            --compact)
                STATUSLINE_COMPACT="true"
                shift
                ;;
            --no-compact)
                STATUSLINE_COMPACT="false"
                shift
                ;;
            --color-scope)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --color-scope requires a value (percentage|full)"
                    exit 1
                fi
                case "$2" in
                    percentage|full)
                        STATUSLINE_COLOR_SCOPE="$2"
                        ;;
                    *)
                        echo "Error: Invalid color scope '$2'. Choose: percentage, full"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            --icon)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --icon requires a value (none, spark, anthropic, sparkle, star, or a custom string)"
                    exit 1
                fi
                case "$2" in
                    none)       STATUSLINE_ICON="" ;;
                    spark)      STATUSLINE_ICON="✻" ;;
                    anthropic)  STATUSLINE_ICON='A\' ;;
                    sparkle)    STATUSLINE_ICON="❇" ;;
                    star)       STATUSLINE_ICON="✦" ;;
                    *)          STATUSLINE_ICON="$2" ;;
                esac
                shift 2
                ;;
            --weekly-show-reset)
                STATUSLINE_WEEKLY_SHOW_RESET="true"
                shift
                ;;
            --no-weekly-show-reset)
                STATUSLINE_WEEKLY_SHOW_RESET="false"
                shift
                ;;
            --icon-style)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --icon-style requires a value"
                    exit 1
                fi
                case "$2" in
                    plain|bold|bracketed|rounded|reverse|bold-color|angle|double-bracket)
                        STATUSLINE_ICON_STYLE="$2"
                        ;;
                    *)
                        echo "Error: Invalid icon style '$2'. Choose: plain, bold, bracketed, rounded, reverse, bold-color, angle, double-bracket"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Error: Unknown option: $1"
                echo ""
                show_usage
                exit 1
                ;;
        esac
    done
}

# ============================================================================
# Interactive Installation Menu
# ============================================================================

show_install_menu() {
    local agents_label="yes"
    local mcp_label="yes"
    local settings_label="merge (preserve existing, add new)"
    local pct_label="no"

    [[ "${INSTALL_AGENTS_SKILLS}" == "false" ]] && agents_label="no"
    [[ "${INSTALL_MCP}" == "false" ]] && mcp_label="no"
    [[ "${SETTINGS_MODE}" == "overwrite" ]] && settings_label="overwrite (replace with repo defaults)"
    [[ "${SETTINGS_MODE}" == "skip" ]] && settings_label="skip (don't modify)"
    [[ "${STATUSLINE_BAR_PCT_INSIDE}" == "true" ]] && pct_label="yes"

    local comp_display="${STATUSLINE_COMPONENTS//,/, }"
    [[ ${#comp_display} -gt 50 ]] && comp_display="${comp_display:0:47}..."

    echo "Current installation options:"
    echo "  core (hooks, scripts, commands):  always"
    echo "  agents & skills:                  ${agents_label}"
    echo "  brave search MCP:                 ${mcp_label}"
    echo "  settings.json:                    ${settings_label}"
    echo "  statusline color theme:           ${STATUSLINE_THEME}"
    echo "  statusline components:            ${comp_display}"
    local compact_label="yes"
    [[ "${STATUSLINE_COMPACT}" != "true" ]] && compact_label="no"

    echo "  statusline compact mode:          ${compact_label}"
    echo "  statusline color scope:           ${STATUSLINE_COLOR_SCOPE}"
    echo "  statusline bar style:             ${STATUSLINE_BAR_STYLE}"
    echo "  statusline pct inside bar:        ${pct_label}"
    echo "  statusline icon:                  ${STATUSLINE_ICON:-none}"
    echo "  statusline icon style:            ${STATUSLINE_ICON_STYLE}"
    local weekly_reset_label="no"
    [[ "${STATUSLINE_WEEKLY_SHOW_RESET}" == "true" ]] && weekly_reset_label="yes"
    echo "  statusline weekly reset:          ${weekly_reset_label}"
    echo ""

    local menu_choice
    tui_select menu_choice "What would you like to do?" \
        "Proceed with installation" \
        "Customize installation" \
        "Cancel"

    case "${menu_choice}" in
        "Proceed"*)
            ;;
        "Customize"*)
            customize_installation
            ;;
        "Cancel"*)
            echo "Installation cancelled."
            exit 0
            ;;
    esac
}

# ============================================================================
# Interactive Customization (TUI-powered)
# ============================================================================

customize_installation() {
    # --- Agents & Skills ---
    if tui_confirm "Install agents & skills?" "yes"; then
        INSTALL_AGENTS_SKILLS="true"
    else
        INSTALL_AGENTS_SKILLS="false"
    fi

    # --- MCP ---
    if tui_confirm "Install Brave Search MCP server?" "yes"; then
        INSTALL_MCP="true"
    else
        INSTALL_MCP="false"
    fi

    # --- Settings mode ---
    local settings_choice
    tui_select settings_choice "Settings.json mode:" \
        "merge     - Preserve existing settings, add new" \
        "overwrite - Replace with repo defaults" \
        "skip      - Don't modify settings.json"

    case "${settings_choice}" in
        overwrite*) SETTINGS_MODE="overwrite" ;;
        skip*)      SETTINGS_MODE="skip" ;;
        *)          SETTINGS_MODE="merge" ;;
    esac

    # --- Statusline customization with preview loop ---
    customize_statusline_with_preview
}

customize_statusline_with_preview() {
    while true; do
        # --- Theme ---
        local theme_choice
        tui_select theme_choice "Statusline color theme:" \
            "dark       - Yellow/red on dark background" \
            "light      - Blue/red on light background" \
            "colorblind - Bold yellow/magenta, accessible (no red/green)" \
            "none       - No colors"

        case "${theme_choice}" in
            light*)      STATUSLINE_THEME="light" ;;
            colorblind*) STATUSLINE_THEME="colorblind" ;;
            none*)       STATUSLINE_THEME="none" ;;
            *)           STATUSLINE_THEME="dark" ;;
        esac

        # --- Compact mode ---
        if tui_confirm "Compact mode? (no labels, merged tokens — matches original format)" "yes"; then
            STATUSLINE_COMPACT="true"
        else
            STATUSLINE_COMPACT="false"
        fi

        # --- Color scope ---
        local color_scope_choice
        tui_select color_scope_choice "Color scope (which part gets colored by utilization):" \
            "percentage - Color only the usage/percentage component" \
            "full       - Color the entire statusline"

        case "${color_scope_choice}" in
            full*) STATUSLINE_COLOR_SCOPE="full" ;;
            *)     STATUSLINE_COLOR_SCOPE="percentage" ;;
        esac

        # --- Components (multi-select with checkboxes) ---
        # Build initial selection from current STATUSLINE_COMPONENTS
        local init_selected=()
        local IFS=','
        local current_comps=(${STATUSLINE_COMPONENTS})
        unset IFS

        for comp in "${current_comps[@]}"; do
            for ((j = 0; j < ${#ALL_COMPONENT_KEYS[@]}; j++)); do
                if [[ "${ALL_COMPONENT_KEYS[$j]}" == "${comp}" ]]; then
                    init_selected+=("${j}")
                    break
                fi
            done
        done

        local selected_indices=()
        tui_multiselect selected_indices \
            "Statusline components (space: toggle, a: all, n: none, enter: confirm):" \
            init_selected \
            ALL_COMPONENT_KEYS \
            ALL_COMPONENT_DESCS

        # Convert indices back to comma-separated keys
        local new_components=""
        for idx in "${selected_indices[@]}"; do
            [[ -n "${new_components}" ]] && new_components+=","
            new_components+="${ALL_COMPONENT_KEYS[$idx]}"
        done
        STATUSLINE_COMPONENTS="${new_components:-model}"

        # --- Bar Style (single-select with visual examples) ---
        local bar_options=(
            "text      session: 42% used"
            "block     [████████············] 42%"
            "smooth    ████████▍░░░░░░░░░░░░ 42%    (1/8th precision)"
            "gradient  ████████▓▒░░░░░░░░░░░░ 42%"
            "thin      ━━━━━━━━╌╌╌╌╌╌╌╌╌╌╌╌ 42%"
            "spark     ██▁▁▁ 42%                   (compact 5-char)"
        )

        local bar_choice
        tui_select bar_choice "Progress bar style (for 'usage' component, wide mode):" \
            "${bar_options[@]}"

        # Extract style name (first word)
        STATUSLINE_BAR_STYLE="${bar_choice%% *}"

        # --- Pct Inside (only for bar styles that support it) ---
        STATUSLINE_BAR_PCT_INSIDE="false"
        if [[ "${STATUSLINE_BAR_STYLE}" != "text" && "${STATUSLINE_BAR_STYLE}" != "spark" ]]; then
            if tui_confirm "Show percentage inside the bar?" "no"; then
                STATUSLINE_BAR_PCT_INSIDE="true"
            fi
        fi

        # --- Weekly reset toggle (only if weekly component is selected) ---
        if [[ "${STATUSLINE_COMPONENTS}" == *"weekly"* ]]; then
            if tui_confirm "Show weekly reset countdown inline? (e.g. 63% (4d2h))" "no"; then
                STATUSLINE_WEEKLY_SHOW_RESET="true"
            else
                STATUSLINE_WEEKLY_SHOW_RESET="false"
            fi
        fi

        # --- Icon Prefix ---
        local icon_choice
        tui_select icon_choice "Statusline prefix icon:" \
            "✻  Claude spark   (teardrop asterisk — Claude logo)" \
            'A\  Anthropic      (text logo)' \
            "❋  Propeller      (heavy teardrop spokes)" \
            "✦  Star           (four-pointed star)" \
            "❇  Sparkle        (sparkle symbol)" \
            "none               (no icon)"

        case "${icon_choice}" in
            "✻"*)    STATUSLINE_ICON="✻" ;;
            "A\\"*)  STATUSLINE_ICON='A\' ;;
            "❋"*)    STATUSLINE_ICON="❋" ;;
            "✦"*)    STATUSLINE_ICON="✦" ;;
            "❇"*)    STATUSLINE_ICON="❇" ;;
            *)        STATUSLINE_ICON="" ;;
        esac

        # --- Icon Style (only if an icon was selected) ---
        if [[ -n "${STATUSLINE_ICON}" ]]; then
            local icon_style_choice
            tui_select icon_style_choice "Icon style:" \
                "plain          ${STATUSLINE_ICON}                   (as-is)" \
                "bold           ${STATUSLINE_ICON}                   (bold weight)" \
                "bracketed      [${STATUSLINE_ICON}]                  (square brackets)" \
                "rounded        (${STATUSLINE_ICON})                  (parentheses)" \
                "reverse        ${STATUSLINE_ICON}                   (inverted background)" \
                "bold-color     ${STATUSLINE_ICON}                   (bold + blue accent)" \
                "angle          ⟨${STATUSLINE_ICON}⟩                  (angle brackets)" \
                "double-bracket ⟦${STATUSLINE_ICON}⟧                  (double brackets)"

            STATUSLINE_ICON_STYLE="${icon_style_choice%% *}"
        else
            STATUSLINE_ICON_STYLE="plain"
        fi

        # --- Live Preview + Confirm ---
        show_preview_box

        if tui_confirm "Look good?" "yes"; then
            break
        fi

        echo ""
        echo "  Let's try again..."
    done
}

# ============================================================================
# Main
# ============================================================================

main() {
    parse_arguments "$@"

    echo "Claude Code Config Setup"
    echo "========================"
    echo "Repo location: ${REPO_DIR}"
    echo ""

    # Check prerequisites
    echo "Checking prerequisites..."

    check_prerequisite "jq" "jq" "false" "required for IDE diagnostics hook and file suggestion"
    check_prerequisite "python3" "python3" "true" ""
    check_prerequisite "fd" "fd" "false" "optional: for faster file suggestions"
    check_prerequisite "fzf" "fzf" "false" "optional: for faster file suggestions"
    check_prerequisite "ccusage" "ccusage" "false" "optional: for statusline billing tracking"
    check_prerequisite "bc" "bc" "false" "optional: for statusline number formatting"

    echo ""

    # Show interactive menu (unless --yes flag was passed)
    if [[ "${ACCEPT_DEFAULTS}" == "false" ]]; then
        show_install_menu
    fi

    echo ""

    local step=0

    # --- Create symlinks ---
    step=$((step + 1))
    mkdir -p "${CLAUDE_DIR}"

    echo "Step ${step}: Creating symlinks..."

    create_symlink "${REPO_DIR}/.claude/commands" "${CLAUDE_DIR}/commands" "commands"
    create_symlink "${REPO_DIR}/.claude/hooks" "${CLAUDE_DIR}/hooks" "hooks"
    create_symlink "${REPO_DIR}/.claude/scripts" "${CLAUDE_DIR}/scripts" "scripts"

    if [[ "${INSTALL_AGENTS_SKILLS}" == "true" ]]; then
        create_symlink "${REPO_DIR}/.claude/skills" "${CLAUDE_DIR}/skills" "skills"
        create_symlink "${REPO_DIR}/.claude/agents" "${CLAUDE_DIR}/agents" "agents"
    else
        echo "  ⊘ Skipping agents & skills (not selected)"
    fi

    echo ""

    # --- Configure settings.json ---
    if [[ "${SETTINGS_MODE}" == "overwrite" ]]; then
        step=$((step + 1))
        echo "Step ${step}: Overwriting settings.json with repo defaults..."
        echo ""

        cp "${REPO_DIR}/.claude/settings.json" "${SETTINGS_JSON}"
        echo "  ✓ settings.json replaced with repo defaults"

        echo ""

        step=$((step + 1))
        echo "Step ${step}: Configuring file suggestion (user scope)..."
        echo ""

        if command -v fd &>/dev/null && command -v fzf &>/dev/null; then
            configure_file_suggestion
        else
            echo "  ⚠ Skipping file suggestion (fd and fzf not installed)"
            echo "    Install with: brew install fd fzf  # macOS"
            echo "                  sudo apt-get install fd-find fzf  # Ubuntu/Debian"
        fi

        echo ""

        step=$((step + 1))
        echo "Step ${step}: Configuring statusline config..."
        echo ""

        configure_statusline_conf

    elif [[ "${SETTINGS_MODE}" == "merge" ]]; then
        step=$((step + 1))
        echo "Step ${step}: Configuring hooks (user scope)..."
        echo ""

        if [[ ! -f "${SETTINGS_JSON}" ]]; then
            echo "  Creating ~/.claude/settings.json with default hooks..."
            cat > "${SETTINGS_JSON}" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "mcp__ide__getDiagnostics",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/open-file-in-ide.sh"
          }
        ]
      }
    ]
  }
}
EOF
            echo "  ✓ IDE diagnostics hook configured"
        else
            configure_ide_hook
        fi

        echo ""

        step=$((step + 1))
        echo "Step ${step}: Configuring file suggestion (user scope)..."
        echo ""

        if command -v fd &>/dev/null && command -v fzf &>/dev/null; then
            configure_file_suggestion
        else
            echo "  ⚠ Skipping file suggestion (fd and fzf not installed)"
            echo "    Install with: brew install fd fzf  # macOS"
            echo "                  sudo apt-get install fd-find fzf  # Ubuntu/Debian"
        fi

        echo ""

        step=$((step + 1))
        echo "Step ${step}: Configuring statusline (user scope)..."
        echo ""

        configure_statusline

        if ! command -v ccusage &>/dev/null; then
            echo ""
            echo "  Note: Install ccusage for full statusline functionality:"
            echo "    npm install -g ccusage"
        fi

        echo ""

        step=$((step + 1))
        echo "Step ${step}: Configuring statusline config..."
        echo ""

        configure_statusline_conf

    else
        step=$((step + 1))
        echo "Step ${step}: Skipping settings.json configuration (not selected)"
    fi

    echo ""

    # --- Configure MCP servers ---
    if [[ "${INSTALL_MCP}" == "true" ]]; then
        step=$((step + 1))
        echo "Step ${step}: Configuring MCP servers (user scope)..."
        echo ""

        configure_mcp_servers

        echo ""

        step=$((step + 1))
        echo "Step ${step}: Environment variables"
        echo ""

        if [[ -n "${BRAVE_API_KEY:-}" ]]; then
            echo "  ✓ BRAVE_API_KEY is set (${#BRAVE_API_KEY} chars)"
        else
            echo "  ⚠ BRAVE_API_KEY not set. Add to your shell profile:"
            echo ""
            echo "    # Add to ~/.zshrc or ~/.bashrc:"
            echo "    export BRAVE_API_KEY=\"your-api-key-here\""
            echo ""
            echo "    Get a free API key (2,000 searches/month):"
            echo "    https://api-dashboard.search.brave.com/"
        fi
    else
        step=$((step + 1))
        echo "Step ${step}: Skipping MCP servers (not selected)"
    fi

    echo ""
    echo "========================================"
    echo "Setup complete!"
    echo "========================================"
    echo ""
    echo "Verify in any project:"
    echo "  cd ~/some-project"
    echo "  claude"
    echo "  > /help           # Should show custom commands"

    if [[ "${INSTALL_MCP}" == "true" ]]; then
        echo "  > /brave-search   # Test the MCP integration"
        echo ""
        echo "To check MCP server status:"
        echo "  claude mcp list"
    fi
}

main "$@"
