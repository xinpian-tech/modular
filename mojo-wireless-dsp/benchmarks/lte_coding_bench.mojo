"""Allocation-inclusive CPU reference benchmark for LTE TS 36.212 coding."""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.lte.coding import (
    LTE_QPP_BLOCK_SIZE_COUNT,
    LTEQPPParameters,
    LTECodeBlockSegmentationProfile,
    LTECodeBlockSegments,
    LTECodeBlockConcatenationResult,
    LTETurboCodeword,
    LTESubblockBits,
    LTETurboRateRecovery,
    LTETurboDecodeResult,
    lte_crc8,
    lte_crc8_append,
    lte_crc8_check,
    lte_crc16,
    lte_crc16_append,
    lte_crc16_check,
    lte_crc24a,
    lte_crc24a_append,
    lte_crc24a_check,
    lte_crc24b,
    lte_crc24b_append,
    lte_crc24b_check,
    lte_code_block_segmentation_profile,
    lte_code_block_bit_range,
    lte_code_block_segment,
    lte_code_block_concatenate,
    lte_qpp_block_size,
    lte_qpp_deinterleave,
    lte_qpp_index,
    lte_qpp_interleave,
    lte_qpp_parameters,
    lte_tail_biting_convolutional_decode_hard,
    lte_tail_biting_convolutional_decode_soft,
    lte_tail_biting_convolutional_encode,
    lte_turbo_decode_max_log,
    lte_turbo_circular_buffer,
    lte_turbo_encode,
    lte_turbo_k0,
    lte_turbo_rate_match,
    lte_turbo_rate_recover,
    lte_turbo_subblock_interleave,
)


comptime _WARMUP = 3
comptime _SAMPLES = 9
comptime _CRC_BLOCKS_PER_SAMPLE = 4
comptime _TAIL_BLOCKS_PER_SAMPLE = 4
comptime _TURBO_BLOCKS_PER_SAMPLE = 4
comptime _SEGMENT_BLOCKS_PER_SAMPLE = 2


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value)) * UInt64(1099511628211)


def _pattern(length: Int, seed: UInt64) -> List[UInt8]:
    var state = seed
    var result = List[UInt8](capacity=length)
    for _ in range(length):
        state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
        result.append(UInt8((state >> UInt64(63)) & UInt64(1)))
    return result^


@no_inline
def _workload_lte_crc24a(bits: Span[UInt8, ...]) raises -> UInt64:
    return lte_crc24a(bits)


