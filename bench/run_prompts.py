# Runs prompts.jsonl against a server: one warm-up pass, then RUNS measured passes. Prints per-category medians of decode tok/s,
# and the overall median, so a change has to help across texts rather than one prompt.
import json, statistics, sys, urllib.request

port, runs, path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
rows = [json.loads(l) for l in open(path)]

def gen(r):
    body = {"model": "x", "messages": [{"role": "user", "content": r["prompt"]}], "max_tokens": r["max_tokens"],
            "temperature": 0, "chat_template_kwargs": {"enable_thinking": False}}
    req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions", json.dumps(body).encode(), {"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=900))["timings"]["predicted_per_second"]

for r in rows:
    gen(r)
by = {}
for _ in range(runs):
    for r in rows:
        by.setdefault(r["cat"], []).append(gen(r))
allv = [v for vs in by.values() for v in vs]
print("RESULT " + "  ".join(f"{c} {statistics.median(v):6.1f}" for c, v in by.items()) + f"  | all {statistics.median(allv):6.1f}")
