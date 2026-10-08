"""Bounded bit-exact fixed-point NR PDSCH frequency-selective reference.

This module is a hardware-facing golden model for one deliberately bounded
3GPP NR downlink configuration.  It models one normal-CP, single-layer,
single-codeword, QPSK PDSCH OFDM symbol at mu=0 with a 512-point transform,
36-sample CP, and a contiguous 480-RE allocation.  Configuration-type-1
comb-2 DM-RS occupies half the REs.  The other 240 REs carry the 480
rate-matched bits of a 100-bit transport block encoded at target rate 1/2.

The complete physical path is integer and bit-exact: Gold scrambling, QPSK
mapping, grid placement, IFFT/CP, a configurable two- or three-tap causal
channel, FFT, per-pilot LS, comb-2 interpolation, per-tone ZF, coordinate
LLRs, and hard decisions.  Every multiplication, accumulator, reciprocal,
rounding, and overflow boundary is selected by ``FixedNRPDSCHFormats``.
Only nearest-away rounding and saturation are accepted by the audited
contract; wrap arithmetic is rejected.

TS 38.212 CRC/LDPC encoding and rate matching feed the fixed physical path.
The receive path remains fixed after ``llrs_raw``: it performs a registered
Q20.14-to-Q10.6 rescale, Gold descrambling, RV circular-buffer recovery,
layered min-sum BG2 decoding, desegmentation, and CRC decisions without a
floating-point boundary.  A parallel Float64 decode is retained only as an
independent software audit and never selects the returned payload or status.

This is not a multi-layer receiver, a general resource scheduler, a timing or
frequency acquisition algorithm, an arbitrary numerology implementation, or
a noise model.  Those exclusions are intentional rather than implicit.
"""

from std.collections import Span
from std.math import cos, isfinite, sin, sqrt
from wireless_dsp.numerics.fixed import (
    OVERFLOW_SATURATE,
    ROUND_NEAREST_AWAY,
)
from wireless_dsp.numerics.quantization import (
    QFormat,
    dequantize_raw,
    fixed_mac_raw,
    fixed_mul_raw,
    narrow_raw,
    require_raw_fits,
    rescale_raw,
    rounded_shift_right,
)
from wireless_dsp.numerics.complex_fixed import (
    ComplexRaw,
    complex_conjugate_raw,
    complex_mac_conjugate_raw,
    complex_mul_raw,
    require_complex_fits,
)
from wireless_dsp.numerics.scale_schedule import (
    ScaleStage,
    ScaleTrace,
    apply_scale_schedule,
)
from wireless_dsp.backend.fixed_reference import complex_fir_raw
from wireless_dsp.backend.fixed_ldpc_reference import (
    FixedLDPCConfig,
    FIXED_LDPC_LAYERED,
    fixed_ldpc_default_config,
    fixed_nr_ldpc_decode_raw,
    fixed_nr_ldpc_rate_recover_raw,
)
from wireless_dsp.backend.fixed_phy_reference import (
    fixed_ofdm_demodulate_raw,
    fixed_ofdm_modulate_raw,
    fixed_qpsk_hard_bits,
    fixed_qpsk_llrs_raw,
    fixed_qpsk_map_raw,
    fixed_reciprocal_positive_raw,
)
from wireless_dsp.testing.fixed_vectors import (
    serialize_complex_fixed_vector,
    serialize_fixed_vector,
    serialize_scale_trace,
)
from wireless_dsp.wireless.nr import (
    nr_gold_bits,
    nr_ldpc_decode_code_blocks,
    nr_ldpc_desegment,
    nr_ldpc_rate_recover_code_blocks,
    nr_pdsch_descramble_llrs,
    nr_pdsch_dmrs_c_init,
    nr_pdsch_encode_transport_block,
    nr_transport_crc_check,
)


comptime FIXED_NR_PDSCH_FFT_SIZE = 512
comptime FIXED_NR_PDSCH_CP_LENGTH = 36
comptime FIXED_NR_PDSCH_FIRST_SUBCARRIER = 16
comptime FIXED_NR_PDSCH_ALLOCATION_SIZE = 480
comptime FIXED_NR_PDSCH_DATA_RE = 240
comptime FIXED_NR_PDSCH_DMRS_RE = 240
comptime FIXED_NR_PDSCH_OUTPUT_BITS = 480
comptime FIXED_NR_PDSCH_PAYLOAD_BITS = 100
comptime FIXED_NR_PDSCH_MODULATION_ORDER = 2
comptime FIXED_NR_PDSCH_MIN_TAPS = 2
comptime FIXED_NR_PDSCH_MAX_TAPS = 3
comptime FIXED_NR_PDSCH_MIN_AMPLITUDE_RAW = 4096
comptime FIXED_NR_PDSCH_MAX_AMPLITUDE_RAW = 16384
comptime _TWO_PI = 6.283185307179586476925286766559


struct FixedNRPDSCHConfig(ImplicitlyCopyable):
    """Protocol fields allowed by the bounded single-symbol reference.

    ``slot`` is bounded to the ten slots in a mu=0 radio frame.  ``codeword``
    is intentionally fixed to zero because this model has one layer and one
    codeword.  Allocation geometry, modulation, target rate, and transform
    size are compile-time constants above and cannot masquerade as a general
    scheduler through this configuration object.
    """

    var slot: Int
    var dmrs_symbol: Int
    var dmrs_offset: Int
    var n_id: Int
    var n_scid: Int
    var rnti: Int
    var redundancy_version: Int
    var decoder_llr_scale: Float64

    def __init__(
        out self,
        *,
        slot: Int = 3,
        dmrs_symbol: Int = 2,
        dmrs_offset: Int = 0,
        n_id: Int = 42,
        n_scid: Int = 0,
        rnti: Int = 0x1234,
        redundancy_version: Int = 0,
        decoder_llr_scale: Float64 = 32.0,
    ) raises:
        if slot < 0 or slot > 9:
            raise Error("fixed NR PDSCH slot must be in a mu=0 radio frame")
        if dmrs_symbol < 0 or dmrs_symbol > 13:
            raise Error("fixed NR PDSCH DM-RS symbol must be in [0,13]")
        if dmrs_offset < 0 or dmrs_offset > 1:
            raise Error("fixed NR PDSCH comb-2 offset must be zero or one")
        if n_id < 0 or n_id > 1007:
            raise Error("fixed NR PDSCH cell identity must be in [0,1007]")
        if n_scid < 0 or n_scid > 1:
            raise Error("fixed NR PDSCH n_scid must be zero or one")
        if rnti < 0 or rnti > 0xFFFF:
            raise Error("fixed NR PDSCH RNTI must be in [0,65535]")
        if redundancy_version < 0 or redundancy_version > 3:
            raise Error("fixed NR PDSCH redundancy version must be in [0,3]")
        if (
            not isfinite(decoder_llr_scale)
            or decoder_llr_scale <= 0.0
            or decoder_llr_scale > 1000000.0
        ):
            raise Error(
                "fixed NR PDSCH decoder LLR scale must be in (0,1e6]"
            )
        self.slot = slot
        self.dmrs_symbol = dmrs_symbol
        self.dmrs_offset = dmrs_offset
        self.n_id = n_id
        self.n_scid = n_scid
        self.rnti = rnti
        self.redundancy_version = redundancy_version
        self.decoder_llr_scale = decoder_llr_scale


struct FixedNRPDSCHFormats(ImplicitlyCopyable):
    """Q formats for every arithmetic boundary in the fixed physical path."""

    var symbol: QFormat
    var time: QFormat
    var tap: QFormat
    var channel_accumulator: QFormat
    var frequency: QFormat
    var channel_estimate: QFormat
    var reciprocal: QFormat
    var equalized: QFormat
    var llr: QFormat
    var twiddle: QFormat

    def __init__(
        out self,
        symbol: QFormat,
        time: QFormat,
        tap: QFormat,
        channel_accumulator: QFormat,
        frequency: QFormat,
        channel_estimate: QFormat,
        reciprocal: QFormat,
        equalized: QFormat,
        llr: QFormat,
        twiddle: QFormat,
    ):
        self.symbol = symbol
        self.time = time
        self.tap = tap
        self.channel_accumulator = channel_accumulator
        self.frequency = frequency
        self.channel_estimate = channel_estimate
        self.reciprocal = reciprocal
        self.equalized = equalized
        self.llr = llr
        self.twiddle = twiddle


