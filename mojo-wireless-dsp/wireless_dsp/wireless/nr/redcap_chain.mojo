"""Bounded Rel-17 RedCap FR1 20-MHz CPU reference compositions.

The two entry points in this module bind existing NR primitives to an explicit
Rel-17 RedCap feature profile instead of treating an ordinary-NR loopback as
RedCap evidence.  The profile is FR1, 20-MHz maximum UE channel bandwidth,
30-kHz SCS, a 51-PRB initial BWP, one receive branch/downlink layer, and one
transmit branch/uplink layer.  The downlink crosses
PSS/SSS -> PBCH/MIB -> PDCCH/DCI -> PDSCH.  The uplink crosses
PRACH -> PUSCH -> PUCCH/UCI.  A decoded result at every stage supplies data or
identity to the next stage, and all nested checkpoint envelopes receive the
same owned ``testcase_id``.

Rel-17 feature constraints follow TS 38.306 V17.16.0 clause 4.2.21, TS
38.331 V17.17.0 RedCap initial-BWP fields, and TS 38.213 V17.13.0 clause 17.
The inherited physical algorithms follow TS 38.211/38.212 Release 17.  This is
a deterministic CPU golden composition, not a complete RRC/MAC stack,
scheduler, radio-rate PRACH placement, RF model, or conformance claim.  In
particular, the PRACH stage deliberately retains the bounded normalized
sequence-sample representation provided by ``nr_prach_normalized_composite``.
"""

from std.collections import Span
from wireless_dsp.core import Complex64
from wireless_dsp.testing.checkpoint import (
    CheckpointMetadata,
    checkpoint_metadata_1d,
    checkpoint_metadata_2d,
)
from .sequences import nr_pss, nr_sss
from .synchronization import (
    NRPSSDetection,
    NRCellDetection,
    nr_search_pss,
    nr_detect_sss,
)
from .pbch import (
    NRPBCHTransmitBlock,
    NRPBCHDecodeResult,
    nr_pbch_encode,
    nr_pbch_decode,
)
from .control import (
    NRPDCCHTransmitBlock,
    NRPDCCHDecodeResult,
    nr_pdcch_encode,
    nr_pdcch_decode,
)
from .grid import NRResourceGrid, nr_pdsch_dmrs_c_init, nr_map_pdsch_comb2
from .pdsch import nr_pdsch_dmrs
from .pdsch_chain import (
    NRPDSCHWaveformConfig,
    NRPDSCHTransmitBlock,
    NRPDSCHDecodeResult,
    nr_pdsch_grid_to_waveform,
    nr_pdsch_encode_transport_block,
    nr_pdsch_decode_waveform_comb2,
)
from .prach import (
    NRPRACHNormalizedCompositeResult,
    PRACH_FORMAT_A1,
    PRACH_SET_UNRESTRICTED,
    nr_prach_format_parameters,
    nr_prach_normalized_composite,
)
from .pusch_chain import (
    NRPUSCHConfig,
    NRPUSCHTransmitBlock,
    NRPUSCHDecodeResult,
    nr_pusch_encode_transport_block,
    nr_pusch_decode_waveform,
)
from .pucch_chain import (
    NRPUCCHFormat2Config,
    NRPUCCHFormat2TransmitResult,
    NRPUCCHFormat2DecodeResult,
    nr_pucch_format2_encode,
    nr_pucch_format2_flat_channel,
    nr_pucch_format2_decode,
)
from .redcap import (
    NR_FREQUENCY_RANGE_FR1,
    NR_DUPLEX_TDD,
    NR_REDCAP_DL_BWP_PAGING,
    NRRedCapRel17Capabilities,
    NRRedCapInitialBWP,
    NRRedCapRel17InitialAccessConfig,
    nr_redcap_rel17_validate_initial_access,
    nr_redcap_rel17_ra_search_space_first_cces,
)


