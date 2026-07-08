#!/bin/bash
# Claude Code Status Line — Session & Token Usage Display
# Receives JSON session data via stdin, outputs single-line formatted status bar

input=$(cat)

# Options (set via environment variables)
SHOW_COST="${CLAUDE_STATUS_SHOW_COST:-0}"

# Parse fields with safe defaults
MODEL=$(echo "$input" | jq -r '.model.display_name // "—"')
SESSION_ID=$(echo "$input" | jq -r '.session_id // ""' | cut -c1-8)

# Project name (folder) and git branch
CWD=$(echo "$input" | jq -r '.cwd // ""')
PROJECT=$(basename "$CWD" 2>/dev/null || echo "—")
BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
[ -z "$BRANCH" ] && BRANCH=$(git -C "$CWD" rev-parse --short HEAD 2>/dev/null || echo "—")

# Cost & duration
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
LINES_ADDED=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
LINES_REMOVED=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')

# Context window
CTX_PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
TOTAL_IN=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
TOTAL_OUT=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')

# Rate limits
RATE_5H=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
RATE_5H_RESETS=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
RATE_7D=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
RATE_7D_RESETS=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null)

# Format reset time as relative countdown
format_reset() {
    local resets_at=$1
    [ -z "$resets_at" ] || [ "$resets_at" = "null" ] && return
    local now=$(date +%s)
    local diff=$(( resets_at - now ))
    [ "$diff" -le 0 ] && { echo "now"; return; }
    local days=$(( diff / 86400 ))
    local hours=$(( (diff % 86400) / 3600 ))
    local mins=$(( (diff % 3600) / 60 ))
    if [ "$days" -gt 0 ]; then
        echo "${days}d${hours}h"
    elif [ "$hours" -gt 0 ]; then
        echo "${hours}h${mins}m"
    else
        echo "${mins}m"
    fi
}

# Colors
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
MAGENTA='\033[35m'
BLUE='\033[34m'

# Separator
SEP="${DIM} │ ${RESET}"

# Color based on context usage
if [ "$CTX_PCT" -ge 90 ] 2>/dev/null; then
    CTX_COLOR="$RED"
elif [ "$CTX_PCT" -ge 70 ] 2>/dev/null; then
    CTX_COLOR="$YELLOW"
else
    CTX_COLOR="$GREEN"
fi

# Build context progress bar (15 chars wide)
BAR_WIDTH=15
FILLED=$(( (CTX_PCT * BAR_WIDTH) / 100 ))
EMPTY=$(( BAR_WIDTH - FILLED ))
BAR=""
for ((i=0; i<FILLED; i++)); do BAR+="█"; done
for ((i=0; i<EMPTY; i++)); do BAR+="░"; done

# Format duration
MINS=$((DURATION_MS / 60000))
SECS=$(( (DURATION_MS % 60000) / 1000 ))
if [ "$MINS" -gt 0 ] 2>/dev/null; then
    DURATION_FMT="${MINS}m${SECS}s"
else
    DURATION_FMT="${SECS}s"
fi

# Format cost
COST_FMT=$(printf '$%.4f' "$COST")

# Format token counts (compact)
format_tokens() {
    local n=$1
    if [ "$n" -ge 1000000 ] 2>/dev/null; then
        printf "%.1fM" "$(echo "scale=1; $n / 1000000" | bc)"
    elif [ "$n" -ge 1000 ] 2>/dev/null; then
        printf "%.1fk" "$(echo "scale=1; $n / 1000" | bc)"
    else
        echo "$n"
    fi
}

IN_FMT=$(format_tokens "$TOTAL_IN")
OUT_FMT=$(format_tokens "$TOTAL_OUT")

# Rate limit colors
rate_color() {
    local pct=$(echo "$1" | cut -d. -f1)
    if [ "$pct" -ge 80 ] 2>/dev/null; then echo "$RED"
    elif [ "$pct" -ge 50 ] 2>/dev/null; then echo "$YELLOW"
    else echo "$GREEN"; fi
}

