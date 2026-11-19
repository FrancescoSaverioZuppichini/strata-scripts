# [Agent] Lab prompt set with N clients at once: per-request decode tok/s (what one agent feels) and aggregate tokens/wall-second
# (what the box delivers). Both clients run the full set, so N=2 does twice the work in roughly the same wall time if it scales.
import json, statistics, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor
port, n, path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
rows = [json.loads(l) for l in open(path)]
def gen(r):
    body = {"model": "x", "messages": [{"role": "user", "content": r["prompt"]}], "max_tokens": r["max_tokens"],
            "temperature": 0, "chat_template_kwargs": {"enable_thinking": False}}
    req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions", json.dumps(body).encode(), {"Content-Type": "application/json"})
    t = json.load(urllib.request.urlopen(req, timeout=900))["timings"]
    return t["predicted_per_second"], t["predicted_n"]
def client(k):
    # [Agent] Rotate the order per client so the two streams are not decoding the same prompt in lockstep.
    return [gen(r) for r in rows[k*5 % len(rows):] + rows[:k*5 % len(rows)]]
for r in rows[:3]: gen(r)
t0 = time.time()
with ThreadPoolExecutor(n) as ex: res = [x for out in ex.map(client, range(n)) for x in out]
wall = time.time() - t0
print(f"RESULT clients={n}  per-request median {statistics.median(r[0] for r in res):6.1f} tok/s  aggregate {sum(r[1] for r in res)/wall:6.1f} tok/s  ({sum(r[1] for r in res)} tokens in {wall:.0f} s)")