comptime _REDCAP_FR1_CHANNEL_BANDWIDTH_MHZ = 20.0
comptime _REDCAP_FR1_SCS_KHZ = 30
comptime _REDCAP_FR1_BWP_RESOURCE_BLOCKS = 51
comptime _REDCAP_FR1_FFT_SIZE = 1024
comptime _REDCAP_FR1_CYCLIC_PREFIX = 72
comptime _REDCAP_PHYSICAL_CHANNEL_LLR = 80.0
comptime _REDCAP_PDSCH_PAYLOAD_BITS = 128
comptime _REDCAP_PUSCH_PAYLOAD_BITS = 128
comptime _REDCAP_UCI_PAYLOAD_BITS = 12


struct NRRedCapRel17FR120MHzChainConfig(ImplicitlyCopyable):
    """Variable identities inside the fixed FR1 20-MHz RedCap profile.

    Geometry, layer counts, modulation, BWP width, numerology, and channel
    models are deliberately fixed by the composite.  Keeping only identities
    and the selected PRACH preamble variable makes profile coverage auditable
    while still allowing seeded property and boundary tests.  Public entry
    points revalidate this mutable record on every call.
    """

    var physical_cell_id: Int
    var system_frame_number: Int
    var half_frame: Int
    var ssb_index: Int
    var rnti: Int
    var prach_preamble_index: Int

    def __init__(
        out self,
        physical_cell_id: Int = 321,
        system_frame_number: Int = 713,
        half_frame: Int = 1,
        ssb_index: Int = 6,
        rnti: Int = 0x1234,
        prach_preamble_index: Int = 17,
    ) raises:
        self.physical_cell_id = physical_cell_id
        self.system_frame_number = system_frame_number
        self.half_frame = half_frame
        self.ssb_index = ssb_index
        self.rnti = rnti
        self.prach_preamble_index = prach_preamble_index
        self.validate()

    def validate(self) raises:
        if self.physical_cell_id < 0 or self.physical_cell_id > 1007:
            raise Error("RedCap chain physical cell identity must be in [0,1007]")
        if self.system_frame_number < 0 or self.system_frame_number > 1023:
            raise Error("RedCap chain system frame number must be in [0,1023]")
        if self.half_frame < 0 or self.half_frame > 1:
            raise Error("RedCap chain half-frame field must be zero or one")
        if self.ssb_index < 0 or self.ssb_index >= 8:
            raise Error("RedCap chain uses the FR1 Lmax=8 SSB-index domain")
        if self.rnti < 1 or self.rnti > 0xFFFF:
            raise Error("RedCap chain C-RNTI must be in [1,65535]")
        if self.prach_preamble_index < 0 or self.prach_preamble_index >= 64:
            raise Error("RedCap chain PRACH preamble index must be in [0,63]")


