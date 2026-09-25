#!/usr/bin/env bash
# chat.sh DIR — messenger-style live view of a swarm run: message bubbles per agent,
# replies quote the addressee's previous message, system events, "typing" line.
# Needs bash, jq and gawk (character-aware wrapping of UTF-8 text).
set -uo pipefail
dir=$(realpath "${1:?usage: chat.sh RUN_DIR}")
[[ -d $dir ]] || { echo "chat.sh: no run directory: $dir" >&2; exit 2; }
case ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} in *UTF-8* | *utf8*) ;; *) export LC_ALL=C.UTF-8 ;; esac
max_lines=${SWARM_CHAT_MAX_LINES:-0} # 0 = show messages in full; N = cut after N lines

iso() { date -u -d "@$1" +%FT%T.000000000Z; }

# Model per agent id (anon.map for all/loop, run.json ids for run batches).
names() {
  { [[ -f $dir/anon.map ]] && awk -F'\t' '{m=$2; if ($3 != "") m=m "@" $3; print $1 "\t" m}' "$dir/anon.map"
    [[ -f $dir/run.json ]] && jq -r '.agents[]? | select(.model) | "\(.id)\t\(.model)"' "$dir/run.json" 2>/dev/null
  } | awk -F'\t' '!seen[$1]++'
}

# System events as JSON lines: round starts, failed agents, the verdict.
events() {
  local d f rc t id why
  for d in "$dir"/r[0-9]* "$dir"/it[0-9]*; do
    [[ -d $d ]] || continue
    t=$(find "$d" -maxdepth 1 -name '*.prompt' -printf '%T@\n' 2>/dev/null | sort -n | head -1)
    [[ -n $t ]] && jq -cn --arg ts "$(iso "${t%.*}")" --arg m "${d##*/}" \
      '{ts:$ts,kind:"sys",msg:(if $m|startswith("it") then "iteration " + $m[2:] else "round " + $m[1:] end)}'
  done
  while IFS= read -r f; do
    rc=$(<"$f"); [[ $rc == 0 || $rc == running ]] && continue
    id=$(basename "$f" .rc); why="rc $rc"
    if grep -qsiE 'usage.?limit|quota|insufficient.?credit' "${f%.rc}.log" "${f%.rc}.stderr"; then why='usage limit'
    elif grep -qsiE 'rate.?limit|429|too many requests|overloaded' "${f%.rc}.log" "${f%.rc}.stderr"; then why='rate limited'
    elif [[ $rc == 65 ]]; then why='empty or incomplete answer'; fi
    jq -cn --arg ts "$(iso "$(stat -c %Y "$f")")" --arg m "$id dropped out ($why)" '{ts:$ts,kind:"sys",msg:$m,bad:true}'
  done < <(find "$dir" \( -path "$dir/a" -o \( -type d -name j \) \) -prune -o -name '*.rc' ! -name 'judge*.rc' ! -name '*.attempt*.rc' -print 2>/dev/null)
  [[ -s $dir/final.md ]] && jq -cn --arg ts "$(iso "$(stat -c %Y "$dir/final.md")")" '{ts:$ts,kind:"sys",msg:"verdict ready: final.md"}'
  return 0
}

typing() { # agents whose current call is still running
  find "$dir" -path "$dir/a" -prune -o -name '*.rc' -print 2>/dev/null | while IFS= read -r f; do
    [[ $(<"$f") == running ]] && basename "$f" .rc
  done | sort -uV | paste -sd' '
}

