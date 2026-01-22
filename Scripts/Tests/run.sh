#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

main_extractor="$root/Scripts/extract_sample_main_thread.sh"
hotspots_extractor="$root/Scripts/extract_sample_hotspots.sh"
analyzer="$root/Scripts/analyze_triage_run.sh"

fixture="$root/Scripts/fixtures/sample_callgraph.txt"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$main_extractor" ]] || fail "Missing or not executable: $main_extractor"
[[ -x "$hotspots_extractor" ]] || fail "Missing or not executable: $hotspots_extractor"
[[ -x "$analyzer" ]] || fail "Missing or not executable: $analyzer"
[[ -f "$fixture" ]] || fail "Missing fixture: $fixture"

out="$("$main_extractor" "$fixture" --lines 200)" || fail "main extractor failed for fixture"
[[ -n "$out" ]] || fail "main output is empty"
echo "$out" | grep -q 'com\.apple\.main-thread' || fail "main output missing com.apple.main-thread"

out="$("$hotspots_extractor" "$fixture" --lines 200)" || fail "hotspots extractor failed for fixture"
[[ -n "$out" ]] || fail "hotspots output is empty"
echo "$out" | grep -q '^Sort by top of stack' || fail "hotspots output missing 'Sort by top of stack'"

tmp_dir="$(mktemp -d "/tmp/chameleon-triage-test.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

"$main_extractor" "$fixture" --lines 200 >"$tmp_dir/main-thread-1.txt" || fail "failed to generate main-thread-1.txt"
"$hotspots_extractor" "$fixture" --lines 200 >"$tmp_dir/hotspots-1.txt" || fail "failed to generate hotspots-1.txt"

"$analyzer" "$tmp_dir" >/dev/null 2>&1 || fail "analyzer failed"
[[ -f "$tmp_dir/report.md" ]] || fail "report.md not created"
grep -q "## Classification" "$tmp_dir/report.md" || fail "report.md missing Classification section"
grep -Eq 'MAIN_THREAD_IDLE|MAIN_THREAD_BUSY|HOT_BACKGROUND_CPU|INSUFFICIENT_DATA' "$tmp_dir/report.md" || fail "report.md missing classification label"
grep -q 'com\.apple\.main-thread' "$tmp_dir/report.md" || fail "report.md missing com.apple.main-thread marker"

echo "OK"
