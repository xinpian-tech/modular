from std.sys.info import _TargetType


def target() -> _TargetType:
    """Returns the compiler target shipped by the standalone T1 package."""
    return __mlir_attr[
        `#kgen.target<triple = "riscv32-unknown-elf", `,
        `stdlib_plugin = "default", `,
        `arch = "generic-rv32", `,
        `features = "+m,+a,+c,+f,+zve32f,+zvl2048b", `,
        `tune_cpu = "generic-rv32", `,
        `data_layout = "e-m:e-p:32:32-i64:64-n32-S128", `,
        `index_bit_width = 32, simd_bit_width = 2048`,
        `> : !kgen.target`,
    ]


comptime api = "t1"
