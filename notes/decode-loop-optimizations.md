# Decode-Loop Optimizations: What Production Engines Do That We Are Missing

Target: RTX 3050 8GB (GA106-150, **20 SMs**, 128-bit GDDR6, **224 GB/s** spec, ~180 GB/s
STREAM-reachable, **PCIe 4.0 x8** ≈ 14–16 GB/s). Model: 4B Q4_K_M, 3.6 GiB packed,
~1.1 GiB spilled to system RAM. Current: 18 tok/s (55.6 ms/step).

---

## 0. TL;DR — ranked by expected return

| # | Action | Expected | Cost | Why now |
|---|---|---|---|---|
| 1 | **Split-KV attention decode** (fixed split count, device-side work queue) | 50 ms → 2–6 ms | M | Attention is **38x off the bandwidth roofline**. Nothing else matters until this is fixed. |
| 2 | **CUDA Graph the decode step** (`FULL_DECODE_ONLY` mode) | 0 → +60% if CPU-bound; ~0 if GPU-bound | S–M | Only pays if we're host-bound. **Measure first** (§5.1). |
| 3 | **Eliminate the per-step PCIe spill** or double-buffer it | up to −84 ms | M | 1.1 GiB over PCIe = 84 ms/step. Either it's not per-step, or it's our real ceiling. |
| 4 | Fuse residual+RMSNorm+proj, SwiGLU, RoPE+KV-write | +1–3% | S | **Low ROI at batch 1** — these vectors are 6 KB, so it's a launch problem, not a bandwidth problem. Graph it instead (#2). |
| 5 | Stream overlap (Q4) | **~0** | — | Weight streaming and attention are both bandwidth-bound *and* dependent. No win. |
| 6 | Megakernel | +6–45% *after* #1–#2 | XL | Amortizes fixed per-tile sync across all layers. Only worth it once nothing bigger is left. |

**The headline finding: the weight GEMV is nearly optimal; the attention is catastrophically
broken. We are optimizing the wrong phase.**

---

## 1. The arithmetic that reframes the problem

