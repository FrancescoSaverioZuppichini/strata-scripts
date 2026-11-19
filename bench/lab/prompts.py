# Benchmark prompts for the DFlash2 lab: several per category so no change is tuned to one text. Writes prompts.jsonl.
import json, random

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
with open("prompts.jsonl", "w") as f:
    for cat, text, n in rows:
        f.write(json.dumps({"cat": cat, "prompt": text, "max_tokens": n}) + "\n")
print(len(rows), "prompts")
