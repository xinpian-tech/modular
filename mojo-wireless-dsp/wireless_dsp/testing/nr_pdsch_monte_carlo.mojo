"""CPU-only one-symbol NR PDSCH Monte-Carlo over AWGN and TDL-A/C/D.

The representative allocation is a standards-facing single-layer comb-2
PDSCH symbol: each PRB contains six data REs and six configuration-type-1
DM-RS REs.  MCS and TBS come from the exact TS 38.214 tables and integer TBS
algorithm.  Noise is injected after a ``1/N`` IFFT in the complex sample
domain, then decoded with ``N * N0 / |H_hat[k]|^2`` per data tone.

Receiver exceptions are explicit erasures.  An erasure contributes one CRC
BLER/PER/convergence failure and all payload bits as a conservative BER upper
bound; EVM is omitted because no valid corrected constellation was returned.
"""

from std.collections import Span
from std.math import ceil, isfinite
from wireless_dsp.channel import (
    add_awgn,
    apply_standard_channel,
    tdl_profile,
)
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.nr.grid import (
    NRResourceGrid,
    nr_pdsch_dmrs_c_init,
    nr_map_pdsch_comb2,
)
from wireless_dsp.wireless.nr.pdsch import nr_pdsch_dmrs
from wireless_dsp.wireless.nr.mcs_tbs import (
    NRMCSProfile,
    NRTransportBlockAllocation,
    nr_mcs_profile,
    nr_mcs_target_code_rate,
    nr_transport_block_allocation,
)
from wireless_dsp.wireless.nr.pdsch_chain import (
    NRPDSCHWaveformConfig,
    nr_pdsch_grid_to_waveform,
    nr_pdsch_encode_transport_block,
    nr_pdsch_decode_waveform_comb2,
)
from .monte_carlo import (
    SNR_ESN0_DATA,
    SNR_EBN0_INFORMATION,
    MONTE_CARLO_METRIC_BLER,
    MONTE_CARLO_CONTINUE,
    LINK_SEED_STREAM_PAYLOAD,
    LINK_SEED_STREAM_CHANNEL,
    LINK_SEED_STREAM_NOISE,
    LinkSNRPoint,
    LinkEnergyReference,
    LinkCounters,
    MonteCarloStop,
    LinkCase,
    LinkSweepPoint,
    link_noise_variance,
    wilson_interval,
    monte_carlo_stop_reason,
    derive_link_seed,
)
from .nr_monte_carlo import (
    NR_LINK_CHANNEL_AWGN,
    NR_LINK_CHANNEL_TDL_A,
    NR_LINK_CHANNEL_TDL_C,
    NR_LINK_CHANNEL_TDL_D,
)


comptime NR_LINK_PROTOCOL_PDSCH = UInt64(0x4E525044534348)

# Non-normative deterministic CPU-reference resource bounds.  They constrain
# execution cost only; the MCS and TBS values still come from 3GPP tables.
comptime _MAX_NR_PDSCH_MONTE_CARLO_FFT_SIZE = 4_096
comptime _MAX_NR_PDSCH_MONTE_CARLO_WAVEFORM_SAMPLES = 8_192
comptime _MAX_NR_PDSCH_MONTE_CARLO_TBS_BITS = 1_048_576
comptime _MAX_NR_PDSCH_MONTE_CARLO_ITERATIONS = 256
comptime _MAX_NR_PDSCH_MONTE_CARLO_TRIALS = 65_536
comptime _MAX_NR_PDSCH_MONTE_CARLO_SWEEP_POINTS = 1_024
comptime _MAX_NR_PDSCH_MONTE_CARLO_SWEEP_WORK = 65_536


def _validate_channel(channel_model: Int) raises:
    if (
        channel_model != NR_LINK_CHANNEL_AWGN
        and channel_model != NR_LINK_CHANNEL_TDL_A
        and channel_model != NR_LINK_CHANNEL_TDL_C
        and channel_model != NR_LINK_CHANNEL_TDL_D
    ):
        raise Error("NR PDSCH channel must be AWGN or TDL-A/C/D")


