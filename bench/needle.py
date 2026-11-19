import json, random, sys, time, requests

target = int(sys.argv[1])
random.seed(7)
words = "river stone engine ledger copper window garden signal harbor lantern violet canyon meadow orbit pencil quartz summit tunnel velvet walnut".split()

# [Agent] ~1 token per word for this filler; we calibrate from the server's own count after, so the target is only approximate.
def sentence():
    return " ".join(random.choice(words) for _ in range(random.randint(8, 16))).capitalize() + "."

needles = {0.1: "The code for the blue door is 4817.", 0.5: "The captain's cat is named Pistacchio.", 0.9: "The train to Cancro leaves from platform 23."}
n_sent = target // 12
body, placed = [], sorted(needles)
for i in range(n_sent):
    while placed and i >= placed[0] * n_sent:
        body.append(needles[placed.pop(0)])
    body.append(sentence())
doc = " ".join(body)
q = "Answer three questions from the document, one line each: 1) the code for the blue door, 2) the captain's cat's name, 3) the platform for the train to Cancro."
t = time.time()
r = requests.post("http://127.0.0.1:8080/v1/chat/completions", json={
    "model": "x", "messages": [{"role": "user", "content": doc + "\n\n" + q}],
    "max_tokens": 200, "temperature": 0, "chat_template_kwargs": {"enable_thinking": False}}, timeout=7200).json()
if "choices" not in r: sys.exit(json.dumps(r)[:600])
print(json.dumps({"wall_s": round(time.time() - t, 1), "usage": r.get("usage"), "timings": r.get("timings"),
                  "answer": r["choices"][0]["message"]["content"]}, indent=1))
