#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: extract_sample_main_thread.sh <sample.txt> [--lines N]

Extracts the "main thread" (Thread 0 equivalent) from macOS `sample` output.
Supports both:
  A) per-thread format (Thread 0:, Dispatch Queue: com.apple.main-thread)
  B) call graph aggregation (Thread_#### DispatchQueue_#: com.apple.main-thread)
EOF
}

lines=200
file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lines)
      shift
      lines="${1:-}"
      shift || true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$file" ]]; then
        file="$1"
        shift
      else
        echo "Unexpected argument: $1" >&2
        usage
        exit 2
      fi
      ;;
  esac
done

if [[ -z "$file" ]]; then
  usage
  exit 2
fi

if [[ ! -f "$file" ]]; then
  echo "File not found: $file" >&2
  exit 2
fi

if ! [[ "$lines" =~ ^[0-9]+$ ]] || [[ "$lines" -le 0 ]]; then
  echo "Invalid --lines value: $lines" >&2
  exit 2
fi

# A) Per-thread format: Thread 0:
if grep -q '^Thread 0:' "$file"; then
  awk '
    BEGIN { printing=0 }
    /^Thread 0:/ { printing=1 }
    printing && NR > 1 && /^Thread [0-9]+:/ && $0 !~ /^Thread 0:/ { exit 0 }
    printing { print }
  ' "$file" | head -n "$lines"
  exit 0
fi

# B) Per-thread format: Dispatch Queue: com.apple.main-thread
# Find the nearest preceding thread header and print that thread's block.
dispatch_thread_start="$(
  awk '
    BEGIN { threadStart=0 }
    /^Thread [0-9]+:/ { threadStart=NR }
    /^[[:space:]]*Dispatch Queue:.*com[.]apple[.]main-thread/ { print threadStart; exit 0 }
  ' "$file" || true
)"

if [[ -n "$dispatch_thread_start" && "$dispatch_thread_start" != "0" ]]; then
  awk -v start="$dispatch_thread_start" '
    BEGIN { printing=0 }
    NR == start { printing=1 }
    printing && NR > start && /^Thread [0-9]+:/ { exit 0 }
    printing { print }
  ' "$file" | head -n "$lines"
  exit 0
fi

# C) Call graph aggregation format:
# Thread lines look like:
#   "    8667 Thread_5568201   DispatchQueue_1: com.apple.main-thread  (serial)"
# There may be no literal "Thread 0:" lines.
if grep -q 'com\.apple\.main-thread' "$file"; then
  awk '
    BEGIN { inCallGraph=0; found=0 }
    /^Call graph:/ { inCallGraph=1; next }
    inCallGraph && /^[[:space:]]*[0-9]+[[:space:]]+Thread_[0-9]+/ {
      if(found) { exit 0 }
      if($0 ~ /com[.]apple[.]main-thread/) { found=1; print; next }
      next
    }
    found { print }
    END { if(!found) exit 1 }
  ' "$file" | head -n "$lines"
  exit 0
fi

echo "Could not find a main-thread marker in: $file" >&2
echo "Expected one of:" >&2
echo "  - 'Thread 0:'" >&2
echo "  - 'Dispatch Queue: ... com.apple.main-thread'" >&2
echo "  - any line containing 'com.apple.main-thread' (call graph format)" >&2
exit 1
