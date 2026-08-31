#!/usr/bin/env bash
#
# Generate TIMELINE.md from git history across all five app-hub repositories.
#
# Git already timestamps every commit, so this derives the project timeline
# rather than asking anyone to maintain one by hand. Hand-typed dates drift;
# commit timestamps cannot.
#
# Usage (from the project root, either shell):
#   ./scripts/timeline.sh          # write TIMELINE.md
#   ./scripts/timeline.sh --stdout # print instead of writing
#
# Timestamps are rendered in IST (+05:30) because that is the wall clock the
# work happens on. Note the machine has two clocks -- Windows is IST, WSL is
# UTC -- so bare times are ambiguous here. Git stores an absolute instant plus
# an offset, so converting to a single zone is always correct.

set -euo pipefail
cd "$(dirname "$0")/.."

REPOS=(. infra links-service manifests n8n)
OUT="TIMELINE.md"
[[ "${1:-}" == "--stdout" ]] && OUT=/dev/stdout

repo_name() { [[ "$1" == "." ]] && echo "app-hub" || echo "$1"; }

# Collect: sortable-epoch | IST datetime | repo | short sha | subject
collect() {
  for d in "${REPOS[@]}"; do
    [[ -d "$d/.git" ]] || continue
    git -C "$d" log --pretty=format:"%at|%H|%h|%s" 2>/dev/null | while IFS='|' read -r epoch full short subj; do
      # %at is a UTC epoch; render it in IST regardless of who committed it.
      ist=$(TZ=Asia/Kolkata date -d "@$epoch" '+%Y-%m-%d %H:%M' 2>/dev/null \
            || TZ=Asia/Kolkata date -r "$epoch" '+%Y-%m-%d %H:%M' 2>/dev/null)
      printf '%s|%s|%s|%s|%s\n' "$epoch" "$ist" "$(repo_name "$d")" "$short" "$subj"
    done
    echo
  done
}

rows=$(collect | grep -v '^$' | sort -n -t'|' -k1)
total=$(printf '%s\n' "$rows" | grep -c . || true)
days=$(printf '%s\n' "$rows" | cut -d'|' -f2 | cut -d' ' -f1 | sort -u | grep -c . || true)
first=$(printf '%s\n' "$rows" | head -1 | cut -d'|' -f2)
last=$(printf '%s\n' "$rows" | tail -1 | cut -d'|' -f2)

{
  echo "# TIMELINE — app-hub"
  echo
  echo "**Generated from git history. Do not edit by hand — run \`./scripts/timeline.sh\` to refresh.**"
  echo
  echo "Every timestamp below is a real commit time, rendered in **IST (+05:30)**."
  echo "Git records an absolute instant, so these are accurate regardless of which"
  echo "shell made the commit — relevant here, because Windows runs IST and WSL runs UTC."
  echo
  echo "| | |"
  echo "|---|---|"
  echo "| Commits | $total across ${#REPOS[@]} repositories |"
  echo "| Active days | $days |"
  echo "| First commit | $first IST |"
  echo "| Latest commit | $last IST |"
  echo
  echo "---"
  echo

  current_day=""
  while IFS='|' read -r _epoch ist repo short subj; do
    [[ -z "${ist:-}" ]] && continue
    day="${ist%% *}"
    time="${ist##* }"
    if [[ "$day" != "$current_day" ]]; then
      [[ -n "$current_day" ]] && echo
      echo "## $day"
      echo
      echo "| Time (IST) | Repo | Commit | Change |"
      echo "|---|---|---|---|"
      current_day="$day"
    fi
    printf '| %s | `%s` | `%s` | %s |\n' "$time" "$repo" "$short" "$subj"
  done <<< "$rows"
} > "$OUT"

[[ "$OUT" != /dev/stdout ]] && echo "Wrote $OUT — $total commits, $days active days, $first to $last IST"
