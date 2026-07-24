#!/bin/bash
# <xbar.title>Amp Free Credit Monitor</xbar.title>
# <xbar.version>v2.0</xbar.version>
# <xbar.author>xshoji</xbar.author>
# <xbar.desc>Display Amp Free credit remaining in the menu bar</xbar.desc>
#
# SwiftBar plugin: Always display Amp Free credit remaining in the menu bar.
#
# Data source:
#   - /tmp/amp-credit-menubar.txt (JSON output written by this script from `amp usage`)
#   - Runs `amp usage` only when the Amp process is active
#   - Shows cached data when Amp is not running (balance doesn't decrease while idle)
#
# The "10s" in the filename sets the SwiftBar refresh interval (every 10 seconds).

# Default icon (16x16 PNG, base64) using an orange palette with a readable dot-style `amp` label.
DEFAULT_AMP_ICON="iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAA+ElEQVR4nKWTsWoCQRCGvxMJRC5a2FvoQcRKLuADhHBPIHmCPFaeIPgA4QgpBQ2mCaYIxMI2RYh39UwKnWVNRFf8m5ndmf/nn2EXTkRkSXmb6THE+CGPnMBqeKMAF1kWRC7yHID66CmqAogI08WSgTwGCUwXSwbtFgBrAV27txgC662YA4D+2w8igoi43I+W+5wKgKpyV9aZ9WLSeYFu1NN5gdUBV/fvthxcvZdb6s6uV3/p1v47sHkml+ccOv/dV9VXC407d3Afr1BVxsnZ3miz6z4HIbDek9+Bc5A0G3x8fQeRk2bDOXCf6fM6PeozdZ5fo8NdAfgFWA3GVky3FzwAAAAASUVORK5CYII="

if [[ -n "${AMP_ICON_BASE64:-}" ]]; then
  AMP_ICON="${AMP_ICON_BASE64#data:image/*;base64,}"
else
  AMP_ICON="$DEFAULT_AMP_ICON"
fi

AMP_LOOKUP_PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
MENUBAR_FILE="${AMP_CREDIT_FILE:-/tmp/amp-credit-menubar.txt}"
CRITICAL_BALANCE_THRESHOLD="10"
LOW_BALANCE_THRESHOLD="30"

remaining=""
limit="0"
individual_credits="0"
show_limit="false"
amp_running="false"

current_utc_timestamp() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# --- Check if the Amp process is running ---
# Using `ps` instead of `pgrep -x amp` due to detection issues on macOS
# shellcheck disable=SC2009
is_amp_running() {
  ps -eo comm= 2>/dev/null | grep -qx "amp"
}

resolve_amp_bin() {
  PATH="$AMP_LOOKUP_PATH" command -v amp 2>/dev/null
}

parse_usage_output() {
  local output="$1"

  parsed_remaining=$(printf '%s\n' "$output" | sed -n 's/.*Amp Free: \([0-9.]*\)%.*/\1/p' | head -n 1)
  parsed_individual_credits=$(printf '%s\n' "$output" | sed -n 's/.*Individual credits: \$\([0-9.]*\) remaining.*/\1/p' | head -n 1)

  [[ -n "$parsed_remaining" ]]
}

write_cache_file() {
  local cache_remaining="$1"
  local cache_limit="${2:-0}"
  local cache_individual_credits="${3:-0}"

  printf '{"remaining":%s,"limit":%s,"individualCredits":%s,"showLimit":false,"updatedAt":"%s"}\n' \
    "$cache_remaining" "$cache_limit" "$cache_individual_credits" "$(current_utc_timestamp)" > "$MENUBAR_FILE" || return 1

  return 0
}

read_cache_updated_at() {
  local updated_at

  if [[ ! -f "$MENUBAR_FILE" ]]; then
    return 1
  fi

  updated_at=$(grep -o '"updatedAt":"[^"]*' "$MENUBAR_FILE" | cut -d'"' -f4)

  [[ -n "$updated_at" ]] || return 1
  printf '%s\n' "$updated_at"
}

