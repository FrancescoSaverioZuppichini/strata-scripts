#!/usr/bin/env bash
# [Agent] Repeats the workstation benchmark (strata 0.2.16, 5950X + 3090): plain Coder IQ1_M, int8 KV, 512K, one slot, MTP
# draft 3. The lab prompts give decode tok/s per category; strata's suite gives chat, 4K-32K prompt reading and agent turns.
# Usage: ./bench.sh   Results go to results/<host>-<date>-<model>/. KV=q4_0 ./bench.sh tries another KV format.
# MODEL=inkling ./bench.sh runs the same prompts on Inkling 2 Mini SQ-20 (the lossless 24 GiB pack), one slot. Its weights
# take 18 GiB of the 3090, so it gets 48K and no picture reader: 64K runs out of memory even without vision, and the
# suite's 32K prompt needs more than 32K. The printed reference stays the Coder's, so the two read side by side.
set -uo pipefail
STRATA="$HOME/.local/bin/strata"
MODEL="${MODEL:-coder}"
case "$MODEL" in
  coder) ARGS=(--family coder --model iq1_m --context 512k --kv "${KV:-int8}" --parallel 1 --drafting mtp --set spec=3 --vision gpu) ;;
  inkling) ARGS=(--family inkling-2-mini --model sq-20 --context 48k --parallel 1 --vision off) ;;
  *) echo "MODEL must be coder or inkling"; exit 1 ;;
esac
OUT="$(cd "$(dirname "$0")" && pwd)/results/$(hostname)-$(date +%Y%m%d-%H%M)-$MODEL"
mkdir -p "$OUT"
# [Agent] The bench owns the server: it restarts whatever runs on 8080 and stops it on exit, even after a failed start.
trap '"$STRATA" launch --stop > /dev/null 2>&1' EXIT

"$STRATA" launch "${ARGS[@]}" --tune skip --access local --restart --yes --no-tui > "$OUT/launch.log" 2>&1 < /dev/null
if ! curl -sf -m 5 127.0.0.1:8080/health | grep -q '"loaded": true'; then
  echo "server did not start:"; tail -5 "$OUT/launch.log"; exit 1
fi
echo "ram $(free -g | awk '/Mem/{print $3"G used, "$7"G available"}'), vram $(nvidia-smi --query-gpu=memory.used --format=csv,noheader)" | tee "$OUT/memory.txt"

# [Agent] Several prompts per category so no result hangs on one text; one warm-up pass, then the median of two measured
# passes. Thinking off and temperature 0 so every run decodes the same text. Seed 11 rebuilds the exact lab prompt set.
python3 - <<'EOF' | tee "$OUT/prompts.txt"
import json, random, statistics, urllib.request

random.seed(11)
handlers = "".join(f"def handler_{i}(req):\n    return {{'id': {i}, 'path': req.path, 'ok': {random.choice(['True', 'False'])}}}\n" for i in range(700))
rows = [
    ("code", "Write a complete Python CLI that tails an nginx access log, parses each line with a regex, and prints per-minute request counts and p95 latency. Code only.", 900),
    ("code", "Implement an LRU cache in TypeScript with get, set, delete and a max size, plus Jest tests covering eviction order. Code only.", 900),
    ("code", "Write a Rust function that parses a CSV file of (timestamp, sensor, value) rows and returns per-sensor min, max and mean, with error handling and unit tests.", 900),
    ("prose", "Explain how TCP congestion control works, covering slow start, congestion avoidance, fast retransmit and BBR, in about 900 words.", 900),
    ("prose", "Write a short story (about 700 words) about a lighthouse keeper who finds a radio that receives messages from the future.", 900),
    ("prose", "Compare PostgreSQL and MongoDB for an e-commerce backend: data modeling, transactions, scaling and operations. About 800 words.", 900),
    ("chat", "What are three good names for a grey cat? One line each.", 120),
    ("chat", "Give me a one-sentence summary of what a hash map is.", 120),
    ("chat", "Translate to Italian: 'The meeting moved to Thursday at ten.'", 120),
    ("longctx", handlers + "\nRefactor these handlers into one generic handler plus a registry, and explain the change. Show the full code.", 600),
]

def gen(prompt, max_tokens):
    body = {"model": "x", "messages": [{"role": "user", "content": prompt}], "max_tokens": max_tokens,
            "temperature": 0, "chat_template_kwargs": {"enable_thinking": False}}
    req = urllib.request.Request("http://127.0.0.1:8080/v1/chat/completions", json.dumps(body).encode(), {"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=900))["timings"]["predicted_per_second"]

for _, prompt, n in rows:
    gen(prompt, n)
by = {}
for _ in range(2):
    for cat, prompt, n in rows:
        by.setdefault(cat, []).append(gen(prompt, n))
allv = [v for vs in by.values() for v in vs]
print("this box     " + "  ".join(f"{c} {statistics.median(v):6.1f}" for c, v in by.items()) + f"  | all {statistics.median(allv):6.1f}")
EOF
echo "coder ref    code  135.5  prose  104.6  chat   93.9  longctx  131.3  | all  109.7"

cd "$HOME/.local/share/strata/terminal/current"
python/bin/python3.12 tools/strata_bench.py --url http://127.0.0.1:8080 --long --runs 3 --out "$OUT/suite" --quiet > /dev/null 2>&1
grep -hE "^\| (short chat|4K|16K|32K|agent)" "$OUT"/suite/*/README.md | cut -d"|" -f2,7,8
echo "coder ref: chat 102.0, agent 101.5 decode tok/s | 4K 2652.6, 16K 3164.4, 32K 3209.6 prompt tok/s"
echo "full report: $(ls "$OUT"/suite/*/README.md)"