render() {
  local cols rows boxes=("$dir"/a/*/outbox.jsonl)
  cols=$(tput cols 2>/dev/null || echo 100); rows=$(tput lines 2>/dev/null || echo 40)
  {
    if [[ -e ${boxes[0]} ]]; then cat "${boxes[@]}"; fi
    events
  } | jq -Rrs '
      split("\n") | map(fromjson? | select(type == "object" and (.ts|type) == "string" and (.msg|type) == "string"))
      | sort_by(.ts)
      | reduce .[] as $e ({out: [], last: {}};
          ($e.msg | gsub("\\\\n"; "\n")) as $msg
          | (if ($e.kind // "") != "sys" and ($e.to // "all") != "all" then .last[$e.to] else null end) as $q
          | .out += [$e + {msg: $msg, quote: ($q // ""),
              hm: ($e.ts | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 | localtime | strftime("%H:%M"))}]
          | if ($e.kind // "") != "sys" then .last[$e.from] = $msg else . end)
      | .out[]
      | [(.kind // "msg"), .hm, (.from // ""), (.to // "all"), (if .bad then "1" else "" end),
         (.quote | gsub("[\u0000-\u0008\u000b-\u001e\u007f]"; "") | gsub("[\n\t]"; " ")),
         (.msg | gsub("[\u0000-\u0008\u000b-\u001e\u007f]"; "") | gsub("\t"; " ") | gsub("\n"; "\u001f"))] | @tsv' |
    gawk -F'\t' -v cols="$cols" -v maxl="$max_lines" -v namefile=<(names) '
      BEGIN {
        while ((getline l < namefile) > 0) { split(l, nm, "\t"); model[nm[1]] = nm[2] }
        split("39 208 170 76 214 141 147 45 112 220 99 168 81 179", pal, " ")
        w = cols - 6; if (w > 96) w = 96; if (w < 24) w = 24
        R = "\033[0m"; D = "\033[2m"; B = "\033[1m"
      }
      function color(s,   h, i) { if (s ~ /^a[0-9]+$/) return "\033[38;5;" pal[(substr(s, 2) - 1) % 14 + 1] "m"; h = 0; for (i = 1; i <= length(s); i++) h = (h * 31 + index("abcdefghijklmnopqrstuvwxyz0123456789-_.@", substr(s, i, 1))) % 9973; return "\033[38;5;" pal[h % 14 + 1] "m" }
      function rep(c, n,   s) { s = ""; while (n-- > 0) s = s c; return s }
      function wrap(t, width, arr,   n, words, i, line, k, wd) {
        n = 0; k = split(t, words, " "); line = ""
        for (i = 1; i <= k; i++) {
          wd = words[i]
          while (length(wd) > width) { if (line != "") { arr[++n] = line; line = "" } arr[++n] = substr(wd, 1, width); wd = substr(wd, width + 1) }
          if (line == "") line = wd; else if (length(line) + 1 + length(wd) <= width) line = line " " wd; else { arr[++n] = line; line = wd }
        }
        arr[++n] = line; return n
      }
      function row(text, c) { printf "  %s│%s %s%s %s│%s\n", D, R, c text R, rep(" ", w - 2 - length(text)), D, R }
      {
        kind = $1; hm = $2; from = $3; to = $4; bad = $5; quote = $6; msg = $7
        if (kind == "sys") {
          t = " " msg " "; pad = int((w + 2 - length(t)) / 2); if (pad < 0) pad = 0
          printf "\n  %s%s%s%s%s\n", D, rep(" ", pad), (bad ? "\033[22;38;5;203m" : ""), t, R; next
        }
        c = color(from); title = from (model[from] != "" ? " · " model[from] : "")
        head = " " title " "; tl = length(head) + length(hm) + 4
        if (tl > w) { head = substr(head, 1, w - length(hm) - 5) "… "; tl = length(head) + length(hm) + 4 }
        printf "\n  %s╭─%s%s%s%s%s%s %s ─╮%s\n", D, R, c B, head, R D, rep("─", w - tl), "", hm, R
        if (to != "all" && to != "") {
          qc = color(to); qt = "↩ " to (quote != "" ? ": " quote : "")
          if (length(qt) > w - 3) qt = substr(qt, 1, w - 4) "…"
          printf "  %s│%s %s▎%s%s%s %s│%s\n", D, R, qc, D, qt, rep(" ", w - 3 - length(qt)), R D, R
        }
        n = 0; np = split(msg, paras, "\037"); shown = 0; total = 0
        for (p = 1; p <= np; p++) { k = wrap(paras[p], w - 2, L); for (j = 1; j <= k; j++) { total++; if (maxl == 0 || shown < maxl) { row(L[j], ""); shown++ } } }
        if (total > shown) row("… +" (total - shown) " lines (swarm.sh read DIR)", D)
        printf "  %s╰%s╯%s\n", D, rep("─", w), R
      }' > "$dir/.chat.render"
  n_agents=$(names | wc -l); n_msgs=$(cat "$dir"/a/*/outbox.jsonl 2>/dev/null | grep -c . || true)
  typing_now=$(typing)
  total=$(wc -l < "$dir/.chat.render")
}