Hardware floor: 224 GB/s spec, realistically ~180 GB/s (STREAM hits ~80–85% of rated; a
decode GEMV is a *worse* access pattern than STREAM because it also reads quantization scales
on a different stride — [ZINC, RX 9070 XT](https://zolotukhin.ai/blog/2026-07-15-weight-streaming-is-under-half-of-an-rdna4-decode-token)).

### Weight GEMV: 18 ms — this is close to done

| Hypothesis | Implied BW | % of 224 spec | % of 180 realistic |
|---|---|---|---|
| 2.5 GiB resident in VRAM (matches "1.1 GiB spilled") | 149 GB/s | 67% | **83%** |
| 3.6 GiB all in VRAM | 215 GB/s | 96% | **119% — physically impossible** |

Since 119% of a realistic ceiling is not achievable, **~2.5 GiB is what actually streams per
step**, and we're at ~83% of realistic peak. Remaining headroom: **≤20%**. Compare
[L40S measurements](https://github.com/RightNow-AI/local-kimi/blob/main/engine/OPTIMIZATION-LIMITS.md),
where a good W4A16 GEMV hits 36% of peak and the bf16 vocab head hits 84% — our 83% is already
at the top of the published range. **Do not spend effort here.**

### Attention: 50 ms — this is 38x off the roofline

4B model, 28 layers, 8 KV heads, head_dim 128, fp16 KV → **112 KiB of KV per context token**.

| Context | True KV | Roofline @180 GB/s | ×4 naive GQA expand | **Measured 50 ms** | Read amplification |
|---|---|---|---|---|---|
| 512 | 58.7 MB | 0.33 ms | 1.3 ms | 50 ms | **153x** |
| 2048 | 234.9 MB | 1.30 ms | 5.2 ms | 50 ms | **38x** |
| 8192 | 939.5 MB | 5.22 ms | 20.9 ms | 50 ms | **9.6x** |

At full bandwidth, 50 ms buys 9.00 GB of reads. If our context is ~2048, we are moving **38x more
bytes than the cache contains**. Solve for your actual number: `amp = (180e9 × 0.050) / (112·1024 × ctx)`.

If our real context is ~78k tokens, there is no bug — 50 ms would be correct. **Verify this first.**
Otherwise we are re-reading the KV cache ~38 times per step, which is a correctness-level
inefficiency, not a tuning problem.

### Occupancy: 8 blocks on 20 SMs

| Heads × split | Blocks | Waves (÷20) | Efficiency |
|---|---|---|---|
| 8 × 1 (**what we likely do now**) | 8 | 0.40 | **40%** |
| 8 × 2 | 16 | 0.80 | 80% |
| **8 × 5** | 40 | 2.00 | **100%** |
| 8 × 8 | 64 | 3.20 | 80% |

This is *exactly* the documented FlashAttention-3 occupancy collapse. FA3's dispatch heuristic
returns `s=1` when `L_K ≤ 512`, assuming split overhead dominates — on an H100 that means
**8 CTAs, 6% of 132 SMs idle**. On our 20-SM card the same bug is 8/20 = 40%. Overriding that
guard with a sequence-aware split recovers **21–24% on the attention kernel alone**
([arXiv:2604.00028](https://arxiv.org/pdf/2604.00028)).

With GQA, worse: a KV head's data should be loaded once and reused across all query heads in its
group. The naive per-q-head split re-reads each KV head 4x
([SharpInference #235](https://github.com/pekkah/SharpInference/issues/235)).

### The spill, unexamined

**1.1 GiB over PCIe 4.0 x8 = 84 ms per pass.** Our entire step budget is 55.6 ms. Either:

- the spilled 1.1 GiB is *not* touched every step (it is touched once — e.g. embeddings or a
  permanently-CPU-resident tail), **or**
- we are already 84 ms deep and the "18 tok/s" figure is measuring something else.

**Resolve this before anything else.** If the spill is per-step, it is a 1.5x ceiling on our
entire engine and every other optimization is noise. If it is a one-time touch, we should
**lock those tensors to VRAM and stop worrying about it.**

### An inconsistency in our own numbers

18 ms (weights) + 50 ms (attention) = **68 ms**, but 18 tok/s implies **55.6 ms/step**. The
numbers cannot both be steady-state. Most likely: the 50 ms attention figure was measured under
a different (colder / longer-context / non-graphed) condition, or the tok/s number predates the
GQA fix. **Re-profile all three numbers in the same process before acting on any of them.**

---

## 2. CUDA Graphs — mechanism, constraints, what breaks

### Mechanism

Three stages ([CUDA Programming Guide §4.2](https://docs.nvidia.com/cuda/cuda-programming-guide/04-special-topics/cuda-graphs.html)):

1. **Definition** — build a `cudaGraph_t` describing ops and their dependencies.
2. **Instantiation** — `cudaGraphInstantiate` snapshots, validates, and does all setup work.
   This is where the per-launch cost is paid.
3. **Execution** — `cudaGraphLaunch` on an already-instantiated graph.

PyTorch wraps **stream capture** only: `torch.cuda.graph(g)` does
`cudaStreamBeginCapture` → run your model (recording, not executing) → `cudaStreamEndCapture` →
instantiate. Then `static_input.copy_(new_data); g.replay()` per step.

The win is that per-kernel host work — parameter validation, kernel selection, memory
preparation — happens once at instantiation and is reused on every replay.

### The number that matters (Ampere+)

| | CPU cost per launch |
|---|---|
| Per-kernel stream launch | 2 μs + **200 ns/node** |
| **Graph repeat-launch, straight-line, ≥10 nodes** | **2.5 μs + ~1 ns/node** |

CUDA 11.8 → 12.6 cut first-launch CPU overhead by up to 66% for long graphs, instantiation by
40%, and repeat-launch *device* runtime by ~15%
([NVIDIA: Constant Time Launch](https://developer.nvidia.com/blog/constant-time-launch-for-straight-line-cuda-graphs-and-other-performance-enhancements/)).
So on 20 SMs, per-node host cost is **~0.1 ns-scale, effectively free** — a 400-node graph
costs about what one kernel launch costs.

Independent measurement ([hezhiqian01/cudagraphlaunch](https://github.com/hezhiqian01/cudagraphlaunch)):
graph ≈ 3.4 μs + 0.08 μs/node vs node ≈ 4.9 μs + 0.80 μs/node; idle-GPU→first-kernel latency is
~10 μs for a graph vs ~6–8 μs for a single kernel.

### What breaks it

| Constraint | Our exposure |
|---|---|
| **Static shapes** | **Worst one.** KV length grows every step. |
| Static addresses | Solved by a static input buffer + `copy_()` |
| No CPU↔GPU sync in captured region | `.item()`, `torch.any()`, host-side `if` on tensor values, `nonzero()` all break it. Megatron requires `--no-check-for-nan-in-loss-and-grad` for exactly this. |
| No dynamic allocation | PyTorch uses a private graph memory pool; keep it separate |
| Triton autotune | Autotune benchmarks at runtime = CPU sync. Resolve/autotune **before** capture. |
| **Split-KV count varying with seq_len** | **Silent correctness bomb** — see below |

**The static-shape fix is the whole trick:** make sequence length a *value on the device*, never
a *host-side shape decision*. FlashInfer's `plan()` fixes `max_kv_len` as a static bound and
passes per-run `seq_lens` as a **CUDA tensor**; the kernel reads lengths on-device. One graph then
serves every context length. Same for vLLM: it pads batches to a captured `batch_descriptor` and
lets the *backend* see the real length from device memory.

### The split-KV trap (this will bite us)

From the [FlashInfer API docs](https://docs.flashinfer.ai/api/attention.html), on
`fixed_split_size` / `disable_split_kv`:

> "…will lead to deterministic softmax score reduction in the merge_states kernel, and therefore
> batch-size invariant outputs. **Note that compatibility with CUDA graph is NOT guaranteed, as
> even when bs is fixed, kv seq len can change and lead to a varied number of launched CTAs.**"

If we implement split-KV with a **host-computed** split count, then seq_len changes → split count
changes → grid changes → graph invalid, and we also silently lose determinism. **We must use a
FIXED split count with a device-side work queue** (FlashInfer's scheduler: priority queue,
sort splits by length, CTAs pull work — [arXiv:2501.01005](https://arxiv.org/html/2501.01005),
Fig. 6). Fixed count, device-side compaction. This satisfies both graphs and determinism.

### Which mode: use vLLM's `FULL_DECODE_ONLY`

vLLM documents the exact problem:
> "Many attention backends also weren't ready for unified 'full' CUDA Graphs capture (e.g., only
> FlashAttention 3 supports it currently) or **only support CUDA Graphs for pure decode batches**
> (e.g., Flashinfer, FlashMLA, and Mamba, etc.)."

Its modes ([vLLM CUDA Graphs design](https://docs.vllm.ai/en/stable/design/cuda_graphs/)):

- `PIECEWISE` — attention stays eager, everything else graphed. Flexible, some win.
- `FULL` — whole model graphed; **requires the attention backend to support capture.**
- **`FULL_DECODE_ONLY` — graph pure decode only, prefill eager. "Suitable for decode instances in
  a P/D setup where prefill is not as important."** ← **This is our mode.** Batch-1 local engine,
  prefill is a one-off; we want zero memory overhead from graph pools.
- `FULL_AND_PIECEWISE` — most performant, most memory, longest capture. Overkill for us.

**Caveat:** if we ever want to fuse attention *quantization* into the graph, vLLM notes that
`AttnQuantFusionPass` and `SequenceParallelismPass` need whole-graph visibility and force
`splitting_ops=[]`, disabling piecewise. Plan for `FULL_DECODE_ONLY` and accept eager prefill.

### Realistic win on our hardware — and why it may be zero

**Graphs eliminate host overhead. They do not eliminate device-side work.** The NVIDIA fusion
blog is explicit:

> "Kernels inside a graph run separately and pass intermediate results through global memory.
> Wrapping a naive baseline in a graph shaves microseconds off the host side, but the one GiB
> round-trip through the intermediate buffer remains unchanged."

On 20 SMs, graphs also do **not** fix wave quantization — each kernel still drains before the
next starts. A kernel with 8 blocks on 20 SMs is still 40% efficient inside a graph. The GraCE
paper (OSDI'26) measured a captured graph executing in 75 μs where the kernel alone took 70 μs —
**7% overhead, and 0% of the underlying stall removed.**

So the win is entirely conditional:

> **CUDA graphs are worth ~0% if we are GPU-bound and worth 2–4x if we are CPU-bound.**

The test is 10 minutes of work (§5.1). Do it before writing any graph code.

---

## 3. Fusing the layer

### What production engines actually fuse

| Fusion | Where it's real | Our ROI at batch 1 |
|---|---|---|
| **Residual add + RMSNorm + next projection** | vLLM `reduce_norm` (fuses ResidualAdd+LayerNorm post-AllReduce, "recommended when batch size is small and the generation phase is dominant"); per-sublayer RMSNorm folded into the fused epilogue | **Low** |
| **SwiGLU as one kernel** | TRT-LLM fused GEMM-SwiGLU; standard practice | **Low** |
| **RoPE + KV-cache write** | vLLM PR #45798: DeepSeek-R1 61 MLA layers — "reduces **976 kernel launches to 488 per decode step**", `k_pe` stays in registers, eliminates an HBM round-trip | **Medium** — halves launches |
| **QK-Norm + RoPE + cache + quant** | vLLM PR #38621 | **Medium** |
| **Attention as FlashAttention** | The big one — see below | **Critical** |
| **Dequant fused into GEMM main loop** | Mandatory for W4 | Verify we're doing this |

### Why fusion is LOW ROI for us specifically — and graphs are high ROI

This is the non-obvious finding. At batch 1, the vectors involved are tiny:

- hidden state: 1 × 3072 × 2 B = **6 KB**
- A fused RMSNorm reads 6 KB and writes 6 KB = **12 KB**
- At 180 GB/s that is **68 nanoseconds**
- The kernel takes **~2–3 μs**, of which ~2 μs is launch overhead

**So a norm kernel is ~97% pure overhead.** Fusing it into a neighbor saves essentially zero
bandwidth — it only saves a launch. And **CUDA graphs save the launch for free, without
rewriting a single kernel.** Same for RoPE, residual, SwiGLU.

Published confirmation: fusing residual+RMSNorm+QKV in one Triton kernel gave **+1.4% at B=1** on
Llama-3-8B/A10G — and *lost to* `torch.compile(mode='max-autotune')` by 12.8% at B=1
([fused-triton-rmsnorm-residual-qkv](https://github.com/varad-more/fused-triton-rmsnorm-residual-qkv)).
Isolated microbenchmarks: RMSNorm ~3.3x, SwiGLU ~1.68x, RoPE ~5x — but all of these are versus
*naive PyTorch*, versus an already-fused kernel the win is near zero.

Contrast with the megakernel literature: of ~280 launches per token on H100, **158 are small
RMSNorm/RoPE/KV-store kernels accounting for ~one-fifth of per-token latency**
([ForgeMegakernel, arXiv:2609.12379](https://arxiv.org/pdf/2609.12379)). Fusing them is worth
~20%. **CUDA graphs capture that ~20% for a fraction of the effort** — do graphs first, and
revisit fusion only for whatever the graph can't cover.

### What FlashAttention-style fusion buys, and Triton feasibility

FlashAttention's fusion (online softmax, K/V never leave SMEM, no `[N,N]` materialization) is
worth **orders of magnitude** and is not optional. But FA2's outer loop over query tiles
**collapses to a single iteration at decode** (M=1), which is exactly the occupancy problem in
§1. FlashDecoding adds the missing parallel dimension — the KV sequence length
([Stanford CRFM](https://crfm.stanford.edu/2023/10/12/flashdecoding.html)):

1. Split K/V into chunks — free, they're views.
2. Run FlashAttention per chunk in parallel, writing one extra scalar per row: the LSE.
3. Reduce across chunks using LSE to rescale. Softmax is associative when carrying (max, sum-exp),
   so this is exact, not approximate.

Crossover: FlashAttention is fine when `B × H ≥ numSMs`. Below that, FlashDecoding wins.
**On 20 SMs with 8 KV heads at batch 1, `B×H = 8 < 20` — we are 2.5x below the crossover, so we
need FlashDecoding, and we need it with GQA-aware KV loading** (load each KV head once, reuse
across its 4 query heads).

**Triton is sufficient for all of this.** Triton gives you: `tl.dot` for the QK/AV matmuls,
fp32 accumulators, explicit SMEM staging, `tl.atomic_add` for split-K, and constexpr specialization
for prefill/decode dispatch. You do **not** need CUDA for split-KV decode attention. FlashInfer's
own decode backends include Triton, and its scheduler is a device-side priority queue that Triton
can express. Use FlashInfer (plan/run split is graph-compatible by design) or write it in Triton;
only reach for CUDA if you're chasing the last 10%.

### Megakernel — the endgame, not the start

A megakernel runs the entire decode step in one persistent cooperative launch
(one `cudaLaunchCooperativeKernel`, one block per SM). Three separate stalls removed, in
descending order of impact:

1. **Wave quantization** — 200 tiles on 132 SMs runs two waves to do 1.5 waves of work, and
   *the smaller the kernel, the worse the rounding*. Inside a megakernel there is no boundary to
   round up to: a tile whose inputs are ready starts on whichever SM is free. **On 20 SMs this
   effect is roughly 1.6x worse than on 132 SMs** — this is the single biggest reason a megakernel
   is relatively *more* attractive for us.
2. **Full-grid barrier** at each kernel boundary.
3. **Idle SMs** left by each boundary.

Measured results and, importantly, the failure mode:
- ForgeMegakernel: 50.5–85.9% MBU, 1.21x over SGLang, 1.54x over a megakernel compiler.
  Per-step vs per-kernel: **1.06–1.45x**, i.e. launch removal alone is modest.
- AutoMegaKernel, the honest comparison
  ([GitHub](https://github.com/RightNow-AI/AutoMegaKernel)): int8 megakernel beats
  CUDA-graphed cuBLAS bf16 by **1.18–1.33x on L4, 1.25–1.27x on L40S, 1.19–1.23x on RTX 5090**,
  but **loses 0.79x → 0.55x on A100/H100**. "What governs the win is the inference-class vs.
  training-class regime, not bandwidth ordering."
- **The critical caveat for us:** on the *like-for-like bf16 path* AMK trails cuBLAS —
  ~1.38 ms/token vs CUDA-graphed cuBLAS, and its optimized bf16 GEMV sustains 451 GB/s =
  **~51% of spec / ~63% of measured HBM peak, versus a cuBLAS ceiling of ~90%**. Its int8 win came
  from *reading fewer bytes*, not from a better kernel. It also has a fixed per-tile cross-SM sync
  that larger GEMV-dominated models amortize over.

Read together: a megakernel costs you ~10-20% of your GEMV efficiency to buy back launch and wave
stalls. Since our GEMV is at **83% of realistic peak** (top of the published range), **we would be
paying the expensive side of that trade.** Only after #1–#3.

---

## 4. Batched prefill vs decode — and why one kernel can't do both

### The shape difference

For M×K @ K×N with fp16: `FLOPs ≈ 2MKN`, `bytes ≈ (MK + KN + MN)·2`, intensity = FLOPs/bytes.

| Phase | M | K, N | Intensity | Regime |
|---|---|---|---|---|
| Prefill | 256–32k+ (prompt len) | ~8192 | **~1300 FLOP/B** | compute-bound, tensor cores |
| Decode | **1** | ~8192 | **~1 FLOP/B** | memory-bound, idle tensor cores |
| Spec-decode k=8 | 8 | ~8192 | ~8 FLOP/B | still memory-bound |

Machine balance `I_ridge = P_peak / BW`: H100 fp16 ≈ 148, A100 ≈ 153, MI300X ≈ 245 FLOP/byte.
Decode sits **~two orders of magnitude below the ridge** — idle tensor cores during decode are
*correct*, not a bug. Chase bandwidth, not FLOPs.

### Why a kernel tuned for one is bad at the other

- **Prefill tiles (BLOCK_M=128–256):** at M=1, 127/128 of the MMA's M dimension is idle, and the
  grid is `ceil(N/BLOCK_N)` blocks — on 20 SMs that is 1–3 blocks. **Undersubscribed by ~10x.**
- **Decode tiles (BLOCK_M=16, split-K):** at M=2048 the grid explodes to thousands of blocks and
  each block's split-K reduction + fp32 workspace becomes pure overhead. Prefill at
  BLOCK_M=16 wastes 16x the tensor-core width.

Two hard rules from
[tensormux kernel-skills](https://github.com/tensormux/kernel-skills/blob/master/skills/inference/optimize-prefill-vs-decode-kernels/SKILL.md):

- `BLOCK_M < 16` saves nothing — MMA fragments are 16×8×16 minimum on Ampere/Hopper; the compiler
  pads. **Use BLOCK_M=16 at M=1 and stop optimizing it.**
- Split factor `S = ceil(numSMs × blocks_per_SM_target / (M_blocks × N_blocks))`, target grid
  `≥ numSMs × 2–4` (= **40–80 blocks on our 20 SMs**), and clamp so each split still covers
  **≥512–1024 K elements** or the reduction dominates. For attention, **split along the KV axis,
  never along M** (M=1 by definition).

### The standard way to write one set of kernels

Not one kernel — **one codebase, two specializations**, dispatched on a shape predicate:

- Keep separate `constexpr`-specialized paths for `IS_DECODE` (M small) and prefill.
- Split the math into device functions; only the launch config and grid differ.
- FlashInfer's answer is a **`plan()` / `run()` split**: `plan()` fixes batch size, geometry, dtypes
  and `max_kv_len` (all host-known, all static — **capture the plan, replay the run**), while
  `run()` takes per-request `seq_lens` as device tensors. This is exactly the shape-static /
  value-dynamic pattern §2 needs, and it comes free.
- `use_cuda_graph=True` in the FlashInfer wrapper requires you to supply the metadata buffers
  *outside* the wrapper, and "manual CUDA graph capture binds to one completed plan; recapture
  after re-planning."

**For us specifically:** batch is fixed at 1 forever, so this is the *easy* case. One plan per
context bucket, or one plan with a generous `max_kv_len` and device-side lengths. Prefill and
decode get separate graphs (hence `FULL_DECODE_ONLY`).

**Scheduler note:** chunked prefill ([Sarathi, arXiv:2403.02310](https://arxiv.org/pdf/2403.02310))
is a *throughput* optimization for concurrent serving. **We have one user and one sequence — it
buys us nothing.** Don't implement it. P/D disaggregation likewise.

---

## 5. Small-kernel overhead — the numbers, and the test

### Measured cost per kernel

| Source | Per-launch host cost |
|---|---|
| [GraCE, OSDI'26](https://www.usenix.org/system/files/osdi26-ghosh.pdf) | **5–10 μs** per CPU-launched kernel |
| [TensorRT perf guide](https://docs.nvidia.com/deeplearning/tensorrt/latest/performance/optimization.html) | **5–15 μs** of host time; "that launch overhead can exceed the actual GPU work and become the bottleneck" |
| [NVIDIA CUDA Graph best practices](https://docs.nvidia.com/dl-cuda-graph/cuda-graph-basics/cuda-graph.html) | **20–200 μs** "typically per operation in Deep Learning applications" (framework-level) |
| [Tsukuba ICPP'19](https://www.hpcs.cs.tsukuba.ac.jp/icpp2019/data/posters/Poster17-abst.pdf) | CPU launch overhead *is* the dominant source of added latency, and it's ≈ the per-kernel added latency |
| Graph replay (Ampere+, ≥10 nodes) | **2.5 μs + ~1 ns/node** — effectively free |

The 5–10 μs figure is C-level launch. In a **hand-written Python forward loop** the real number
is framework dispatch: **20–200 μs**. That 4–40x gap is the whole game.

### Crossover: when does launch overhead dominate?

Host-bound when `Σ kernel GPU time < N × per-op host cost`.

For a 4B at 20 SMs, a decode step is ~370–400 ops (28 layers × ~13 ops, plus embedding, final
norm, lm_head, sampling).

| Per-op host cost | 385 ops → host time | vs 55.6 ms budget |
|---|---|---|
| 5 μs (raw CUDA) | 1.9 ms | 3% — **GPU-bound, graphs buy ~0** |
| 15 μs (TensorRT upper) | 5.8 ms | 10% — marginal |
| 30 μs (PyTorch eager, typical) | 11.6 ms | 21% — **graphs help** |
| 50 μs (Python loop + autograd + dispatch) | 19.3 ms | 35% — **graphs help a lot** |
| 200 μs (NVIDIA's DL-app upper) | 77 ms | **exceeds budget — fully host-bound** |

So: **if our per-op cost is >145 μs we are entirely host-bound; below ~30 μs graphs are nearly
worthless.** A hand-written Python-level forward loop with many small ops plausibly lands in the
50–200 μs band — which would mean graphs are our *single largest* remaining win, larger than all
of §3.

Reference case: DALL·E 2 at batch 1 issued **740 kernels totalling 3.4 ms of GPU time but 14 ms
end-to-end — 75% of latency was CPU launch delay** (GraCE).

### 5.1 The 10-minute test that decides everything

1. `torch.cuda.synchronize()`; `t0 = time.perf_counter()`
2. Run the full decode step **without** syncing
3. `t_cpu = time.perf_counter() - t0`   ← CPU time to *issue* the step
4. `torch.cuda.synchronize()`; `t_wall = time.perf_counter() - t0`

- **`t_cpu ≈ t_wall`** → host-bound. **CUDA graphs is the top priority.** Expect 2–4x.
- **`t_cpu ≪ t_wall`** → GPU-bound. **Graphs are worth ~0%.** Go fix attention occupancy (§1)
  and the PCIe spill. Stop reading about graphs.

Also record: `Σ GPU kernel time` from Nsight Systems vs `t_wall`. The gap is launch bubbles; the
gap between `Σ GPU` and the bandwidth roofline is wasted bandwidth. These are different bugs with
different fixes, and conflating them is how a 4x opportunity gets missed.

### What engines do once they know

1. **CUDA Graph** the step (`FULL_DECODE_ONLY` for us) — removes host dispatch entirely.
2. **Fuse** the ~50% of kernels that are pure overhead (norms, RoPE, residual, SwiGLU) — the
   launch-and-drain path.
3. **Megakernel** to kill wave quantization and the inter-kernel barrier — the endgame.
4. Keep the graph pool separate from the eager pool so prefill and decode don't fight
   (PyTorch's `make_graphed_callables` even refuses to capture under `autocast` with cache on).

Note the ordering trap: PyTorch's `mode='max-autotune'` **enables CUDA graphs by default** and
can throw `CUDAGraph overwrite` errors inside HF `generate()`'s KV-cache update — a known gap. If
we go the `torch.compile` route, use `max-autotune-no-cudagraphs` and graph manually.

---

## 6. Scheduling and overlap — the honest answer is "no win here"

**Do engines overlap weight streaming of one token with attention compute? Not within a layer.**

Reason: attention for layer N depends on layer N's QKV projection, and layer N+1's weight
streaming depends on layer N's full output. The dependency chain is strictly serial. And both
operations are **bandwidth-bound on the same bus** — running a bandwidth-bound op concurrently
with another bandwidth-bound op on one memory system yields ~0. TensorRT documents this directly:
"Concurrent streams share SMs, register files, L2, and DRAM bandwidth, so kernels TensorRT picked
while profiling against a fully available GPU may no longer be optimal at runtime."

**The measured benefit is zero. Do not spend time here.**

The three forms of overlap that *do* pay, in the order we should care:

1. **PCIe ↔ VRAM double-buffering — the only one that matters for us.** Prefetch layer N+1's
   weights over PCIe on a copy stream while layer N computes. This is the *entire* 84 ms
   question from §1: if the 1.1 GiB spill is per-step, overlapping hides it behind the 55 ms of
   compute. If it isn't per-step, this is moot. **Resolve §1 first.** This is the standard
   technique in llama.cpp/EXL2-style offload and is the single highest-leverage scheduling
   change available to a 3.6 GiB model on an 8 GB card.
2. **Intra-kernel pipelining** — double-buffered K/V tiles inside the attention kernel. This is
   FlashAttention's mechanism, not CUDA streams. Comes free with §3.
3. **Multi-stream for tensor-parallel / multi-GPU** — we have one GPU. N/A.

Cohere's megakernel writeup notes a related subtlety that *does* apply to us: "Fusion mostly buys
back memory traffic; a megakernel mostly buys back stalls — the launch gap, the full-grid barrier,
and the SMs that a kernel boundary leaves idle." At batch 1 with 6 KB vectors there is almost no
memory traffic to buy back. **Everything we have left is stalls.**

---

## 7. Ordered action plan

**Phase 0 — measure (do this before writing any code; ~1 hour, and it may invalidate everything else)**
1. Re-profile weights / attention / total **in one process** — our 18+50=68 ms vs 55.6 ms
   discrepancy must be resolved (§1).
2. Run the `t_cpu` vs `t_wall` test (§5.1). This decides whether graphs are the top priority or
   worthless.
3. Nsight Systems: `Σ GPU kernel time`, and **bytes moved per kernel**. Compute
   `amp = bytes_moved / (112 KiB × ctx)` to confirm or kill the 38x read-amplification hypothesis.
4. Confirm whether the 1.1 GiB spill is per-step (instrument the H2D copy) — 84 ms either way.

**Phase 1 — fix attention (the 38x). Expected: 50 ms → 2–6 ms, ~2x end-to-end.**
- FlashDecoding / split-KV with **fixed** split count + device-side work queue (graph- and
  determinism-safe, per §2).
- Split factor from context: target **40–80 blocks on 20 SMs**; each split ≥512–1024 KV elements.
- **GQA-aware KV loading**: one load per KV head, reused across its 4 query heads. Not 4 loads.
- Override any seq-len-based `s=1` guard — on 20 SMs that guard is costing us 2.5x.

**Phase 2 — CUDA Graph (`FULL_DECODE_ONLY`), *if* Phase 0.2 says host-bound.**
- `plan()` once (static geometry, static `max_kv_len`), capture `run()`, replay per step.
- `seq_lens` as a **device tensor**; never a host-side shape decision.
- All Triton autotuning resolved before capture. Static input buffer + `copy_()`. Private memory
  pool. No `.item()` / `nonzero()` / host-side tensor branches in the captured region.

**Phase 3 — PCIe spill.** If per-step: double-buffer layer N+1's H2D against layer N's compute,
or shrink the resident set so nothing spills. If not per-step: pin those tensors and close the
question.

**Phase 4 — fusion, only for what the graph can't cover.** RoPE+KV-write is the best ratio
(halves launches: 976→488 in the vLLM DeepSeek-R1 measurement). Residual+RMSNorm+proj and SwiGLU
are ~1–3% each — graph them if possible, fuse only if the graph can't capture them.

**Phase 5 — megakernel.** Only if #1–#4 leave us launch-bound. Expect 1.06–1.45x over graphed
per-kernel execution, and be aware it will *cost* us GEMV efficiency (83% of realistic peak is
already near the top of the published range; AMK's bf16 path runs at 51% of spec vs a cuBLAS
ceiling of ~90%). On 20 SMs wave quantization is ~1.6x worse than on 132, which is the one thing
genuinely in its favor.

---

## Sources

**CUDA Graphs**
- [CUDA Programming Guide §4.2 — CUDA Graphs](https://docs.nvidia.com/cuda/cuda-programming-guide/04-special-topics/cuda-graphs.html)
- [CUDA Graph Best Practices for PyTorch](https://docs.nvidia.com/dl-cuda-graph/cuda-graph-basics/cuda-graph.html)
- [PyTorch CUDA Graph Integration](https://docs.nvidia.com/dl-cuda-graph/torch-cuda-graph/torch-integration.html)
- [Constant Time Launch for Straight-Line CUDA Graphs](https://developer.nvidia.com/blog/constant-time-launch-for-straight-line-cuda-graphs-and-other-performance-enhancements/) — 2 μs+200ns/node → 2.5 μs+~1ns/node
- [GraCE: Unlocking CUDA Graphs with Compiler Support (OSDI'26)](https://www.usenix.org/system/files/osdi26-ghosh.pdf) — 5–10 μs/launch; DALL·E 2 740 kernels, 3.4 ms GPU vs 14 ms wall
- [vLLM CUDA Graphs design doc](https://docs.vllm.ai/en/stable/design/cuda_graphs/) — modes, attention backend limitations
- [hezhiqian01/cudagraphlaunch](https://github.com/hezhiqian01/cudagraphlaunch) — graph 3.4 μs + 0.08 μs/node
- [Megatron Core CUDA Graph](https://docs.nvidia.com/megatron-core/developer-guide/nightly/user-guide/features/cuda_graph.html) — NaN-check sync prohibition
- [CUDA Driver Command Stream Analysis (arXiv:2604.26889)](https://arxiv.org/html/2604.26889v1)

**Fusion**
- [Kernel Fusion in NVIDIA CUDA (NVIDIA blog)](https://developer.nvidia.com/blog/kernel-fusion-in-nvidia-cuda-optimizing-memory-traffic-and-launch-overhead) — graphs ≠ body fusion; 1 GiB round-trip survives
- [TensorRT-LLM v0.11.0 release](https://github.com/NVIDIA/TensorRT-LLM/releases/tag/v0.11.0) — reduce-norm, fused GEMM-SwiGLU
- [vLLM PR #45798](https://github.com/vllm-project/vllm/pull/45798) — RoPE+KV-cache fusion, 976→488 launches/step
- [vLLM PR #38621](https://github.com/vllm-project/vllm/pull/38621) — QK-Norm+RoPE+Cache+Quant
- [TRT-LLM Triton fusion patterns](https://github.com/NVIDIA/tensorrt-llm/blob/HEAD/.claude/skills/kernel-triton-writing/references/patterns-fusion.md) — SwiGLU 1.5–2x, RMSNorm 1.4–2x
- [fused-triton-rmsnorm-residual-qkv](https://github.com/varad-more/fused-triton-rmsnorm-residual-qkv) — +1.4% B=1, −12.8% vs torch.compile
- [ForgeMegakernel (arXiv:2609.12379)](https://arxiv.org/pdf/2609.12379) — 158/280 launches are small ops = 1/5 of latency
- [AutoMegaKernel](https://github.com/RightNow-AI/AutoMegaKernel) — inference-class wins, training-class losses, bf16 GEMV 51% of spec
- [AutoMegaKernel analysis](https://emergentmind.com/topics/automegakernel-amk)
- [Cohere decode megakernel](https://learnaivisually.com/ai-explained/cohere-megakernel-persistent-decode-kernel) — wave quantization, fusion vs megakernel distinction
- [MRAnayDongre/Inference-Kernels](https://github.com/MrAnayDongre/Inference-Kernels) — isolated fusion microbenchmarks

**Attention / prefill vs decode**
- [Flash-Decoding (Stanford CRFM)](https://crfm.stanford.edu/2023/10/12/flashdecoding.html) — 3-step split-KV + LSE merge
- [FlashInfer (arXiv:2501.01005)](https://arxiv.org/html/2501.01005) — plan/run split, device-side scheduler, 29–69% ITL reduction
- [FlashInfer Attention API](https://docs.flashinfer.ai/api/attention.html) — **split-KV × CUDA graph incompatibility**
- [FA3 low-head-count occupancy (arXiv:2604.00028)](https://arxiv.org/pdf/2604.00028) — 8 CTAs, 21–24% recoverable
- [Four Things Nobody Has Written About FlashDecode](https://manishklach.github.io/writings/kv-cache-decode-unique.html) — B* = ⌈S/H⌉ crossover
- [SharpInference #235](https://github.com/pekkah/SharpInference/issues/235) — 8-block launch at 6% of peak; GQA-aware loading
- [FlashAttention-2](https://saikatkumardey.com/ml-wiki/sources/flash-attention-2)
- [ZINC KV split (RX 9070 XT)](https://zolotukhin.ai/blog/2026-05-20-the-kv-split-that-fills-rdna4-idle-compute-units-on-long-context-decode)
- [tensormux: prefill vs decode kernels](https://github.com/tensormux/kernel-skills/blob/master/skills/inference/optimize-prefill-vs-decode-kernels/SKILL.md) — BLOCK_M≥16, split-K sizing
- [CUTLASS Efficient GEMM](https://docs.nvidia.com/cutlass/latest/media/docs/cpp/efficient_gemm.html) — split-K, sliced-k
- [MLC-LLM low-batch GEMM PR #1769](https://github.com/mlc-ai/mlc-llm/pull/1769) — GEMV-like schedule below M=8
- [GemLite](https://github.com/gabe-engineers/gemlite) — GEMV RevSplit-K for B=1
- [Bandwidth-bound operations (roofline)](https://aicassindra.com/blogs/transformer_math/tm_bandwidth_bound.html) — machine balance, GEMV intensity

**Overlap / scheduling**
- [TensorRT perf guide](https://docs.nvidia.com/deeplearning/tensorrt/latest/performance/optimization.html) — stream contention caveat
- [local-kimi OPTIMIZATION-LIMITS](https://github.com/RightNow-AI/local-kimi/blob/main/engine/OPTIMIZATION-LIMITS.md) — measured in-situ GEMV efficiency
- [ZINC: weight streaming roofline](https://zolotukhin.ai/blog/2026-07-15-weight-streaming-is-under-half-of-an-rdna4-decode-token) — 80–85% STREAM
- [Chunked prefill (Sarathi-Serve, arXiv:2403.02310)](https://arxiv.org/pdf/2403.02310) — throughput-only, N/A for us

**Hardware**
- [RTX 3050 8GB specs (TechPowerUp)](https://www.techpowerup.com/gpu-specs/geforce-rtx-3050-8-gb.c3858) — 20 SMs, 224 GB/s, PCIe 4.0 x8
