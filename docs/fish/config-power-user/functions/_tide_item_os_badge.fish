# Tide custom item: OS badge — auto-detects the host platform.
#
# Returns a Nerd Font (font-logos / Font Awesome) glyph for the
# current OS or distribution. Detection runs once per shell session
# (cached in a global var), so per-prompt cost is a single var read.
#
# Codepoints use \uXXXX escapes (ASCII-safe through any pipe).
#
# Detection order (first match wins):
#   1. macOS / FreeBSD / OpenBSD via `uname -s`
#   2. Raspberry Pi hardware via /sys/firmware/devicetree/base/model
#      (works regardless of which Linux distro is installed on it)
#   3. WSL via /proc/version (Microsoft kernel signature)
#   4. /etc/os-release ID — covers ~50 named distros
#   5. /etc/os-release ID_LIKE fallback for derivatives
#      (e.g. an unknown Arch derivative falls back to Arch)
#   6. Generic Tux glyph for unknown Linux
#
# Show behavior:
#   - Default: badge always renders.
#   - Set `tide_os_badge_ssh_only` (any value) to gate on $SSH_CONNECTION.
#     Useful on a daily-driver workstation where you only want the
#     badge to identify *remote* sessions.
#
# Enable in your prompt:
#   set -U tide_left_prompt_items os_badge pwd git newline character
#   set -U tide_os_badge_bg_color f38ba8   # mocha red
#   set -U tide_os_badge_color    1e1e2e   # mocha base

function _tide_item_os_badge --description "Tide OS badge (auto-detect)"
    if set -q tide_os_badge_ssh_only
        test -n "$SSH_CONNECTION"; or return
    end

    if not set -q __os_badge_cache
        set -g __os_badge_cache (__os_badge_compute)
    end

    _tide_print_item os_badge $__os_badge_cache
end

function __os_badge_compute
    switch (uname -s)
        case Darwin
            echo ; return    # nf-fa-apple
        case FreeBSD
            echo ; return    # nf-linux-freebsd
        case OpenBSD
            echo ; return    # nf-linux-openbsd
    end

    # Raspberry Pi hardware (any OS) — devicetree model string.
    if test -r /sys/firmware/devicetree/base/model
        set -l model (tr -d '\0' </sys/firmware/devicetree/base/model 2>/dev/null)
        if string match -q "Raspberry Pi*" -- $model
            echo ; return    # nf-linux-raspberry_pi
        end
    end

    # WSL — Microsoft kernel signature in /proc/version.
    if test -r /proc/version; and grep -qiE "microsoft|wsl" /proc/version 2>/dev/null
        echo ; return        # nf-fa-windows
    end

    set -l id ""
    set -l id_like ""
    if test -r /etc/os-release
        set id      (grep -E '^ID='      /etc/os-release | head -1 | cut -d= -f2 | tr -d '"')
        set id_like (grep -E '^ID_LIKE=' /etc/os-release | head -1 | cut -d= -f2 | tr -d '"')
    end

    set -l icon (__os_badge_id_to_icon $id)
    if test -n "$icon"
        echo $icon; return
    end

    for like in (string split " " -- $id_like)
        set icon (__os_badge_id_to_icon $like)
        if test -n "$icon"
            echo $icon; return
        end
    end

    echo                     # nf-fa-linux (Tux fallback)
end

function __os_badge_id_to_icon --argument-names id
    switch $id
        case alma          ; echo 
        case alpine        ; echo 
        case aosc          ; echo 
        case arch          ; echo 
        case archcraft     ; echo 
        case archlabs      ; echo 
        case arcolinux     ; echo 
        case artix         ; echo 
        case centos        ; echo 
        case crystal       ; echo 
        case debian        ; echo 
        case deepin        ; echo 
        case devuan        ; echo 
        case elementary    ; echo 
        case endeavouros   ; echo 
        case fedora        ; echo 
        case garuda        ; echo 
        case gentoo        ; echo 
        case guix          ; echo 
        case hyperbola     ; echo 
        case kali          ; echo 
        case linuxmint     ; echo 
        case mageia        ; echo 
        case mandriva      ; echo 
        case manjaro       ; echo 
        case 'mx*'         ; echo 
        case nixos         ; echo 
        case 'opensuse*'   ; echo 
        case parabola      ; echo 
        case parrot        ; echo 
        case pop           ; echo 
        case postmarketos  ; echo 
        case puppy         ; echo 
        case 'qubes*'      ; echo 
        case raspbian      ; echo 
        case rhel redhat   ; echo 
        case rocky         ; echo 
        case sabayon       ; echo 
        case slackware     ; echo 
        case solus         ; echo 
        case 'suse*'       ; echo 
        case tails         ; echo 
        case trisquel      ; echo 
        case tumbleweed    ; echo 
        case ubuntu        ; echo 
        case vanilla       ; echo 
        case void          ; echo 
        case xerolinux     ; echo 
        case zorin         ; echo 
    end
end