struct NRRedCapRel17FR120MHzDownlinkResult(Movable):
    """Owned runtime checkpoints for the bounded RedCap downlink chain."""

    var capabilities: NRRedCapRel17Capabilities
    var initial_access: NRRedCapRel17InitialAccessConfig
    var ra_first_cces: List[Int]
    var pss_samples: List[Complex64]
    var pss_detection: NRPSSDetection
    var sss_samples: List[Complex64]
    var sss_detection: NRCellDetection
    var mib_bits: List[UInt8]
    var pbch_transmit: NRPBCHTransmitBlock
    var pbch_llrs: List[Float64]
    var pbch_decode: NRPBCHDecodeResult
    var dci_payload: List[UInt8]
    var pdcch_transmit: NRPDCCHTransmitBlock
    var pdcch_llrs: List[Float64]
    var pdcch_decode: NRPDCCHDecodeResult
    var pdsch_payload: List[UInt8]
    var pdsch_config: NRPDSCHWaveformConfig
    var pdsch_transmit: NRPDSCHTransmitBlock
    var pdsch_grid: NRResourceGrid
    var pdsch_waveform: List[Complex64]
    var pdsch_received_waveform: List[Complex64]
    var pdsch_decode: NRPDSCHDecodeResult
    var checkpoint_metadata: List[CheckpointMetadata]
    var complete: Bool

    def __init__(
        out self,
        capabilities: NRRedCapRel17Capabilities,
        initial_access: NRRedCapRel17InitialAccessConfig,
        var ra_first_cces: List[Int],
        var pss_samples: List[Complex64],
        pss_detection: NRPSSDetection,
        var sss_samples: List[Complex64],
        sss_detection: NRCellDetection,
        var mib_bits: List[UInt8],
        var pbch_transmit: NRPBCHTransmitBlock,
        var pbch_llrs: List[Float64],
        var pbch_decode: NRPBCHDecodeResult,
        var dci_payload: List[UInt8],
        var pdcch_transmit: NRPDCCHTransmitBlock,
        var pdcch_llrs: List[Float64],
        var pdcch_decode: NRPDCCHDecodeResult,
        var pdsch_payload: List[UInt8],
        pdsch_config: NRPDSCHWaveformConfig,
        var pdsch_transmit: NRPDSCHTransmitBlock,
        var pdsch_grid: NRResourceGrid,
        var pdsch_waveform: List[Complex64],
        var pdsch_received_waveform: List[Complex64],
        var pdsch_decode: NRPDSCHDecodeResult,
        var checkpoint_metadata: List[CheckpointMetadata],
        complete: Bool,
    ):
        self.capabilities = capabilities
        self.initial_access = initial_access
        self.ra_first_cces = ra_first_cces^
        self.pss_samples = pss_samples^
        self.pss_detection = pss_detection
        self.sss_samples = sss_samples^
        self.sss_detection = sss_detection
        self.mib_bits = mib_bits^
        self.pbch_transmit = pbch_transmit^
        self.pbch_llrs = pbch_llrs^
        self.pbch_decode = pbch_decode^
        self.dci_payload = dci_payload^
        self.pdcch_transmit = pdcch_transmit^
        self.pdcch_llrs = pdcch_llrs^
        self.pdcch_decode = pdcch_decode^
        self.pdsch_payload = pdsch_payload^
        self.pdsch_config = pdsch_config
        self.pdsch_transmit = pdsch_transmit^
        self.pdsch_grid = pdsch_grid^
        self.pdsch_waveform = pdsch_waveform^
        self.pdsch_received_waveform = pdsch_received_waveform^
        self.pdsch_decode = pdsch_decode^
        self.checkpoint_metadata = checkpoint_metadata^
        self.complete = complete


struct NRRedCapRel17FR120MHzUplinkResult(Movable):
    """Owned runtime checkpoints for the bounded RedCap uplink chain."""

    var capabilities: NRRedCapRel17Capabilities
    var initial_access: NRRedCapRel17InitialAccessConfig
    var prach: NRPRACHNormalizedCompositeResult
    var pusch_payload: List[UInt8]
    var pusch_config: NRPUSCHConfig
    var pusch_transmit: NRPUSCHTransmitBlock
    var pusch_received_waveform: List[Complex64]
    var pusch_decode: NRPUSCHDecodeResult
    var uci_payload: List[UInt8]
    var pucch_config: NRPUCCHFormat2Config
    var pucch_transmit: NRPUCCHFormat2TransmitResult
    var pucch_received_waveform: List[Complex64]
    var pucch_decode: NRPUCCHFormat2DecodeResult
    var checkpoint_metadata: List[CheckpointMetadata]
    var complete: Bool

    def __init__(
        out self,
        capabilities: NRRedCapRel17Capabilities,
        initial_access: NRRedCapRel17InitialAccessConfig,
        var prach: NRPRACHNormalizedCompositeResult,
        var pusch_payload: List[UInt8],
        pusch_config: NRPUSCHConfig,
        var pusch_transmit: NRPUSCHTransmitBlock,
        var pusch_received_waveform: List[Complex64],
        var pusch_decode: NRPUSCHDecodeResult,
        var uci_payload: List[UInt8],
        pucch_config: NRPUCCHFormat2Config,
        var pucch_transmit: NRPUCCHFormat2TransmitResult,
        var pucch_received_waveform: List[Complex64],
        var pucch_decode: NRPUCCHFormat2DecodeResult,
        var checkpoint_metadata: List[CheckpointMetadata],
        complete: Bool,
    ):
        self.capabilities = capabilities
        self.initial_access = initial_access
        self.prach = prach^
        self.pusch_payload = pusch_payload^
        self.pusch_config = pusch_config
        self.pusch_transmit = pusch_transmit^
        self.pusch_received_waveform = pusch_received_waveform^
        self.pusch_decode = pusch_decode^
        self.uci_payload = uci_payload^
        self.pucch_config = pucch_config
        self.pucch_transmit = pucch_transmit^
        self.pucch_received_waveform = pucch_received_waveform^
        self.pucch_decode = pucch_decode^
        self.checkpoint_metadata = checkpoint_metadata^
        self.complete = complete