struct FixedNRPDSCHAudit(ImplicitlyCopyable):
    """Float64 audit metrics computed only after raw outputs are finalized."""

    var equalized_evm_rms: Float64
    var channel_evm_rms: Float64
    var scrambled_bit_errors: Int
    var rate_matched_bit_errors: Int
    var payload_bit_errors: Int
    var physical_bits_checked: Int
    var payload_bits_checked: Int

    def __init__(
        out self,
        equalized_evm_rms: Float64,
        channel_evm_rms: Float64,
        scrambled_bit_errors: Int,
        rate_matched_bit_errors: Int,
        payload_bit_errors: Int,
        physical_bits_checked: Int,
        payload_bits_checked: Int,
    ):
        self.equalized_evm_rms = equalized_evm_rms
        self.channel_evm_rms = channel_evm_rms
        self.scrambled_bit_errors = scrambled_bit_errors
        self.rate_matched_bit_errors = rate_matched_bit_errors
        self.payload_bit_errors = payload_bit_errors
        self.physical_bits_checked = physical_bits_checked
        self.payload_bits_checked = payload_bits_checked


struct FixedNRPDSCHPhysicalCheckpoints(Movable):
    """All raw, bit-exact checkpoints from rate-matched bits through RX bits."""

    var rate_matched_bits: List[UInt8]
    var scrambling_gold_bits: List[UInt8]
    var scrambled_bits: List[UInt8]
    var mapped_data_symbols: List[ComplexRaw]
    var dmrs_gold_bits: List[UInt8]
    var dmrs_symbols: List[ComplexRaw]
    var transmit_grid: List[ComplexRaw]
    var transmit_samples: List[ComplexRaw]
    var channel_taps: List[ComplexRaw]
    var channel_samples: List[ComplexRaw]
    var received_bins: List[ComplexRaw]
    var received_dmrs: List[ComplexRaw]
    var pilot_channel_estimates: List[ComplexRaw]
    var interpolated_channel: List[ComplexRaw]
    var received_data: List[ComplexRaw]
    var equalized_data_symbols: List[ComplexRaw]
    var llrs_raw: List[Int64]
    var hard_scrambled_bits: List[UInt8]
    var hard_rate_matched_bits: List[UInt8]

    def __init__(
        out self,
        var rate_matched_bits: List[UInt8],
        var scrambling_gold_bits: List[UInt8],
        var scrambled_bits: List[UInt8],
        var mapped_data_symbols: List[ComplexRaw],
        var dmrs_gold_bits: List[UInt8],
        var dmrs_symbols: List[ComplexRaw],
        var transmit_grid: List[ComplexRaw],
        var transmit_samples: List[ComplexRaw],
        var channel_taps: List[ComplexRaw],
        var channel_samples: List[ComplexRaw],
        var received_bins: List[ComplexRaw],
        var received_dmrs: List[ComplexRaw],
        var pilot_channel_estimates: List[ComplexRaw],
        var interpolated_channel: List[ComplexRaw],
        var received_data: List[ComplexRaw],
        var equalized_data_symbols: List[ComplexRaw],
        var llrs_raw: List[Int64],
        var hard_scrambled_bits: List[UInt8],
        var hard_rate_matched_bits: List[UInt8],
    ):
        self.rate_matched_bits = rate_matched_bits^
        self.scrambling_gold_bits = scrambling_gold_bits^
        self.scrambled_bits = scrambled_bits^
        self.mapped_data_symbols = mapped_data_symbols^
        self.dmrs_gold_bits = dmrs_gold_bits^
        self.dmrs_symbols = dmrs_symbols^
        self.transmit_grid = transmit_grid^
        self.transmit_samples = transmit_samples^
        self.channel_taps = channel_taps^
        self.channel_samples = channel_samples^
        self.received_bins = received_bins^
        self.received_dmrs = received_dmrs^
        self.pilot_channel_estimates = pilot_channel_estimates^
        self.interpolated_channel = interpolated_channel^
        self.received_data = received_data^
        self.equalized_data_symbols = equalized_data_symbols^
        self.llrs_raw = llrs_raw^
        self.hard_scrambled_bits = hard_scrambled_bits^
        self.hard_rate_matched_bits = hard_rate_matched_bits^


struct FixedNRPDSCHResult(Movable):
    """Bounded coded PDSCH result with a bit-exact fixed LDPC boundary."""

    var config: FixedNRPDSCHConfig
    var amplitude_raw: Int64
    var payload_bits: List[UInt8]
    var transport_block: List[UInt8]
    var encoded_null_mask: List[UInt8]
    var base_graph: Int
    var lifting_size: Int
    var encoded_bits_per_block: Int
    var physical: FixedNRPDSCHPhysicalCheckpoints
    var fixed_decoder_config: FixedLDPCConfig
    var decoder_input_llrs_raw: List[Int64]
    var decoder_descrambled_llrs_raw: List[Int64]
    var decoder_rate_recovered_llrs_raw: List[Int64]
    var decoder_posterior_llrs_raw: List[Int64]
    var decoder_variable_to_check_raw: List[Int64]
    var decoder_check_to_variable_raw: List[Int64]
    var decoder_syndrome_weight: Int
    var decoder_rate_recovery_saturations: Int
    var decoder_ldpc_saturations: Int
    var decoder_input_llrs_float64: List[Float64]
    var decoder_descrambled_llrs_float64: List[Float64]
    var decoder_rate_recovered_llrs_float64: List[Float64]
    var float64_decoder_agrees: Bool
    var decoder_iterations: List[Int]
    var decoded_transport_block: List[UInt8]
    var decoded_payload_bits: List[UInt8]
    var ldpc_converged: Bool
    var code_block_crc_ok: Bool
    var transport_crc_ok: Bool
    var audit: FixedNRPDSCHAudit

    def __init__(
        out self,
        config: FixedNRPDSCHConfig,
        amplitude_raw: Int64,
        var payload_bits: List[UInt8],
        var transport_block: List[UInt8],
        var encoded_null_mask: List[UInt8],
        base_graph: Int,
        lifting_size: Int,
        encoded_bits_per_block: Int,
        var physical: FixedNRPDSCHPhysicalCheckpoints,
        fixed_decoder_config: FixedLDPCConfig,
        var decoder_input_llrs_raw: List[Int64],
        var decoder_descrambled_llrs_raw: List[Int64],
        var decoder_rate_recovered_llrs_raw: List[Int64],
        var decoder_posterior_llrs_raw: List[Int64],
        var decoder_variable_to_check_raw: List[Int64],
        var decoder_check_to_variable_raw: List[Int64],
        decoder_syndrome_weight: Int,
        decoder_rate_recovery_saturations: Int,
        decoder_ldpc_saturations: Int,
        var decoder_input_llrs_float64: List[Float64],
        var decoder_descrambled_llrs_float64: List[Float64],
        var decoder_rate_recovered_llrs_float64: List[Float64],
        float64_decoder_agrees: Bool,
        var decoder_iterations: List[Int],
        var decoded_transport_block: List[UInt8],
        var decoded_payload_bits: List[UInt8],
        ldpc_converged: Bool,
        code_block_crc_ok: Bool,
        transport_crc_ok: Bool,
        audit: FixedNRPDSCHAudit,
    ):
        self.config = config
        self.amplitude_raw = amplitude_raw
        self.payload_bits = payload_bits^
        self.transport_block = transport_block^
        self.encoded_null_mask = encoded_null_mask^
        self.base_graph = base_graph
        self.lifting_size = lifting_size
        self.encoded_bits_per_block = encoded_bits_per_block
        self.physical = physical^
        self.fixed_decoder_config = fixed_decoder_config
        self.decoder_input_llrs_raw = decoder_input_llrs_raw^
        self.decoder_descrambled_llrs_raw = decoder_descrambled_llrs_raw^
        self.decoder_rate_recovered_llrs_raw = (
            decoder_rate_recovered_llrs_raw^
        )
        self.decoder_posterior_llrs_raw = decoder_posterior_llrs_raw^
        self.decoder_variable_to_check_raw = decoder_variable_to_check_raw^
        self.decoder_check_to_variable_raw = decoder_check_to_variable_raw^
        self.decoder_syndrome_weight = decoder_syndrome_weight
        self.decoder_rate_recovery_saturations = (
            decoder_rate_recovery_saturations
        )
        self.decoder_ldpc_saturations = decoder_ldpc_saturations
        self.decoder_input_llrs_float64 = decoder_input_llrs_float64^
        self.decoder_descrambled_llrs_float64 = (
            decoder_descrambled_llrs_float64^
        )
        self.decoder_rate_recovered_llrs_float64 = (
            decoder_rate_recovered_llrs_float64^
        )
        self.float64_decoder_agrees = float64_decoder_agrees
        self.decoder_iterations = decoder_iterations^
        self.decoded_transport_block = decoded_transport_block^
        self.decoded_payload_bits = decoded_payload_bits^
        self.ldpc_converged = ldpc_converged
        self.code_block_crc_ok = code_block_crc_ok
        self.transport_crc_ok = transport_crc_ok
        self.audit = audit


