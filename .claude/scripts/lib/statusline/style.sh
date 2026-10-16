# style.sh -- Per-component styles (style.<component>= in statusline.conf)
# Path: .claude/scripts/lib/statusline/style.sh
# Sourced by statusline.sh — do not execute directly.
#
# A style string is Starship's: words split by spaces or commas, each one of
# bold, dimmed, italic, underline, blink, inverted, hidden, strikethrough, none,
# fg:<color>, bg:<color>, or a bare <color> for the foreground. A color is an
# ANSI name (black red green yellow blue magenta/purple cyan white), the same
# with bright- in front, 0-255, or #RRGGBB. Unknown words are skipped, so a
# typo drops one word rather than the line.

# Sets REPLY to the 256-color index nearest to $1 $2 $3 (0-255 each): the
# closer of the 6x6x6 cube and the grey ramp, by squared distance.
_style_x256() {
    local v i cube=0 dist=0 level grey
    for v in "$1" "$2" "$3"; do
        i=$((v < 48 ? 0 : v < 115 ? 1 : (v - 35) / 40))
        level=$((i == 0 ? 0 : 55 + 40 * i))
        cube=$((cube * 6 + i))
        dist=$((dist + (v - level) * (v - level)))
    done
    v=$((($1 + $2 + $3) / 3))
    grey=$((v < 8 ? 0 : v > 238 ? 23 : (v - 3) / 10))
    level=$((8 + 10 * grey))
    v=$((($1 - level) * ($1 - level) + ($2 - level) * ($2 - level) + ($3 - level) * ($3 - level)))
    REPLY=$((v < dist ? 232 + grey : 16 + cube))
}

# Sets REPLY to the SGR parameters for color $1 as foreground ($2 = 38) or
# background ($2 = 48). Fails on a word that is not a color.
_style_color() {
    local c="$1" layer="$2" bright=0 i=""
    if [[ "${c}" == bright-* ]]; then
        bright=60
        c="${c#bright-}"
    fi
    case "${c}" in
        black) i=0 ;;
        red) i=1 ;;
        green) i=2 ;;
        yellow) i=3 ;;
        blue) i=4 ;;
        magenta | purple) i=5 ;;
        cyan) i=6 ;;
        white) i=7 ;;
    esac
    if [[ -n "${i}" ]]; then
        REPLY=$(((layer == 48 ? 40 : 30) + bright + i))
        return 0
    fi
    ((bright == 0)) || return 1
    if [[ "${c}" =~ ^[0-9]{1,3}$ ]] && ((10#${c} <= 255)); then
        REPLY="${layer};5;$((10#${c}))"
        return 0
    fi
    [[ "${c}" =~ ^#[0-9A-Fa-f]{6}$ ]] || return 1
    local r=$((16#${c:1:2})) g=$((16#${c:3:2})) b=$((16#${c:5:2}))
    case "${COLORTERM:-}" in
        truecolor | 24bit) REPLY="${layer};2;${r};${g};${b}" ;;
        *)
            _style_x256 "${r}" "${g}" "${b}"
            REPLY="${layer};5;${REPLY}"
            ;;
    esac
}

# Sets REPLY to the escape sequence for style string $1, or empty.
style_sgr() {
    local words word params="" IFS=$' \t,'
    read -ra words <<<"$1"
    for word in "${words[@]}"; do
        case "${word}" in
            bold) params+=";1" ;;
            dimmed | dim) params+=";2" ;;
            italic) params+=";3" ;;
            underline) params+=";4" ;;
            blink) params+=";5" ;;
            inverted | reverse) params+=";7" ;;
            hidden) params+=";8" ;;
            strikethrough) params+=";9" ;;
            none) params="" ;;
            fg:*) _style_color "${word#fg:}" 38 && params+=";${REPLY}" ;;
            bg:*) _style_color "${word#bg:}" 48 && params+=";${REPLY}" ;;
            *) _style_color "${word}" 38 && params+=";${REPLY}" ;;
        esac
    done
    REPLY=""
    [[ -n "${params}" ]] && REPLY=$'\033['"${params#;}m"
    return 0
}

# Sets REPLY to rendered component $2 wrapped in style string $1. The style is
# re-applied after each reset inside, so the component's own colors keep it.
style_component() {
    REPLY="$2"
    [[ -n "${NO_COLOR:-}" ]] && return 0
    local text="$2" rst=$'\033[0m' sgr
    style_sgr "$1"
    sgr="${REPLY}"
    if [[ -z "${sgr}" ]]; then
        REPLY="${text}"
        return 0
    fi
    REPLY="${sgr}${text//"${rst}"/${rst}${sgr}}${rst}"
}