struct NRPDSCHLinkSetup(ImplicitlyCopyable):
    """Shared PDSCH allocation, MCS table, numerology, and decoder policy.

    This CPU reference caps FFT size at 4,096, one-symbol waveform size at
    8,192 samples, transport blocks at 1,048,576 bits, and LDPC iterations at
    256.  These are non-normative execution-capacity bounds.
    """

    var waveform: NRPDSCHWaveformConfig
    var mcs_table: Int
    var redundancy_version: Int
    var subcarrier_spacing_hz: Float64
    var tdl_delay_spread_ns: Float64
    var max_iterations: Int

    def __init__(
        out self,
        waveform: NRPDSCHWaveformConfig,
        mcs_table: Int,
        *,
        redundancy_version: Int = 0,
        subcarrier_spacing_hz: Float64 = 30000.0,
        tdl_delay_spread_ns: Float64 = 100.0,
        max_iterations: Int = 30,
    ) raises:
        waveform.validate()
        if waveform.fft_size > _MAX_NR_PDSCH_MONTE_CARLO_FFT_SIZE:
            raise Error("NR PDSCH setup exceeds the CPU FFT capacity")
        if (
            waveform.fft_size + waveform.cyclic_prefix
            > _MAX_NR_PDSCH_MONTE_CARLO_WAVEFORM_SAMPLES
        ):
            raise Error("NR PDSCH waveform exceeds the CPU sample capacity")
        if redundancy_version < 0 or redundancy_version > 3:
            raise Error("NR PDSCH redundancy version must be in [0,3]")
        if (
            not isfinite(subcarrier_spacing_hz)
            or subcarrier_spacing_hz <= 0.0
            or not isfinite(
                Float64(waveform.fft_size) * subcarrier_spacing_hz
            )
        ):
            raise Error("NR PDSCH subcarrier spacing is invalid")
        if (
            not isfinite(tdl_delay_spread_ns)
            or tdl_delay_spread_ns <= 0.0
        ):
            raise Error("NR PDSCH TDL delay spread is invalid")
        if (
            max_iterations < 1
            or max_iterations > _MAX_NR_PDSCH_MONTE_CARLO_ITERATIONS
        ):
            raise Error("NR PDSCH decoder iteration limit is invalid")
        _ = nr_mcs_profile(mcs_table, 0)
        self.waveform = waveform
        self.mcs_table = mcs_table
        self.redundancy_version = redundancy_version
        self.subcarrier_spacing_hz = subcarrier_spacing_hz
        self.tdl_delay_spread_ns = tdl_delay_spread_ns
        self.max_iterations = max_iterations

    def validate(self) raises:
        _ = NRPDSCHLinkSetup(
            self.waveform,
            self.mcs_table,
            redundancy_version=self.redundancy_version,
            subcarrier_spacing_hz=self.subcarrier_spacing_hz,
            tdl_delay_spread_ns=self.tdl_delay_spread_ns,
            max_iterations=self.max_iterations,
        )

    def sample_rate_hz(self) raises -> Float64:
        self.validate()
        return (
            Float64(self.waveform.fft_size) * self.subcarrier_spacing_hz
        )

    def profile(self, mcs_index: Int) raises -> NRMCSProfile:
        self.validate()
        return nr_mcs_profile(self.mcs_table, mcs_index)

    def allocation(
        self, mcs_index: Int
    ) raises -> NRTransportBlockAllocation:
        var result = nr_transport_block_allocation(
            self.waveform.resource_blocks,
            1,
            6,
            0,
            self.profile(mcs_index),
            1,
        )
        if (
            result.resource_elements_per_prb != 6
            or result.total_resource_elements
            != self.waveform.data_re_count()
        ):
            raise Error("NR PDSCH resource accounting disagrees with mapping")
        if result.transport_block_size > _MAX_NR_PDSCH_MONTE_CARLO_TBS_BITS:
            raise Error("NR PDSCH transport block exceeds the CPU capacity")
        return result


