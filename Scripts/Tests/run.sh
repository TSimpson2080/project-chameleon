#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

main_extractor="$root/Scripts/extract_sample_main_thread.sh"
hotspots_extractor="$root/Scripts/extract_sample_hotspots.sh"

fixture_dir="$root/Scripts/Tests/Fixtures"
per_thread="$fixture_dir/per-thread-sample.txt"
call_graph="$fixture_dir/call-graph-sample.txt"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$main_extractor" ]] || fail "Missing or not executable: $main_extractor"
[[ -x "$hotspots_extractor" ]] || fail "Missing or not executable: $hotspots_extractor"

out="$("$main_extractor" "$per_thread" --lines 200)" || fail "main extractor failed for per-thread fixture"
echo "$out" | grep -q '^Thread 0:' || fail "per-thread main output missing 'Thread 0:'"
echo "$out" | grep -q 'com\.apple\.main-thread' || fail "per-thread main output missing com.apple.main-thread"

out="$("$main_extractor" "$call_graph" --lines 200)" || fail "main extractor failed for call-graph fixture"
echo "$out" | grep -q 'com\.apple\.main-thread' || fail "call-graph main output missing com.apple.main-thread"
echo "$out" | grep -q 'Thread_' || fail "call-graph main output missing Thread_ header"

out="$("$hotspots_extractor" "$per_thread" --lines 200)" || fail "hotspots extractor failed for per-thread fixture"
echo "$out" | grep -q '^Sort by top of stack' || fail "hotspots output missing 'Sort by top of stack'"

out="$("$hotspots_extractor" "$call_graph" --lines 200)" || fail "hotspots extractor failed for call-graph fixture"
echo "$out" | grep -q '^Sort by top of stack' || fail "call-graph hotspots output expected 'Sort by top of stack'"

echo "OK"

