#!/usr/bin/env bash
# watch.sh DIR — live view of a swarm run: agent status per round + message board.
set -uo pipefail
dir=$(realpath "${1:?usage: watch.sh RUN_DIR}")

agents() { # one line per round: green = done, red! = failed, yellow… = running
  local d n s
  for d in "$dir" "$dir"/r*; do
    s=""
    for n in $(find "$d" -maxdepth 1 \( -name '*.md' -o -name '*.log' \) ! -name task.md -printf '%f\n' | sed 's/\.[^.]*$//' | sort -u); do
      if [[ ! -f $d/$n.rc ]]; then s+=$'\e[33m'"$n…"$'\e[0m '
      elif [[ $(<"$d/$n.rc") == 0 ]]; then s+=$'\e[32m'"$n"$'\e[0m '
      else s+=$'\e[31m'"$n!"$'\e[0m '; fi
    done
    [[ -n $s ]] && printf '\e[1m%s:\e[0m %s\n' "$([[ $d == "$dir" ]] && echo run || basename "$d")" "$s"
  done
}

board() {
  [[ -f $dir/board.jsonl ]] || { echo "(board empty)"; return; }
  jq -r '"\(.ts)\t\(.from)\t\(.to)\t\(.msg | gsub("\\s+"; " "))"' "$dir/board.jsonl" |
    while IFS=$'\t' read -r ts from to msg; do
      c=$((31 + $(cksum <<<"$from" | cut -d' ' -f1) % 6))   # stable color per agent
      [[ $to == all ]] && to="" || to=" → $to"
      printf '\e[2m%s\e[0m \e[1;%sm%s\e[0m%s: %s\n' "$ts" "$c" "$from" "$to" "$msg"
    done | fold -s -w "$(tput cols)"
}

while :; do
  head=$(printf '\e[1;36mswarm\e[0m %s  \e[2m%s msgs · %s\e[0m\n' "${dir##*/}" \
    "$(wc -l <"$dir/board.jsonl" 2>/dev/null || echo 0)" "$(date +%T)"; agents
    [[ -f $dir/final.rc ]] && printf '\e[1;32m== final.md ready\e[0m\n')
  body=$(board)
  clear
  printf '%s\n\n' "$head"
  tail -n "$(($(tput lines) - $(wc -l <<<"$head") - 2))" <<<"$body"
  sleep 2
done
