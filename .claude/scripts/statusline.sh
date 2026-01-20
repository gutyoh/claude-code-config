#!/bin/bash
# Claude Code Statusline - Two-Tier (Full vs Compact)
# Wide:   opus-4.5 | session: 39% used | resets: 3h15m | in: 1.5k out: 563 | cache: 6.2M | $5.21 ($2.99/hr)
# Narrow: opus-4.5 | 39% | 3h15m | 1.5k/563/6.2M | $5.21

# Read Claude's JSON input
INPUT=$(cat)

# Get terminal width (default 120 if unavailable)
TERM_WIDTH=${COLUMNS:-$(tput cols 2>/dev/null || echo 120)}

# Parse model name and convert to lowercase short form
MODEL=$(echo "$INPUT" | jq -r '.model.display_name // "claude"' | sed 's/Claude //' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

# Get ccusage data for active block
CCDATA=$(ccusage blocks --json 2>/dev/null)

if [ -z "$CCDATA" ] || [ "$CCDATA" = "null" ]; then
    printf "%s | session: -- | resets: --" "$MODEL"
    exit 0
fi

# Parse active block data
ACTIVE_BLOCK=$(echo "$CCDATA" | jq '.blocks[] | select(.isActive == true)' 2>/dev/null)

if [ -z "$ACTIVE_BLOCK" ] || [ "$ACTIVE_BLOCK" = "null" ]; then
    printf "%s | session: -- | resets: --" "$MODEL"
    exit 0
fi

# Extract values
TOTAL_TOKENS=$(echo "$ACTIVE_BLOCK" | jq -r '.totalTokens // 0')
INPUT_TOKENS=$(echo "$ACTIVE_BLOCK" | jq -r '.tokenCounts.inputTokens // 0')
OUTPUT_TOKENS=$(echo "$ACTIVE_BLOCK" | jq -r '.tokenCounts.outputTokens // 0')
CACHE_READ=$(echo "$ACTIVE_BLOCK" | jq -r '.tokenCounts.cacheReadInputTokens // 0')
COST_USD=$(echo "$ACTIVE_BLOCK" | jq -r '.costUSD // 0')
BURN_RATE=$(echo "$ACTIVE_BLOCK" | jq -r '.burnRate.costPerHour // 0')
REMAINING_MIN=$(echo "$ACTIVE_BLOCK" | jq -r '.projection.remainingMinutes // 0')

# Calculate session percentage (based on ~17M token limit)
SESSION_LIMIT=17213778
SESSION_PCT=$((TOTAL_TOKENS * 100 / SESSION_LIMIT))

# Format time remaining
HOURS=$((REMAINING_MIN / 60))
MINS=$((REMAINING_MIN % 60))
TIME_LEFT="${HOURS}h${MINS}m"

# Format numbers with k/M suffixes
format_num() {
    local num=$1
    if [ "$num" -ge 1000000 ]; then
        printf "%.1fM" "$(echo "scale=1; $num / 1000000" | bc)"
    elif [ "$num" -ge 1000 ]; then
        printf "%.1fk" "$(echo "scale=1; $num / 1000" | bc)"
    else
        printf "%d" "$num"
    fi
}

IN_FMT=$(format_num "$INPUT_TOKENS")
OUT_FMT=$(format_num "$OUTPUT_TOKENS")
CACHE_FMT=$(format_num "$CACHE_READ")

# Format cost
COST_FMT=$(printf "%.2f" "$COST_USD")
BURN_FMT=$(printf "%.2f" "$BURN_RATE")

# Choose format based on terminal width
if [ "$TERM_WIDTH" -ge 110 ]; then
    # Wide terminal - full format
    printf "%s | session: %d%% used | resets: %s | in: %s out: %s | cache: %s | \$%s (\$%s/hr)" \
        "$MODEL" "$SESSION_PCT" "$TIME_LEFT" "$IN_FMT" "$OUT_FMT" "$CACHE_FMT" "$COST_FMT" "$BURN_FMT"
else
    # Narrow terminal - compact format
    printf "%s | %d%% | %s | %s/%s/%s | \$%s" \
        "$MODEL" "$SESSION_PCT" "$TIME_LEFT" "$IN_FMT" "$OUT_FMT" "$CACHE_FMT" "$COST_FMT"
fi
