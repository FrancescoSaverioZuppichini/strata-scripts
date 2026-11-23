# strata-scripts

How I run Qwen3.8-Flash-Next with strata on one RTX 3090 and 64 GB of RAM: the launch scripts, the benchmark, and the
OpenCode config to code with it. It needs strata installed with its official `install.sh` (the CLI at `~/.local/bin/strata`).

| File | What it is |
|---|---|
| `start-coder.sh` | The Coder (IQ1_M: half the experts, stored at 3.5 bits) at 512K context, int8 KV, MTP draft 3. The default for coding. |
| `start.sh` | The general model (IQ2_XS, 2-bit) at 512K context, q4_0 KV, MTP draft 3, refusals removed (`ABL=0` for the plain model). Better outside code. |
| `bench.sh` | Repeats the workstation benchmark and prints this machine's numbers next to the workstation's. |
| `configs/opencode/opencode.jsonc` | OpenCode pointed at the strata server, with both models. |

## Serve

```sh
git clone https://github.com/FrancescoSaverioZuppichini/strata-scripts && cd strata-scripts
./start-coder.sh            # or ./start.sh; serves on 127.0.0.1:8080, this machine only
strata launch --stop        # stop it
```

The first launch downloads the model: 58 GB for the Coder, 68 GB for IQ2_XS.

`start-coder.sh` removes the model's refusals by default: it subtracts a refusal direction at run time and leaves the
weights alone. That needs `abliteration/Huihui-Qwen3.8-Flash-Next-refusal-direction-r.gguf` in strata's model folder
(or `VEC=<file>`). Run `ABL=0 ./start-coder.sh` for the plain model. `KV=q4_0 ./start-coder.sh` changes the KV format.

## Benchmark

```sh
./bench.sh
```

It starts the plain Coder (int8 KV, 512K, one slot) and runs a fixed set of 10 prompts (code, prose, chat, a ~20K-token
refactor), then strata's own suite (short chat, 4K-32K prompt reading, agent turns). It stops the server when it ends
and writes everything to `results/<host>-<date>/`. The reference it prints, from the workstation (Ryzen 9 5950X,
RTX 3090 at 300 W, 64 GB DDR4-3200, strata 0.2.16):

| | tok/s |
|---|---:|
| Decode: code / prose / chat / long context | 135.5 / 104.6 / 93.9 / 131.3 |
| Decode: strata suite chat / agent turns | 102.0 / 101.5 |
| Prompt reading: 4K / 16K / 32K | 2652.6 / 3164.4 / 3209.6 |

## OpenCode

On any machine:

```sh
cp configs/opencode/opencode.jsonc ~/.config/opencode/opencode.jsonc
ssh -N -L 8080:127.0.0.1:8080 <strata-box>   # only if strata runs on another machine
opencode
```

The server only listens on its own machine, so from a laptop the `ssh` line forwards port 8080 to it. The Coder is the
default model; pick IQ2_XS in OpenCode's model list when `start.sh` is the one running. Low, medium and high reasoning
effort are there as variants. `limit.input` is set on purpose: without it OpenCode never compacts a long conversation and
runs into the 512K limit.
