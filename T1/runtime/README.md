# libT1RT — Mojo `DeviceContext` runtime for the T1 RVV accelerator

Implements the AsyncRT C ABI (see `../docs/asyncrt-abi-inventory.md`) against
the batch `t1rocketemu` simulator from the T1 repository: on `synchronize`,
the runtime composes the launch trampoline (`trampoline.S`), the kernel ELF
produced by the Mojo T1 compiler backend, the argblock and the device-buffer
contents into a single bare-metal ELF, runs the simulator, and reads results
and the kernel cycle count back from the PERF MMIO event stream
(`mmio-event.jsonl`). `HtoD`/`DtoH` maintain the host shadow of the device
window (coherence semantics, not copies). The memory-map contract lives in
`t1_layout.h`.

Kernels are compiled with the soft-float ilp32 calling convention (hard
float/vector instructions, `+zve32f`), so the trampoline loads every argument
slot into a GPR without knowing argument types. `grid_dim`/`block_dim` other
than all-ones are rejected by design.

## Build

```sh
CC=cc RV_CLANG=clang RV_LLD=ld.lld OBJCOPY=llvm-objcopy ./build.sh
```

## Run

```sh
# simulator from the T1 repository (xinpian-tech/T1):
#   nix build .#legacyPackages.x86_64-linux.t1.blastoise.t1rocketemu.verilator-emu
export T1RT_EMULATOR=/path/to/bin/t1-blastoise-t1rocketemu-verilated-simulator
export T1RT_TRAMPOLINE=$PWD/out/trampoline.bin

# 1. Pure C smoke (no Mojo): drive a compiler-produced kernel ELF.
./out/t1rt_smoke saxpy_t1.elf entry-symbol.txt

# 2. Mojo with the standalone T1 support package (see ../examples/saxpy.mojo):
export MODULAR_MOJO_MAX_MOJO_PLUGIN_PATHS=/path/to/libT1CompilerPlugin.so
export MODULAR_MOJO_MAX_SHARED_LIBS=$PWD/out/libT1RT.so
mojo build -I ../mojo ../examples/saxpy.mojo -o saxpy
./saxpy
# -> SAXPY OK on T1 (standard Mojo): n = 64 , kernel cycles = ...
```

`execution_time` returns **simulation cycles** on T1, not nanoseconds.

## Fast readback (memory dump)

The default readback path streams every result word over the PERF MMIO
(~15 cycles per word — fine for a SAXPY, ruinous for LLM-sized outputs).
With a simulator carrying `emulator-memdump.patch` (adds
`+t1_memory_dump_path=`/`+t1_memory_dump_range=`, ~30 lines in the
`dpi_t1rocketemu` Rust library; the verilated RTL is unchanged), set:

```sh
export T1RT_MEMDUMP=1            # readback from the exit-time memory dump
export T1RT_DUMP_MAX_BYTES=...   # buffers above this are not read back
```

The runtime then keeps the PERF stream down to the BEGIN/END cycle markers
and refreshes buffer shadows from the dump file at zero simulation-cycle
cost. `T1RT_DUMP_MAX_BYTES` selects which buffers are refreshed — set it
above the size of every buffer a kernel writes (streamed read-only weight
buffers can stay above it; see `../examples/t1llama.mojo`, which allocates
them first so the refreshed buffers form one compact range).

## Functional simulation (pokedex)

`emulator-memdump.patch` also teaches the T1 repository's `pokedex` ISA
simulator a batch mode (`pokedex run --machine t1emu` + the same memory
dump and PERF-event options).  It models the same address map, HTIF exit
and PERF protocol as `t1rocketemu`, so libT1RT drives it unmodified:

```sh
export T1RT_EMULATOR=/path/to/bin/pokedex
export T1RT_EMULATOR_KIND=pokedex     # switches the invocation style
export T1RT_MEMDUMP=1
```

pokedex retires ~1-3M instructions/s versus ~10-20k cycles/s for the
verilated RTL — use it for model-scale workloads and the RTL simulator
for cycle-accurate spot checks of the same kernels (the composed images
are identical; both must produce identical results).  In pokedex mode
`execution_time` reports retired instructions (a 1-IPC approximation),
not RTL cycles.

## Instruction-mix auditing

With the patched pokedex, `T1RT_PC_HISTOGRAM=<prefix>` writes one
`(pc, count, word)` CSV per launch.  `T1/tools/analyze-rvv-mix.py` merges
them, classifies every executed instruction from its encoding (RVV vs
scalar classes), and attributes scalar hotspots to kernel functions via
`llvm-objdump` — the tool behind the t1llama kernel iteration
(47.8% → 71.5% dynamic RVV share; 99.8% of element operations vector).
