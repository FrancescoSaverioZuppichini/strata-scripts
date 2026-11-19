#!/usr/bin/env bash
# Installs the Coder pack (Qwen3.8-Flash-Next Coder IQ1_M) on its first launch, then times each KV format on it
# with the lab's fixed prompt set, and puts the regular server (start.sh) back at the end.
set -uo pipefail
S=/media/zuppif/Cancro/strata
LAB=/media/zuppif/Cancro/strata-lab
OUT=$S/bench/coder-kv
mkdir -p "$OUT"

for kv in q4_0 k8v4 int8; do
  echo "== $kv $(date +%H:%M)"
  "$HOME/.local/bin/strata" launch --family coder --model iq1_m --context 512k --kv "$kv" --parallel 1 \
    --vision gpu --set spec=3 --tune skip --access local --port 8080 \
    --data-dir "$S/models" --restart --yes --no-tui > "$OUT/launch-$kv.log" 2>&1 < /dev/null
  if ! curl -sf -m 5 127.0.0.1:8080/health | grep -q '"loaded": true'; then
    echo "$kv: server did not start"; tail -5 "$OUT/launch-$kv.log"; continue
  fi
  echo "ram $(free -g | awk '/Mem/{print $3"G used, "$7"G available"}'), vram $(nvidia-smi --query-gpu=memory.used --format=csv,noheader)"
  python3 "$LAB/run_prompts.py" 8080 2 "$LAB/prompts.jsonl" | sed "s/^RESULT /RESULT coder-$kv /"
done

echo "== restoring start.sh $(date +%H:%M)"
"$S/start.sh" > "$S/launch.log" 2>&1 < /dev/null
curl -s -m 5 127.0.0.1:8080/health | head -c 90; echo