def _validate_testcase_id(testcase_id: StringSlice) raises:
    if testcase_id.byte_length() == 0 or "\n" in testcase_id or "\r" in testcase_id:
        raise Error("RedCap chain testcase_id must be non-empty and single-line")


def _redcap_capabilities() raises -> NRRedCapRel17Capabilities:
    return NRRedCapRel17Capabilities(
        NR_FREQUENCY_RANGE_FR1,
        _REDCAP_FR1_CHANNEL_BANDWIDTH_MHZ,
        1,
        1,
        tx_branches=1,
        ul_layers=1,
        duplex_mode=NR_DUPLEX_TDD,
    )


def _redcap_initial_access() raises -> NRRedCapRel17InitialAccessConfig:
    var downlink = NRRedCapInitialBWP(
        0, _REDCAP_FR1_BWP_RESOURCE_BLOCKS, 3500000, _REDCAP_FR1_SCS_KHZ
    )
    var uplink = NRRedCapInitialBWP(
        0, _REDCAP_FR1_BWP_RESOURCE_BLOCKS, 3500000, _REDCAP_FR1_SCS_KHZ
    )
    return NRRedCapRel17InitialAccessConfig(
        downlink,
        uplink,
        _REDCAP_FR1_BWP_RESOURCE_BLOCKS,
        _REDCAP_FR1_BWP_RESOURCE_BLOCKS,
        NR_REDCAP_DL_BWP_PAGING,
        has_cd_ssb=True,
        contains_coreset0=True,
        ra_coreset_id=0,
        coreset_start_prb=0,
        coreset_resource_blocks=24,
        coreset_duration_symbols=2,
        monitors_type1_css=True,
        monitors_type2_css=True,
    )


def _mib_bits(config: NRRedCapRel17FR120MHzChainConfig) -> List[UInt8]:
    var result = List[UInt8](capacity=24)
    for index in range(24):
        if index < 6:
            result.append(UInt8((config.system_frame_number >> (9 - index)) & 1))
        else:
            result.append(UInt8(
                (
                    config.physical_cell_id
                    + 5 * index
                    + config.rnti
                    + (config.system_frame_number >> (index % 10))
                ) & 1
            ))
    return result^


def _ideal_bit_llrs(bits: Span[UInt8, ...]) raises -> List[Float64]:
    var result = List[Float64](capacity=len(bits))
    for index in range(len(bits)):
        var bit = bits[index]
        if bit > 1:
            raise Error("RedCap ideal-channel input must be binary")
        result.append(_REDCAP_PHYSICAL_CHANNEL_LLR if bit == 0 else -_REDCAP_PHYSICAL_CHANNEL_LLR)
    return result^


def _flat_channel(
    samples: Span[Complex64, ...], gain: Complex64
) raises -> List[Complex64]:
    if gain.re == 0.0 and gain.im == 0.0:
        raise Error("RedCap bounded flat channel must be non-singular")
    var result = List[Complex64](capacity=len(samples))
    for index in range(len(samples)):
        var sample = Complex64(samples[index].re, samples[index].im)
        result.append(sample * gain)
    return result^


