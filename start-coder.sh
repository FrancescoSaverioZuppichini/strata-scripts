#!/usr/bin/env bash
set -euo pipefail

# [Agent] Qwen3.8-Flash-Next Coder IQ1_M: 256 of 512 experts per layer, picked on code/agentic data (91% of the full model on
# SWE-bench Verified). Half the experts keeps more of them on the GPU and expert RAM near 23 GB, so 512K fits with int8 KV.
KV="${KV:-int8}"
# [Agent] ABL=1 projects the Huihui refusal direction out of the residual stream on layers 1-47 at run time; weights untouched.
# The vector is not in this repo: it is read from Strata's model folder (data_dir in its settings), or set VEC=<file>.
ABL="${ABL:-1}"
DATA=$(sed -n 's/.*"data_dir": "\([^"]*\)".*/\1/p' "$HOME/.config/strata/settings.json" 2>/dev/null || true)
VEC="${VEC:-$DATA/abliteration/Huihui-Qwen3.8-Flash-Next-refusal-direction-r.gguf}"
ABL_ARGS=()
if [[ "$ABL" == 1 ]]; then
  [[ -f "$VEC" ]] || { echo "refusal vector not found at $VEC: set VEC=<file> or ABL=0" >&2; exit 1; }
  ABL_ARGS=(--set "control-vector-scaled=$VEC:1.0" --set "control-vector-layer-range=1 47" --set cvec-mode=project)
fi

exec "$HOME/.local/bin/strata" launch \
  --family coder \
  --model iq1_m \
  --context 512k \
  --kv "$KV" \
  --parallel 1 \
  --set spec=3 \
  "${ABL_ARGS[@]}" \
  --vision gpu \
  --tune skip \
  --access local \
  --restart \
  --yes --no-tui \
  "$@"
