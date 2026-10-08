"""Report the host capabilities relevant to Phase-0 backend selection."""

from std.sys import has_accelerator
from std.sys.info import simd_width_of


def main():
    print("Float32 native SIMD width:", simd_width_of[DType.float32]())
    print("Float64 native SIMD width:", simd_width_of[DType.float64]())
    print("compatible accelerator available:", has_accelerator())
