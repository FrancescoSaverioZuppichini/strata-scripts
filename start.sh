#!/usr/bin/env bash
set -euo pipefail

# [Agent] General model, Qwen3.8-Flash-Next IQ2_XS at 512K. q4_0 KV is what fits 512K in 62 GB of RAM (int8 got OOM-killed),
# one slot frees VRAM for more resident experts, and MTP draft length 3 beat 4, 6 and 7. MTP is pinned because since 0.2.16
# strata picks the DFlash2 drafter for IQ2_XS by default, which is not the setup we measured.
# [Agent] Local only, no key: from another machine run `ssh -N -L 8080:127.0.0.1:8080 <this box>`, then open http://localhost:8080.
exec "$HOME/.local/bin/strata" launch \
  --model iq2_xs \
  --context 512k \
  --kv q4_0 \
  --parallel 1 \
  --drafting mtp \
  --set spec=3 \
  --vision gpu \
  --tune skip \
  --access local \
  --restart \
  --yes --no-tui \
  "$@"
