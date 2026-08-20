# Standalone T1 device support

T1 is an out-of-tree-style custom device package.  Mojo itself contains only
the generic compiler-plugin loader and the ability to pass an explicit target
to `DeviceContext.compile_function`; the T1 triple, RVV feature set, backend,
runtime API name, and simulator integration all live under this directory.

Build the compiler plugin independently of Mojo:

```sh
nix develop -c bazel-nix build --config=build-mojo //T1:compiler-plugin
CC=cc RV_CLANG=clang RV_LLD=ld.lld OBJCOPY=llvm-objcopy T1/runtime/build.sh
```

The independently replaceable support package consists of:

- `libT1CompilerPlugin.so`: compiler target traits and object backend;
- `mojo/t1`: the Mojo-facing target and runtime API declaration;
- `libT1RT.so` and `trampoline.bin`: the AsyncRT device implementation.

Use it with any Mojo driver that implements the generic plugin ABI:

```sh
export MODULAR_MOJO_MAX_MOJO_PLUGIN_PATHS=/path/to/libT1CompilerPlugin.so
export MODULAR_MOJO_MAX_SHARED_LIBS=/path/to/libT1RT.so

mojo build -I /path/to/t1/mojo saxpy.mojo -o saxpy
```

The application imports `t1.target` and passes it explicitly to
`compile_function`; there is intentionally no `--target-accelerator=t1` and no
T1 entry in the Mojo standard library.
