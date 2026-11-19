#!/usr/bin/env bash
# Times the general model (IQ2_XS, q4_0 KV) and the Coder with each KV format on one quiet machine, the way they are served
# (512K, one slot, MTP draft 3). Per config: a fresh server, then the lab prompt set (one warm-up pass, two measured passes:
# 3 code, 3 prose, 3 short chat, one ~20K-token context task) and strata's suite (4K/16K/32K prompt reading, agent turns).
set -uo pipefail
S=/media/zuppif/Cancro/strata
LAB=/media/zuppif/Cancro/strata-lab
OUT=$S/bench/models
PY=$HOME/.local/share/strata/terminal/current/python/bin/python3.12
mkdir -p "$OUT"

bench() {
  local name=$1; shift
  echo "== $name $(date +%H:%M)"
  "$@" > "$OUT/launch-$name.log" 2>&1 < /dev/null
  if ! curl -sf -m 5 127.0.0.1:8080/health | grep -q '"loaded": true'; then
    echo "$name: server did not start"; tail -3 "$OUT/launch-$name.log"; return
  fi
  echo "ram $(free -g | awk '/Mem/{print $3"G used, "$7"G available"}'), vram $(nvidia-smi --query-gpu=memory.used --format=csv,noheader)"
  python3 "$LAB/run_prompts.py" 8080 2 "$LAB/prompts.jsonl" | sed "s/^RESULT /RESULT $name /"
  rm -rf "$OUT/suite-$name"
  (cd "$HOME/.local/share/strata/terminal/current" && $PY tools/strata_bench.py --url http://127.0.0.1:8080 --long --runs 3 --out "$OUT/suite-$name" --quiet) >/dev/null 2>&1
  grep -E "^\| (short chat|4K|16K|32K|agent)" "$(find "$OUT/suite-$name" -name README.md | head -1)" | cut -d"|" -f2,7,8 | sed "s/^/suite $name:/"
}

bench iq2xs-q4_0 "$S/start.sh"
for kv in q4_0 k8v4 int8; do
  bench "coder-$kv" env KV="$kv" "$S/start-coder.sh"
done
echo "== done $(date +%H:%M)"