struct NRPDSCHPacketTrial(ImplicitlyCopyable):
    """One replayable packet outcome plus exact energy/seed checkpoints."""

    var mcs: NRMCSProfile
    var allocation: NRTransportBlockAllocation
    var counters: LinkCounters
    var payload_seed: UInt64
    var channel_seed: UInt64
    var noise_seed: UInt64
    var sample_noise_variance: Float64
    var frequency_bin_noise_variance: Float64
    var waveform_energy: Float64
    var waveform_sample_count: Int
    var bit_errors: Int
    var receiver_erasure: Bool
    var transport_crc_ok: Bool
    var decoder_converged: Bool

    def __init__(
        out self,
        mcs: NRMCSProfile,
        allocation: NRTransportBlockAllocation,
        counters: LinkCounters,
        payload_seed: UInt64,
        channel_seed: UInt64,
        noise_seed: UInt64,
        sample_noise_variance: Float64,
        frequency_bin_noise_variance: Float64,
        waveform_energy: Float64,
        waveform_sample_count: Int,
        bit_errors: Int,
        receiver_erasure: Bool,
        transport_crc_ok: Bool,
        decoder_converged: Bool,
    ) raises:
        mcs.validate()
        counters.validate()
        if (
            not isfinite(sample_noise_variance)
            or sample_noise_variance <= 0.0
            or not isfinite(frequency_bin_noise_variance)
            or frequency_bin_noise_variance <= 0.0
            or not isfinite(waveform_energy)
            or waveform_energy <= 0.0
            or waveform_sample_count < 1
            or bit_errors < 0
            or bit_errors > allocation.transport_block_size
            or counters.bit_count != allocation.transport_block_size
            or counters.bit_errors != bit_errors
        ):
            raise Error("NR PDSCH packet-trial checkpoint is inconsistent")
        self.mcs = mcs
        self.allocation = allocation
        self.counters = counters
        self.payload_seed = payload_seed
        self.channel_seed = channel_seed
        self.noise_seed = noise_seed
        self.sample_noise_variance = sample_noise_variance
        self.frequency_bin_noise_variance = frequency_bin_noise_variance
        self.waveform_energy = waveform_energy
        self.waveform_sample_count = waveform_sample_count
        self.bit_errors = bit_errors
        self.receiver_erasure = receiver_erasure
        self.transport_crc_ok = transport_crc_ok
        self.decoder_converged = decoder_converged


struct NRPDSCHLinkPoint(ImplicitlyCopyable):
    """One exact MCS/TBS case and its generic stopped link result."""

    var mcs: NRMCSProfile
    var allocation: NRTransportBlockAllocation
    var result: LinkSweepPoint

    def __init__(
        out self,
        mcs: NRMCSProfile,
        allocation: NRTransportBlockAllocation,
        result: LinkSweepPoint,
    ) raises:
        mcs.validate()
        result.counters.validate()
        self.mcs = mcs
        self.allocation = allocation
        self.result = result


struct _NRPDSCHDecodeSummary(ImplicitlyCopyable):
    var receiver_returned: Bool
    var bit_errors: Int
    var transport_crc_ok: Bool
    var decoder_converged: Bool
    var evm_error_energy: Float64
    var evm_reference_energy: Float64

    def __init__(out self, payload_bits: Int):
        self.receiver_returned = False
        self.bit_errors = payload_bits
        self.transport_crc_ok = False
        self.decoder_converged = False
        self.evm_error_energy = 0.0
        self.evm_reference_energy = 0.0


def _mcs_identity(table: Int, index: Int) -> UInt64:
    return UInt64(64 * table + index)