# --- Run `amp usage` and write results to the cache file ---
update_from_amp() {
  local amp_bin output

  amp_bin=$(resolve_amp_bin)
  if [[ -z "$amp_bin" ]]; then
    return 1
  fi

  output=$(env -i \
    HOME="$HOME" \
    PATH="$AMP_LOOKUP_PATH" \
    USER="$USER" \
    TERM="${TERM:-xterm-256color}" \
    LANG="${LANG:-en_US.UTF-8}" \
    TMPDIR="${TMPDIR:-/tmp}" \
    SHELL="${SHELL:-/bin/bash}" \
    "$amp_bin" usage 2>&1)

  if ! parse_usage_output "$output"; then
    return 1
  fi

  remaining="$parsed_remaining"
  limit="${parsed_limit:-0}"
  individual_credits="${parsed_individual_credits:-0}"
  show_limit="false"

  write_cache_file "$remaining" "$limit" "$individual_credits" >/dev/null 2>&1 || true

  return 0
}

# --- Detect SwiftBar restart ---
# If SwiftBar was started after the cache file was last written, treat it as a fresh restart
# and force a refresh so the menu bar shows live data instead of a stale cache.
swiftbar_just_restarted() {
  local swiftbar_pid swiftbar_start_str swiftbar_start_epoch updated_at updated_epoch

  # Use `ps` instead of `pgrep` — pgrep may not be available in SwiftBar's plugin environment.
  # comm shows the full path (e.g. /Applications/SwiftBar.app/Contents/MacOS/SwiftBar).
  swiftbar_pid=$(ps -eo pid=,comm= 2>/dev/null | grep "/SwiftBar$" | head -n 1 | awk '{print $1}')
  if [[ -z "$swiftbar_pid" ]]; then
    return 1
  fi

  swiftbar_start_str=$(ps -p "$swiftbar_pid" -o lstart= 2>/dev/null | xargs)
  if [[ -z "$swiftbar_start_str" ]]; then
    return 1
  fi

  swiftbar_start_epoch=$(date -j -f "%a %b %d %H:%M:%S %Y" "$swiftbar_start_str" +%s 2>/dev/null)
  if [[ -z "$swiftbar_start_epoch" ]]; then
    return 1
  fi

  updated_at=$(read_cache_updated_at)
  if [[ -z "$updated_at" || "$updated_at" == "null" ]]; then
    return 1
  fi

  updated_epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$updated_at" +%s 2>/dev/null)
  if [[ -z "$updated_epoch" ]]; then
    return 1
  fi

  (( swiftbar_start_epoch > updated_epoch ))
}

# --- Detect sleep/wake recovery ---
# Get the last wake time via `sysctl kern.waketime`; if within 60 seconds, treat as just woken up
just_woke_up() {
  local last_wake_epoch now_epoch

  last_wake_epoch=$(sysctl -n kern.waketime 2>/dev/null | awk -F'[ ,}]+' '/sec =/{print $4; exit}')
  if [[ -z "$last_wake_epoch" || "$last_wake_epoch" == "0" ]]; then
    return 1
  fi

  now_epoch=$(date +%s)
  (( now_epoch - last_wake_epoch <= 60 ))
}

# --- Force refresh if cache predates the latest UTC midnight daily reset ---
# Amp Free credits reset daily at UTC 00:00; if the cache is from before that, refresh
cache_missed_latest_daily_refresh() {
  local updated_at updated_epoch today_utc_midnight_epoch

  updated_at=$(read_cache_updated_at)
  if [[ -z "$updated_at" || "$updated_at" == "null" ]]; then
    return 1
  fi

  # Parse cached UTC timestamp
  updated_epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$updated_at" +%s 2>/dev/null)
  if [[ -z "$updated_epoch" ]]; then
    return 1
  fi

  # Most recent UTC midnight (00:00:00 UTC today)
  today_utc_midnight_epoch=$(date -u +%s)
  today_utc_midnight_epoch=$(( today_utc_midnight_epoch - (today_utc_midnight_epoch % 86400) ))

  (( updated_epoch < today_utc_midnight_epoch ))
}

