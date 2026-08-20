# T1 microarchitectural performance analysis of the llama kernels

Non-invasive analysis of the hand-written RVV llama kernels
(`T1/examples/t1llama.mojo`) on the cycle-accurate `t1rocketemu` RTL
simulation of the **blastoise** design.  All data comes from the
simulator's per-instruction retirement trace (`rtl-event.jsonl`:
`T1Issue`/`T1Retire`/`T1Release` events with cycle timestamps for every
vector instruction, plus scalar retires) — no instrumentation
instructions were inserted into the kernels.

Workload: stories15M (dim 288, hidden 768), one transformer layer
launch (2,976 matvec rows) and the classifier head launch
(32,000 × 288).  The same kernels run TinyLlama-1.1B; only `n` and the
row counts change.

## 1. The machine (blastoise)

From `t1zaozi/params/blastoise/*.json`:

| Parameter | Value | Consequence |
|---|---|---|
| VLEN | 2048 | m1 = 64 f32 lanes-worth of state |
| Lanes × datapath | 4 × 64 bit | DLEN = 256 bit = 8 f32/cycle execute |
| `chainingSize` | 4 | at most 4 vector instructions in flight per lane |
| VRF | banked SRAM, `p0rw` (single port), `portFactor` 4, read latency 2 | loads writing the VRF contend with VFU reads |
| LSU | 3 MSHRs/bank, AXI 256-bit data, `toVRFWriteQueueSize` 96 | 32 B/cycle peak memory bandwidth, deep outstanding |
| Scalar core | Rocket (in-order), decoupled vector issue queue | scalar instructions run under vector execution |

## 2. Headline results (RTL, cycle-accurate)

| Kernel version | layer kernel | head kernel |
|---|---|---|
| v1 generic Mojo SIMD | 3,343,155 | — |
| v2 first asm (m4, vfredusum, no tails) | 1,465,269 | 15,081,105 |
| v5 row-loop-in-asm, 6-row groups, packed stores | 1,088,598 | 11,147,993 |
| v6 two-level `vfadd` fold before short reduce | **824,567** | **8,310,745** |

Total: **4.05×** (layer) / **1.81×** (head, v2 baseline) over the
generic-SIMD kernels, entirely from
restructuring against measured microarchitectural behavior.  Cycle
counts are bit-identical across layers and across runs — the RTL is
deterministic, which makes every one of these numbers exactly
reproducible.

## 3. Chaining works — and hides all scalar overhead

From the v5 layer-launch trace (20,550 vector instructions):

- Unit-stride `vle32` (m4, vl=256) issue back-to-back: the issue-to-issue
  gap median is **1 cycle**; up to 5 vector instructions are
  simultaneously in flight, and ≥2 are in flight during **98.5%** of
  kernel cycles.
- The dependent `vfmul`/`vfmacc` issues ~33 cycles after the `vle32`
  producing its operand and executes while the load is still streaming
  beats — Load→Exec chaining exactly as advertised by the Cray-style
  design.
- **96.6% (layer) / 100.0% (head) of scalar retires happen while vector
  instructions are in flight.**  The address increments, pointer chains
  and loop control that dominate the scalar instruction count (§ audit
  in the previous commit) cost **zero cycles**: Rocket runs them in the
  shadow of vector execution.

The last point corrects the natural reading of the instruction-mix
metric: pushing dynamic RVV share from 47.8% to 71.5% mattered because
it *removed serialized work* (scalar tails, reduction trees, a
byte-wise memset), not because scalar instructions were expensive — the
surviving ones are already free.

## 4. Anatomy of one 6-row matvec group (v5, n=288)

Timeline reconstructed from issue/retire events (one group, 2,090
cycles):

```
phase        cycles   what the trace shows
loads+MACs   0-585    7 x vle32 pairs cadence ~66 cy; vfmul chained ~33 cy
                      behind each load; 2 loads overlapped throughout
reduce      585-1947  6 x vfredusum (vl=256): occupancy 446 cy each,
                      accepted every ~224 cy -> phase 1,362 cy
pack/store 1725-2133  5 x vslideup + vse32, chained under the reduce tail
next group  2090-     first vle32 of the next group issues 1 cy after vse32
```

Aggregated over the launch: the reduce phase costs **62.1%** of all
kernel cycles; loads are in flight during only 30.1% of them.

### 4.1 The reduction unit is the bottleneck