def _next_payload_bit(mut state: UInt64) -> UInt8:
    state = (
        state * UInt64(6364136223846793005)
        + UInt64(1442695040888963407)
    )
    return UInt8((state >> 63) & UInt64(1))


def _payload(length: Int, seed: UInt64) -> List[UInt8]:
    var state = seed
    var result = List[UInt8](capacity=length)
    for _ in range(length):
        result.append(_next_payload_bit(state))
    return result^


def _energy(values: Span[Complex64, ...]) raises -> Float64:
    if len(values) == 0:
        raise Error("NR PDSCH energy vector must be non-empty")
    var result = 0.0
    for index in range(len(values)):
        if not isfinite(values[index].re) or not isfinite(values[index].im):
            raise Error("NR PDSCH energy requires finite samples")
        result += (
            values[index].re * values[index].re
            + values[index].im * values[index].im
        )
        if not isfinite(result):
            raise Error("NR PDSCH energy overflows Float64")
    if result <= 0.0:
        raise Error("NR PDSCH energy must be positive")
    return result


def _sample_noise_variance(
    snr: LinkSNRPoint,
    waveform_energy: Float64,
    waveform_samples: Int,
    payload_bits: Int,
    fft_size: Int,
) raises -> Float64:
    if snr.mode == SNR_ESN0_DATA:
        var frequency_noise = link_noise_variance(
            snr, LinkEnergyReference(data_symbol_energy=1.0)
        )
        var result = frequency_noise / Float64(fft_size)
        if not isfinite(result) or result <= 0.0:
            raise Error("NR PDSCH Es/N0 sample variance is unrepresentable")
        return result
    if snr.mode == SNR_EBN0_INFORMATION:
        return link_noise_variance(
            snr,
            LinkEnergyReference(
                waveform_energy=waveform_energy,
                information_bits=payload_bits,
                sample_count=waveform_samples,
            ),
        )
    raise Error("NR PDSCH runner supports Es/N0 or exact information Eb/N0")


def _tdl_name(channel_model: Int) raises -> String:
    if channel_model == NR_LINK_CHANNEL_TDL_A:
        return String("A")
    if channel_model == NR_LINK_CHANNEL_TDL_C:
        return String("C")
    if channel_model == NR_LINK_CHANNEL_TDL_D:
        return String("D")
    raise Error("NR PDSCH channel is not a TDL profile")


def _apply_channel(
    waveform: Span[Complex64, ...],
    setup: NRPDSCHLinkSetup,
    channel_model: Int,
    channel_seed: UInt64,
) raises -> List[Complex64]:
    _validate_channel(channel_model)
    if channel_model == NR_LINK_CHANNEL_AWGN:
        var copied = List[Complex64](capacity=len(waveform))
        for index in range(len(waveform)):
            copied.append(waveform[index])
        return copied^
    var profile = tdl_profile(
        _tdl_name(channel_model),
        desired_delay_spread_ns=setup.tdl_delay_spread_ns,
    )
    var sample_rate = setup.sample_rate_hz()
    var maximum_delay_samples = (
        profile.maximum_delay_ns() * sample_rate * 1.0e-9
    )
    if (
        not isfinite(maximum_delay_samples)
        or Int(ceil(maximum_delay_samples))
        > setup.waveform.cyclic_prefix
    ):
        raise Error("NR PDSCH TDL delay exceeds the configured cyclic prefix")
    var full = apply_standard_channel(
        waveform,
        profile,
        sample_rate,
        maximum_doppler_hz=0.0,
        seed=channel_seed,
    )
    if len(full) < len(waveform):
        raise Error("NR PDSCH channel output is unexpectedly short")
    var result = List[Complex64](capacity=len(waveform))
    for index in range(len(waveform)):
        result.append(full[index])
    return result^