# Draw the header, a window of the rendered chat ending `offset` lines above the bottom, and the footer.
draw() {
  local rows body end start
  rows=${view_rows:-$(tput lines 2>/dev/null || echo 40)}; body=$((rows - 3))
  ((offset > total - body)) && offset=$((total - body))
  ((offset < 0)) && offset=0
  end=$((total - offset)); start=$((end - body + 1)); ((start < 1)) && start=1
  printf '\033[H\033[2J\033[1;97;48;5;24m  swarm · %s  \033[0;38;5;250;48;5;24m %s agents · %s messages \033[0m\033[K\n' \
    "${dir##*/}" "$n_agents" "$n_msgs"
  sed -n "${start},${end}p" "$dir/.chat.render"
  if ((offset > 0)); then printf '\n  \033[1;30;48;5;81m ↓ %s more lines below — End or G to jump \033[0m' "$offset"
  elif [[ -n $typing_now ]]; then printf '\n  \033[2;3m✎ %s typing…\033[0m' "$typing_now"
  elif [[ -s $dir/final.md ]]; then printf '\n  \033[32m✔ done — %s/final.md\033[0m' "$dir"
  else printf '\n  \033[2m↑↓ PgUp PgDn scroll · End follow · q quit\033[0m'; fi
}

offset=0 total=0 n_agents=0 n_msgs=0 typing_now=''
if [[ ! -t 1 ]]; then render; view_rows=$((total + 3)) draw; echo; rm -f "$dir/.chat.render"; exit 0; fi
saved_stty=$(stty -g 2>/dev/null || true)
stty -echo -icanon min 0 2>/dev/null || true
printf '\033[?1049h\033[?25l'
trap 'stty "$saved_stty" 2>/dev/null; printf "\033[?25h\033[?1049l"; rm -f "$dir/.chat.render"; exit 0' INT TERM EXIT
prev='' ticks=0
while :; do
  if ((ticks % 4 == 0)); then # check files every ~2s, keys every 0.5s
    sig=$(find "$dir" \( -name 'outbox.jsonl' -o -name '*.rc' -o -name 'final.md' \) -printf '%T@%s\n' 2>/dev/null | sort | md5sum)
    sig+=$(tput cols)x$(tput lines)
    if [[ $sig != "$prev" ]]; then
      old=$total; render; prev=$sig
      ((offset > 0)) && offset=$((offset + total - old)) # keep the viewport still while reading history
      draw
    fi
  fi
  ((ticks++))
  key=''; IFS= read -rsn1 -t 0.5 key || true
  [[ -n $key ]] || continue
  page=$(($(tput lines) - 4))
  if [[ $key == $'\e' ]]; then
    rest=''; IFS= read -rsn2 -t 0.05 rest || true
    case $rest in
      '[A') key=k ;; '[B') key=j ;; '[H') key=g ;; '[F') key=G ;;
      '[5') IFS= read -rsn1 -t 0.05 _ || true; key=b ;;
      '[6') IFS= read -rsn1 -t 0.05 _ || true; key=f ;;
      *) continue ;;
    esac
  fi
  case $key in
    k) offset=$((offset + 1)) ;; j) offset=$((offset - 1)) ;;
    b) offset=$((offset + page)) ;; f | ' ') offset=$((offset - page)) ;;
    g) offset=$total ;; G) offset=0 ;;
    q | Q) exit 0 ;;
    *) continue ;;
  esac
  draw
done
