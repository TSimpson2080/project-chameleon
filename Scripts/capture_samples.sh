#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: capture_samples.sh

Captures repeated macOS `sample` output from the running Chameleon Simulator process,
then extracts the com.apple.main-thread call-graph block and the "Sort by top of stack"
hotspots block for each sample.

Configuration via env vars:
  SAMPLES  (default: 3)
  DURATION (default: 5 seconds per sample)
EOF
}

SAMPLES="${SAMPLES:-3}"
DURATION="${DURATION:-5}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
if [[ $# -gt 0 ]]; then
  echo "Unexpected arguments: $*" >&2
  usage
  exit 2
fi

if ! [[ "$SAMPLES" =~ ^[0-9]+$ ]] || [[ "$SAMPLES" -le 0 ]]; then
  echo "Invalid SAMPLES value: $SAMPLES" >&2
  exit 2
fi
if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [[ "$DURATION" -le 0 ]]; then
  echo "Invalid DURATION value: $DURATION" >&2
  exit 2
fi

pid="$(
  ps aux | awk '/\/Chameleon\.app\/Chameleon/ && !/awk/ {print $2; exit}'
)"

if [[ -z "$pid" ]]; then
  echo "Could not find a running Chameleon Simulator process." >&2
  echo "Launch the app in the Simulator (Cmd+R), then re-run:" >&2
  echo "  cd ~/dev/project-chameleon/Chameleon && Scripts/capture_samples.sh" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

main_extractor="${script_dir}/extract_sample_main_thread.sh"
hot_extractor="${script_dir}/extract_sample_hotspots.sh"

if [[ ! -x "$main_extractor" ]]; then
  echo "Missing or not executable: $main_extractor" >&2
  exit 1
fi
if [[ ! -x "$hot_extractor" ]]; then
  echo "Missing or not executable: $hot_extractor" >&2
  exit 1
fi

ts="$(date +"%Y%m%d-%H%M%S")"
out_dir="${repo_root}/Scripts/output/${ts}"
mkdir -p "$out_dir"

created_files=()

run_extractor() {
  local extractor="$1"
  local sample_file="$2"
  local lines="$3"
  local output_file="$4"
  local label="$5"

  if ! "${extractor}" "${sample_file}" --lines "${lines}" >"${output_file}"; then
    echo "Extraction failed (${label}) for: ${sample_file}" >&2
    echo "Output file: ${output_file}" >&2
    exit 1
  fi
}

for i in $(seq 1 "$SAMPLES"); do
  sample_file="${out_dir}/chameleon-sample-${i}.txt"
  main_file="${out_dir}/main-thread-${i}.txt"
  hot_file="${out_dir}/hotspots-${i}.txt"

  echo "=== SAMPLE $i/$SAMPLES (PID=$pid) ==="
  echo "Capturing: sudo sample \"$pid\" $DURATION -file \"${sample_file}\""
  sudo sample "$pid" "$DURATION" -file "$sample_file" >/dev/null

  created_files+=("$sample_file" "$main_file" "$hot_file")

  run_extractor "$main_extractor" "$sample_file" 120 "$main_file" "main-thread"
  run_extractor "$hot_extractor" "$sample_file" 80 "$hot_file" "hotspots"

  echo "Wrote:"
  echo "  $sample_file"
  echo "  $main_file"
  echo "  $hot_file"
  echo
done

echo "Done. Output directory:"
echo "  $out_dir"
echo "Files:"
for f in "${created_files[@]}"; do
  echo "  $f"
done