def _evm_energies(
    actual: Span[Complex64, ...], expected: Span[Complex64, ...]
) raises -> Tuple[Float64, Float64]:
    if len(actual) != len(expected) or len(actual) == 0:
        raise Error("NR PDSCH EVM vectors must be equal and non-empty")
    var error_energy = 0.0
    var reference_energy = 0.0
    for index in range(len(actual)):
        var error_re = actual[index].re - expected[index].re
        var error_im = actual[index].im - expected[index].im
        error_energy += error_re * error_re + error_im * error_im
        reference_energy += (
            expected[index].re * expected[index].re
            + expected[index].im * expected[index].im
        )
        if not isfinite(error_energy) or not isfinite(reference_energy):
            raise Error("NR PDSCH EVM energy overflows Float64")
    if reference_energy <= 0.0:
        raise Error("NR PDSCH EVM reference energy must be positive")
    return (error_energy, reference_energy)


def _link_case(
    setup: NRPDSCHLinkSetup,
    mcs_index: Int,
    snr: LinkSNRPoint,
    snr_identity: UInt64,
    channel_model: Int,
    channel_seed_identity: UInt64,
) raises -> LinkCase:
    _validate_channel(channel_model)
    _ = setup.profile(mcs_index)
    return LinkCase(
        NR_LINK_PROTOCOL_PDSCH,
        _mcs_identity(setup.mcs_table, mcs_index),
        snr,
        snr_identity,
        UInt64(channel_model),
        channel_seed_identity,
    )


