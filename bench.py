#!/usr/bin/env python3
# [Agent] Benchmarks the one model served at an OpenAI-compatible endpoint and prints the result as JSON on stdout
# (progress goes to stderr). Everything is timed here from streamed answers, because some engines (vLLM) report no
# timings of their own, so two engines are always measured with the same stopwatch. Token counts come from the streamed
# usage, not from counting chunks: with speculative decoding one chunk can carry several tokens.
# Every request is the same text on every invocation, so two builds of one engine answer the same greedy text and a speed
# difference is the engine's, not the luck of a draft model on a different answer. Each request stores a hash of its answer
# to prove it. Every summary row is the median, with its min and max in "spread".
# Usage: ./bench.py [URL] [--quick] > result.json        (default http://127.0.0.1:8080)
# --quick: the fixed prompts and the 32K prompt only, a few minutes, for A/B between two builds.
import hashlib, json, random, shutil, statistics, subprocess, sys, time, urllib.request

QUICK = "--quick" in sys.argv
ARGS = [a for a in sys.argv[1:] if a != "--quick"]
URL = (ARGS[0] if ARGS else "http://127.0.0.1:8080").rstrip("/")
# [Agent] Fresh-prompt depths in the model's own tokens, with runs per depth. 230K is the deepest vLLM serves Inkling at on
# one 24 GB card that also drives a desktop (240K max context); depths past the server's max context are skipped.
DEPTHS = {"4K": 4_000, "32K": 32_000, "128K": 128_000, "230K": 230_000}
RUNS = 3
if QUICK:
    DEPTHS = {"32K": DEPTHS["32K"]}
TASK = "\nList three handlers that return ok False, then sketch in about 150 words one generic handler that replaces them all."
rng = random.Random(11)
HANDLERS = "".join(f"def handler_{i}(req):\n    return {{'id': {i}, 'path': req.path, 'ok': {rng.choice(['True', 'False'])}}}\n"
                   for i in range(700))
LAB = [
    ("code", "Write a complete Python CLI that tails an nginx access log, parses each line with a regex, and prints per-minute request counts and p95 latency. Code only.", 900),
    ("code", "Implement an LRU cache in TypeScript with get, set, delete and a max size, plus Jest tests covering eviction order. Code only.", 900),
    ("code", "Write a Rust function that parses a CSV file of (timestamp, sensor, value) rows and returns per-sensor min, max and mean, with error handling and unit tests.", 900),
    ("prose", "Explain how TCP congestion control works, covering slow start, congestion avoidance, fast retransmit and BBR, in about 900 words.", 900),
    ("prose", "Write a short story (about 700 words) about a lighthouse keeper who finds a radio that receives messages from the future.", 900),
    ("prose", "Compare PostgreSQL and MongoDB for an e-commerce backend: data modeling, transactions, scaling and operations. About 800 words.", 900),
    ("chat", "What are three good names for a grey cat? One line each.", 120),
    ("chat", "Give me a one-sentence summary of what a hash map is.", 120),
    ("chat", "Translate to Italian: 'The meeting moved to Thursday at ten.'", 120),
    ("longctx", HANDLERS + "\nRefactor these handlers into one generic handler plus a registry, and explain the change. Show the full code.", 600),
]


def log(*a):
    print(*a, file=sys.stderr, flush=True)


MODEL = json.load(urllib.request.urlopen(URL + "/v1/models", timeout=30))["data"][0]
MAX = MODEL.get("max_model_len")


def ask(messages, max_tokens):
    body = {"model": MODEL["id"], "messages": messages, "max_tokens": max_tokens, "temperature": 0, "stream": True,
            "stream_options": {"include_usage": True}, "reasoning_effort": "none",
            "chat_template_kwargs": {"enable_thinking": False}}
    req = urllib.request.Request(URL + "/v1/chat/completions", json.dumps(body).encode(), {"Content-Type": "application/json"})
    t0, first, text, usage = time.perf_counter(), None, [], {}
    with urllib.request.urlopen(req, timeout=3600) as r:
        for raw in r:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:") or line[5:].strip() == "[DONE]":
                continue
            j = json.loads(line[5:])
            for ch in j.get("choices") or []:
                d = ch.get("delta") or {}
                if first is None and (d.get("content") or d.get("reasoning") or d.get("reasoning_content")):
                    first = time.perf_counter() - t0
                text.append(d.get("content") or "")
            usage = j.get("usage") or usage
    total = time.perf_counter() - t0
    if first is None:
        raise RuntimeError(f"no tokens came back (usage {usage})")
    n, p = usage["completion_tokens"], usage["prompt_tokens"]
    cached = (usage.get("prompt_tokens_details") or {}).get("cached_tokens") or 0
    # [Agent] Only a hash of the answer is kept: enough to see that two runs gave the same text, small enough for the JSON.
    return {"prompt": p, "cached": cached, "out": n, "ttft": round(first, 3), "prefill": round((p - cached) / first, 1),
            "decode": round((n - 1) / (total - first), 1) if n > 1 else None,
            "hash": hashlib.sha256("".join(text).encode()).hexdigest()[:12]}


