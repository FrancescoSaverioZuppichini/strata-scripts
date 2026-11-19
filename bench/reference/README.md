# Community benchmark on NVIDIA GeForce RTX 3090

Measured on 2026-11-19 with `tools/strata_bench.py` (suite 1, 3 runs per test, medians with ranges). Speeds are the engine's own timings; first-token times are measured by the client over HTTP. Speed only: no correctness check was run.

## Hardware and software

- GPU and VRAM: NVIDIA GeForce RTX 3090, 24 GiB VRAM
- CPU: AMD Ryzen 9 5950X 16-Core Processor (16 cores, 32 threads); installed RAM: 62.7 GiB; storage: sda     ST4000VN008-2DR166             sata; sdb     Samsung SSD 870 QVO 2TB        sata; sdc     INTEL SSDSA2BZ300G3            sata; nvme1n1 Samsung SSD 970 EVO Plus 500GB nvme; nvme0n1 WD_BLACK SN770 2TB             nvme
- OS: Linux 6.8.0-149-generic; GPU driver: 595.99.02; CUDA (driver supports up to): 13.2
- Strata: project ?, commit not a git checkout; engine 0.1.62
- GPU detail (after the run, near idle): power_limit_w=300.00, power_draw_w=246.34, pcie=gen4 x16, pstate=P2, temp_c=69
- Background workloads: not recorded (GPU power limit/draw read above)

## Model and configuration

- Model and quantization: qwen3.8-flash-next-coder-iq1_m
- Context: 524288 tokens; parallel slots: 1
- Settings: the install's own configuration, unchanged; thinking off for the suite; temperature 0

## Method

Run by `python tools/strata_bench.py --long` against the HTTP API of a Strata server (already running); model loading is not timed. One warm-up chat and a 1K prompt are discarded first. Every prompt starts with a unique tag, so the conversation cache cannot help the fresh-prompt tests.

- short chat: the three questions of `tools/ab_engine.py`, up to 100 new tokens, 3 runs
- 4K / 16K prompts: generated word lists sized by a calibration request, 24 new tokens, 3 fresh prompts each
- agent session: system prompt and four tools, then 5 turns that each add about 1500 words of a project file and continue from the model's own earlier answers (the way agent clients resend a conversation), 64 new tokens per turn, 3 sessions; the cache numbers come from the answer's usage (`cached_tokens`) and timings (`prompt_n`)
- concurrency (when run): N requests sent at the same moment, total tokens over the wall time of the burst, latency over all requests

## Results

| Configuration | Actual prompt tokens | Reused tokens | Generated tokens | Runs | Prompt tok/s median and range | Decode tok/s median and range | TTFT seconds median and range |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| short chat | 46 (43-51) | 0 | 100 (100-100) | 9 | not measured | 102.0 (93.4-122.1) | 0.38 (0.35-0.48) |
| 4K prompt, fresh | 4019 (4019-4019) | 0 (0-0) | 24 cap | 3 | 2652.6 (2514.4-2672.7) | not measured | 1.54 (1.52-1.62) |
| 16K prompt, fresh | 16058 (16058-16058) | 0 (0-0) | 24 cap | 3 | 3164.4 (3085.5-3168.3) | not measured | 5.10 (5.10-5.24) |
| 32K prompt, fresh | 32049 (32049-32049) | 0 (0-0) | 24 cap | 3 | 3209.6 (3136.5-3218.4) | not measured | 10.02 (9.99-10.25) |
| agent session, follow-up turns | 9005 (8969-9020) at the last turn | see below | up to 64 | 3 | see below | 101.5 (31.5-127.4) | 0.79 (0.76-0.81) |

Ranges are the lowest and highest of the runs; `Runs` counts requests that returned a token.

### Agent session (conversation cache)

Cache hit over the follow-up turns: 71.0 % (70.9-71.0); earlier-turn tokens read again per session: 5 (5-5) (earlier turns that the cache did not hold; the 8206 (8206-8206) new tokens of the files are read once); first turn (nothing cached) first token: 0.90 s (0.77-1.00).

| Turn (run 1) | Prompt tokens | Reused | Read | Prompt tok/s | First token (s) | Decode tok/s |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 609 | 0 | 609 | 814.2 | 0.767 | 103.9 |
| 1 | 2272 | 630 | 1642 | 2149.2 | 0.784 | 106.1 |
| 2 | 3978 | 2335 | 1643 | 2110.2 | 0.799 | 110.4 |
| 3 | 5656 | 4014 | 1642 | 2136.4 | 0.789 | 93.6 |
| 4 | 7325 | 5683 | 1642 | 2113.3 | 0.798 | 31.5 |
| 5 | 8969 | 7327 | 1642 | 2112.2 | 0.799 | 94.5 |

Per-request data: `results.json`. Engine log lines from the start: `engine-log-excerpt.txt` (when this run started the server).

## Correctness and limitations

Not measured: this is a speed suite. The conversation uses the model's own replies, so token counts differ a little between runs. Machine details come from the server, `nvidia-smi`/`rocm-smi` and the OS; background load is not recorded. Total time of the suite: 87 s.