def simulate_nr_pdsch_packet_trial(
    setup: NRPDSCHLinkSetup,
    mcs_index: Int,
    snr: LinkSNRPoint,
    *,
    snr_identity: UInt64,
    channel_model: Int,
    channel_seed_identity: UInt64,
    trial_index: UInt64,
    master_seed: UInt64,
    receiver_fixture_failure: Bool = False,
) raises -> NRPDSCHPacketTrial:
    """Run one packet; ``receiver_fixture_failure`` verifies erasure policy."""
    setup.validate()
    snr.validate()
    _validate_channel(channel_model)
    var mcs = setup.profile(mcs_index)
    var allocation = setup.allocation(mcs_index)
    var identity = _mcs_identity(mcs.table, mcs.index)
    var payload_seed = derive_link_seed(
        master_seed,
        NR_LINK_PROTOCOL_PDSCH,
        identity,
        snr_identity,
        UInt64(channel_model),
        channel_seed_identity,
        trial_index,
        LINK_SEED_STREAM_PAYLOAD,
    )
    var channel_seed = derive_link_seed(
        master_seed,
        NR_LINK_PROTOCOL_PDSCH,
        identity,
        snr_identity,
        UInt64(channel_model),
        channel_seed_identity,
        trial_index,
        LINK_SEED_STREAM_CHANNEL,
    )
    var noise_seed = derive_link_seed(
        master_seed,
        NR_LINK_PROTOCOL_PDSCH,
        identity,
        snr_identity,
        UInt64(channel_model),
        channel_seed_identity,
        trial_index,
        LINK_SEED_STREAM_NOISE,
    )
    var payload = _payload(allocation.transport_block_size, payload_seed)
    var transmit = nr_pdsch_encode_transport_block(
        Span(payload),
        nr_mcs_target_code_rate(mcs),
        mcs.modulation_order,
        setup.redundancy_version,
        setup.waveform.coded_bit_capacity(mcs.modulation_order),
        setup.waveform.rnti,
        setup.waveform.codeword,
        setup.waveform.n_id,
    )
    if len(transmit.symbols) != setup.waveform.data_re_count():
        raise Error("NR PDSCH coded capacity disagrees with mapped data REs")
    var dmrs = nr_pdsch_dmrs(
        nr_pdsch_dmrs_c_init(
            setup.waveform.slot,
            setup.waveform.dmrs_symbol,
            setup.waveform.n_id,
            setup.waveform.n_scid,
        ),
        setup.waveform.dmrs_re_count(),
    )
    var grid = NRResourceGrid(1, setup.waveform.fft_size)
    nr_map_pdsch_comb2(
        grid,
        0,
        setup.waveform.first_subcarrier,
        setup.waveform.allocation_subcarriers(),
        setup.waveform.dmrs_offset,
        Span(transmit.symbols),
        Span(dmrs),
    )
    var waveform = nr_pdsch_grid_to_waveform(setup.waveform, grid)
    var waveform_energy = _energy(Span(waveform))
    var sample_noise = _sample_noise_variance(
        snr,
        waveform_energy,
        len(waveform),
        allocation.transport_block_size,
        setup.waveform.fft_size,
    )
    var frequency_noise = sample_noise * Float64(setup.waveform.fft_size)
    if not isfinite(frequency_noise) or frequency_noise <= 0.0:
        raise Error("NR PDSCH FFT-bin noise variance is unrepresentable")
    var faded = _apply_channel(
        Span(waveform), setup, channel_model, channel_seed
    )
    var received = add_awgn(Span(faded), sample_noise, seed=noise_seed)

    var summary = _NRPDSCHDecodeSummary(allocation.transport_block_size)
    try:
        if receiver_fixture_failure:
            raise Error("injected NR PDSCH receiver fixture failure")
        var decoded = nr_pdsch_decode_waveform_comb2(
            Span(received),
            setup.waveform,
            Span(transmit.encoded_null_mask),
            transmit.profile,
            allocation.transport_block_size,
            mcs.modulation_order,
            setup.redundancy_version,
            sample_noise,
            max_iterations=setup.max_iterations,
        )
        if len(decoded.payload) != allocation.transport_block_size:
            raise Error("NR PDSCH receiver returned an invalid payload length")
        var bit_errors = 0
        for index in range(allocation.transport_block_size):
            if decoded.payload[index] != payload[index]:
                bit_errors += 1
        var evm = _evm_energies(
            Span(decoded.equalized_symbols), Span(transmit.symbols)
        )
        summary.receiver_returned = True
        summary.bit_errors = bit_errors
        summary.transport_crc_ok = decoded.transport_crc_ok
        summary.decoder_converged = decoded.ldpc_converged
        summary.evm_error_energy = evm[0]
        summary.evm_reference_energy = evm[1]
    except:
        summary.bit_errors = allocation.transport_block_size

    var erasure = not summary.receiver_returned
    var crc_failure = erasure or not summary.transport_crc_ok
    var convergence_failure = erasure or not summary.decoder_converged
    var packet_failure = (
        erasure
        or summary.bit_errors > 0
        or crc_failure
        or convergence_failure
    )
    var counters = LinkCounters(
        bit_count=allocation.transport_block_size,
        bit_errors=summary.bit_errors,
        transport_block_count=1,
        transport_block_errors=1 if crc_failure else 0,
        packet_count=1,
        packet_errors=1 if packet_failure else 0,
        crc_check_count=1,
        crc_failures=1 if crc_failure else 0,
        decoder_attempt_count=1,
        convergence_failures=1 if convergence_failure else 0,
        evm_error_energy=summary.evm_error_energy,
        evm_reference_energy=summary.evm_reference_energy,
    )
    return NRPDSCHPacketTrial(
        mcs,
        allocation,
        counters,
        payload_seed,
        channel_seed,
        noise_seed,
        sample_noise,
        frequency_noise,
        waveform_energy,
        len(waveform),
        summary.bit_errors,
        erasure,
        summary.transport_crc_ok,
        summary.decoder_converged,
    )


