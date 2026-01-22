#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
Usage: analyze_triage_run.sh [path/to/Scripts/output/<YYYYMMDD-HHMMSS>]

If no folder is provided, uses the newest folder under Scripts/output/.
Writes a Markdown report to <folder>/report.md.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

target_dir="${1:-}"
if [[ -z "$target_dir" ]]; then
  newest="$(
    ls -1dt "${repo_root}/Scripts/output/"*/ 2>/dev/null | head -n 1 || true
  )"
  [[ -n "$newest" ]] || die "No triage output folders found under Scripts/output/ (run Scripts/capture_samples.sh first)."
  target_dir="${newest%/}"
else
  case "$target_dir" in
    /*) : ;;
    *) target_dir="${repo_root}/${target_dir}" ;;
  esac
fi

[[ -d "$target_dir" ]] || die "Folder not found: $target_dir"

shopt -s nullglob
main_files=( "${target_dir}/main-thread-"*.txt )
hot_files=( "${target_dir}/hotspots-"*.txt )
shopt -u nullglob

[[ ${#main_files[@]} -gt 0 ]] || die "No main-thread-*.txt files found in: $target_dir"
[[ ${#hot_files[@]} -gt 0 ]] || die "No hotspots-*.txt files found in: $target_dir"

report_file="${target_dir}/report.md"

extract_nonempty_last_line() {
  local file="$1"
  awk 'NF { line=$0 } END { print line }' "$file"
}

extract_hotspots_top3() {
  local file="$1"
  awk '
    NR==1 { next }
    NF {
      print
      c++
      if(c==3) exit 0
    }
  ' "$file"
}

extract_hotspots_top3_joined() {
  local file="$1"
  awk '
    NR==1 { next }
    NF {
      if(c > 0) printf "<br>"
      printf "%s", $0
      c++
      if(c==3) exit 0
    }
    END { printf "\n" }
  ' "$file"
}

parse_hotspot_top() {
  local file="$1"
  # Returns: "<func> <count>" or empty.
  awk '
    NR==1 { next }
    NF {
      fn=$1
      count=$NF
      if(count ~ /^[0-9]+$/) { print fn " " count } else { print fn " " 0 }
      exit 0
    }
  ' "$file"
}

escape_md_cell() {
  # Escape pipe characters to keep markdown tables intact.
  sed 's/|/\\|/g'
}

rows=""
idle_samples=0
busy_samples=0
hot_bg_samples=0
total_samples=0
insufficient=0
rule_notes=()

for main_path in "${main_files[@]}"; do
  base="$(basename "$main_path")"
  idx="${base#main-thread-}"
  idx="${idx%.txt}"

  hot_path="${target_dir}/hotspots-${idx}.txt"
  if [[ ! -f "$hot_path" ]]; then
    insufficient=1
    rule_notes+=("Missing hotspots file for sample ${idx}: $(basename "$hot_path")")
    continue
  fi

  [[ -s "$main_path" ]] || die "Empty file: $main_path"
  [[ -s "$hot_path" ]] || die "Empty file: $hot_path"

  leaf="$(extract_nonempty_last_line "$main_path")"
  [[ -n "$leaf" ]] || die "Could not extract a main-thread leaf line from: $main_path"

  hot3_joined="$(extract_hotspots_top3_joined "$hot_path")"
  [[ -n "$hot3_joined" ]] || die "Could not extract hotspots entries from: $hot_path"

  leaf_escaped="$(printf "%s" "$leaf" | escape_md_cell)"
  hot_escaped="$(printf "%s" "$hot3_joined" | escape_md_cell)"

  rows+=$"| ${idx} | ${leaf_escaped} | ${hot_escaped} |\n"

  total_samples=$((total_samples + 1))

  if echo "$leaf" | grep -Eq '(mach_msg2_trap|mach_msg_overwrite|__CFRunLoop|_CFRunLoop|GSEventRunModal)'; then
    idle_samples=$((idle_samples + 1))
  else
    busy_samples=$((busy_samples + 1))
  fi

  read -r top_func top_count < <(parse_hotspot_top "$hot_path")
  if [[ "$top_func" == "start_wqthread" && "$top_count" -gt 0 ]]; then
    read -r second_count < <(awk 'NR==1{next} NF{c++; if(c==2){print $NF; exit}}' "$hot_path")
    if ! [[ "${second_count:-0}" =~ ^[0-9]+$ ]]; then second_count=0; fi
    if [[ "$second_count" -gt 0 && "$top_count" -ge $((second_count * 2)) ]]; then
      hot_bg_samples=$((hot_bg_samples + 1))
    fi
  fi
done

[[ "$total_samples" -gt 0 ]] || die "No complete (main-thread + hotspots) sample pairs found in: $target_dir"

classification="INSUFFICIENT_DATA"
matched_rule="D"

if [[ "$insufficient" -eq 1 ]]; then
  classification="INSUFFICIENT_DATA"
  matched_rule="D (missing files/markers)"
elif [[ "$hot_bg_samples" -ge $(((total_samples + 1) / 2)) ]]; then
  classification="HOT_BACKGROUND_CPU"
  matched_rule="C (start_wqthread dominates hotspots by >=2x)"
elif [[ "$idle_samples" -ge $(((total_samples + 1) / 2)) ]]; then
  classification="MAIN_THREAD_IDLE"
  matched_rule="A (main thread leaf looks like runloop idle)"
else
  classification="MAIN_THREAD_BUSY"
  matched_rule="B (main thread leaf is not a runloop idle frame)"
fi

folder_name="$(basename "$target_dir")"
generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

{
  echo "# Blank Screen Triage Report"
  echo
  echo "- Folder: \`$target_dir\`"
  echo "- Folder name: \`$folder_name\`"
  echo "- Generated at (UTC): \`$generated_at\`"
  echo "- Marker searched: \`com.apple.main-thread\`"
  echo
  echo "## Samples"
  echo
  echo "| Sample | Main thread leaf (last line) | Hotspots (top 3) |"
  echo "|---:|---|---|"
  printf "%b" "$rows"
  echo
  echo "## Classification"
  echo
  echo "**Result:** \`$classification\`"
  echo
  echo "### Heuristics"
  echo
  echo "- A) MAIN_THREAD_IDLE: leaf contains one of: \`mach_msg2_trap\`, \`__CFRunLoop\`, \`_CFRunLoop\`, \`GSEventRunModal\`"
  echo "- B) MAIN_THREAD_BUSY: leaf does not match the idle pattern"
  echo "- C) HOT_BACKGROUND_CPU: hotspots top function is \`start_wqthread\` and its count is >= 2x the second hotspot (majority of samples)"
  echo "- D) INSUFFICIENT_DATA: missing sample files / markers"
  echo
  echo "### Matched rule"
  echo
  echo "- Matched: $matched_rule"
  echo "- Totals: samples=$total_samples idle=$idle_samples busy=$busy_samples hot_bg=$hot_bg_samples"
  if [[ ${#rule_notes[@]} -gt 0 ]]; then
    echo
    echo "### Notes"
    for n in "${rule_notes[@]}"; do
      echo "- $n"
    done
  fi
} >"$report_file"

echo "Wrote: $report_file"
