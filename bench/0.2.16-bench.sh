#!/usr/bin/env bash
# [Agent] Same run as 5950x-3200-bench.sh (5950X, DDR4-3200, engine 0.1.54), repeated on the fresh 0.2.16 install (engine
# 0.1.62) with nothing else on the GPU, so the engine update is the only change: plain Coder, int8 KV, 512K, 300 W.
set -uo pipefail
S=/media/zuppif/Cancro/strata
LAB=$S/bench/lab
OUT=$S/bench/0.2.16
T=$HOME/.local/share/strata/terminal/current

# [Agent] ComfyUI and the stash embed sidecar were stopped to free the 3090. Bring them back on any exit, even a failed
# start, with the flags, venv and log they had before.
restore() {
  echo "== restoring $(date +%H:%M)"
  "$HOME/.local/bin/strata" launch --stop > "$OUT/stop.log" 2>&1
  sleep 5
  (cd /media/zuppif/Cancro/ComfyUI && . .venv/bin/activate && nohup python main.py --use-sage-attention --reserve-vram 0.5 --enable-triton-backend >> /media/zuppif/Cancro/tmp/viggle/comfy.log 2>&1 < /dev/null &)
  (cd /media/zuppif/Cancro/stash/embed-sidecar && . ./env.sh && EMBED_COMPILE=none nohup "$HOME/.local/bin/uv" run --frozen uvicorn app:app --host 127.0.0.1 --port 8100 > "$EMBED_HOME/tmp/sidecar.log" 2>&1 < /dev/null &)
  echo "== done $(date +%H:%M)"
}
mkdir -p "$OUT"
trap restore EXIT

echo "== coder-int8 5950X RAM 3200, strata 0.2.16 $(date +%H:%M)"
"$HOME/.local/bin/strata" --version
lscpu | grep "Model name"; nvidia-smi --query-gpu=power.limit,pcie.link.gen.max,memory.used --format=csv,noheader
udevadm info -e | grep -E "MEMORY_DEVICE_[0-9]+_CONFIGURED_SPEED_MTS=" | sed "s/^E: //" | tr "\n" " "; echo
ABL=0 KV=int8 "$S/start-coder.sh" > "$OUT/launch.log" 2>&1 < /dev/null
if ! curl -sf -m 5 127.0.0.1:8080/health | grep -q "\"loaded\": true"; then echo "server did not start"; tail -5 "$OUT/launch.log"; exit 1; fi
grep -iE "engine [0-9]|workers|cores|draft" "$OUT/launch.log" | head -5
echo "ram $(free -g | awk "/Mem/{print \$3\"G used, \"\$7\"G available\"}"), vram $(nvidia-smi --query-gpu=memory.used --format=csv,noheader)"
python3 "$LAB/run_prompts.py" 8080 2 "$LAB/prompts.jsonl" | sed "s/^RESULT /RESULT coder-int8-0.2.16 /"
rm -rf "$OUT/suite"
(cd "$T" && python/bin/python3.12 tools/strata_bench.py --url http://127.0.0.1:8080 --long --runs 3 --out "$OUT/suite" --quiet) >/dev/null 2>&1
grep -E "^\| (short chat|4K|16K|32K|agent)" "$(find "$OUT/suite" -name README.md | head -1)" | cut -d"|" -f2,7,8 | sed "s/^/suite 0.2.16:/"
