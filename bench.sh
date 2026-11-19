#!/usr/bin/env bash
# [Agent] Repeats the workstation run (strata 0.2.16, 5950X + 3090): plain Coder, int8 KV, 512K, one slot. Then the lab prompt
# set (decode tok/s per category) and strata's suite (chat, 4K-32K prompt reading, agent turns) beside the workstation's numbers.
# Usage: ./bench.sh   (KV=q4_0 ./bench.sh to try another KV format). Results land in results/<host>-<date>/.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
OUT="$ROOT/results/$(hostname)-$(date +%Y%m%d-%H%M)"
T="$HOME/.local/share/strata/terminal/current"
mkdir -p "$OUT"
# [Agent] The bench owns the server: it restarts whatever runs on 8080 and stops it on exit, even after a failed start.
trap '"$HOME/.local/bin/strata" launch --stop > /dev/null 2>&1' EXIT

ABL=0 KV="${KV:-int8}" "$ROOT/start-coder.sh" > "$OUT/launch.log" 2>&1 < /dev/null
if ! curl -sf -m 5 127.0.0.1:8080/health | grep -q '"loaded": true'; then
  echo "server did not start:"; tail -5 "$OUT/launch.log"; exit 1
fi
echo "ram $(free -g | awk '/Mem/{print $3"G used, "$7"G available"}'), vram $(nvidia-smi --query-gpu=memory.used --format=csv,noheader)" | tee "$OUT/memory.txt"

python3 "$ROOT/bench/run_prompts.py" 8080 2 "$ROOT/bench/prompts.jsonl" | tee "$OUT/prompts.txt"
cd "$T"
python/bin/python3.12 tools/strata_bench.py --url http://127.0.0.1:8080 --long --runs 3 --out "$OUT/suite" --quiet > /dev/null 2>&1
python/bin/python3.12 tools/strata_bench.py --compare-only "$(ls -d "$OUT"/suite/*/)" --compare "$ROOT/bench/reference" | tee "$OUT/compare.txt"
echo "full report: $(ls "$OUT"/suite/*/README.md)"
