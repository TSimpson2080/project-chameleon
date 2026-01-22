#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

main_extractor="$root/Scripts/extract_sample_main_thread.sh"
hotspots_extractor="$root/Scripts/extract_sample_hotspots.sh"

fixture="$root/Scripts/fixtures/sample_callgraph.txt"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$main_extractor" ]] || fail "Missing or not executable: $main_extractor"
[[ -x "$hotspots_extractor" ]] || fail "Missing or not executable: $hotspots_extractor"
[[ -f "$fixture" ]] || fail "Missing fixture: $fixture"

out="$("$main_extractor" "$fixture" --lines 200)" || fail "main extractor failed for fixture"
[[ -n "$out" ]] || fail "main output is empty"
echo "$out" | grep -q 'com\.apple\.main-thread' || fail "main output missing com.apple.main-thread"

out="$("$hotspots_extractor" "$fixture" --lines 200)" || fail "hotspots extractor failed for fixture"
[[ -n "$out" ]] || fail "hotspots output is empty"
echo "$out" | grep -q '^Sort by top of stack' || fail "hotspots output missing 'Sort by top of stack'"

echo "OK"
