#!/usr/bin/env bats
# forecast.sh: run-out suffix and level for the 5-hour and weekly windows.

setup() {
    L="${BATS_TEST_DIRNAME}/../.claude/scripts/lib/statusline"
    PLATFORM=linux
    source "${L}/utils.sh"
    source "${L}/cache.sh"
    source "${L}/color.sh"
    FORECAST_FILE="${BATS_TEST_TMPDIR}/usage-forecast.tsv"
    source "${L}/forecast.sh"
    NOW=$(date +%s)
}

@test "5h at 52% after 2h20m runs out in 2h9m, before its reset: orange" {
    forecast_window five_hour 52 $((NOW + 9600))
    [ "${FC_SUFFIX}" = "⇥2h9m" ]
    [ "${FC_LEVEL}" = 3 ]
}

@test "5h running out within 30 minutes is red" {
    forecast_window five_hour 85 $((NOW + 3 * 3600))
    [ "${FC_LEVEL}" = 4 ]
}

@test "on pace: no suffix, no level" {
    forecast_window five_hour 40 $((NOW + 3000))
    [ -z "${FC_SUFFIX}" ]
    [ "${FC_LEVEL}" = 0 ]
}

@test "the first minutes of a window do not judge pace" {
    forecast_window five_hour 3 $((NOW + 18000 - 300))
    [ -z "${FC_SUFFIX}" ]
}

@test "a spent window is red with no suffix" {
    forecast_window seven_day 100 $((NOW + 86400))
    [ -z "${FC_SUFFIX}" ]
    [ "${FC_LEVEL}" = 4 ]
}

@test "the mod's forecast wins over the average when it names the same window" {
    printf 'five_hour\t%s\tidle\t\nseven_day\t%s\thits\t200000\n' $((NOW + 9600 + 2)) $((NOW + 578000)) >"${FORECAST_FILE}"
    forecast_window five_hour 52 $((NOW + 9600))
    [ -z "${FC_SUFFIX}" ]
    _FC_LOADED=1
    forecast_window seven_day 25 $((NOW + 578000))
    [ "${FC_SUFFIX}" = "⇥2d7h" ]
}

@test "a mod file for another window is ignored" {
    printf 'five_hour\t%s\tidle\t\n' $((NOW + 99999)) >"${FORECAST_FILE}"
    forecast_window five_hour 52 $((NOW + 9600))
    [ "${FC_SUFFIX}" = "⇥2h9m" ]
}

@test "levels follow 25 / 50 / 75 / 90" {
    for p in 0 24 25 49 50 74 75 89 90 100; do level_for_pct "$p"; out+="${REPLY}"; done
    [ "${out}" = "0011223344" ]
}