# 2x promotion: March 13–28, 2026
# Off-peak = weekends OR weekday outside 8 AM–2 PM ET
PROMO_LABEL=""
NOW_EPOCH=$(date +%s)
# Promotion window (UTC): Mar 13 00:00 ET = Mar 13 05:00 UTC, Mar 29 00:00 ET = Mar 29 04:00 UTC (EDT)
PROMO_START=1773374400  # 2026-03-13 00:00:00 ET (04:00 UTC, EDT)
PROMO_END=1774756800    # 2026-03-29 00:00:00 ET (04:00 UTC, EDT)
if [ "$NOW_EPOCH" -ge "$PROMO_START" ] && [ "$NOW_EPOCH" -lt "$PROMO_END" ]; then
    # Get current day-of-week and hour in ET (America/New_York)
    DOW=$(TZ="America/New_York" date +%u)  # 1=Mon..7=Sun
    HOUR_ET=$(TZ="America/New_York" date +%-H)
    if [ "$DOW" -ge 6 ]; then
        # Weekend — always off-peak
        PROMO_LABEL="${GREEN}⚡2x${RESET}"
    elif [ "$HOUR_ET" -ge 8 ] && [ "$HOUR_ET" -lt 14 ]; then
        # Weekday peak: 8 AM – 2 PM ET
        PROMO_LABEL="${DIM}1x${RESET}"
    else
        # Weekday off-peak
        PROMO_LABEL="${GREEN}⚡2x${RESET}"
    fi
fi

# Build single line
LINE=""

# Project & branch
LINE+="${BOLD}${CYAN}${PROJECT}${RESET}"
LINE+=" ${MAGENTA}${BRANCH}${RESET}"

LINE+="${SEP}"

# Model & session
LINE+="${BOLD}${MODEL}${RESET}"
LINE+=" ${DIM}${SESSION_ID}${RESET}"

# 2x promo indicator (only during promotion)
if [ -n "$PROMO_LABEL" ]; then
    LINE+="${SEP}${PROMO_LABEL}"
fi

LINE+="${SEP}"

# Context bar
LINE+="${CTX_COLOR}${BAR}${RESET} ${CTX_COLOR}${CTX_PCT}%${RESET}"

LINE+="${SEP}"

# Tokens
LINE+="${MAGENTA}↑${OUT_FMT}${RESET} ${BLUE}↓${IN_FMT}${RESET}"

LINE+="${SEP}"

# Cost (optional) & duration
if [ "$SHOW_COST" = "1" ]; then
    LINE+="${GREEN}${COST_FMT}${RESET} "
fi
LINE+="${DIM}${DURATION_FMT}${RESET}"

# Rate limits with reset countdowns
if [ -n "$RATE_5H" ] && [ "$RATE_5H" != "null" ]; then
    RATE_5H_INT=$(echo "$RATE_5H" | cut -d. -f1)
    RC=$(rate_color "$RATE_5H")
    RESET_5H=$(format_reset "$RATE_5H_RESETS")
    LINE+="${SEP}${DIM}5h:${RESET}${RC}${RATE_5H_INT}%${RESET}"
    [ -n "$RESET_5H" ] && LINE+="${DIM}(${RESET_5H})${RESET}"
fi
if [ -n "$RATE_7D" ] && [ "$RATE_7D" != "null" ]; then
    RATE_7D_INT=$(echo "$RATE_7D" | cut -d. -f1)
    RC=$(rate_color "$RATE_7D")
    RESET_7D=$(format_reset "$RATE_7D_RESETS")
    LINE+=" ${DIM}7d:${RESET}${RC}${RATE_7D_INT}%${RESET}"
    [ -n "$RESET_7D" ] && LINE+="${DIM}(${RESET_7D})${RESET}"
fi

# Lines changed
if [ "$LINES_ADDED" -gt 0 ] 2>/dev/null || [ "$LINES_REMOVED" -gt 0 ] 2>/dev/null; then
    LINE+="${SEP}${GREEN}+${LINES_ADDED}${RESET}${RED}-${LINES_REMOVED}${RESET}"
fi

echo -e "$LINE"