def code(lines, seed):
    # [Agent] Fixed-width ids keep every line the same number of tokens, so one calibration sizes every depth.
    r = random.Random(seed)
    return "".join(f"def handler_{i:05d}(req):\n    return {{'id': '{i:05d}', 'ok': {r.choice(['True', 'False'])}}}\n"
                   for i in range(lines))


def fresh(lines, seed, tag):
    # [Agent] The tag comes first and names the depth and the run, so no prompt shares a prefix with another one in the same
    # server (nothing can come from a prefix cache), yet the text is identical on every invocation.
    return [{"role": "user", "content": f"[{tag}]\n{code(lines, seed)}{TASK}"}]


def agent(seed):
    # [Agent] An agent-style session: each turn adds a file part and resends the whole conversation, as coding agents do.
    # Only the follow-up turns count, since their earlier turns can come from the engine's prefix cache. The history holds a
    # fixed reply instead of the model's own, so a build that answers differently still gets the same next prompt.
    msgs = [{"role": "system", "content": f"[agent session {seed}] You are a coding agent. Answer in two sentences."}]
    rows = []
    for turn in range(6):
        msgs.append({"role": "user", "content": f"File part {turn}:\n{code(60, seed * 10 + turn)}\nWhat does this part add?"})
        rows.append(ask(msgs, 64))
        msgs.append({"role": "assistant", "content": "This part adds more handlers that each return an id and an ok flag."})
    return rows[1:]


summary, spread = {}, {}


def put(name, values):
    summary[name] = round(statistics.median(values), 1)
    spread[name] = [round(min(values), 1), round(max(values), 1)]


log(f"{MODEL['id']} at {URL}, max context {MAX}")
ask([{"role": "user", "content": "Say hi."}], 8)
for _, prompt, n in LAB:
    ask([{"role": "user", "content": prompt}], n)
lab = {}
for rep in range(2):
    log(f"lab pass {rep + 1}/2")
    for cat, prompt, n in LAB:
        lab.setdefault(cat, []).append(ask([{"role": "user", "content": prompt}], n))
# [Agent] 16 tokens, not 1: some models (Inkling) open with a control token that never reaches the visible text.
per_line = ask(fresh(1000, 0, "calibration"), 16)["prompt"] / 1000
depth = {}
for label, tokens in DEPTHS.items():
    if MAX and tokens + 256 > MAX:
        continue
    log(f"fresh prompt {label}")
    depth[label] = [ask(fresh(int(tokens * 0.98 / per_line), run, f"{label} run {run}"), 256) for run in range(RUNS)]
sessions = []
if not QUICK:
    log("agent sessions")
    sessions = [agent(seed) for seed in range(3)]
turns = [row for session in sessions for row in session]

for cat, rows in lab.items():
    put(f"decode {cat}", [r["decode"] for r in rows])
for label, rows in depth.items():
    put(f"prefill {label}", [r["prefill"] for r in rows])
    put(f"decode @{label}", [r["decode"] for r in rows])
if turns:
    put("agent decode", [r["decode"] for r in turns])
    put("agent follow-up ttft s", [r["ttft"] for r in turns])
    # [Agent] One share over all turns, as before; its spread is across the three sessions.
    share = lambda rows: 100 * sum(r["cached"] for r in rows) / sum(r["prompt"] for r in rows)
    put("agent cached %", [share(session) for session in sessions])
    summary["agent cached %"] = round(share(turns), 1)
# [Agent] The GPU of the machine running the bench: the server's own when the endpoint is local, the usual case.
gpu = shutil.which("nvidia-smi") and subprocess.run(
    ["nvidia-smi", "--query-gpu=name,power.limit,memory.used,driver_version", "--format=csv,noheader"],
    capture_output=True, text=True).stdout.strip()
requests = {"lab": lab, "depth": depth, "agent": turns}
print(json.dumps({"url": URL, "model": MODEL["id"], "max_context": MAX, "gpu": gpu, "date": time.strftime("%Y-%m-%d %H:%M"),
                  "quick": QUICK, "summary": summary, "spread": spread, "requests": requests}, indent=1))
