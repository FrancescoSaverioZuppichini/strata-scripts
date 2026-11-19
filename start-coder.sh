#!/usr/bin/env bash
set -euo pipefail

# [Agent] Qwen3.8-Flash-Next Coder (ISTA-DASLab IQ1_M: 256 of 512 experts per layer, chosen on code/agentic data; 91% of the
# full model on SWE-bench Verified, 99% on LiveCodeBench). Half the experts means more of them stay on the 3090 and the
# expert RAM drops to ~23 GB, so 512K context also fits with 8-bit KV. Weaker outside code and English.
# [Agent] KV format: KV=<q4_0|k8v4|int8>, default from the measured benchmark (bench/coder-kv.log).
KV="${KV:-int8}"
# [Agent] Abliteration: alesha-pro's Huihui refusal direction (480 KB, sha256 59f9ae8b...), projected out of the residual
# stream on layers 1-47 at run time; weights untouched. ABL=0 runs the original Coder. Per request: "cvec": 0 turns it off.
ABL="${ABL:-1}"
VEC=/media/zuppif/Cancro/strata/models/abliteration/Huihui-Qwen3.8-Flash-Next-refusal-direction-r.gguf
ABL_ARGS=()
if [[ "$ABL" == 1 ]]; then
  ABL_ARGS=(--set "control-vector-scaled=$VEC:1.0" --set "control-vector-layer-range=1 47" --set cvec-mode=project)
fi

exec "$HOME/.local/bin/strata" launch \
  --family coder \
  --model iq1_m \
  --data-dir /media/zuppif/Cancro/strata/models \
  --context 512k \
  --kv "$KV" \
  --parallel 1 \
  --set spec=3 \
  "${ABL_ARGS[@]}" \
  --vision gpu \
  --tune skip \
  --access local \
  --port 8080 \
  --restart \
  --yes --no-tui \
  "$@"
