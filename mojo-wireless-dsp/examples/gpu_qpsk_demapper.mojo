"""Compile/runtime-gated GPU QPSK hard-demapper smoke backend."""

from std.math import ceildiv
from std.sys import has_accelerator
from max.gpu.host import DeviceContext
from std.gpu import block_dim, block_idx, thread_idx
from layout import TileTensor, row_major

comptime symbol_count = 4096
comptime sample_layout = row_major[symbol_count * 2]()
comptime bit_layout = row_major[symbol_count * 2]()
comptime block_size = 256
comptime grid_size = ceildiv(symbol_count, block_size)


def qpsk_hard_demapper_kernel(
    iq: TileTensor[DType.float32, type_of(sample_layout), MutAnyOrigin],
    bits: TileTensor[DType.uint8, type_of(bit_layout), MutAnyOrigin],
):
    var index = block_idx.x * block_dim.x + thread_idx.x
    if index < symbol_count:
        bits[2 * index] = UInt8(iq[2 * index] < 0.0)
        bits[2 * index + 1] = UInt8(iq[2 * index + 1] < 0.0)


def main() raises:
    comptime if not has_accelerator():
        print("GPU QPSK demapper compiled; runtime skipped (no accelerator)")
    else:
        var context = DeviceContext()
        var input_host = context.enqueue_create_host_buffer[DType.float32](symbol_count * 2)
        for i in range(symbol_count):
            input_host[2 * i] = 1.0 if i % 2 == 0 else -1.0
            input_host[2 * i + 1] = 1.0 if i % 4 < 2 else -1.0
        var input_device = context.enqueue_create_buffer[DType.float32](symbol_count * 2)
        var output_device = context.enqueue_create_buffer[DType.uint8](symbol_count * 2)
        context.enqueue_copy(dst_buf=input_device, src_buf=input_host)
        var input_tensor = TileTensor(input_device, sample_layout)
        var output_tensor = TileTensor(output_device, bit_layout)
        context.enqueue_function[qpsk_hard_demapper_kernel](
            input_tensor, output_tensor, grid_dim=grid_size, block_dim=block_size
        )
        var output_host = context.enqueue_create_host_buffer[DType.uint8](symbol_count * 2)
        context.enqueue_copy(dst_buf=output_host, src_buf=output_device)
        context.synchronize()
        for i in range(symbol_count):
            if output_host[2 * i] != UInt8(i % 2):
                raise Error("GPU QPSK I-bit demapper mismatch")
            if output_host[2 * i + 1] != UInt8(i % 4 >= 2):
                raise Error("GPU QPSK Q-bit demapper mismatch")
        print("GPU QPSK demapper runtime passed")