def _dci_payload(
    mib: Span[UInt8, ...], config: NRRedCapRel17FR120MHzChainConfig
) raises -> List[UInt8]:
    if len(mib) != 24:
        raise Error("RedCap DCI composition requires a decoded 24-bit MIB")
    var result = List[UInt8](capacity=32)
    for index in range(32):
        result.append(UInt8(
            Int(mib[(7 * index + 3) % 24])
            ^ ((config.rnti >> (index % 16)) & 1)
            ^ ((config.system_frame_number >> (index % 10)) & 1)
        ))
    return result^


def _downlink_payload(
    dci: Span[UInt8, ...], mib: Span[UInt8, ...],
    config: NRRedCapRel17FR120MHzChainConfig,
) raises -> List[UInt8]:
    if len(dci) != 32 or len(mib) != 24:
        raise Error("RedCap PDSCH composition requires decoded DCI and MIB")
    var result = List[UInt8](capacity=_REDCAP_PDSCH_PAYLOAD_BITS)
    for index in range(_REDCAP_PDSCH_PAYLOAD_BITS):
        result.append(UInt8(
            Int(dci[(11 * index + 1) % 32])
            ^ Int(mib[(5 * index + 2) % 24])
            ^ ((config.physical_cell_id >> (index % 10)) & 1)
        ))
    return result^


