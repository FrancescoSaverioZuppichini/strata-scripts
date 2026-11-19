#!/usr/bin/env bash
set -uo pipefail
S=/media/zuppif/Cancro/strata; LAB=/media/zuppif/Cancro/strata-lab; OUT=$S/bench/par2; mkdir -p "$OUT"
echo "== abl coder --parallel 2 --context 512k $(date +%H:%M)"
"$S/start-coder.sh" --parallel 2 > "$OUT/launch.log" 2>&1 < /dev/null
curl -sf -m 5 127.0.0.1:8080/health | grep -q "\"loaded\": true" || { echo "server did not start"; tail -8 "$OUT/launch.log"; exit 1; }
L=~/.local/state/strata/launch/iq1_m-512k.engine.log
n=$(grep -n "engine started" $L | tail -1 | cut -d: -f1)
tail -n +$n $L | grep -iE "KV streaming: [0-9]+ of|memory guard|expert cache [0-9]+ slots|VRAM free with|parallel|slots? " | head -8
echo "ram $(free -g | awk "/Mem/{print \$3\"G used, \"\$7\"G available\"}"), vram $(nvidia-smi --query-gpu=memory.used --format=csv,noheader)"
python3 $S/bench/par_bench.py 8080 1 $LAB/prompts.jsonl
python3 $S/bench/par_bench.py 8080 2 $LAB/prompts.jsonl
echo "== done $(date +%H:%M)"
