#!/usr/bin/env bash
# Outside-in probe for Go Green Verify and DocGen AI.
#
# Usage: probe.sh <targets-file> <state-file>
# Alerts through Telegram when TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID are set.
#
# Two-strike rule: a target must fail in TWO consecutive runs before anyone is
# told, and each run already retries a failing target once after 15 s. One
# dropped packet from a GitHub runner is not an outage. The run that first
# reaches two strikes alerts; later failing runs stay quiet; the first passing
# run after an alert sends a recovery message. Strike counts live in the state
# file, which the workflow carries between runs through the Actions cache.
set -uo pipefail

targets_file=${1:?targets file}
state_file=${2:?state file}
touch "$state_file"

declare -A strikes
while IFS='=' read -r k v; do
  [ -n "$k" ] && strikes["$k"]=$v
done < "$state_file"

send() {
  if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
    echo "::warning::Telegram is not configured; alert not sent: $1"
    return 0
  fi
  # The token goes in the URL Telegram defines; curl never echoes it, and
  # Actions masks secrets in logs.
  if ! curl -s -m 20 -o /dev/null -w '%{http_code}' \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
      --data-urlencode "text=$1" | grep -q '^200$'; then
    echo "::warning::Telegram send failed"
  fi
}

check() { # url want needle -> prints the observed status; returns 0 on pass
  local url=$1 want=$2 needle=$3 body code
  body=$(mktemp)
  code=$(curl -s -o "$body" -m 20 -w '%{http_code}' "$url" || true)
  if [ "$code" = "$want" ] && { [ "$needle" = "-" ] || grep -qF -- "$needle" "$body"; }; then
    rm -f "$body"; echo "$code"; return 0
  fi
  if [ "$code" = "$want" ]; then code="$code (body check failed)"; fi
  rm -f "$body"; echo "$code"; return 1
}

alert_at=${STRIKES_TO_ALERT:-2}
failed=0
run_url="${GITHUB_SERVER_URL:-}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"
while IFS='|' read -r name url want needle; do
  case "$name" in ''|'#'*) continue ;; esac
  key=$(printf '%s' "$name" | tr -c 'A-Za-z0-9' '_')
  if got=$(check "$url" "$want" "$needle"); then
    ok=1
  else
    sleep 15
    if got=$(check "$url" "$want" "$needle"); then ok=1; else ok=0; fi
  fi

  prev=${strikes[$key]:-0}
  if [ "$ok" = 1 ]; then
    echo "OK    $name  $got  $url"
    if [ "$prev" -ge "$alert_at" ]; then
      send "RECOVERED: $name is answering again ($url -> $got)."
    fi
    strikes[$key]=0
  else
    failed=1
    now=$((prev + 1))
    strikes[$key]=$now
    echo "::error title=$name down (strike $now)::$url answered $got, expected $want"
    if [ "$now" -eq "$alert_at" ]; then
      send "DOWN: $name failed $now consecutive check(s). $url answered $got, expected $want. $run_url"
    fi
  fi
done < "$targets_file"

: > "$state_file"
for k in "${!strikes[@]}"; do echo "$k=${strikes[$k]}" >> "$state_file"; done
exit $failed
