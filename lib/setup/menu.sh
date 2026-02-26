# menu.sh -- Interactive installation menu and customization
# Path: lib/setup/menu.sh
# Sourced by setup.sh — do not execute directly.

show_install_menu() {
    local agents_label="yes"
    local settings_label="merge (preserve existing, add new)"
    local pct_label="no"

    [[ "${INSTALL_AGENTS_SKILLS}" == "false" ]] && agents_label="no"
    [[ "${SETTINGS_MODE}" == "overwrite" ]] && settings_label="overwrite (replace with repo defaults)"
    [[ "${SETTINGS_MODE}" == "skip" ]] && settings_label="skip (don't modify)"
    [[ "${STATUSLINE_BAR_PCT_INSIDE}" == "true" ]] && pct_label="yes"

    # Build MCP servers display
    local mcp_label="none"
    if [[ ${#INSTALL_MCP_SERVERS[@]} -gt 0 ]]; then
        mcp_label="${INSTALL_MCP_SERVERS[*]}"
        mcp_label="${mcp_label// /, }"
    fi

    local comp_display="${STATUSLINE_COMPONENTS//,/, }"
    [[ ${#comp_display} -gt 50 ]] && comp_display="${comp_display:0:47}..."

    echo "Current installation options:"
    echo "  core (hooks, scripts, commands):  always"
    local teams_label="yes"
    [[ "${INSTALL_AGENT_TEAMS}" == "false" ]] && teams_label="no"

    echo "  agents & skills:                  ${agents_label}"
    echo "  MCP search servers:               ${mcp_label}"
    local proxy_path_label="yes"
    [[ "${INSTALL_PROXY_PATH}" == "false" ]] && proxy_path_label="no"

    echo "  agent teams (experimental):       ${teams_label}"
    echo "  proxy launcher PATH:              ${proxy_path_label}"
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
        "Proceed"*) ;;
        "Customize"*)
            customize_installation
            ;;
        "Cancel"*)
            echo "Installation cancelled."
            exit 0
            ;;
    esac
}

customize_installation() {
    # --- Agents & Skills ---
    local agents_default="yes"
    [[ "${INSTALL_AGENTS_SKILLS}" == "false" ]] && agents_default="no"
    if tui_confirm "Install agents & skills?" "${agents_default}"; then
        INSTALL_AGENTS_SKILLS="true"
    else
        INSTALL_AGENTS_SKILLS="false"
    fi

    # --- MCP Servers (multi-select) ---
    local mcp_init_selected=()
    local i
    for i in "${!MCP_SERVER_KEYS[@]}"; do
        local key="${MCP_SERVER_KEYS[$i]}"
        local j
        for j in "${!INSTALL_MCP_SERVERS[@]}"; do
            if [[ "${INSTALL_MCP_SERVERS[$j]}" == "${key}" ]]; then
                mcp_init_selected+=("${i}")
                break
            fi
        done
    done

    local mcp_descs=()
    for key in "${MCP_SERVER_KEYS[@]}"; do
        mcp_descs+=("${MCP_SERVER_DESCS[${key}]}")
    done

    local mcp_selected_indices=()
    tui_multiselect mcp_selected_indices \
        "MCP search servers (space: toggle, a: all, n: none, enter: confirm):" \
        mcp_init_selected \
        MCP_SERVER_KEYS \
        mcp_descs

    INSTALL_MCP_SERVERS=()
    for i in "${mcp_selected_indices[@]}"; do
        INSTALL_MCP_SERVERS+=("${MCP_SERVER_KEYS[$i]}")
    done

    # --- Agent Teams ---
    local teams_default="yes"
    [[ "${INSTALL_AGENT_TEAMS}" == "false" ]] && teams_default="no"
    if tui_confirm "Enable agent teams? (experimental)" "${teams_default}"; then
        INSTALL_AGENT_TEAMS="true"
    else
        INSTALL_AGENT_TEAMS="false"
    fi

    # --- Proxy Launcher PATH ---
    local proxy_default="yes"
    [[ "${INSTALL_PROXY_PATH}" == "false" ]] && proxy_default="no"
    if tui_confirm "Add proxy launcher (bin/) to PATH? (enables 'claude-proxy' from anywhere)" "${proxy_default}"; then
        INSTALL_PROXY_PATH="true"
    else
        INSTALL_PROXY_PATH="false"
    fi

    # --- Settings mode ---
    local settings_choice
    tui_select settings_choice "Settings.json mode:" \
        "merge     - Preserve existing settings, add new" \
        "overwrite - Replace with repo defaults" \
        "skip      - Don't modify settings.json"

    case "${settings_choice}" in
        overwrite*) SETTINGS_MODE="overwrite" ;;
        skip*) SETTINGS_MODE="skip" ;;
        *) SETTINGS_MODE="merge" ;;
    esac

    # --- Statusline customization with preview loop ---
    customize_statusline_with_preview
    USER_CUSTOMIZED_STATUSLINE="true"
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
            light*) STATUSLINE_THEME="light" ;;
            colorblind*) STATUSLINE_THEME="colorblind" ;;
            none*) STATUSLINE_THEME="none" ;;
            *) STATUSLINE_THEME="dark" ;;
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
            *) STATUSLINE_COLOR_SCOPE="percentage" ;;
        esac

        # --- Components (multi-select with checkboxes) ---
        # Build initial selection from current STATUSLINE_COMPONENTS
        local init_selected=()
        IFS=',' read -ra current_comps <<<"${STATUSLINE_COMPONENTS}"

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
            "✻"*) STATUSLINE_ICON="✻" ;;
            "A\\"*) STATUSLINE_ICON='A\' ;;
            "❋"*) STATUSLINE_ICON="❋" ;;
            "✦"*) STATUSLINE_ICON="✦" ;;
            "❇"*) STATUSLINE_ICON="❇" ;;
            *) STATUSLINE_ICON="" ;;
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