refresh_cached_data_if_needed() {
  if [[ ! -f "$MENUBAR_FILE" ]]; then
    update_from_amp
    return
  fi

  if swiftbar_just_restarted || just_woke_up || cache_missed_latest_daily_refresh; then
    update_from_amp
  fi
}

# --- Read from cache file ---
read_cache_file() {
  if [[ ! -f "$MENUBAR_FILE" ]]; then
    return 1
  fi

  remaining=$(grep -o '"remaining":[0-9.]*' "$MENUBAR_FILE" | cut -d: -f2)
  limit=$(grep -o '"limit":[0-9.]*' "$MENUBAR_FILE" | cut -d: -f2)
  individual_credits=$(grep -o '"individualCredits":[0-9.]*' "$MENUBAR_FILE" | cut -d: -f2)
  if grep -q '"showLimit":true' "$MENUBAR_FILE"; then
    show_limit="1"
  else
    show_limit="0"
  fi

  [[ -n "$limit" && "$limit" != "null" ]] || limit="0"
  [[ -n "$individual_credits" && "$individual_credits" != "null" ]] || individual_credits="0"
  [[ -n "$show_limit" && "$show_limit" != "null" ]] || show_limit="false"

  [[ -n "$remaining" && "$remaining" != "null" ]]
}

compare_decimal_lte() {
  local left="$1"
  local right="$2"

  (( $(echo "$left <= $right" | bc -l 2>/dev/null || echo 0) ))
}

color_for_remaining() {
  local current_remaining="$1"

  if compare_decimal_lte "$current_remaining" "$CRITICAL_BALANCE_THRESHOLD"; then
    printf '%s\n' "red"
  elif compare_decimal_lte "$current_remaining" "$LOW_BALANCE_THRESHOLD"; then
    printf '%s\n' "orange"
  fi
}

print_empty_state() {
  echo "-- | image=${AMP_ICON}"
  echo "---"
  echo "Amp not running / No data"
}

print_menu() {
  local remaining_fmt color display_text status_text

  remaining_fmt="$remaining"
  color=$(color_for_remaining "$remaining")

  # Convert remaining percentage to dollar value (100% = $5)
  local dollar_value
  dollar_value=$(echo "scale=2; ${remaining_fmt} * 5 / 100" | bc -l 2>/dev/null | sed 's/^\./0./')
  display_text="Free ${remaining_fmt}% (\$${dollar_value})"

  if [[ -n "$color" ]]; then
    echo "${display_text} | image=${AMP_ICON} color=${color}"
  else
    echo "${display_text} | image=${AMP_ICON}"
  fi

  echo "---"
  echo "Amp Free Credit | size=14"
  echo "Remaining: ${remaining_fmt}% (\$${dollar_value})"
  if [[ -n "$individual_credits" && "$individual_credits" != "0" ]]; then
    echo "Individual Credits: \$${individual_credits}"
  fi
  echo "---"

  if [[ "$amp_running" == "true" ]]; then
    status_text="✅ Amp is running"
  else
    status_text="⏸ Amp not running (cached)"
  fi

  echo "$status_text"
  echo "Refresh | refresh=true"
  echo "Open Amp Dashboard | href=https://ampcode.com/settings"
}

load_credit_data() {
  if is_amp_running; then
    amp_running="true"
    update_from_amp || read_cache_file
  else
    amp_running="false"
    refresh_cached_data_if_needed
    read_cache_file
  fi
}

# --- Main ---
# 1. If the Amp process is running, run `amp usage` and update the cache
# 2. If not running, show cached data (balance doesn't decrease while idle)
# 3. Force refresh on SwiftBar restart, sleep/wake recovery (within 60s), or if cache predates the latest UTC midnight daily reset
# 4. If no cache file exists, display "--"
main() {
  load_credit_data

  if [[ -z "$remaining" || "$remaining" == "null" ]]; then
    print_empty_state
    exit 0
  fi

  print_menu
}

main
