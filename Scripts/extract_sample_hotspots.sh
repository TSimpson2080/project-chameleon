#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: extract_sample_hotspots.sh <sample.txt> [--lines N]

Extracts hotspots from macOS `sample` output.
Extracts the "Sort by top of stack" section.
EOF
}

lines=120
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

if grep -q '^Sort by top of stack' "$file"; then
  awk '
    BEGIN { printing=0; printed=0 }
    /^Sort by top of stack/ { printing=1 }
    printing {
      if($0 ~ /^[[:space:]]*$/) { exit 0 }
      print
      printed++
    }
  ' "$file" | head -n "$lines"
  exit 0
fi

echo "Could not find a hotspots section in: $file" >&2
echo "Expected one of:" >&2
echo "  - 'Sort by top of stack'" >&2
exit 1