@no_inline
def _workload_lte_crc24a_append(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    return lte_crc24a_append(bits)


@no_inline
def _workload_lte_crc24a_check(bits: Span[UInt8, ...]) raises -> Bool:
    return lte_crc24a_check(bits)


@no_inline
def _workload_lte_crc24b(bits: Span[UInt8, ...]) raises -> UInt64:
    return lte_crc24b(bits)


@no_inline
def _workload_lte_crc24b_append(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    return lte_crc24b_append(bits)


@no_inline
def _workload_lte_crc24b_check(bits: Span[UInt8, ...]) raises -> Bool:
    return lte_crc24b_check(bits)


@no_inline
def _workload_lte_crc16(bits: Span[UInt8, ...]) raises -> UInt64:
    return lte_crc16(bits)


@no_inline
def _workload_lte_crc16_append(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    return lte_crc16_append(bits)


@no_inline
def _workload_lte_crc16_check(bits: Span[UInt8, ...]) raises -> Bool:
    return lte_crc16_check(bits)


@no_inline
def _workload_lte_crc8(bits: Span[UInt8, ...]) raises -> UInt64:
    return lte_crc8(bits)


@no_inline
def _workload_lte_crc8_append(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    return lte_crc8_append(bits)


@no_inline
def _workload_lte_crc8_check(bits: Span[UInt8, ...]) raises -> Bool:
    return lte_crc8_check(bits)


@no_inline
def _workload_lte_tail_biting_convolutional_encode(
    bits: Span[UInt8, ...],
) raises -> List[UInt8]:
    return lte_tail_biting_convolutional_encode(bits)


@no_inline
def _workload_lte_tail_biting_convolutional_decode_hard(
    bits: Span[UInt8, ...],
) raises -> List[UInt8]:
    return lte_tail_biting_convolutional_decode_hard(bits)


@no_inline
def _workload_lte_tail_biting_convolutional_decode_soft(
    llrs: Span[Float64, ...],
) raises -> List[UInt8]:
    return lte_tail_biting_convolutional_decode_soft(llrs)


@no_inline
def _workload_lte_qpp_block_size(index: Int) raises -> Int:
    return lte_qpp_block_size(index)


@no_inline
def _workload_lte_qpp_parameters(size: Int) raises -> LTEQPPParameters:
    return lte_qpp_parameters(size)


@no_inline
def _workload_lte_qpp_index(index: Int, parameters: LTEQPPParameters) raises -> Int:
    return lte_qpp_index(index, parameters)


@no_inline
def _workload_lte_qpp_interleave(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    return lte_qpp_interleave(bits)


@no_inline
def _workload_lte_qpp_deinterleave(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    return lte_qpp_deinterleave(bits)


@no_inline
def _workload_lte_code_block_segmentation_profile(size: Int) raises -> LTECodeBlockSegmentationProfile:
    return lte_code_block_segmentation_profile(size)


@no_inline
def _workload_lte_code_block_bit_range(
    profile: LTECodeBlockSegmentationProfile, block: Int,
) raises -> Tuple[Int, Int]:
    return lte_code_block_bit_range(profile, block)


@no_inline
def _workload_lte_code_block_segment(bits: Span[UInt8, ...]) raises -> LTECodeBlockSegments:
    return lte_code_block_segment(bits)


@no_inline
def _workload_lte_code_block_concatenate(
    bits: Span[UInt8, ...], profile: LTECodeBlockSegmentationProfile,
) raises -> LTECodeBlockConcatenationResult:
    return lte_code_block_concatenate(bits, profile)


@no_inline
def _workload_lte_turbo_encode(bits: Span[UInt8, ...]) raises -> LTETurboCodeword:
    return lte_turbo_encode(bits)


@no_inline
def _workload_lte_turbo_subblock_interleave(
    bits: Span[UInt8, ...],
) raises -> LTESubblockBits:
    return lte_turbo_subblock_interleave(bits)


@no_inline
def _workload_lte_turbo_circular_buffer(
    systematic: Span[UInt8, ...], parity1: Span[UInt8, ...], parity2: Span[UInt8, ...],
) raises -> LTESubblockBits:
    return lte_turbo_circular_buffer(systematic, parity1, parity2)


@no_inline
def _workload_lte_turbo_k0(stream_bits: Int, rv: Int) raises -> Int:
    return lte_turbo_k0(stream_bits, rv)


@no_inline
def _workload_lte_turbo_rate_match(
    systematic: Span[UInt8, ...], parity1: Span[UInt8, ...], parity2: Span[UInt8, ...], rv: Int, output_bits: Int,
) raises -> List[UInt8]:
    return lte_turbo_rate_match(systematic, parity1, parity2, rv, output_bits)


@no_inline
def _workload_lte_turbo_rate_recover(
    llrs: Span[Float64, ...], block_size: Int, rv: Int,
) raises -> LTETurboRateRecovery:
    return lte_turbo_rate_recover(llrs, block_size, rv)


@no_inline
def _workload_lte_turbo_decode_max_log(
    systematic: Span[Float64, ...], parity1: Span[Float64, ...], parity2: Span[Float64, ...],
) raises -> LTETurboDecodeResult:
    return lte_turbo_decode_max_log(systematic, parity1, parity2, iterations=4)


def _qpp_table_workload() raises -> UInt64:
    var checksum = UInt64(14695981039346656037)
    for table_index in range(LTE_QPP_BLOCK_SIZE_COUNT):
        var block_size = _workload_lte_qpp_block_size(table_index)
        var parameters = _workload_lte_qpp_parameters(block_size)
        checksum = _mix(checksum, block_size)
        checksum = _mix(checksum, parameters.f1)
        checksum = _mix(checksum, parameters.f2)
        checksum = _mix(checksum, _workload_lte_qpp_index(0, parameters))
        var bits = _pattern(block_size, UInt64(100 + table_index))
        var interleaved = _workload_lte_qpp_interleave(Span(bits))
        var recovered = _workload_lte_qpp_deinterleave(Span(interleaved))
        checksum = _mix(checksum, Int(recovered[block_size - 1]))
    return checksum


def _crc_workload() raises -> UInt64:
    var checksum = UInt64(14695981039346656037)
    for block in range(_CRC_BLOCKS_PER_SAMPLE):
        var bits = _pattern(72 + 8 * block, UInt64(200 + block))
        checksum = _mix(checksum, Int(_workload_lte_crc24a(Span(bits))))
        checksum = _mix(checksum, Int(_workload_lte_crc24b(Span(bits))))
        checksum = _mix(checksum, Int(_workload_lte_crc16(Span(bits))))
        checksum = _mix(checksum, Int(_workload_lte_crc8(Span(bits))))
        var a = _workload_lte_crc24a_append(Span(bits))
        var b = _workload_lte_crc24b_append(Span(bits))
        var c = _workload_lte_crc16_append(Span(bits))
        var d = _workload_lte_crc8_append(Span(bits))
        checksum = _mix(checksum, Int(_workload_lte_crc24a_check(Span(a))))
        checksum = _mix(checksum, Int(_workload_lte_crc24b_check(Span(b))))
        checksum = _mix(checksum, Int(_workload_lte_crc16_check(Span(c))))
        checksum = _mix(checksum, Int(_workload_lte_crc8_check(Span(d))))
    return checksum


def _segmentation_workload() raises -> UInt64:
    var checksum = UInt64(14695981039346656037)
    var sizes: List[Int] = [6145, 12000]
    for block in range(_SEGMENT_BLOCKS_PER_SAMPLE):
        var profile = _workload_lte_code_block_segmentation_profile(sizes[block])
        var last_range = _workload_lte_code_block_bit_range(
            profile, profile.code_blocks - 1
        )
        var bits = _pattern(sizes[block], UInt64(250 + block))
        var segments = _workload_lte_code_block_segment(Span(bits))
        var reassembled = _workload_lte_code_block_concatenate(
            Span(segments.bits), segments.profile
        )
        checksum = _mix(checksum, profile.code_blocks)
        checksum = _mix(checksum, profile.filler_bits)
        checksum = _mix(checksum, last_range[1] - last_range[0])
        checksum = _mix(checksum, Int(reassembled.code_block_crc_ok))
        checksum = _mix(checksum, Int(reassembled.bits[len(bits) - 1]))
    return checksum


def _tail_biting_workload() raises -> UInt64:
    var checksum = UInt64(14695981039346656037)
    for block in range(_TAIL_BLOCKS_PER_SAMPLE):
        var bits = _pattern(32 + 8 * block, UInt64(300 + block))
        var encoded = _workload_lte_tail_biting_convolutional_encode(Span(bits))
        var decoded = _workload_lte_tail_biting_convolutional_decode_hard(Span(encoded))
        var llrs = List[Float64](capacity=len(encoded))
        for encoded_bit in encoded:
            llrs.append(3.0 if encoded_bit == 0 else -3.0)
        var soft_decoded = _workload_lte_tail_biting_convolutional_decode_soft(Span(llrs))
        for bit in decoded:
            checksum = _mix(checksum, Int(bit))
        for bit in soft_decoded:
            checksum = _mix(checksum, Int(bit))
    return checksum


def _turbo_workload() raises -> UInt64:
    var checksum = UInt64(14695981039346656037)
    var block_sizes: List[Int] = [40, 48, 56, 64]
    for block in range(_TURBO_BLOCKS_PER_SAMPLE):
        var block_size = block_sizes[block]
        var bits = _pattern(block_size, UInt64(600 + block))
        var encoded = _workload_lte_turbo_encode(Span(bits))
        var subblock = _workload_lte_turbo_subblock_interleave(Span(encoded.systematic))
        var circular = _workload_lte_turbo_circular_buffer(
            Span(encoded.systematic),
            Span(encoded.parity1),
            Span(encoded.parity2),
        )
        checksum = _mix(checksum, subblock.rows)
        checksum = _mix(checksum, len(circular.bits))
        checksum = _mix(checksum, _workload_lte_turbo_k0(block_size + 4, block))
        var matched = _workload_lte_turbo_rate_match(
            Span(encoded.systematic),
            Span(encoded.parity1),
            Span(encoded.parity2),
            block,
            3 * (block_size + 4),
        )
        var llrs = List[Float64](capacity=len(matched))
        for index in range(len(matched)):
            llrs.append(5.0 if matched[index] == 0 else -5.0)
        var recovered = _workload_lte_turbo_rate_recover(
            Span(llrs), block_size, block
        )
        var decoded = _workload_lte_turbo_decode_max_log(
            Span(recovered.systematic),
            Span(recovered.parity1),
            Span(recovered.parity2),
        )
        for bit in decoded.bits:
            checksum = _mix(checksum, Int(bit))
        checksum = _mix(checksum, decoded.iterations)
    return checksum


def _benchmark_qpp() raises -> UInt64:
    for _ in range(_WARMUP):
        keep(_qpp_table_workload())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(0)
    for sample in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var one_checksum = _qpp_table_workload()
        samples.append(global_perf_counter_ns() - start)
        keep(one_checksum)
        checksum ^= one_checksum + UInt64(sample)
    report_timing_samples(
        "lte_qpp_complete_table_lookup",
        samples,
        _WARMUP,
        LTE_QPP_BLOCK_SIZE_COUNT,
        denominator_unit="normative_table_row",
    )
    return checksum


def _benchmark_crc() raises -> UInt64:
    for _ in range(_WARMUP):
        keep(_crc_workload())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(0)
    for sample in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var one_checksum = _crc_workload()
        samples.append(global_perf_counter_ns() - start)
        keep(one_checksum)
        checksum ^= one_checksum + UInt64(sample)
    report_timing_samples(
        "lte_crc_compute_append_check",
        samples,
        _WARMUP,
        _CRC_BLOCKS_PER_SAMPLE,
        denominator_unit="four_polynomial_block_set",
    )
    return checksum


def _benchmark_segmentation() raises -> UInt64:
    for _ in range(_WARMUP):
        keep(_segmentation_workload())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(0)
    for sample in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var one_checksum = _segmentation_workload()
        samples.append(global_perf_counter_ns() - start)
        keep(one_checksum)
        checksum ^= one_checksum + UInt64(sample)
    report_timing_samples(
        "lte_code_block_segment_crc_concatenate",
        samples,
        _WARMUP,
        _SEGMENT_BLOCKS_PER_SAMPLE,
        denominator_unit="segmented_transport_block",
    )
    return checksum


def _benchmark_tail_biting() raises -> UInt64:
    for _ in range(_WARMUP):
        keep(_tail_biting_workload())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(0)
    for sample in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var one_checksum = _tail_biting_workload()
        samples.append(global_perf_counter_ns() - start)
        keep(one_checksum)
        checksum ^= one_checksum + UInt64(sample)
    report_timing_samples(
        "lte_tail_biting_encode_hard_decode",
        samples,
        _WARMUP,
        _TAIL_BLOCKS_PER_SAMPLE,
        denominator_unit="encoded_and_decoded_block",
    )
    return checksum


def _benchmark_turbo() raises -> UInt64:
    for _ in range(_WARMUP):
        keep(_turbo_workload())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(0)
    for sample in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var one_checksum = _turbo_workload()
        samples.append(global_perf_counter_ns() - start)
        keep(one_checksum)
        checksum ^= one_checksum + UInt64(sample)
    report_timing_samples(
        "lte_turbo_encode_rate_match_recover_max_log_decode",
        samples,
        _WARMUP,
        _TURBO_BLOCKS_PER_SAMPLE,
        denominator_unit="four_iteration_block_chain",
    )
    return checksum


def _report_api(name: StringSlice, mut samples: List[UInt64]) raises:
    report_timing_samples(name, samples, _WARMUP, 1, "api_call")


def main() raises:
    print_benchmark_metadata()
    print("lte_coding_standard_baseline:", "3GPP-TS-36.212-V18.1.0")
    print("execution_scope:", "cpu_reference_algorithms")
    print("timing_scope_includes_allocations:", True)
    # All owned fixtures and Span views precede every timed region.
    var crc_bits = _pattern(72, UInt64(200))
    var crc_bits_span = Span(crc_bits)
    var crc24a_word = _workload_lte_crc24a_append(crc_bits_span)
    var crc24b_word = _workload_lte_crc24b_append(crc_bits_span)
    var crc16_word = _workload_lte_crc16_append(crc_bits_span)
    var crc8_word = _workload_lte_crc8_append(crc_bits_span)
    var crc24a_word_span = Span(crc24a_word)
    var crc24b_word_span = Span(crc24b_word)
    var crc16_word_span = Span(crc16_word)
    var crc8_word_span = Span(crc8_word)

    var tail_bits = _pattern(40, UInt64(300))
    var tail_bits_span = Span(tail_bits)
    var tail_encoded = _workload_lte_tail_biting_convolutional_encode(tail_bits_span)
    var tail_encoded_span = Span(tail_encoded)
    var tail_llrs = List[Float64](capacity=len(tail_encoded))
    for bit in tail_encoded:
        tail_llrs.append(3.0 if bit == 0 else -3.0)
    var tail_llrs_span = Span(tail_llrs)

    var qpp_bits = _pattern(512, UInt64(417))
    var qpp_bits_span = Span(qpp_bits)
    var qpp_parameters = _workload_lte_qpp_parameters(512)
    var qpp_interleaved = _workload_lte_qpp_interleave(qpp_bits_span)
    var qpp_interleaved_span = Span(qpp_interleaved)

    var segmentation_bits = _pattern(12000, UInt64(250))
    var segmentation_bits_span = Span(segmentation_bits)
    var segmentation_profile = _workload_lte_code_block_segmentation_profile(12000)
    var segmented = _workload_lte_code_block_segment(segmentation_bits_span)
    var segmented_bits_span = Span(segmented.bits)

    var turbo_bits = _pattern(512, UInt64(600))
    var turbo_bits_span = Span(turbo_bits)
    var turbo_encoded = _workload_lte_turbo_encode(turbo_bits_span)
    var turbo_systematic_span = Span(turbo_encoded.systematic)
    var turbo_parity1_span = Span(turbo_encoded.parity1)
    var turbo_parity2_span = Span(turbo_encoded.parity2)
    var turbo_matched = _workload_lte_turbo_rate_match(
        turbo_systematic_span, turbo_parity1_span, turbo_parity2_span, 2, 1536
    )
    var turbo_matched_llrs = List[Float64](capacity=len(turbo_matched))
    for bit in turbo_matched:
        turbo_matched_llrs.append(5.0 if bit == 0 else -5.0)
    var turbo_matched_llrs_span = Span(turbo_matched_llrs)
    var turbo_recovered = _workload_lte_turbo_rate_recover(
        turbo_matched_llrs_span, 512, 2
    )
    var recovered_systematic_span = Span(turbo_recovered.systematic)
    var recovered_parity1_span = Span(turbo_recovered.parity1)
    var recovered_parity2_span = Span(turbo_recovered.parity2)

    for _ in range(_WARMUP):
        keep(_workload_lte_crc24a(crc_bits_span))
        keep(_workload_lte_crc24a_append(crc_bits_span))
        keep(_workload_lte_crc24a_check(crc24a_word_span))
        keep(_workload_lte_crc24b(crc_bits_span))
        keep(_workload_lte_crc24b_append(crc_bits_span))
        keep(_workload_lte_crc24b_check(crc24b_word_span))
        keep(_workload_lte_crc16(crc_bits_span))
        keep(_workload_lte_crc16_append(crc_bits_span))
        keep(_workload_lte_crc16_check(crc16_word_span))
        keep(_workload_lte_crc8(crc_bits_span))
        keep(_workload_lte_crc8_append(crc_bits_span))
        keep(_workload_lte_crc8_check(crc8_word_span))
        keep(_workload_lte_tail_biting_convolutional_encode(tail_bits_span))
        keep(_workload_lte_tail_biting_convolutional_decode_hard(tail_encoded_span))
        keep(_workload_lte_tail_biting_convolutional_decode_soft(tail_llrs_span))
        keep(_workload_lte_qpp_block_size(17))
        keep(_workload_lte_qpp_parameters(512))
        keep(_workload_lte_qpp_index(31, qpp_parameters))
        keep(_workload_lte_qpp_interleave(qpp_bits_span))
        keep(_workload_lte_qpp_deinterleave(qpp_interleaved_span))
        keep(_workload_lte_code_block_segmentation_profile(12000))
        keep(_workload_lte_code_block_bit_range(
            segmentation_profile, segmentation_profile.code_blocks - 1
        ))
        keep(_workload_lte_code_block_segment(segmentation_bits_span))
        keep(_workload_lte_code_block_concatenate(
            segmented_bits_span, segmentation_profile
        ))
        keep(_workload_lte_turbo_encode(turbo_bits_span))
        keep(_workload_lte_turbo_subblock_interleave(turbo_systematic_span))
        keep(_workload_lte_turbo_circular_buffer(
            turbo_systematic_span, turbo_parity1_span, turbo_parity2_span
        ))
        keep(_workload_lte_turbo_k0(516, 2))
        keep(_workload_lte_turbo_rate_match(
            turbo_systematic_span, turbo_parity1_span, turbo_parity2_span, 2, 1536
        ))
        keep(_workload_lte_turbo_rate_recover(turbo_matched_llrs_span, 512, 2))
        keep(_workload_lte_turbo_decode_max_log(
            recovered_systematic_span, recovered_parity1_span, recovered_parity2_span
        ))

    var samples0 = List[UInt64](capacity=_SAMPLES)
    var samples1 = List[UInt64](capacity=_SAMPLES)
    var samples2 = List[UInt64](capacity=_SAMPLES)
    var samples3 = List[UInt64](capacity=_SAMPLES)
    var samples4 = List[UInt64](capacity=_SAMPLES)
    var samples5 = List[UInt64](capacity=_SAMPLES)
    var samples6 = List[UInt64](capacity=_SAMPLES)
    var samples7 = List[UInt64](capacity=_SAMPLES)
    var samples8 = List[UInt64](capacity=_SAMPLES)
    var samples9 = List[UInt64](capacity=_SAMPLES)
    var samples10 = List[UInt64](capacity=_SAMPLES)
    var samples11 = List[UInt64](capacity=_SAMPLES)
    var samples12 = List[UInt64](capacity=_SAMPLES)
    var samples13 = List[UInt64](capacity=_SAMPLES)
    var samples14 = List[UInt64](capacity=_SAMPLES)
    var samples15 = List[UInt64](capacity=_SAMPLES)
    var samples16 = List[UInt64](capacity=_SAMPLES)
    var samples17 = List[UInt64](capacity=_SAMPLES)
    var samples18 = List[UInt64](capacity=_SAMPLES)
    var samples19 = List[UInt64](capacity=_SAMPLES)
    var samples20 = List[UInt64](capacity=_SAMPLES)
    var samples21 = List[UInt64](capacity=_SAMPLES)
    var samples22 = List[UInt64](capacity=_SAMPLES)
    var samples23 = List[UInt64](capacity=_SAMPLES)
    var samples24 = List[UInt64](capacity=_SAMPLES)
    var samples25 = List[UInt64](capacity=_SAMPLES)
    var samples26 = List[UInt64](capacity=_SAMPLES)
    var samples27 = List[UInt64](capacity=_SAMPLES)
    var samples28 = List[UInt64](capacity=_SAMPLES)
    var samples29 = List[UInt64](capacity=_SAMPLES)
    var samples30 = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(14695981039346656037)

    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var r0 = _workload_lte_crc24a(crc_bits_span)
        samples0.append(global_perf_counter_ns() - start)
        keep(r0); checksum = _mix(checksum, Int(r0))
        start = global_perf_counter_ns()
        var r1 = _workload_lte_crc24a_append(crc_bits_span)
        samples1.append(global_perf_counter_ns() - start)
        keep(r1); checksum = _mix(checksum, len(r1) + Int(r1[len(r1) - 1]))
        start = global_perf_counter_ns()
        var r2 = _workload_lte_crc24a_check(crc24a_word_span)
        samples2.append(global_perf_counter_ns() - start)
        keep(r2); checksum = _mix(checksum, Int(r2))
        start = global_perf_counter_ns()
        var r3 = _workload_lte_crc24b(crc_bits_span)
        samples3.append(global_perf_counter_ns() - start)
        keep(r3); checksum = _mix(checksum, Int(r3))
        start = global_perf_counter_ns()
        var r4 = _workload_lte_crc24b_append(crc_bits_span)
        samples4.append(global_perf_counter_ns() - start)
        keep(r4); checksum = _mix(checksum, len(r4) + Int(r4[len(r4) - 1]))
        start = global_perf_counter_ns()
        var r5 = _workload_lte_crc24b_check(crc24b_word_span)
        samples5.append(global_perf_counter_ns() - start)
        keep(r5); checksum = _mix(checksum, Int(r5))
        start = global_perf_counter_ns()
        var r6 = _workload_lte_crc16(crc_bits_span)
        samples6.append(global_perf_counter_ns() - start)
        keep(r6); checksum = _mix(checksum, Int(r6))
        start = global_perf_counter_ns()
        var r7 = _workload_lte_crc16_append(crc_bits_span)
        samples7.append(global_perf_counter_ns() - start)
        keep(r7); checksum = _mix(checksum, len(r7) + Int(r7[len(r7) - 1]))
        start = global_perf_counter_ns()
        var r8 = _workload_lte_crc16_check(crc16_word_span)
        samples8.append(global_perf_counter_ns() - start)
        keep(r8); checksum = _mix(checksum, Int(r8))
        start = global_perf_counter_ns()
        var r9 = _workload_lte_crc8(crc_bits_span)
        samples9.append(global_perf_counter_ns() - start)
        keep(r9); checksum = _mix(checksum, Int(r9))
        start = global_perf_counter_ns()
        var r10 = _workload_lte_crc8_append(crc_bits_span)
        samples10.append(global_perf_counter_ns() - start)
        keep(r10); checksum = _mix(checksum, len(r10) + Int(r10[len(r10) - 1]))
        start = global_perf_counter_ns()
        var r11 = _workload_lte_crc8_check(crc8_word_span)
        samples11.append(global_perf_counter_ns() - start)
        keep(r11); checksum = _mix(checksum, Int(r11))
        start = global_perf_counter_ns()
        var r12 = _workload_lte_tail_biting_convolutional_encode(tail_bits_span)
        samples12.append(global_perf_counter_ns() - start)
        keep(r12); checksum = _mix(checksum, len(r12) + Int(r12[0]))
        start = global_perf_counter_ns()
        var r13 = _workload_lte_tail_biting_convolutional_decode_hard(tail_encoded_span)
        samples13.append(global_perf_counter_ns() - start)
        keep(r13); checksum = _mix(checksum, len(r13) + Int(r13[0]))
        start = global_perf_counter_ns()
        var r14 = _workload_lte_tail_biting_convolutional_decode_soft(tail_llrs_span)
        samples14.append(global_perf_counter_ns() - start)
        keep(r14); checksum = _mix(checksum, len(r14) + Int(r14[0]))
        start = global_perf_counter_ns()
        var r15 = _workload_lte_qpp_block_size(17)
        samples15.append(global_perf_counter_ns() - start)
        keep(r15); checksum = _mix(checksum, r15)
        start = global_perf_counter_ns()
        var r16 = _workload_lte_qpp_parameters(512)
        samples16.append(global_perf_counter_ns() - start)
        keep(r16); checksum = _mix(checksum, r16.f1 + r16.f2)
        start = global_perf_counter_ns()
        var r17 = _workload_lte_qpp_index(31, qpp_parameters)
        samples17.append(global_perf_counter_ns() - start)
        keep(r17); checksum = _mix(checksum, r17)
        start = global_perf_counter_ns()
        var r18 = _workload_lte_qpp_interleave(qpp_bits_span)
        samples18.append(global_perf_counter_ns() - start)
        keep(r18); checksum = _mix(checksum, len(r18) + Int(r18[0]))
        start = global_perf_counter_ns()
        var r19 = _workload_lte_qpp_deinterleave(qpp_interleaved_span)
        samples19.append(global_perf_counter_ns() - start)
        keep(r19); checksum = _mix(checksum, len(r19) + Int(r19[0]))
        start = global_perf_counter_ns()
        var r20 = _workload_lte_code_block_segmentation_profile(12000)
        samples20.append(global_perf_counter_ns() - start)
        keep(r20); checksum = _mix(checksum, r20.code_blocks + r20.filler_bits)
        start = global_perf_counter_ns()
        var r21 = _workload_lte_code_block_bit_range(
            segmentation_profile, segmentation_profile.code_blocks - 1
        )
        samples21.append(global_perf_counter_ns() - start)
        keep(r21); checksum = _mix(checksum, r21[1] - r21[0])
        start = global_perf_counter_ns()
        var r22 = _workload_lte_code_block_segment(segmentation_bits_span)
        samples22.append(global_perf_counter_ns() - start)
        keep(r22); checksum = _mix(checksum, len(r22.bits) + Int(r22.bits[0]))
        start = global_perf_counter_ns()
        var r23 = _workload_lte_code_block_concatenate(
            segmented_bits_span, segmentation_profile
        )
        samples23.append(global_perf_counter_ns() - start)
        keep(r23); checksum = _mix(checksum, len(r23.bits) + Int(r23.code_block_crc_ok))
        start = global_perf_counter_ns()
        var r24 = _workload_lte_turbo_encode(turbo_bits_span)
        samples24.append(global_perf_counter_ns() - start)
        keep(r24); checksum = _mix(checksum, len(r24.systematic) + Int(r24.systematic[0]))
        start = global_perf_counter_ns()
        var r25 = _workload_lte_turbo_subblock_interleave(turbo_systematic_span)
        samples25.append(global_perf_counter_ns() - start)
        keep(r25); checksum = _mix(checksum, len(r25.bits) + r25.rows)
        start = global_perf_counter_ns()
        var r26 = _workload_lte_turbo_circular_buffer(
            turbo_systematic_span, turbo_parity1_span, turbo_parity2_span
        )
        samples26.append(global_perf_counter_ns() - start)
        keep(r26); checksum = _mix(checksum, len(r26.bits) + r26.rows)
        start = global_perf_counter_ns()
        var r27 = _workload_lte_turbo_k0(516, 2)
        samples27.append(global_perf_counter_ns() - start)
        keep(r27); checksum = _mix(checksum, r27)
        start = global_perf_counter_ns()
        var r28 = _workload_lte_turbo_rate_match(
            turbo_systematic_span, turbo_parity1_span, turbo_parity2_span, 2, 1536
        )
        samples28.append(global_perf_counter_ns() - start)
        keep(r28); checksum = _mix(checksum, len(r28) + Int(r28[0]))
        start = global_perf_counter_ns()
        var r29 = _workload_lte_turbo_rate_recover(turbo_matched_llrs_span, 512, 2)
        samples29.append(global_perf_counter_ns() - start)
        keep(r29); checksum = _mix(checksum, len(r29.systematic) + Int(abs(r29.systematic[0]) * 1000.0))
        start = global_perf_counter_ns()
        var r30 = _workload_lte_turbo_decode_max_log(
            recovered_systematic_span, recovered_parity1_span, recovered_parity2_span
        )
        samples30.append(global_perf_counter_ns() - start)
        keep(r30); checksum = _mix(checksum, len(r30.bits) + r30.iterations)

    _report_api("lte_crc24a", samples0)
    _report_api("lte_crc24a_append", samples1)
    _report_api("lte_crc24a_check", samples2)
    _report_api("lte_crc24b", samples3)
    _report_api("lte_crc24b_append", samples4)
    _report_api("lte_crc24b_check", samples5)
    _report_api("lte_crc16", samples6)
    _report_api("lte_crc16_append", samples7)
    _report_api("lte_crc16_check", samples8)
    _report_api("lte_crc8", samples9)
    _report_api("lte_crc8_append", samples10)
    _report_api("lte_crc8_check", samples11)
    _report_api("lte_tail_biting_convolutional_encode", samples12)
    _report_api("lte_tail_biting_convolutional_decode_hard", samples13)
    _report_api("lte_tail_biting_convolutional_decode_soft", samples14)
    _report_api("lte_qpp_block_size", samples15)
    _report_api("lte_qpp_parameters", samples16)
    _report_api("lte_qpp_index", samples17)
    _report_api("lte_qpp_interleave", samples18)
    _report_api("lte_qpp_deinterleave", samples19)
    _report_api("lte_code_block_segmentation_profile", samples20)
    _report_api("lte_code_block_bit_range", samples21)
    _report_api("lte_code_block_segment", samples22)
    _report_api("lte_code_block_concatenate", samples23)
    _report_api("lte_turbo_encode", samples24)
    _report_api("lte_turbo_subblock_interleave", samples25)
    _report_api("lte_turbo_circular_buffer", samples26)
    _report_api("lte_turbo_k0", samples27)
    _report_api("lte_turbo_rate_match", samples28)
    _report_api("lte_turbo_rate_recover", samples29)
    _report_api("lte_turbo_decode_max_log", samples30)
    keep(checksum)
    print("lte_coding_retained_checksum:", checksum)