struct _FixedNRBitsPair(Movable):
    var first: List[UInt8]
    var second: List[UInt8]

    def __init__(
        out self, var first: List[UInt8], var second: List[UInt8]
    ):
        self.first = first^
        self.second = second^


struct _FixedNRDMRSPair(Movable):
    var bits: List[UInt8]
    var symbols: List[ComplexRaw]

    def __init__(
        out self, var bits: List[UInt8], var symbols: List[ComplexRaw]
    ):
        self.bits = bits^
        self.symbols = symbols^


struct _FixedNRExtracted(Movable):
    var data: List[ComplexRaw]
    var dmrs: List[ComplexRaw]

    def __init__(
        out self, var data: List[ComplexRaw], var dmrs: List[ComplexRaw]
    ):
        self.data = data^
        self.dmrs = dmrs^


def fixed_nr_pdsch_default_formats() raises -> FixedNRPDSCHFormats:
    """Return the audited nearest-away, saturating fixed-point contract."""
    return FixedNRPDSCHFormats(
        QFormat(18, 14, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(18, 14, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(18, 14, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(30, 20, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(24, 14, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(18, 14, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(24, 18, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(18, 14, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(20, 14, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
        QFormat(18, 16, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE),
    )


def _validate_formats(formats: FixedNRPDSCHFormats) raises:
    for qformat in [
        formats.symbol,
        formats.time,
        formats.tap,
        formats.channel_accumulator,
        formats.frequency,
        formats.channel_estimate,
        formats.reciprocal,
        formats.equalized,
        formats.llr,
        formats.twiddle,
    ]:
        if qformat.rounding_mode != ROUND_NEAREST_AWAY:
            raise Error("fixed NR PDSCH requires nearest-away rounding")
        if qformat.overflow_mode != OVERFLOW_SATURATE:
            raise Error("fixed NR PDSCH rejects wrap arithmetic")
    if (
        formats.symbol.storage_bits != 18
        or formats.symbol.fraction_bits != 14
        or formats.time.storage_bits != 18
        or formats.time.fraction_bits != 14
        or formats.tap.storage_bits != 18
        or formats.tap.fraction_bits != 14
        or formats.channel_accumulator.storage_bits != 30
        or formats.channel_accumulator.fraction_bits != 20
        or formats.frequency.storage_bits != 24
        or formats.frequency.fraction_bits != 14
        or formats.channel_estimate.storage_bits != 18
        or formats.channel_estimate.fraction_bits != 14
        or formats.reciprocal.storage_bits != 24
        or formats.reciprocal.fraction_bits != 18
        or formats.equalized.storage_bits != 18
        or formats.equalized.fraction_bits != 14
        or formats.llr.storage_bits != 20
        or formats.llr.fraction_bits != 14
        or formats.twiddle.storage_bits != 18
        or formats.twiddle.fraction_bits != 16
    ):
        raise Error("fixed NR PDSCH requires the audited default Q contract")


def _validate_taps(
    taps: Span[ComplexRaw, ...], formats: FixedNRPDSCHFormats
) raises:
    if len(taps) < FIXED_NR_PDSCH_MIN_TAPS or len(taps) > FIXED_NR_PDSCH_MAX_TAPS:
        raise Error("fixed NR PDSCH channel requires two or three taps")
    if len(taps) - 1 > FIXED_NR_PDSCH_CP_LENGTH:
        raise Error("fixed NR PDSCH channel delay exceeds the cyclic prefix")
    var any_nonzero = False
    for index in range(len(taps)):
        var tap = ComplexRaw(taps[index].re, taps[index].im)
        require_complex_fits(tap, formats.tap)
        any_nonzero = any_nonzero or tap.re != 0 or tap.im != 0
    if not any_nonzero:
        raise Error("fixed NR PDSCH channel cannot contain only zero taps")


def _copy_bits(values: Span[UInt8, ...]) raises -> List[UInt8]:
    var result = List[UInt8](capacity=len(values))
    for index in range(len(values)):
        if values[index] > 1:
            raise Error("fixed NR PDSCH inputs must be binary")
        result.append(values[index])
    return result^


def _scramble_bits(
    bits: Span[UInt8, ...], config: FixedNRPDSCHConfig
) raises -> _FixedNRBitsPair:
    var c_init = UInt32((config.rnti << 15) + config.n_id)
    var gold = nr_gold_bits(c_init, len(bits))
    var scrambled = List[UInt8](capacity=len(bits))
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("fixed NR PDSCH rate-matched bits must be binary")
        scrambled.append(bits[index] ^ gold[index])
    return _FixedNRBitsPair(gold^, scrambled^)


def _fixed_dmrs(
    config: FixedNRPDSCHConfig,
    formats: FixedNRPDSCHFormats,
    amplitude_raw: Int64,
) raises -> _FixedNRDMRSPair:
    var c_init = nr_pdsch_dmrs_c_init(
        config.slot, config.dmrs_symbol, config.n_id, config.n_scid
    )
    var bits = nr_gold_bits(c_init, 2 * FIXED_NR_PDSCH_DMRS_RE)
    var symbols = fixed_qpsk_map_raw(
        Span(bits), formats.symbol, amplitude_raw
    )
    return _FixedNRDMRSPair(bits^, symbols^)


def _map_comb2_grid(
    data: Span[ComplexRaw, ...],
    dmrs: Span[ComplexRaw, ...],
    config: FixedNRPDSCHConfig,
    formats: FixedNRPDSCHFormats,
) raises -> List[ComplexRaw]:
    if len(data) != FIXED_NR_PDSCH_DATA_RE or len(dmrs) != FIXED_NR_PDSCH_DMRS_RE:
        raise Error("fixed NR PDSCH data/DM-RS counts do not match the grid")
    var result = List[ComplexRaw](
        length=FIXED_NR_PDSCH_FFT_SIZE, fill=ComplexRaw()
    )
    var data_index = 0
    var pilot_index = 0
    for local in range(FIXED_NR_PDSCH_ALLOCATION_SIZE):
        var bin = FIXED_NR_PDSCH_FIRST_SUBCARRIER + local
        if local % 2 == config.dmrs_offset:
            var value = ComplexRaw(dmrs[pilot_index].re, dmrs[pilot_index].im)
            require_complex_fits(value, formats.symbol)
            result[bin] = value
            pilot_index += 1
        else:
            var value = ComplexRaw(data[data_index].re, data[data_index].im)
            require_complex_fits(value, formats.symbol)
            result[bin] = value
            data_index += 1
    if data_index != len(data) or pilot_index != len(dmrs):
        raise Error("fixed NR PDSCH comb-2 mapper did not consume its inputs")
    return result^


def _extract_comb2(
    bins: Span[ComplexRaw, ...],
    config: FixedNRPDSCHConfig,
    formats: FixedNRPDSCHFormats,
) raises -> _FixedNRExtracted:
    if len(bins) != FIXED_NR_PDSCH_FFT_SIZE:
        raise Error("fixed NR PDSCH receiver requires one complete FFT")
    var data = List[ComplexRaw](capacity=FIXED_NR_PDSCH_DATA_RE)
    var pilots = List[ComplexRaw](capacity=FIXED_NR_PDSCH_DMRS_RE)
    for local in range(FIXED_NR_PDSCH_ALLOCATION_SIZE):
        var value = ComplexRaw(
            bins[FIXED_NR_PDSCH_FIRST_SUBCARRIER + local].re,
            bins[FIXED_NR_PDSCH_FIRST_SUBCARRIER + local].im,
        )
        require_complex_fits(value, formats.frequency)
        if local % 2 == config.dmrs_offset:
            pilots.append(value)
        else:
            data.append(value)
    return _FixedNRExtracted(data^, pilots^)


def _fixed_ls_one(
    received: ComplexRaw,
    reference: ComplexRaw,
    formats: FixedNRPDSCHFormats,
) raises -> ComplexRaw:
    var numerator = complex_mac_conjugate_raw(
        ComplexRaw(),
        reference,
        formats.symbol,
        received,
        formats.frequency,
        formats.channel_accumulator,
    )
    var power = fixed_mac_raw(
        Int64(0),
        reference.re,
        formats.symbol,
        reference.re,
        formats.symbol,
        formats.channel_accumulator,
    )
    power = fixed_mac_raw(
        power,
        reference.im,
        formats.symbol,
        reference.im,
        formats.symbol,
        formats.channel_accumulator,
    )
    var reciprocal = fixed_reciprocal_positive_raw(
        power, formats.channel_accumulator, formats.reciprocal
    )
    return ComplexRaw(
        fixed_mul_raw(
            numerator.re,
            formats.channel_accumulator,
            reciprocal,
            formats.reciprocal,
            formats.channel_estimate,
        ),
        fixed_mul_raw(
            numerator.im,
            formats.channel_accumulator,
            reciprocal,
            formats.reciprocal,
            formats.channel_estimate,
        ),
    )


def _fixed_ls_pilots(
    received: Span[ComplexRaw, ...],
    references: Span[ComplexRaw, ...],
    formats: FixedNRPDSCHFormats,
) raises -> List[ComplexRaw]:
    if len(received) != FIXED_NR_PDSCH_DMRS_RE or len(references) != len(received):
        raise Error("fixed NR PDSCH LS pilot vectors have invalid dimensions")
    var result = List[ComplexRaw](capacity=len(received))
    for index in range(len(received)):
        result.append(
            _fixed_ls_one(
                ComplexRaw(received[index].re, received[index].im),
                ComplexRaw(references[index].re, references[index].im),
                formats,
            )
        )
    return result^


def _average_raw(
    lhs: Int64, rhs: Int64, qformat: QFormat
) raises -> Int64:
    require_raw_fits(lhs, qformat)
    require_raw_fits(rhs, qformat)
    return narrow_raw(
        rounded_shift_right(
            lhs + rhs, 1, qformat.rounding_mode
        ),
        qformat,
    )


def _interpolate_comb2(
    pilots: Span[ComplexRaw, ...],
    config: FixedNRPDSCHConfig,
    formats: FixedNRPDSCHFormats,
) raises -> List[ComplexRaw]:
    if len(pilots) != FIXED_NR_PDSCH_DMRS_RE:
        raise Error("fixed NR PDSCH interpolation needs every comb-2 pilot")
    var result = List[ComplexRaw](capacity=FIXED_NR_PDSCH_ALLOCATION_SIZE)
    for local in range(FIXED_NR_PDSCH_ALLOCATION_SIZE):
        if local % 2 == config.dmrs_offset:
            var index = (local - config.dmrs_offset) // 2
            result.append(ComplexRaw(pilots[index].re, pilots[index].im))
        elif local < config.dmrs_offset:
            result.append(ComplexRaw(pilots[0].re, pilots[0].im))
        else:
            var left = (local - config.dmrs_offset) // 2
            var right = left + 1
            if right >= len(pilots):
                result.append(
                    ComplexRaw(pilots[left].re, pilots[left].im)
                )
            else:
                result.append(
                    ComplexRaw(
                        _average_raw(
                            pilots[left].re,
                            pilots[right].re,
                            formats.channel_estimate,
                        ),
                        _average_raw(
                            pilots[left].im,
                            pilots[right].im,
                            formats.channel_estimate,
                        ),
                    )
                )
    return result^


def _fixed_zf_one(
    received: ComplexRaw,
    channel: ComplexRaw,
    formats: FixedNRPDSCHFormats,
) raises -> ComplexRaw:
    require_complex_fits(received, formats.frequency)
    require_complex_fits(channel, formats.channel_estimate)
    var power = fixed_mac_raw(
        Int64(0),
        channel.re,
        formats.channel_estimate,
        channel.re,
        formats.channel_estimate,
        formats.channel_accumulator,
    )
    power = fixed_mac_raw(
        power,
        channel.im,
        formats.channel_estimate,
        channel.im,
        formats.channel_estimate,
        formats.channel_accumulator,
    )
    var reciprocal = fixed_reciprocal_positive_raw(
        power, formats.channel_accumulator, formats.reciprocal
    )
    var conjugate = complex_conjugate_raw(
        channel, formats.channel_estimate
    )
    var numerator = complex_mul_raw(
        received,
        formats.frequency,
        conjugate,
        formats.channel_estimate,
        formats.channel_accumulator,
    )
    return ComplexRaw(
        fixed_mul_raw(
            numerator.re,
            formats.channel_accumulator,
            reciprocal,
            formats.reciprocal,
            formats.equalized,
        ),
        fixed_mul_raw(
            numerator.im,
            formats.channel_accumulator,
            reciprocal,
            formats.reciprocal,
            formats.equalized,
        ),
    )


def _fixed_equalize_data(
    received: Span[ComplexRaw, ...],
    channel: Span[ComplexRaw, ...],
    config: FixedNRPDSCHConfig,
    formats: FixedNRPDSCHFormats,
) raises -> List[ComplexRaw]:
    if (
        len(received) != FIXED_NR_PDSCH_DATA_RE
        or len(channel) != FIXED_NR_PDSCH_ALLOCATION_SIZE
    ):
        raise Error("fixed NR PDSCH equalizer dimensions do not match")
    var result = List[ComplexRaw](capacity=len(received))
    var data_index = 0
    for local in range(FIXED_NR_PDSCH_ALLOCATION_SIZE):
        if local % 2 != config.dmrs_offset:
            result.append(
                _fixed_zf_one(
                    ComplexRaw(
                        received[data_index].re, received[data_index].im
                    ),
                    ComplexRaw(channel[local].re, channel[local].im),
                    formats,
                )
            )
            data_index += 1
    return result^


def _descramble_hard(
    hard_bits: Span[UInt8, ...], gold: Span[UInt8, ...]
) raises -> List[UInt8]:
    if len(hard_bits) != len(gold):
        raise Error("fixed NR PDSCH hard descrambling dimensions do not match")
    var result = List[UInt8](capacity=len(hard_bits))
    for index in range(len(hard_bits)):
        if hard_bits[index] > 1 or gold[index] > 1:
            raise Error("fixed NR PDSCH hard descrambling inputs must be binary")
        result.append(hard_bits[index] ^ gold[index])
    return result^


def _bit_errors(
    lhs: Span[UInt8, ...], rhs: Span[UInt8, ...]
) raises -> Int:
    if len(lhs) != len(rhs):
        raise Error("fixed NR PDSCH bit comparison dimensions do not match")
    var errors = 0
    for index in range(len(lhs)):
        if lhs[index] > 1 or rhs[index] > 1:
            raise Error("fixed NR PDSCH bit comparisons require binary values")
        if lhs[index] != rhs[index]:
            errors += 1
    return errors


def _physical_audit(
    mapped: Span[ComplexRaw, ...],
    equalized: Span[ComplexRaw, ...],
    interpolated_channel: Span[ComplexRaw, ...],
    taps: Span[ComplexRaw, ...],
    formats: FixedNRPDSCHFormats,
) raises -> Tuple[Float64, Float64]:
    if (
        len(mapped) != len(equalized)
        or len(mapped) != FIXED_NR_PDSCH_DATA_RE
        or len(interpolated_channel) != FIXED_NR_PDSCH_ALLOCATION_SIZE
    ):
        raise Error("fixed NR PDSCH audit checkpoint dimensions are invalid")
    var error_energy = 0.0
    var reference_energy = 0.0
    for index in range(len(mapped)):
        var expected_re = dequantize_raw(mapped[index].re, formats.symbol)
        var expected_im = dequantize_raw(mapped[index].im, formats.symbol)
        var actual_re = dequantize_raw(equalized[index].re, formats.equalized)
        var actual_im = dequantize_raw(equalized[index].im, formats.equalized)
        var error_re = actual_re - expected_re
        var error_im = actual_im - expected_im
        error_energy += error_re * error_re + error_im * error_im
        reference_energy += expected_re * expected_re + expected_im * expected_im

    var channel_error = 0.0
    var channel_reference = 0.0
    for local in range(FIXED_NR_PDSCH_ALLOCATION_SIZE):
        var bin = FIXED_NR_PDSCH_FIRST_SUBCARRIER + local
        var expected_re = 0.0
        var expected_im = 0.0
        for tap_index in range(len(taps)):
            var tap_re = dequantize_raw(taps[tap_index].re, formats.tap)
            var tap_im = dequantize_raw(taps[tap_index].im, formats.tap)
            var angle = (
                -_TWO_PI * Float64(bin * tap_index)
                / Float64(FIXED_NR_PDSCH_FFT_SIZE)
            )
            var twiddle_re = cos(angle)
            var twiddle_im = sin(angle)
            expected_re += tap_re * twiddle_re - tap_im * twiddle_im
            expected_im += tap_re * twiddle_im + tap_im * twiddle_re
        var actual_re = dequantize_raw(
            interpolated_channel[local].re, formats.channel_estimate
        )
        var actual_im = dequantize_raw(
            interpolated_channel[local].im, formats.channel_estimate
        )
        var error_re = actual_re - expected_re
        var error_im = actual_im - expected_im
        channel_error += error_re * error_re + error_im * error_im
        channel_reference += expected_re * expected_re + expected_im * expected_im
    if (
        reference_energy <= 0.0
        or channel_reference <= 0.0
        or not isfinite(error_energy)
        or not isfinite(reference_energy)
        or not isfinite(channel_error)
        or not isfinite(channel_reference)
    ):
        raise Error("fixed NR PDSCH Float64 audit energy is invalid")
    return (
        sqrt(error_energy / reference_energy),
        sqrt(channel_error / channel_reference),
    )


def fixed_nr_pdsch_reference(
    payload_bits: Span[UInt8, ...],
    channel_taps: Span[ComplexRaw, ...],
    formats: FixedNRPDSCHFormats,
    amplitude_raw: Int64,
    config: FixedNRPDSCHConfig,
) raises -> FixedNRPDSCHResult:
    """Run the bounded CRC/LDPC -> fixed frequency-selective PDSCH chain.

    The production receive path stays integer through LDPC and CRC.  The
    ``decoder_*_float64`` fields are a parallel differential audit only;
    ``decoder_llr_scale`` affects that audit and never the returned payload,
    convergence, or CRC status.  Decode failure is reported through status
    and audit fields rather than concealed or converted into an exception.
    """
    _validate_formats(formats)
    _validate_taps(channel_taps, formats)
    require_raw_fits(amplitude_raw, formats.symbol)
    if (
        amplitude_raw < FIXED_NR_PDSCH_MIN_AMPLITUDE_RAW
        or amplitude_raw > FIXED_NR_PDSCH_MAX_AMPLITUDE_RAW
    ):
        raise Error("fixed NR PDSCH QPSK amplitude is outside its audited range")
    if len(payload_bits) != FIXED_NR_PDSCH_PAYLOAD_BITS:
        raise Error("fixed NR PDSCH requires exactly 100 payload bits")
    var payload = _copy_bits(payload_bits)
    var taps = List[ComplexRaw](capacity=len(channel_taps))
    for index in range(len(channel_taps)):
        taps.append(
            ComplexRaw(channel_taps[index].re, channel_taps[index].im)
        )

    var encoded = nr_pdsch_encode_transport_block(
        Span(payload),
        0.5,
        FIXED_NR_PDSCH_MODULATION_ORDER,
        config.redundancy_version,
        FIXED_NR_PDSCH_OUTPUT_BITS,
        config.rnti,
        0,
        config.n_id,
    )
    var rate_matched = encoded.rate_matched_bits.copy()
    var scrambled_pair = _scramble_bits(Span(rate_matched), config)
    var scrambling_gold = scrambled_pair.first.copy()
    var scrambled = scrambled_pair.second.copy()
    if scrambled != encoded.scrambled_bits:
        raise Error("fixed NR PDSCH Gold composition disagrees with encoder")
    var mapped = fixed_qpsk_map_raw(
        Span(scrambled), formats.symbol, amplitude_raw
    )
    var dmrs_pair = _fixed_dmrs(config, formats, amplitude_raw)
    var dmrs_gold = dmrs_pair.bits.copy()
    var dmrs = dmrs_pair.symbols.copy()
    var transmit_grid = _map_comb2_grid(
        Span(mapped), Span(dmrs), config, formats
    )
    var transmit_samples = fixed_ofdm_modulate_raw(
        Span(transmit_grid),
        formats.symbol,
        formats.time,
        formats.twiddle,
        FIXED_NR_PDSCH_CP_LENGTH,
    )
    var channel_samples = complex_fir_raw(
        Span(transmit_samples),
        Span(taps),
        formats.time,
        formats.tap,
        formats.channel_accumulator,
        formats.time,
    )
    var received_bins = fixed_ofdm_demodulate_raw(
        Span(channel_samples),
        FIXED_NR_PDSCH_FFT_SIZE,
        FIXED_NR_PDSCH_CP_LENGTH,
        formats.time,
        formats.frequency,
        formats.twiddle,
    )
    var extracted = _extract_comb2(Span(received_bins), config, formats)
    var received_data = extracted.data.copy()
    var received_dmrs = extracted.dmrs.copy()
    var pilot_estimates = _fixed_ls_pilots(
        Span(received_dmrs), Span(dmrs), formats
    )
    var interpolated = _interpolate_comb2(
        Span(pilot_estimates), config, formats
    )
    var equalized = _fixed_equalize_data(
        Span(received_data), Span(interpolated), config, formats
    )
    var llrs = fixed_qpsk_llrs_raw(
        Span(equalized), formats.equalized, formats.llr
    )
    var hard_scrambled = fixed_qpsk_hard_bits(
        Span(equalized), formats.equalized
    )
    var hard_rate_matched = _descramble_hard(
        Span(hard_scrambled), Span(scrambling_gold)
    )

    # Registered fixed receive boundary: physical Q20.14 coordinate LLRs are
    # narrowed to the canonical LDPC Q10.6 message domain before Gold
    # descrambling, circular-buffer combining, and layered min-sum decoding.
    var fixed_decoder_config = fixed_ldpc_default_config(
        max_iterations=30, schedule=FIXED_LDPC_LAYERED
    )
    var decoder_input_raw = List[Int64](capacity=len(llrs))
    var decoder_descrambled_raw = List[Int64](capacity=len(llrs))
    for index in range(len(llrs)):
        var narrowed = rescale_raw(
            llrs[index],
            formats.llr.fraction_bits,
            fixed_decoder_config.llr_format,
        )
        decoder_input_raw.append(narrowed)
        if scrambling_gold[index] != 0:
            narrowed = narrow_raw(
                -narrowed, fixed_decoder_config.llr_format
            )
        decoder_descrambled_raw.append(narrowed)
    var fixed_recovered = fixed_nr_ldpc_rate_recover_raw(
        Span(decoder_descrambled_raw),
        Span(encoded.encoded_null_mask),
        encoded.profile.base_graph,
        encoded.profile.lifting_size,
        config.redundancy_version,
        FIXED_NR_PDSCH_MODULATION_ORDER,
        fixed_decoder_config.llr_format,
        fixed_decoder_config.clip_raw,
    )
    var fixed_blocks = fixed_nr_ldpc_decode_raw(
        Span(fixed_recovered.llrs_raw),
        Span(encoded.encoded_null_mask),
        encoded.profile.base_graph,
        encoded.profile.lifting_size,
        fixed_decoder_config,
    )
    var fixed_information = fixed_blocks.bits.copy()
    var desegmented = nr_ldpc_desegment(
        Span(fixed_information), encoded.profile
    )
    var transport_crc_ok = nr_transport_crc_check(
        Span(desegmented.bits), FIXED_NR_PDSCH_PAYLOAD_BITS
    )
    var decoded_payload = List[UInt8](capacity=FIXED_NR_PDSCH_PAYLOAD_BITS)
    for index in range(FIXED_NR_PDSCH_PAYLOAD_BITS):
        decoded_payload.append(desegmented.bits[index])

    # Parallel Float64 audit.  These values are retained for diagnostics but
    # do not influence any returned bit, convergence flag, or CRC decision.
    var decoder_input = List[Float64](capacity=len(llrs))
    for index in range(len(llrs)):
        decoder_input.append(
            dequantize_raw(llrs[index], formats.llr)
            * config.decoder_llr_scale
        )
    var decoder_descrambled = nr_pdsch_descramble_llrs(
        Span(decoder_input), config.rnti, 0, config.n_id
    )
    var decoder_recovered = nr_ldpc_rate_recover_code_blocks(
        Span(decoder_descrambled),
        Span(encoded.encoded_null_mask),
        encoded.profile,
        config.redundancy_version,
        FIXED_NR_PDSCH_MODULATION_ORDER,
        1,
    )
    var audit_blocks = nr_ldpc_decode_code_blocks(
        Span(decoder_recovered),
        Span(encoded.encoded_null_mask),
        encoded.profile,
        max_iterations=30,
        normalization=0.8,
        offset=0.0,
        clip=50.0,
    )
    var audit_desegmented = nr_ldpc_desegment(
        Span(audit_blocks.bits), encoded.profile
    )
    var float64_decoder_agrees = audit_desegmented.bits == desegmented.bits

    var scrambled_errors = _bit_errors(
        Span(hard_scrambled), Span(scrambled)
    )
    var matched_errors = _bit_errors(
        Span(hard_rate_matched), Span(rate_matched)
    )
    var payload_errors = _bit_errors(
        Span(decoded_payload), Span(payload)
    )
    var (equalized_evm, channel_evm) = _physical_audit(
        Span(mapped),
        Span(equalized),
        Span(interpolated),
        Span(taps),
        formats,
    )
    var audit = FixedNRPDSCHAudit(
        equalized_evm,
        channel_evm,
        scrambled_errors,
        matched_errors,
        payload_errors,
        FIXED_NR_PDSCH_OUTPUT_BITS,
        FIXED_NR_PDSCH_PAYLOAD_BITS,
    )
    var physical = FixedNRPDSCHPhysicalCheckpoints(
        rate_matched^,
        scrambling_gold^,
        scrambled^,
        mapped^,
        dmrs_gold^,
        dmrs^,
        transmit_grid^,
        transmit_samples^,
        taps^,
        channel_samples^,
        received_bins^,
        received_dmrs^,
        pilot_estimates^,
        interpolated^,
        received_data^,
        equalized^,
        llrs^,
        hard_scrambled^,
        hard_rate_matched^,
    )
    var base_graph = encoded.profile.base_graph
    var lifting_size = encoded.profile.lifting_size
    var encoded_bits_per_block = encoded.profile.encoded_bits
    var transport_block = encoded.transport_block.copy()
    var null_mask = encoded.encoded_null_mask.copy()
    var iterations: List[Int] = [fixed_blocks.iterations]
    var decoded_transport = desegmented.bits.copy()
    var recovered_raw = fixed_recovered.llrs_raw.copy()
    var posterior_raw = fixed_blocks.posterior_raw.copy()
    var variable_to_check_raw = fixed_blocks.variable_to_check_raw.copy()
    var check_to_variable_raw = fixed_blocks.check_to_variable_raw.copy()
    return FixedNRPDSCHResult(
        config,
        amplitude_raw,
        payload^,
        transport_block^,
        null_mask^,
        base_graph,
        lifting_size,
        encoded_bits_per_block,
        physical^,
        fixed_decoder_config,
        decoder_input_raw^,
        decoder_descrambled_raw^,
        recovered_raw^,
        posterior_raw^,
        variable_to_check_raw^,
        check_to_variable_raw^,
        fixed_blocks.syndrome_weight,
        fixed_recovered.saturation_count,
        fixed_blocks.saturation_count,
        decoder_input^,
        decoder_descrambled^,
        decoder_recovered^,
        float64_decoder_agrees,
        iterations^,
        decoded_transport^,
        decoded_payload^,
        fixed_blocks.converged,
        desegmented.code_block_crc_ok,
        transport_crc_ok,
        audit,
    )


def _mix_word(mut state: UInt64, word: UInt64):
    for byte_index in range(8):
        state ^= UInt64(
            UInt8((word >> UInt64(8 * byte_index)) & UInt64(0xff))
        )
        state *= UInt64(1099511628211)


def _mix_bits(mut state: UInt64, values: Span[UInt8, ...]):
    _mix_word(state, UInt64(len(values)))
    for index in range(len(values)):
        _mix_word(state, UInt64(values[index]))


def _mix_raw(mut state: UInt64, values: Span[Int64, ...]):
    _mix_word(state, UInt64(len(values)))
    for index in range(len(values)):
        _mix_word(state, UInt64(values[index]))


def _mix_complex(mut state: UInt64, values: Span[ComplexRaw, ...]):
    _mix_word(state, UInt64(len(values)))
    for index in range(len(values)):
        _mix_word(state, UInt64(values[index].re))
        _mix_word(state, UInt64(values[index].im))


def fixed_nr_pdsch_result_checksum(result: FixedNRPDSCHResult) -> UInt64:
    """FNV-1a checksum of every raw stage and fixed decoder result.

    Parallel Float64 audit arrays are deliberately excluded.  Their source
    raw LLRs and scale are bound alongside all fixed rate-recovery and LDPC
    workspaces, discrete decoder outputs, and status flags.
    """
    var state = UInt64(14695981039346656037)
    for value in [
        FIXED_NR_PDSCH_FFT_SIZE,
        FIXED_NR_PDSCH_CP_LENGTH,
        FIXED_NR_PDSCH_FIRST_SUBCARRIER,
        FIXED_NR_PDSCH_ALLOCATION_SIZE,
        result.config.slot,
        result.config.dmrs_symbol,
        result.config.dmrs_offset,
        result.config.n_id,
        result.config.n_scid,
        result.config.rnti,
        result.config.redundancy_version,
        result.base_graph,
        result.lifting_size,
        result.encoded_bits_per_block,
    ]:
        _mix_word(state, UInt64(value))
    _mix_word(state, UInt64(result.amplitude_raw))
    _mix_word(
        state, UInt64(Int64(result.config.decoder_llr_scale * 1000000.0))
    )
    _mix_bits(state, Span(result.payload_bits))
    _mix_bits(state, Span(result.transport_block))
    _mix_bits(state, Span(result.encoded_null_mask))
    _mix_bits(state, Span(result.physical.rate_matched_bits))
    _mix_bits(state, Span(result.physical.scrambling_gold_bits))
    _mix_bits(state, Span(result.physical.scrambled_bits))
    _mix_complex(state, Span(result.physical.mapped_data_symbols))
    _mix_bits(state, Span(result.physical.dmrs_gold_bits))
    _mix_complex(state, Span(result.physical.dmrs_symbols))
    _mix_complex(state, Span(result.physical.transmit_grid))
    _mix_complex(state, Span(result.physical.transmit_samples))
    _mix_complex(state, Span(result.physical.channel_taps))
    _mix_complex(state, Span(result.physical.channel_samples))
    _mix_complex(state, Span(result.physical.received_bins))
    _mix_complex(state, Span(result.physical.received_dmrs))
    _mix_complex(state, Span(result.physical.pilot_channel_estimates))
    _mix_complex(state, Span(result.physical.interpolated_channel))
    _mix_complex(state, Span(result.physical.received_data))
    _mix_complex(state, Span(result.physical.equalized_data_symbols))
    _mix_raw(state, Span(result.physical.llrs_raw))
    _mix_bits(state, Span(result.physical.hard_scrambled_bits))
    _mix_bits(state, Span(result.physical.hard_rate_matched_bits))
    for value in [
        result.fixed_decoder_config.llr_format.storage_bits,
        result.fixed_decoder_config.llr_format.fraction_bits,
        result.fixed_decoder_config.normalization_format.storage_bits,
        result.fixed_decoder_config.normalization_format.fraction_bits,
        result.fixed_decoder_config.max_iterations,
        result.fixed_decoder_config.schedule,
    ]:
        _mix_word(state, UInt64(value))
    for value in [
        result.fixed_decoder_config.normalization_raw,
        result.fixed_decoder_config.offset_raw,
        result.fixed_decoder_config.clip_raw,
    ]:
        _mix_word(state, UInt64(value))
    _mix_raw(state, Span(result.decoder_input_llrs_raw))
    _mix_raw(state, Span(result.decoder_descrambled_llrs_raw))
    _mix_raw(state, Span(result.decoder_rate_recovered_llrs_raw))
    _mix_raw(state, Span(result.decoder_posterior_llrs_raw))
    _mix_raw(state, Span(result.decoder_variable_to_check_raw))
    _mix_raw(state, Span(result.decoder_check_to_variable_raw))
    _mix_word(state, UInt64(result.decoder_syndrome_weight))
    _mix_word(state, UInt64(result.decoder_rate_recovery_saturations))
    _mix_word(state, UInt64(result.decoder_ldpc_saturations))
    _mix_word(state, UInt64(1 if result.float64_decoder_agrees else 0))
    for iteration in result.decoder_iterations:
        _mix_word(state, UInt64(iteration))
    _mix_bits(state, Span(result.decoded_transport_block))
    _mix_bits(state, Span(result.decoded_payload_bits))
    _mix_word(state, UInt64(1 if result.ldpc_converged else 0))
    _mix_word(state, UInt64(1 if result.code_block_crc_ok else 0))
    _mix_word(state, UInt64(1 if result.transport_crc_ok else 0))
    _mix_word(state, UInt64(result.audit.scrambled_bit_errors))
    _mix_word(state, UInt64(result.audit.rate_matched_bit_errors))
    _mix_word(state, UInt64(result.audit.payload_bit_errors))
    return state


def _bits_as_raw(values: Span[UInt8, ...]) -> List[Int64]:
    var result = List[Int64](capacity=len(values))
    for index in range(len(values)):
        result.append(Int64(values[index]))
    return result^


def _ints_as_raw(values: Span[Int, ...]) -> List[Int64]:
    var result = List[Int64](capacity=len(values))
    for index in range(len(values)):
        result.append(Int64(values[index]))
    return result^


def fixed_nr_pdsch_scale_trace_text(
    result: FixedNRPDSCHResult,
    formats: FixedNRPDSCHFormats,
) raises -> String:
    """Serialize IFFT/FFT schedules plus representative raw boundaries."""
    _validate_formats(formats)
    var ifft_stages = List[ScaleStage](capacity=9)
    var fft_stages = List[ScaleStage](capacity=9)
    for _ in range(9):
        ifft_stages.append(ScaleStage(formats.time, 1))
        fft_stages.append(ScaleStage(formats.frequency, 0))
    var ifft_trace = apply_scale_schedule(
        result.amplitude_raw, formats.symbol, Span(ifft_stages)
    )
    var fft_probe = result.physical.channel_samples[
        FIXED_NR_PDSCH_CP_LENGTH
    ].re
    var fft_trace = apply_scale_schedule(
        fft_probe, formats.time, Span(fft_stages)
    )

    var boundary_values: List[Int64] = [
        result.physical.mapped_data_symbols[0].re,
        result.physical.transmit_samples[FIXED_NR_PDSCH_CP_LENGTH].re,
        result.physical.channel_samples[FIXED_NR_PDSCH_CP_LENGTH].re,
        result.physical.received_bins[FIXED_NR_PDSCH_FIRST_SUBCARRIER].re,
        result.physical.pilot_channel_estimates[0].re,
        result.physical.interpolated_channel[0].re,
        result.physical.equalized_data_symbols[0].re,
        result.physical.llrs_raw[0],
        result.decoder_input_llrs_raw[0],
        result.decoder_rate_recovered_llrs_raw[0],
        result.decoder_posterior_llrs_raw[0],
    ]
    var fractions: List[Int] = [
        formats.symbol.fraction_bits,
        formats.time.fraction_bits,
        formats.time.fraction_bits,
        formats.frequency.fraction_bits,
        formats.channel_estimate.fraction_bits,
        formats.channel_estimate.fraction_bits,
        formats.equalized.fraction_bits,
        formats.llr.fraction_bits,
        result.fixed_decoder_config.llr_format.fraction_bits,
        result.fixed_decoder_config.llr_format.fraction_bits,
        result.fixed_decoder_config.llr_format.fraction_bits,
    ]
    var widths: List[Int] = [
        formats.symbol.storage_bits,
        formats.time.storage_bits,
        formats.time.storage_bits,
        formats.frequency.storage_bits,
        formats.channel_estimate.storage_bits,
        formats.channel_estimate.storage_bits,
        formats.equalized.storage_bits,
        formats.llr.storage_bits,
        result.fixed_decoder_config.llr_format.storage_bits,
        result.fixed_decoder_config.llr_format.storage_bits,
        result.fixed_decoder_config.llr_format.storage_bits,
    ]
    var shifts: List[Int] = [0, 9, 0, 0, 0, 0, 0, 0, 8, 0, 0]
    var boundaries = ScaleTrace(
        boundary_values^, fractions^, widths^, shifts^
    )
    var text = String()
    text.write(
        "MWDSP-FIXED-NR-PDSCH-CONFIG-V1\n",
        "scope=single-layer,single-codeword,qpsk,one-ofdm-symbol,mu0\n",
        "fft_size=", FIXED_NR_PDSCH_FFT_SIZE, "\n",
        "cyclic_prefix=", FIXED_NR_PDSCH_CP_LENGTH, "\n",
        "first_subcarrier=", FIXED_NR_PDSCH_FIRST_SUBCARRIER, "\n",
        "allocation_re=", FIXED_NR_PDSCH_ALLOCATION_SIZE, "\n",
        "dmrs_pattern=configuration-type-1-comb2\n",
        "dmrs_offset=", result.config.dmrs_offset, "\n",
        "channel_taps=", len(result.physical.channel_taps), "\n",
        "rounding=nearest-away\n",
        "overflow=saturate\n",
    )
    text.write(
        serialize_scale_trace(
            "fixed-nr-pdsch", "ifft-registers", ifft_trace
        )
    )
    text.write(
        serialize_scale_trace(
            "fixed-nr-pdsch", "fft-registers", fft_trace
        )
    )
    text.write(
        serialize_scale_trace(
            "fixed-nr-pdsch", "physical-boundaries", boundaries
        )
    )
    return text^


def _write_bits_vector(
    mut text: String,
    stage: StringSlice,
    values: Span[UInt8, ...],
    bit_format: QFormat,
) raises:
    var raw = _bits_as_raw(values)
    text.write(
        serialize_fixed_vector(
            "fixed-nr-pdsch", stage, Span(raw), bit_format
        )
    )


def fixed_nr_pdsch_canonical_rtl_vectors(
    result: FixedNRPDSCHResult,
    formats: FixedNRPDSCHFormats,
) raises -> String:
    """Serialize all raw checkpoints, scale traces, and the joint checksum."""
    _validate_formats(formats)
    var bit_format = QFormat(2, 0)
    var metadata_format = QFormat(32, 0)
    var metadata: List[Int64] = [
        Int64(FIXED_NR_PDSCH_FFT_SIZE),
        Int64(FIXED_NR_PDSCH_CP_LENGTH),
        Int64(FIXED_NR_PDSCH_FIRST_SUBCARRIER),
        Int64(FIXED_NR_PDSCH_ALLOCATION_SIZE),
        Int64(result.config.slot),
        Int64(result.config.dmrs_symbol),
        Int64(result.config.dmrs_offset),
        Int64(result.config.n_id),
        Int64(result.config.n_scid),
        Int64(result.config.rnti),
        Int64(result.config.redundancy_version),
        Int64(result.base_graph),
        Int64(result.lifting_size),
        Int64(result.encoded_bits_per_block),
        result.amplitude_raw,
    ]
    var text = String()
    text.write(
        serialize_fixed_vector(
            "fixed-nr-pdsch", "bounded-config", Span(metadata), metadata_format
        )
    )
    _write_bits_vector(text, "payload", Span(result.payload_bits), bit_format)
    _write_bits_vector(
        text, "transport-block-crc", Span(result.transport_block), bit_format
    )
    _write_bits_vector(
        text, "encoded-null-mask", Span(result.encoded_null_mask), bit_format
    )
    _write_bits_vector(
        text,
        "rate-matched-bits",
        Span(result.physical.rate_matched_bits),
        bit_format,
    )
    _write_bits_vector(
        text,
        "scrambling-gold-bits",
        Span(result.physical.scrambling_gold_bits),
        bit_format,
    )
    _write_bits_vector(
        text,
        "scrambled-bits",
        Span(result.physical.scrambled_bits),
        bit_format,
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-nr-pdsch",
            "mapped-data-qpsk",
            Span(result.physical.mapped_data_symbols),
            formats.symbol,
        )
    )
    _write_bits_vector(
        text,
        "dmrs-gold-bits",
        Span(result.physical.dmrs_gold_bits),
        bit_format,
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-nr-pdsch",
            "dmrs-qpsk",
            Span(result.physical.dmrs_symbols),
            formats.symbol,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-nr-pdsch",
            "transmit-grid",
            Span(result.physical.transmit_grid),
            formats.symbol,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-nr-pdsch",
            "ifft-cp",
            Span(result.physical.transmit_samples),
            formats.time,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-nr-pdsch",
            "channel-taps",
            Span(result.physical.channel_taps),
            formats.tap,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-nr-pdsch",
            "frequency-selective-channel",
            Span(result.physical.channel_samples),
            formats.time,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-nr-pdsch",
            "received-fft-bins",
            Span(result.physical.received_bins),
            formats.frequency,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-nr-pdsch",
            "received-dmrs",
            Span(result.physical.received_dmrs),
            formats.frequency,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-nr-pdsch",
            "pilot-ls",
            Span(result.physical.pilot_channel_estimates),
            formats.channel_estimate,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-nr-pdsch",
            "comb2-interpolated-channel",
            Span(result.physical.interpolated_channel),
            formats.channel_estimate,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-nr-pdsch",
            "received-data",
            Span(result.physical.received_data),
            formats.frequency,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-nr-pdsch",
            "zf-equalized-qpsk",
            Span(result.physical.equalized_data_symbols),
            formats.equalized,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-nr-pdsch",
            "raw-coordinate-llrs",
            Span(result.physical.llrs_raw),
            formats.llr,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-nr-pdsch",
            "fixed-decoder-input-llrs",
            Span(result.decoder_input_llrs_raw),
            result.fixed_decoder_config.llr_format,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-nr-pdsch",
            "fixed-descrambled-llrs",
            Span(result.decoder_descrambled_llrs_raw),
            result.fixed_decoder_config.llr_format,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-nr-pdsch",
            "fixed-rate-recovered-llrs",
            Span(result.decoder_rate_recovered_llrs_raw),
            result.fixed_decoder_config.llr_format,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-nr-pdsch",
            "fixed-ldpc-posterior-llrs",
            Span(result.decoder_posterior_llrs_raw),
            result.fixed_decoder_config.llr_format,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-nr-pdsch",
            "fixed-ldpc-variable-to-check",
            Span(result.decoder_variable_to_check_raw),
            result.fixed_decoder_config.llr_format,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-nr-pdsch",
            "fixed-ldpc-check-to-variable",
            Span(result.decoder_check_to_variable_raw),
            result.fixed_decoder_config.llr_format,
        )
    )
    _write_bits_vector(
        text,
        "hard-scrambled-bits",
        Span(result.physical.hard_scrambled_bits),
        bit_format,
    )
    _write_bits_vector(
        text,
        "hard-rate-matched-bits",
        Span(result.physical.hard_rate_matched_bits),
        bit_format,
    )
    var iteration_raw = _ints_as_raw(Span(result.decoder_iterations))
    text.write(
        serialize_fixed_vector(
            "fixed-nr-pdsch",
            "fixed-decoder-iterations",
            Span(iteration_raw),
            QFormat(16, 0),
        )
    )
    _write_bits_vector(
        text,
        "fixed-decoded-transport-block",
        Span(result.decoded_transport_block),
        bit_format,
    )
    _write_bits_vector(
        text,
        "fixed-decoded-payload",
        Span(result.decoded_payload_bits),
        bit_format,
    )
    text.write(
        "MWDSP-FIXED-NR-PDSCH-BOUNDARY-V2\n",
        "fixed_terminal_stage=transport-crc\n",
        "physical_llr_storage_bits=", formats.llr.storage_bits, "\n",
        "physical_llr_fraction_bits=", formats.llr.fraction_bits, "\n",
        "decoder_llr_storage_bits=",
        result.fixed_decoder_config.llr_format.storage_bits,
        "\n",
        "decoder_llr_fraction_bits=",
        result.fixed_decoder_config.llr_format.fraction_bits,
        "\n",
        "decoder_schedule=layered-min-sum\n",
        "decoder_stages=fixed-rescale,descramble,rate-recover,ldpc,crc\n",
        "float64_role=differential-audit-only\n",
        "float64_decoder_agrees=",
        1 if result.float64_decoder_agrees else 0,
        "\n",
        "float64_decoder_llr_scale=", result.config.decoder_llr_scale, "\n",
    )
    text.write(fixed_nr_pdsch_scale_trace_text(result, formats))
    text.write(
        "MWDSP-FIXED-NR-PDSCH-CHECKSUM-V1\nchecksum=",
        fixed_nr_pdsch_result_checksum(result),
        "\n",
    )
    return text^
