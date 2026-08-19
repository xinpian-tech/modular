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

# 2. Standard Mojo (see ../examples/saxpy.mojo):
export MODULAR_MOJO_MAX_SHARED_LIBS=$PWD/out/libT1RT.so
mojo build --target-accelerator=t1 ../examples/saxpy.mojo -o saxpy
./saxpy
# -> SAXPY OK on T1 (standard Mojo): n = 64 , kernel cycles = 131
```

`execution_time` returns **simulation cycles** on T1, not nanoseconds.
