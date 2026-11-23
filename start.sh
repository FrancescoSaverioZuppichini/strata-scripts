#!/usr/bin/env bash
set -euo pipefail

# [Agent] General model, Qwen3.8-Flash-Next IQ2_XS at 512K. q4_0 KV is what fits 512K in 62 GB of RAM (int8 got OOM-killed),
# one slot frees VRAM for more resident experts, and MTP draft length 3 beat 4, 6 and 7. MTP is pinned because since 0.2.16
# strata picks the DFlash2 drafter for IQ2_XS by default, which is not the setup we measured.
# [Agent] Local only, no key: from another machine run `ssh -N -L 8080:127.0.0.1:8080 <this box>`, then open http://localhost:8080.
# [Agent] ABL=1 removes refusals the same way start-coder.sh does: the Huihui refusal direction is projected out of the residual
# stream on layers 1-47 at run time, so it costs no extra memory at 512K. A baked abliterated IQ2_XS (SC117) needs its own pack.
ABL="${ABL:-1}"
DATA=$(sed -n 's/.*"data_dir": "\([^"]*\)".*/\1/p' "$HOME/.config/strata/settings.json" 2>/dev/null || true)
VEC="${VEC:-$DATA/abliteration/Huihui-Qwen3.8-Flash-Next-refusal-direction-r.gguf}"
ABL_ARGS=()
if [[ "$ABL" == 1 ]]; then
  [[ -f "$VEC" ]] || { echo "refusal vector not found at $VEC: set VEC=<file> or ABL=0" >&2; exit 1; }
  ABL_ARGS=(--set "control-vector-scaled=$VEC:1.0" --set "control-vector-layer-range=1 47" --set cvec-mode=project)
fi

exec "$HOME/.local/bin/strata" launch \
  --model iq2_xs \
  --context 512k \
  --kv q4_0 \
  --parallel 1 \
  --drafting mtp \
  --set spec=3 \
  "${ABL_ARGS[@]}" \
  --vision gpu \
  --tune skip \
  --access local \
  --restart \
  --yes --no-tui \
  "$@"
