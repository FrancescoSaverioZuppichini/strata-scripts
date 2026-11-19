#!/usr/bin/env bash
set -uo pipefail
S=/media/zuppif/Cancro/strata
PY=$HOME/.local/share/strata/terminal/current/python/bin/python3.12
OUT=$S/bench/spec
mkdir -p "$OUT"

decode() {
  # [Agent] Long greedy generations so tok/s is measured over hundreds of tokens, not dominated by the first few.
  for p in "Write a complete Python CLI that tails an nginx access log, parses each line with a regex, and prints per-minute request counts and p95 latency. Code only." "Explain how TCP congestion control works, covering slow start, congestion avoidance, fast retransmit and BBR, in about 900 words."; do
    for r in 1 2 3; do
      curl -s 127.0.0.1:8080/v1/chat/completions -H "Content-Type: application/json" \
        -d "$(jq -n --arg p "$p" '{model:"x",messages:[{role:"user",content:$p}],max_tokens:1500,temperature:0,chat_template_kwargs:{enable_thinking:false}}')" \
        | jq -r --arg k "${p:0:5}" '"\($k) \(.timings.predicted_n) \(.timings.predicted_per_second) \(.timings.draft_n_accepted)/\(.timings.draft_n)"'
    done
  done
}

for n in "$@"; do
  SPEC=$n $S/start.sh > "$OUT/launch$n.log" 2>&1 < /dev/null
  got=$(grep -o -E "\-\-spec [0-9]+" "$(ls -t ~/.local/state/strata/launch/*.engine.log | head -1)" | tail -1)
  echo "== spec $n (engine: $got)"
  decode | tee "$OUT/decode$n.txt"
  rm -rf "$OUT/suite$n"
  (cd $HOME/.local/share/strata/terminal/current && $PY tools/strata_bench.py --url http://127.0.0.1:8080 --long --runs 3 --out "$OUT/suite$n" --quiet) >/dev/null 2>&1
  grep -E "^\| (short chat|4K|16K|32K|agent)" "$(find "$OUT/suite$n" -name README.md | head -1)" | cut -d"|" -f2,7,8
done