Measured `vfredusum` behavior:

| vl (e32) | occupancy | acceptance interval |
|---|---|---|
| 256 (m4) | 446 cy | ~224 cy |
| 64 (m1, after fold) | 206 cy | ~103 cy |

Linear fit: **`vfredusum ≈ 126 + 1.25 × vl` cycles, non-pipelined**
(next reduce accepted at roughly half the previous one's occupancy).
Reductions execute near element-serial and do not benefit from the four
lanes.  Consequences:

- Six back-to-back full-width reduces serialize into a 1,362-cycle
  phase during which the (independent!) next group's loads cannot
  issue: with `chainingSize = 4`, the outstanding reduces occupy the
  instruction slots and stall the in-order issue front end.
- This also retroactively explains v1: the generic `reduce_add`
  lowering (log2 slide/add tree + `vfredosum`) paid this fixed cost
  *and* a tree of dependent slides per row.

### 4.2 v6: fold with the lanes, reduce only the stub

The lanes add at 8 f32/cycle and chain; the reduction unit does ~0.8
elem/cycle and does not.  So v6 folds each m4 accumulator 256→128→64
with two lane-parallel `vfadd.vv` (measured occupancy 67 cy, fully
chained) and reduces only 64 elements:

- fold+reduce phase per group: 1,362 → **830 cycles**
- layer kernel: 1,088,598 → **824,567 cycles (-24%)**

The reduce phase is still 50% of the kernel — `vfredusum`'s ~126-cycle
fixed cost now dominates its own execution.

### 4.3 Load phase: 48% of peak bandwidth, VRF-port bound

During the load phase the cadence is one m4 load (1 KiB = 32 AXI
beats) per ~66 cycles ≈ 15.5 B/cycle against the 32 B/cycle AXI peak.
The LSU (3 MSHRs, 96-deep VRF write queue) keeps two loads in flight,
but every load must *write* the VRF while the chained `vfmul`/`vfmacc`
*reads* two operand groups from it — with single-port (`p0rw`) banked
VRF RAM at `portFactor` 4, the write and read streams contend for bank
ports.  The ~2× gap between achieved and peak bandwidth is consistent
with load writes losing roughly half the port slots to execution reads
(hypothesis; confirming it needs VRF-port waveforms rather than the
retirement trace).

## 5. Where the next factor is (software)

In v6, per group: loads ~585 cy (irreducible at current VRF: 252 beats
minimum = 43% of that), fold+reduce ~830 cy, of which only ~180 cy is
lane work.  The two phases barely overlap because the in-order front
end cannot issue the next group's loads past the outstanding reduces.

1. **Software pipelining across groups** — start group *i+1*'s loads
   before group *i*'s fold/reduce section.  Requires freeing two vector
   register groups for double buffering (5-row groups instead of 6) and
   staying within the 4-slot budget: expected to hide most of the load
   phase under the reduce phase, bounding the group at ~max(585, 830) ≈
   830 cy → ~25% further.
2. **Amortize the reduce fixed cost** — reduce two rows per
   `vfredusum` by first `vslideup`-merging two 64-elem stubs into one
   128-elem register (1 fold more, half the reduces): saves ~6 × 63 cy
   fixed per group at the cost of 3 slides + later scalar split; ~10%.
3. **Attention at long context**: `_dot`'s vl=hs=64 reduce pays the
   same 126-cycle fixed cost per cached position; at pos ≫ 64 this
   dominates attention.  Batch the dot products (one m4/m8 load of
   several K rows, MAC against broadcast q, fold, one reduce per 4-8
   positions) before long-context runs.

## 6. Hardware co-design notes

The same numbers, read as design feedback for blastoise-class configs:

- **A pipelined (or logarithmic) reduction unit is the single highest
  value change for GEMV/attention workloads**: `vfredusum` at
  126 + 1.25/elem non-pipelined makes reductions 50-62% of a
  bandwidth-starved kernel.  A tree reducer at DLEN width would cut the
  variable cost to vl/8 and pipelining would remove the serialization;
  both together turn the reduce phase into noise (<5%).
- **`chainingSize` 4 is the second limiter**: long-occupancy
  instructions (reduces today, possibly gathers tomorrow) fill all four
  slots and stall issue of independent memory traffic.  6-8 slots, or
  an issue policy that reserves one slot for loads, would let the load
  phase run under the reduce phase with no software pipelining at all.
- **VRF port pressure caps streaming at ~50%** of AXI bandwidth in
  load+MAC phases.  `portFactor` or a two-port VRF option trades area
  for the other 2× — worthwhile only after the reduction unit, since
  today the load phase is not the critical path.
- The scalar core is never the problem: a minimal in-order Rocket
  fully hides the bookkeeping of hand-tiled vector loops behind
  chaining.  Spending area on the vector side (reduction, slots, VRF
  ports) beats any scalar-side improvement for these kernels.

## 7. Hardware tuning under DLEN = 256 (measured)

Config-space experiments on `designs/blastoise.toml`
(`T1/runtime/blastoise-tuning.patch`), v6 kernels, stories15M:

| Config (DLEN = 256 fixed) | layer kernel | head kernel | verdict |
|---|---|---|---|
| baseline: `p0rw`, 4 banks, 4x64b lanes | 824,567 | 8,310,745 | |
| **`p0rp1w` (1R1W two-port VRF) + 8 banks** | **784,929 (-4.8%)** | **7,990,760 (-3.8%)** | **adopted** |
| + `laneScale=1` (8x32b lanes) | 851,885 | — | rejected: `vfredusum` occupancy 206 -> 252 (deeper cross-lane combine), loads unchanged |
| `chainingSize=8` | does not elaborate | — | generator hardcodes 4 slot pipelines; filed [xinpian-tech/T1#175](https://github.com/xinpian-tech/T1/issues/175) |

The two-port VRF confirms §4.3 exactly where predicted: m4 load
occupancy 123 → 92 cycles, load cadence 66 → 49 cycles — and the
fold+reduce phase is unchanged (830 → 835), because the reduction unit
does not touch VRF load-write ports.  With the load phase now ~44%
faster and the reduce phase untouched, the reduce share rises further:
the config space under DLEN = 256 is effectively exhausted, and the two
remaining walls — the non-pipelined ~`126 + 1.25/elem` reduction unit
and the hardcoded 4 instruction slots — both require RTL changes
(§6, issue #175).

## 8. Does 8-deep chaining help?  (measured: no — and why)

With the elaboration fix (xinpian-tech/T1#176) `chainingSize=8` builds and
runs.  Two kernel generations, both configs, stories15M:

| Kernel | slots=4 | slots=8 | delta |
|---|---|---|---|
| v6 (fold+reduce after each 6-row group) — layer | 824,567 | 833,917 | +1.1% |
| v6 — head | 8,310,745 | 8,422,698 | +1.3% |
| v7 (software-pipelined pairs, conflict-free registers) — layer | 759,219 | 755,400 | **-0.5%** |

v6 cannot exploit extra slots for a *software* reason: its reduce
destinations (v0-v6) alias the next group's load buffers (w v0-v3,
x v4-v7), so the register dependence — not the slot count — blocks
cross-group overlap.  v7 removes the aliasing (buffers v0/v4, reduce
stubs v24-v26) and interleaves each pair's fold+`vfredusum` into the next
pair's load stream: 8.6% faster than v6, but **identical between 4 and 8
slots**.

The v7@cs8 retirement trace explains it: the vector unit is completely
idle **46.9%** of kernel cycles, at most 5 instructions ever in flight,
and scalar-under-vector overlap drops to 57% (from 96-100% in v6).  The
issue front end — vtype ping-pong between the m4 compute shape and the
m1/m2 fold/reduce shapes, plus the scalar bookkeeping between interleave
points that can no longer hide under long vector phases — is the limiter.
Four slots were never the binding constraint for this kernel family;
the §6 recommendation is revised accordingly: pipelining/shortening the
reduction unit remains the high-value hardware change, extra slots are
not.

## 9. SEW/LMUL/vl-templated kernels and the LMUL sweep

All hand-written helpers are now generated at compile time from
SEW/LMUL parameters (`t1llama.mojo`: `MV_LMUL`, `EW_LMUL`, overridable
with `-D T1_MV_LMUL=<1|2|4>`); vl always follows as VLMAX of the shape
with `vsetvli` strip-mining for remainders, and the matvec derives its
whole register allocation (load buffers, double-buffered accumulator
pairs, reduce stubs, fold ladder depth = log2 LMUL) from the parameter.

Layer kernel, stock config, greedy output identical for all shapes:

| MV_LMUL | chunk (e32) | layer cycles |
|---|---|---|
| 1 | 64 | 896,996 |
| **2** | **128** | **751,127** |
| 4 | 256 | 758,733 (= hand-written v7 within 0.06%) |

LMUL=2 edges out LMUL=4: the shorter reduce stubs and cheaper fold
ladder outweigh the doubled loop-iteration count; LMUL=1 loses to pure
per-iteration overhead.  The generator makes such sweeps a rebuild flag
instead of an assembly rewrite.

## 10. Raising the chime (VLEN/DLEN): measured, and it hurts

With DLEN fixed at 256, VLEN raised 2048 -> 4096 doubles the chime (the
cycles one vector instruction occupies: chunk/8 for e32).  The kernel
generator only needs `-D T1_VLEN=4096`; the RTL config changes
`vlen`/`zvl4096b` in `designs/blastoise.toml`.  Layer kernel, identical
(any-n-safe) generator everywhere, outputs token-exact in all cells:

| VLEN | MV_LMUL | chunk | chime/instr | layer cycles |
|---|---|---|---|---|
| 2048 | 2 | 128 | 16 cy | **817,844** |
| 2048 | 4 | 256 | 32 cy | 1,019,522 |
| 4096 | 2 | 256 | 32 cy | 1,047,535 |
| 4096 | 4 | 512 | 64 cy | 1,480,733 |

Monotonically worse with chime, -81% at the extreme.  Three mechanisms,
all visible in the earlier traces:

1. The m1 reduce stub scales with VLEN (64 -> 128 e32 lanes), so
   `vfredusum` (~126 + 1.25/elem, serial) costs 206 -> 286 cycles per
   row — and reductions are already the critical resource.
2. The fold ladder and accumulator init run at the VLMAX of each level
   regardless of how many lanes are useful; at n=288 a 512-lane chunk
   pays full-width occupancies for 288 lanes of work.
3. The overhead that longer vectors classically amortize — scalar loop
   control per instruction — was already free: chaining and the
   decoupled scalar core hide it at chime 8-16 (§3).

The matched-chunk cells make the reduce effect clean: VLEN 2048/LMUL 4
and VLEN 4096/LMUL 2 execute the same chunk length and differ mainly in
stub length (64 vs 128), costing ~3%.

Corollary for blastoise-class configs: with a serial reduction unit and
short GEMV rows, extra VLEN is pure downside for this workload family —
spend the VRF area on reduction throughput instead.  (Long-vector
workloads without reductions — SAXPY-like streaming — are where higher
chime pays.)

Note: this section uses the any-n-safe generator (accumulator zero-init
+ uniformly strip-mined `tu` loop), required once chunk can exceed the
smallest matvec n.  It costs ~9% versus §9's vfmul-first-chunk variant
at VLEN 2048 (817,844 vs 751,127 at LMUL 2); a comptime fast path for
callers that guarantee n >= chunk is the obvious follow-up.

## 11. The DLEN axis: sublinear, and the reduce unit is why

The complementary sweep: VLEN fixed at 2048, DLEN 128/256/512 (2/4/8
lanes x 64 bit; the AXI data width follows DLEN, so this scales execute
*and* memory bandwidth together).  The kernels are unchanged — DLEN is
architecturally invisible to RVV code.  Layer kernel, uniform generator:

| DLEN | chime (m1) | MV_LMUL=2 | MV_LMUL=4 | SAXPY n=4096 |
|---|---|---|---|---|
| 128 | 16 cy | 1,304,573 | 1,732,957 | 4,294 |
| 256 | 8 cy | 817,844 | 1,019,522 | 3,390 |
| 512 | 4 cy | **693,220** | 714,771 | 2,880 |

Doubling DLEN buys 1.60x at the low end but only **1.18x** from 256 to
512, against 2x the datapath and bus area.  The Amdahl term is the same
serial reduction unit as everywhere else in this document: its
throughput does not scale with lanes (§ hardware-tuning even measured it
*degrading* with more lanes at fixed DLEN), so as the streaming phases
shrink, the reduce share of every row grows.  Note LMUL=4 gains more
from DLEN=512 than LMUL=2 does (its longer chunks actually use the wider
datapath), nearly closing the L2/L4 gap.

Taken together, the two chime sweeps give a clean design statement for
GEMV-class workloads on blastoise-family configs:

- chime up via VLEN: strictly worse (serial reduce work per row scales
  with VLEN);
- chime down via DLEN: better but sublinear (serial reduce share grows);
- every axis measured — VLEN, DLEN, LMUL, lanes, VRF ports, slots —
  points at the same conclusion: **pipeline the reduction unit first;
  every other knob is second-order until then.**

## 12. Lane organization (laneScale): a shallow optimum at 64-bit lanes

Last axis: how the fixed DLEN=256 is sliced into lanes
(`--laneScale`: lane datapath = 32 x laneScale bits).  VLEN 2048,
MV_LMUL=2, uniform generator, stock config otherwise:

| laneScale | lanes | layer cycles | SAXPY n=4096 |
|---|---|---|---|
| 1 | 8 x 32b | 853,203 (+4.3%) | 3,390 |
| **2** | **4 x 64b** | **817,844** | 3,390 |
| 4 | 2 x 128b | 903,469 (+10.5%) | 3,390 |

SAXPY is bit-identical in cycles across all three — pure streaming sees
only DLEN.  The GEMV kernel sees the organization: more, narrower lanes
add cross-lane coordination (the earlier tuned-config experiment
measured `vfredusum` occupancy 206 -> 252 at 8 lanes — consistent with
853k here); fewer, wider lanes cost lane-level parallelism in the fold
and elementwise phases without helping the serial reduction at all.
Stock blastoise's 4 x 64b is the right slicing.

### 12.1 Why both directions lose: the per-class decomposition

Retirement traces for all three slicings (same binary, so instruction
counts are identical -- 36,979 vector instructions per layer launch):

| occupancy p50/p90 (cy) | 8 x 32b | 4 x 64b | 2 x 128b |
|---|---|---|---|
| `vle32` m2 vl=128 | 90 / 169 | 91 / 170 | 91 / **236** |
| `vfmacc` m2 vl=128 | 65 / 76 | 66 / 90 | 66 / **165** |
| `vmv.v.i` m2 | 140 | 139 | **171** |
| `vfredusum` m1 vl=64 | **170** / 254 | 148 / 208 | **140** / 190 |
| `vfadd` m1 (fold) | 60 | 60 | 60 |
| layer total | 853,203 | 817,844 | 903,469 |

laneScale moves cost between two different units:

- **More, narrower lanes tax the reduction.**  `vfredusum` occupancy
  climbs 140 -> 148 -> 170 across 2/4/8 lanes: the reduce combines
  per-lane partials through the mask unit, and both the cross-lane
  combine chain and the per-lane orchestration grow with lane count.
  (In-lane chunk count moves the *other* way --
  `reduceResultChunkCount = datapathWidth/eLen` is 4 at 128-bit lanes
  vs 1 at 32-bit -- but the cross-lane part dominates.)  Streaming is
  actually *best* at 8 lanes (tightest p90s, `vfmacc` cadence 42 vs 49
  cy): per-lane port pressure is lowest at 1 elem/lane/cycle.
- **Fewer, wider lanes tax the streaming phases.**  At 2 x 128b the
  p50s are unchanged but the p90 tails explode (`vle32` 170 -> 236,
  `vfmacc` 90 -> 165, `vmv.v.i` +23%): each lane must move 4 e32/cycle
  through its VRF slice -- two operand reads plus the load-write stream
  against the same single-port banks -- so intermittent bank conflicts
  stall the chained load->MAC pipeline.  The reduce improves (140), but
  it cannot pay for the streaming tails.

So the axis is a genuine tradeoff between cross-lane coordination
(reduction path) and per-lane VRF port bandwidth (streaming path), and
at DLEN = 256 the crossover sits exactly at 4 x 64b.  It also cleanly
explains the hardware-tuning section's earlier observation (reduce
206 -> 252 at 8 lanes on the tuned config) and predicts that a two-port
VRF shifts the optimum toward wider lanes, while a pipelined reduction
unit shifts it toward narrower ones.

## 13. Reproducing

```sh
# run any workload on the RTL simulator with per-launch traces kept:
T1RT_KEEP_RTL_EVENTS=1 SIM=rtl ./run-t1llama.sh stories "" 1
# analyze a launch trace:
python3 T1/tools/analyze-rtl-trace.py run/rtl-event.0.jsonl
```

The trace analyzer (occupancy/gap tables, in-flight histogram,
scalar-overlap ratio) lives in `T1/tools/analyze-rtl-trace.py`; the
dynamic instruction-mix tool from the previous commit is
`T1/tools/analyze-rvv-mix.py`.
