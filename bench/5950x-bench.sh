#!/usr/bin/env bash
# [Agent] Same procedure as model-bench.sh coder-int8 on 2026-10-24 (2700X), rerun after the 5950X/X570 swap: plain Coder
# (ABL=0, the Oct run predates abliteration), untuned, 300 W GPU cap left as it was, so only the platform changes.
set -uo pipefail
S=/media/zuppif/Cancro/strata
LAB=/media/zuppif/Cancro/strata-lab
OUT=$S/bench/5950x
PY=$HOME/.local/share/strata/terminal/current/python/bin/python3.12
mkdir -p "$OUT"
echo "== coder-int8 5950X $(date +%H:%M)"
lscpu | grep "Model name"; nvidia-smi --query-gpu=power.limit,pcie.link.gen.max --format=csv,noheader
ABL=0 KV=int8 "$S/start-coder.sh" > "$OUT/launch.log" 2>&1 < /dev/null
if ! curl -sf -m 5 127.0.0.1:8080/health | grep -q "\"loaded\": true"; then echo "server did not start"; tail -5 "$OUT/launch.log"; exit 1; fi
grep -iE "engine [0-9]|workers|cores" "$OUT/launch.log" | head -5
echo "ram $(free -g | awk "/Mem/{print \$3\"G used, \"\$7\"G available\"}"), vram $(nvidia-smi --query-gpu=memory.used --format=csv,noheader)"
python3 "$LAB/run_prompts.py" 8080 2 "$LAB/prompts.jsonl" | sed "s/^RESULT /RESULT coder-int8-5950x /"
rm -rf "$OUT/suite"
(cd "$HOME/.local/share/strata/terminal/current" && $PY tools/strata_bench.py --url http://127.0.0.1:8080 --long --runs 3 --out "$OUT/suite" --quiet) >/dev/null 2>&1
grep -E "^\| (short chat|4K|16K|32K|agent)" "$(find "$OUT/suite" -name README.md | head -1)" | cut -d"|" -f2,7,8 | sed "s/^/suite 5950x:/"
echo "== done $(date +%H:%M)"