def simulate_nr_pdsch_trials(
    setup: NRPDSCHLinkSetup,
    mcs_index: Int,
    snr: LinkSNRPoint,
    snr_identity: UInt64,
    channel_model: Int,
    channel_seed_identity: UInt64,
    master_seed: UInt64,
    first_trial: UInt64,
    trial_count: Int,
) raises -> NRPDSCHLinkPoint:
    """Run a bounded contiguous global packet range for exact shard merging."""
    setup.validate()
    snr.validate()
    _validate_channel(channel_model)
    if trial_count < 0:
        raise Error("NR PDSCH trial count must be non-negative")
    if trial_count > _MAX_NR_PDSCH_MONTE_CARLO_TRIALS:
        raise Error("NR PDSCH trial count exceeds the CPU capacity")
    if (
        trial_count > 0
        and first_trial > UInt64.MAX - UInt64(trial_count - 1)
    ):
        raise Error("NR PDSCH global trial range overflows UInt64")
    var mcs = setup.profile(mcs_index)
    var allocation = setup.allocation(mcs_index)
    if (
        trial_count > 0
        and allocation.transport_block_size > Int.MAX // trial_count
    ):
        raise Error("NR PDSCH accumulated bit count overflows Int")
    var counters = LinkCounters()
    for offset in range(trial_count):
        var trial = simulate_nr_pdsch_packet_trial(
            setup,
            mcs_index,
            snr,
            snr_identity=snr_identity,
            channel_model=channel_model,
            channel_seed_identity=channel_seed_identity,
            trial_index=first_trial + UInt64(offset),
            master_seed=master_seed,
        )
        counters.merge(trial.counters)
    var link_case = _link_case(
        setup,
        mcs_index,
        snr,
        snr_identity,
        channel_model,
        channel_seed_identity,
    )
    return NRPDSCHLinkPoint(
        mcs,
        allocation,
        LinkSweepPoint(
            link_case,
            counters,
            wilson_interval(
                counters.transport_block_errors,
                counters.transport_block_count,
            ),
            MONTE_CARLO_CONTINUE,
        ),
    )


def simulate_nr_pdsch_case(
    setup: NRPDSCHLinkSetup,
    mcs_index: Int,
    snr: LinkSNRPoint,
    snr_identity: UInt64,
    channel_model: Int,
    channel_seed_identity: UInt64,
    master_seed: UInt64,
    policy: MonteCarloStop,
    *,
    first_trial: UInt64 = UInt64(0),
) raises -> NRPDSCHLinkPoint:
    """Run one PDSCH case until its CRC-BLER stopping policy fires."""
    setup.validate()
    snr.validate()
    _validate_channel(channel_model)
    policy.validate()
    if first_trial > UInt64.MAX - UInt64(policy.max_trials - 1):
        raise Error("NR PDSCH stopped trial range overflows UInt64")
    var counters = LinkCounters()
    var mcs = setup.profile(mcs_index)
    var allocation = setup.allocation(mcs_index)
    if allocation.transport_block_size > Int.MAX // policy.max_trials:
        raise Error("NR PDSCH accumulated bit count overflows Int")
    var reason = MONTE_CARLO_CONTINUE
    for offset in range(policy.max_trials):
        var trial = simulate_nr_pdsch_packet_trial(
            setup,
            mcs_index,
            snr,
            snr_identity=snr_identity,
            channel_model=channel_model,
            channel_seed_identity=channel_seed_identity,
            trial_index=first_trial + UInt64(offset),
            master_seed=master_seed,
        )
        counters.merge(trial.counters)
        reason = monte_carlo_stop_reason(
            counters, policy, MONTE_CARLO_METRIC_BLER
        )
        if reason != MONTE_CARLO_CONTINUE:
            break
    var link_case = _link_case(
        setup,
        mcs_index,
        snr,
        snr_identity,
        channel_model,
        channel_seed_identity,
    )
    return NRPDSCHLinkPoint(
        mcs,
        allocation,
        LinkSweepPoint(
            link_case,
            counters,
            wilson_interval(
                counters.transport_block_errors,
                counters.transport_block_count,
                z=policy.confidence_z,
            ),
            reason,
        ),
    )


