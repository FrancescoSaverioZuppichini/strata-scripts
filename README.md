# strata-scripts

How I run Qwen3.8-Flash-Next with strata on one RTX 3090 and 64 GB of RAM: the launch scripts, the benchmark, and the
OpenCode config to code with it. It needs strata installed with its official `install.sh` (the CLI at `~/.local/bin/strata`).

| File | What it is |
|---|---|
| `start.sh` | Serves the Coder (IQ1_M: half the experts, stored at 3.5 bits) at 512K context, int8 KV, MTP draft 3, refusals removed. Any strata launch flag overrides it, e.g. `--model iq2_xs --kv q4_0` for the general model. |
| `bench.py` | Benchmarks the model served at an endpoint (strata, vLLM, any OpenAI-compatible server) and prints JSON. |
| `configs/opencode/opencode.jsonc` | OpenCode pointed at the strata server, with both models. |

## Serve

```sh
git clone https://github.com/FrancescoSaverioZuppichini/strata-scripts && cd strata-scripts
./start.sh                                # the Coder, on 127.0.0.1:8080, this machine only
./start.sh --model iq2_xs --kv q4_0        # the general model (2-bit, better outside code)
strata launch --stop                      # stop it
```

The first launch downloads the model: 58 GB for the Coder, 68 GB for IQ2_XS. Arguments are `strata launch` flags and
override the script's, so `--plan` shows the plan without starting.

`start.sh` removes the model's refusals by default: it subtracts a refusal direction at run time and leaves the
weights alone. That needs `abliteration/Huihui-Qwen3.8-Flash-Next-refusal-direction-r.gguf` in strata's model folder
(or `VEC=<file>`). Run `ABL=0 ./start.sh` for the plain model.

## Benchmark

```sh
ABL=0 ./start.sh                            # the plain Coder; or start any other OpenAI-compatible server
./bench.py > coder.json                     # default http://127.0.0.1:8080, or ./bench.py http://host:port
```

One run benchmarks the one model at that endpoint. It times everything itself from streamed answers, so every engine
gets the same stopwatch, including engines that report no timings of their own (vLLM):

- decode on 10 fixed prompts (code, prose, chat, a ~20K-token refactor), one warm-up pass and two measured;
- prompt reading and decode on fresh 4K / 32K / 128K / 230K-token prompts, 3 runs each (skipped past the server's max context);
- agent turns: a conversation that grows by a file part per turn and is resent each time, as coding agents do.

Every invocation sends exactly the same text, so two builds of one engine generate the same greedy answers and a speed
difference is the engine's. With speculative decoding the decode speed depends on how many drafts the answer accepts, so a
different question each run (the old random tags) swung the deep rows by +-20%. Each deep prompt still starts with its own
tag (depth and run), so nothing in one server is served from a prefix cache.

It prints one JSON: `summary` with the medians, `spread` with `[min, max]` for the same keys, and every request with its
token counts, timings and `hash`, a short hash of the answer. Two runs of one engine, or two builds, gave identical
outputs when the hashes match; compare speeds only then.

```sh
./bench.py --quick > quick.json             # the fixed prompts and 32K only, a few minutes, for A/B between two builds
```

## OpenCode

On any machine:

```sh
cp configs/opencode/opencode.jsonc ~/.config/opencode/opencode.jsonc
ssh -N -L 8080:127.0.0.1:8080 <strata-box>   # only if strata runs on another machine
opencode
```

The server only listens on its own machine, so from a laptop the `ssh` line forwards port 8080 to it. The Coder is the
default model; pick IQ2_XS in OpenCode's model list when that one is running. Low, medium and high reasoning
effort are there as variants. `limit.input` is set on purpose: without it OpenCode never compacts a long conversation and
runs into the 512K limit.
