#!/usr/bin/env bash
# [Agent] Serves Qwen3.8-Flash-Next with strata on 127.0.0.1:8080: 512K context, one slot, MTP draft 3. Arguments are
# strata launch flags and come last, so they override these; without --model it serves the Coder IQ1_M:
#   ./start.sh                                  Coder: 256 of 512 experts per layer, picked on code/agentic data; int8 KV
#   ./start.sh --model iq2_xs --kv q4_0         general 2-bit model; q4_0 KV is what fits 512K in 62 GB of RAM
# [Agent] MTP is pinned because strata picks the DFlash2 drafter for IQ2_XS by default, which is not the setup we measured;
# draft length 3 beat 4, 6 and 7. Local only, no key: from another machine `ssh -N -L 8080:127.0.0.1:8080 <this box>`.
set -euo pipefail
[[ " $* " == *" --model "* ]] || set -- --family coder --model iq1_m "$@"

# [Agent] ABL=1 removes refusals at run time: the Huihui refusal direction is projected out of the residual stream on layers
# 1-47, weights untouched, no extra memory at 512K. The vector is read from strata's model folder (data_dir), or VEC=<file>.
ABL="${ABL:-1}"
DATA=$(sed -n 's/.*"data_dir": "\([^"]*\)".*/\1/p' "$HOME/.config/strata/settings.json" 2>/dev/null || true)
VEC="${VEC:-$DATA/abliteration/Huihui-Qwen3.8-Flash-Next-refusal-direction-r.gguf}"
ABL_ARGS=()
if [[ "$ABL" == 1 ]]; then
  [[ -f "$VEC" ]] || { echo "refusal vector not found at $VEC: set VEC=<file> or ABL=0" >&2; exit 1; }
  ABL_ARGS=(--set "control-vector-scaled=$VEC:1.0" --set "control-vector-layer-range=1 47" --set cvec-mode=project)
fi

exec "$HOME/.local/bin/strata" launch --context 512k --kv int8 --parallel 1 --drafting mtp --set spec=3 "${ABL_ARGS[@]}" \
  --vision gpu --tune skip --access local --restart --yes --no-tui "$@"