def _uplink_payload(
    detected_preamble: Int, config: NRRedCapRel17FR120MHzChainConfig
) -> List[UInt8]:
    var result = List[UInt8](capacity=_REDCAP_PUSCH_PAYLOAD_BITS)
    for index in range(_REDCAP_PUSCH_PAYLOAD_BITS):
        result.append(UInt8(
            ((detected_preamble + 3 * index + index // 7) & 1)
            ^ ((config.rnti >> (index % 16)) & 1)
            ^ ((config.physical_cell_id >> (index % 10)) & 1)
        ))
    return result^


def _uci_payload(
    pusch_payload: Span[UInt8, ...], transport_crc_ok: Bool,
    config: NRRedCapRel17FR120MHzChainConfig,
) raises -> List[UInt8]:
    if len(pusch_payload) != _REDCAP_PUSCH_PAYLOAD_BITS:
        raise Error("RedCap UCI composition requires the decoded PUSCH payload")
    var result = List[UInt8](capacity=_REDCAP_UCI_PAYLOAD_BITS)
    result.append(UInt8(1) if transport_crc_ok else UInt8(0))
    for index in range(1, _REDCAP_UCI_PAYLOAD_BITS):
        result.append(UInt8(
            Int(pusch_payload[(13 * index + 5) % len(pusch_payload)])
            ^ ((config.system_frame_number >> (index % 10)) & 1)
        ))
    return result^


def _downlink_metadata(
    testcase_id: StringSlice,
    pss_samples: Int,
    sss_samples: Int,
    pbch_llrs: Int,
    pdcch_llrs: Int,
    cces: Int,
    pdsch_rows: Int,
    pdsch_columns: Int,
    pdsch_waveform: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=10)
    result.append(checkpoint_metadata_1d(
        testcase_id, "redcap-fr1-20mhz-profile", "int", 8,
        q_format="integer", layout="bw-scs-prb-fft-cp-rx-dl-ul",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id, "pss-search-input", "complex64", pss_samples,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id, "sss-search-input", "complex64", sss_samples,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id, "pbch-physical-llrs", "float64", pbch_llrs,
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id, "ra-css-first-cces", "int", cces,
        q_format="integer",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id, "pdcch-physical-llrs", "float64", pdcch_llrs,
    ))
    result.append(checkpoint_metadata_2d(
        testcase_id, "pdsch-transmit-grid", "complex64",
        pdsch_rows, pdsch_columns, row_stride=pdsch_columns,
        layout="row-major-iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id, "pdsch-transmit-waveform", "complex64", pdsch_waveform,
        layout="cp-then-iq",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id, "pdsch-received-waveform", "complex64", pdsch_waveform,
        layout="cp-then-iq",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id, "downlink-complete", "bool", 1,
        q_format="boolean", layout="scalar",
    ))
    return result^


def _uplink_metadata(
    testcase_id: StringSlice,
    prach_waveform: Int,
    pusch_rows: Int,
    pusch_columns: Int,
    pusch_waveform: Int,
    pucch_rows: Int,
    pucch_columns: Int,
    pucch_waveform: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=10)
    result.append(checkpoint_metadata_1d(
        testcase_id, "redcap-fr1-20mhz-profile", "int", 8,
        q_format="integer", layout="bw-scs-prb-fft-cp-rx-dl-ul",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id, "prach-normalized-waveform", "complex64", prach_waveform,
        layout="cp-then-repeated-iq",
    ))
    result.append(checkpoint_metadata_2d(
        testcase_id, "pusch-transmit-grid", "complex64",
        pusch_rows, pusch_columns, row_stride=pusch_columns,
        layout="row-major-iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id, "pusch-transmit-waveform", "complex64", pusch_waveform,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id, "pusch-received-waveform", "complex64", pusch_waveform,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id, "decoded-pusch-payload", "uint8", _REDCAP_PUSCH_PAYLOAD_BITS,
        q_format="binary-u1", layout="bit-per-byte",
    ))
    result.append(checkpoint_metadata_2d(
        testcase_id, "pucch-transmit-grid", "complex64",
        pucch_rows, pucch_columns, row_stride=pucch_columns,
        layout="row-major-iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id, "pucch-transmit-waveform", "complex64", pucch_waveform,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id, "pucch-received-waveform", "complex64", pucch_waveform,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id, "uplink-complete", "bool", 1,
        q_format="boolean", layout="scalar",
    ))
    return result^


@no_inline
def nr_redcap_rel17_fr1_20mhz_downlink(
    config: NRRedCapRel17FR120MHzChainConfig,
    *,
    testcase_id: StringSlice = "nr-redcap-rel17-fr1-20mhz-dl",
) raises -> NRRedCapRel17FR120MHzDownlinkResult:
    """Run the bounded SISO RedCap DL synchronization-to-PDSCH chain."""
    config.validate()
    _validate_testcase_id(testcase_id)
    var capabilities = _redcap_capabilities()
    var initial_access = _redcap_initial_access()
    _ = nr_redcap_rel17_validate_initial_access(capabilities, initial_access)
    var first_cces = nr_redcap_rel17_ra_search_space_first_cces(
        capabilities, initial_access, 2, 2
    )

    var n_id_2 = config.physical_cell_id % 3
    var n_id_1 = config.physical_cell_id // 3
    var pss_reference = nr_pss(n_id_2)
    var pss_samples = List[Complex64](length=137, fill=Complex64(0.0))
    var sync_gain = Complex64(0.75, -0.25)
    for index in range(127):
        pss_samples[5 + index] = Complex64(pss_reference[index]) * sync_gain
    var pss_detection = nr_search_pss(Span(pss_samples))

    var sss_reference = nr_sss(n_id_1, pss_detection.n_id_2)
    var sss_samples = List[Complex64](capacity=127)
    for value in sss_reference:
        sss_samples.append(Complex64(value) * sync_gain)
    var sss_detection = nr_detect_sss(Span(sss_samples), pss_detection.n_id_2)

    var mib = _mib_bits(config)
    var pbch_transmit = nr_pbch_encode(
        Span(mib),
        sss_detection.physical_cell_id,
        config.system_frame_number,
        config.half_frame,
        config.ssb_index,
        8,
        testcase_id=testcase_id,
    )
    var pbch_llrs = _ideal_bit_llrs(Span(pbch_transmit.physical_channel_bits))
    var pbch_decode = nr_pbch_decode(
        Span(pbch_llrs),
        sss_detection.physical_cell_id,
        config.ssb_index,
        8,
        testcase_id=testcase_id,
    )

    var dci = _dci_payload(Span(pbch_decode.mib_bits), config)
    var pdcch_transmit = nr_pdcch_encode(
        Span(dci),
        config.rnti,
        sss_detection.physical_cell_id,
        2,
        testcase_id=testcase_id,
    )
    var pdcch_llrs = _ideal_bit_llrs(Span(pdcch_transmit.scrambled))
    var pdcch_decode = nr_pdcch_decode(
        Span(pdcch_llrs),
        len(dci),
        config.rnti,
        sss_detection.physical_cell_id,
        2,
        testcase_id=testcase_id,
    )

    var pdsch_payload = _downlink_payload(
        Span(pdcch_decode.payload), Span(pbch_decode.mib_bits), config
    )
    var pdsch_config = NRPDSCHWaveformConfig(
        _REDCAP_FR1_FFT_SIZE,
        _REDCAP_FR1_CYCLIC_PREFIX,
        0,
        _REDCAP_FR1_BWP_RESOURCE_BLOCKS,
        3,
        2,
        sss_detection.physical_cell_id,
        0,
        0,
        config.rnti,
    )
    var pdsch_transmit = nr_pdsch_encode_transport_block(
        Span(pdsch_payload),
        0.5,
        2,
        0,
        pdsch_config.data_re_count() * 2,
        config.rnti,
        0,
        sss_detection.physical_cell_id,
        testcase_id=testcase_id,
    )
    var pdsch_dmrs = nr_pdsch_dmrs(
        nr_pdsch_dmrs_c_init(
            pdsch_config.slot,
            pdsch_config.dmrs_symbol,
            pdsch_config.n_id,
            pdsch_config.n_scid,
        ),
        pdsch_config.dmrs_re_count(),
    )
    var pdsch_grid = NRResourceGrid(1, pdsch_config.fft_size)
    nr_map_pdsch_comb2(
        pdsch_grid,
        0,
        pdsch_config.first_subcarrier,
        pdsch_config.allocation_subcarriers(),
        pdsch_config.dmrs_offset,
        Span(pdsch_transmit.symbols),
        Span(pdsch_dmrs),
    )
    var pdsch_waveform = nr_pdsch_grid_to_waveform(pdsch_config, pdsch_grid)
    var pdsch_received = _flat_channel(
        Span(pdsch_waveform), Complex64(0.8, 0.3)
    )
    var pdsch_decode = nr_pdsch_decode_waveform_comb2(
        Span(pdsch_received),
        pdsch_config,
        Span(pdsch_transmit.encoded_null_mask),
        pdsch_transmit.profile,
        len(pdsch_payload),
        2,
        0,
        1.0e-6,
        testcase_id=testcase_id,
    )
    var complete = (
        pss_detection.offset == 5
        and pss_detection.n_id_2 == n_id_2
        and sss_detection.physical_cell_id == config.physical_cell_id
        and pbch_decode.crc_ok
        and pdcch_decode.crc_ok
        and pdsch_decode.ldpc_converged
        and pdsch_decode.code_block_crc_ok
        and pdsch_decode.transport_crc_ok
    )
    var metadata = _downlink_metadata(
        testcase_id,
        len(pss_samples),
        len(sss_samples),
        len(pbch_llrs),
        len(pdcch_llrs),
        len(first_cces),
        pdsch_grid.symbol_count,
        pdsch_grid.subcarrier_count,
        len(pdsch_waveform),
    )
    return NRRedCapRel17FR120MHzDownlinkResult(
        capabilities,
        initial_access,
        first_cces^,
        pss_samples^,
        pss_detection,
        sss_samples^,
        sss_detection,
        mib^,
        pbch_transmit^,
        pbch_llrs^,
        pbch_decode^,
        dci^,
        pdcch_transmit^,
        pdcch_llrs^,
        pdcch_decode^,
        pdsch_payload^,
        pdsch_config,
        pdsch_transmit^,
        pdsch_grid^,
        pdsch_waveform^,
        pdsch_received^,
        pdsch_decode^,
        metadata^,
        complete,
    )


@no_inline
def nr_redcap_rel17_fr1_20mhz_uplink(
    config: NRRedCapRel17FR120MHzChainConfig,
    *,
    testcase_id: StringSlice = "nr-redcap-rel17-fr1-20mhz-ul",
) raises -> NRRedCapRel17FR120MHzUplinkResult:
    """Run the bounded one-layer RedCap PRACH-to-PUCCH/UCI chain."""
    config.validate()
    _validate_testcase_id(testcase_id)
    var capabilities = _redcap_capabilities()
    var initial_access = _redcap_initial_access()
    _ = nr_redcap_rel17_validate_initial_access(capabilities, initial_access)

    var prach_parameters = nr_prach_format_parameters(
        PRACH_FORMAT_A1, numerology=1, sequence_length=139
    )
    var prach = nr_prach_normalized_composite(
        prach_parameters,
        0,
        13,
        PRACH_SET_UNRESTRICTED,
        config.prach_preamble_index,
        testcase_id=testcase_id,
    )

    var pusch_payload = _uplink_payload(
        prach.detection.preamble_index, config
    )
    var pusch_config = NRPUSCHConfig(
        _REDCAP_FR1_FFT_SIZE,
        _REDCAP_FR1_CYCLIC_PREFIX,
        2,
        0,
        0,
        _REDCAP_FR1_BWP_RESOURCE_BLOCKS,
        3,
        config.physical_cell_id,
        0,
        config.rnti,
    )
    var pusch_transmit = nr_pusch_encode_transport_block(
        Span(pusch_payload),
        0.5,
        2,
        0,
        pusch_config,
        testcase_id=testcase_id,
    )
    var pusch_received = _flat_channel(
        Span(pusch_transmit.waveform), Complex64(0.7, -0.2)
    )
    var pusch_decode = nr_pusch_decode_waveform(
        Span(pusch_received),
        pusch_config,
        Span(pusch_transmit.encoded_null_mask),
        pusch_transmit.profile,
        len(pusch_payload),
        2,
        0,
        0.01,
        testcase_id=testcase_id,
    )

    var uci = _uci_payload(
        Span(pusch_decode.payload), pusch_decode.transport_crc_ok, config
    )
    var pucch_config = NRPUCCHFormat2Config(
        _REDCAP_FR1_FFT_SIZE,
        1,
        3,
        12,
        2,
        0,
        config.physical_cell_id,
        config.physical_cell_id,
        config.rnti,
    )
    var pucch_transmit = nr_pucch_format2_encode(
        Span(uci), pucch_config, testcase_id=testcase_id
    )
    var pucch_received = nr_pucch_format2_flat_channel(
        Span(pucch_transmit.waveform), Complex64(0.75, 0.25)
    )
    var pucch_decode = nr_pucch_format2_decode(
        Span(pucch_received),
        pucch_config,
        len(uci),
        0.0,
        testcase_id=testcase_id,
    )
    var complete = (
        prach.detection.preamble_index == config.prach_preamble_index
        and pusch_decode.ldpc_converged
        and pusch_decode.code_block_crc_ok
        and pusch_decode.transport_crc_ok
        and pucch_decode.crc_ok
        and pucch_decode.parity_ok
    )
    var metadata = _uplink_metadata(
        testcase_id,
        len(prach.normalized_waveform),
        pusch_transmit.grid.symbol_count,
        pusch_transmit.grid.subcarrier_count,
        len(pusch_transmit.waveform),
        pucch_transmit.grid.symbol_count,
        pucch_transmit.grid.subcarrier_count,
        len(pucch_transmit.waveform),
    )
    return NRRedCapRel17FR120MHzUplinkResult(
        capabilities,
        initial_access,
        prach^,
        pusch_payload^,
        pusch_config,
        pusch_transmit^,
        pusch_received^,
        pusch_decode^,
        uci^,
        pucch_config,
        pucch_transmit^,
        pucch_received^,
        pucch_decode^,
        metadata^,
        complete,
    )
