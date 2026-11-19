import random, sys
sys.path.insert(0, "/media/zuppif/Cancro/strata/terminal/current/tools")
from strata_tokenizer import Tokenizer

tk = Tokenizer.from_gguf("/media/zuppif/Cancro/strata/models/models/IQ2_XS/Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00001-of-00002.gguf")
out = sys.argv[1]

# [Agent] Same non-thinking chat framing the server renders with enable_thinking=false, so CLI tok/s matches what the API would see.
def chat(p):
    return tk.encode("<|im_start|>user\n" + p + "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n", parse_special=True)

random.seed(3)
lines = [f"def handler_{i}(req):\n    return {{'id': {i}, 'path': req.path, 'ok': {random.choice(['True', 'False'])}}}\n" for i in range(1400)]
prompts = {
    "code": "Write a complete Python CLI that tails an nginx access log, parses each line with a regex, and prints per-minute request counts and p95 latency. Code only.",
    "prose": "Explain how TCP congestion control works, covering slow start, congestion avoidance, fast retransmit and BBR, in about 900 words.",
    "ctx32k": "".join(lines) + "\nRefactor these handlers into one generic handler plus a registry, and explain the change. Show the full code.",
}
for name, p in prompts.items():
    ids = chat(p)
    open(f"{out}/{name}.tok", "w").write(",".join(map(str, ids)))
    print(name, len(ids))
