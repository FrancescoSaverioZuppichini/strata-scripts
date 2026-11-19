#!/usr/bin/env bash
set -euo pipefail

# [Agent] Qwen3.8-Flash-Next IQ2_XS at 512K (yarn x2), the best measured setup for this box (RTX 3090, Ryzen 7 2700X, 62 GB RAM).
# [Agent] Medians on the lab prompt set: code 135, prose 110, short chat 51, ~20K-token context 116, agent turns 123 tok/s;
# a 490K-token prompt reads at ~2050 tok/s with 3/3 recall.
# [Agent] q4_0 KV is what fits 512K in 62 GB of RAM (int8 got OOM-killed); one slot frees VRAM for ~2k more resident experts;
# MTP (strata's default drafter) with draft length 3 beat 4, 6 and 7. DFlash2 serving lives in /media/zuppif/Cancro/strata-dflash.
# [Agent] Local only, no key: reach it from the Mac with `ssh -N -L 8080:127.0.0.1:8080 workstation`, then http://localhost:8080.
SPEC="${SPEC:-3}"

exec "$HOME/.local/bin/strata" launch \
  --model iq2_xs \
  --data-dir /media/zuppif/Cancro/strata/models \
  --context 512k \
  --kv q4_0 \
  --parallel 1 \
  --set spec="$SPEC" \
  --vision gpu \
  --tune skip \
  --access local \
  --port 8080 \
  --restart \
  --yes --no-tui \
  "$@"
