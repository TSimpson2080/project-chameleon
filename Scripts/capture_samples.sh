#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: capture_samples.sh [--count N] [--seconds S] [--lines-main N] [--lines-hot N]

Captures repeated macOS `sample` output from the running Chameleon Simulator process,
then extracts the com.apple.main-thread call-graph block and the "Sort by top of stack"
hotspots block for each sample.
EOF
}

count=3
seconds=5
lines_main=120
lines_hot=80

while [[ $# -gt 0 ]]; do
  case "$1" in
    --count)
      shift
      count="${1:-}"
      shift || true
      ;;
    --seconds)
      shift
      seconds="${1:-}"
      shift || true
      ;;
    --lines-main)
      shift
      lines_main="${1:-}"
      shift || true
      ;;
    --lines-hot)
      shift
      lines_hot="${1:-}"
      shift || true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unexpected argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

for v in "$count" "$seconds" "$lines_main" "$lines_hot"; do
  if ! [[ "$v" =~ ^[0-9]+$ ]]; then
    echo "Expected numeric arguments, got: $v" >&2
    exit 2
  fi
done

if [[ "$count" -le 0 || "$seconds" -le 0 ]]; then
  echo "--count and --seconds must be > 0" >&2
  exit 2
fi

pid="$(
  ps aux | awk '/\/Chameleon\.app\/Chameleon/ && !/awk/ {print $2; exit}'
)"

if [[ -z "$pid" ]]; then
  echo "Could not find a running Chameleon Simulator process." >&2
  echo "Launch the app in the Simulator, then re-run:" >&2
  echo "  Scripts/capture_samples.sh" >&2
  exit 1
fi

main_extractor="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/extract_sample_main_thread.sh"
hot_extractor="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/extract_sample_hotspots.sh"

if [[ ! -x "$main_extractor" ]]; then
  echo "Missing or not executable: $main_extractor" >&2
  exit 1
fi
if [[ ! -x "$hot_extractor" ]]; then
  echo "Missing or not executable: $hot_extractor" >&2
  exit 1
fi

for i in $(seq 1 "$count"); do
  out_file="chameleon-sample-$i.txt"
  echo "=== SAMPLE $i (PID=$pid) ==="
  echo "Capturing: sudo sample \"$pid\" $seconds -file \"$out_file\""
  sudo sample "$pid" "$seconds" -file "$out_file" >/dev/null
  echo
  echo "--- main thread (com.apple.main-thread) ---"
  if ! "$main_extractor" "$out_file" --lines "$lines_main"; then
    echo "(main thread extractor failed for $out_file)" >&2
  fi
  echo
  echo "--- hotspots (Sort by top of stack) ---"
  if ! "$hot_extractor" "$out_file" --lines "$lines_hot"; then
    echo "(hotspots extractor failed for $out_file)" >&2
  fi
  echo
done

