#!/usr/bin/env bash
set -euo pipefail

bundle_ids=("com.tsimpson.chameleon" "dev.tuist.Chameleon")

if ! xcrun simctl list devices booted | grep -q "Booted"; then
  echo "No booted simulator found." >&2
  exit 1
fi

pid=""
bundle=""
for b in "${bundle_ids[@]}"; do
  if app_path=$(xcrun simctl get_app_container booted "$b" app 2>/dev/null); then
    if pid_candidate=$(pgrep -f "$app_path" | head -n 1); then
      pid="$pid_candidate"
      bundle="$b"
      break
    fi
  fi
done

if [[ -z "$pid" ]]; then
  echo "Could not find simulator PID for bundle ids: ${bundle_ids[*]}" >&2
  exit 1
fi

ts=$(date +"%Y%m%d-%H%M%S")
out="/tmp/chameleon-sample-${ts}.txt"

echo "Sampling PID=${pid} bundle=${bundle}"
sample "$pid" 5 -file "$out" >/dev/null
echo "$out"