def _unique_ints(values: Span[Int, ...]) raises:
    for first in range(len(values)):
        for second in range(first + 1, len(values)):
            if values[first] == values[second]:
                raise Error("NR PDSCH integer sweep axes must be unique")


def _unique_u64(values: Span[UInt64, ...]) raises:
    for first in range(len(values)):
        for second in range(first + 1, len(values)):
            if values[first] == values[second]:
                raise Error("NR PDSCH identifier sweep axes must be unique")


def _checked_product(lhs: Int, rhs: Int) raises -> Int:
    if lhs < 0 or rhs < 0 or (rhs != 0 and lhs > Int.MAX // rhs):
        raise Error("NR PDSCH sweep point count overflows Int")
    return lhs * rhs


def simulate_nr_pdsch_sweep(
    setup: NRPDSCHLinkSetup,
    mcs_indices: Span[Int, ...],
    snr_points: Span[LinkSNRPoint, ...],
    snr_identities: Span[UInt64, ...],
    channel_models: Span[Int, ...],
    channel_seed_identities: Span[UInt64, ...],
    master_seed: UInt64,
    policy: MonteCarloStop,
) raises -> List[NRPDSCHLinkPoint]:
    """Run a bounded MCS/SNR/channel/channel-seed Cartesian product.

    At most 1,024 points and 65,536 point-trials are executed by this
    non-normative CPU reference.
    """
    setup.validate()
    policy.validate()
    if (
        len(mcs_indices) == 0
        or len(snr_points) == 0
        or len(snr_points) != len(snr_identities)
        or len(channel_models) == 0
        or len(channel_seed_identities) == 0
    ):
        raise Error("NR PDSCH sweep axes must be non-empty and aligned")
    # Enforce allocation and total-work limits before quadratic uniqueness
    # checks.  Every product is checked before multiplication.
    var count = _checked_product(len(mcs_indices), len(snr_points))
    count = _checked_product(count, len(channel_models))
    count = _checked_product(count, len(channel_seed_identities))
    if count > _MAX_NR_PDSCH_MONTE_CARLO_SWEEP_POINTS:
        raise Error("NR PDSCH sweep point count exceeds the CPU capacity")
    if count > _MAX_NR_PDSCH_MONTE_CARLO_SWEEP_WORK // policy.max_trials:
        raise Error("NR PDSCH sweep work exceeds the CPU capacity")
    _unique_ints(mcs_indices)
    _unique_u64(snr_identities)
    _unique_ints(channel_models)
    _unique_u64(channel_seed_identities)
    for index in range(len(mcs_indices)):
        _ = setup.profile(mcs_indices[index])
    for index in range(len(snr_points)):
        _ = LinkSNRPoint(snr_points[index].mode, snr_points[index].db)
        if (
            snr_points[index].mode != SNR_ESN0_DATA
            and snr_points[index].mode != SNR_EBN0_INFORMATION
        ):
            raise Error("NR PDSCH sweep SNR mode is unsupported")
        if not isfinite(snr_points[index].db):
            raise Error("NR PDSCH sweep SNR must be finite")
    for index in range(len(channel_models)):
        _validate_channel(channel_models[index])
    var result = List[NRPDSCHLinkPoint](capacity=count)
    for mcs_axis in range(len(mcs_indices)):
        for snr_index in range(len(snr_points)):
            for channel_axis in range(len(channel_models)):
                for seed_axis in range(len(channel_seed_identities)):
                    result.append(simulate_nr_pdsch_case(
                        setup,
                        mcs_indices[mcs_axis],
                        LinkSNRPoint(
                            snr_points[snr_index].mode,
                            snr_points[snr_index].db,
                        ),
                        snr_identities[snr_index],
                        channel_models[channel_axis],
                        channel_seed_identities[seed_axis],
                        master_seed,
                        policy,
                    ))
    return result^
