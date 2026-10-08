"""Per-public-API CPU timings for the bounded Rel-17 feMIMO slice.

Every public algorithm has a separate ``@no_inline`` batched workload.  All
decoded inputs and reusable configurations are built before warmup/timing;
owned list outputs are retained whole and fingerprinted in O(1).
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.wireless.nr.femimo_rel17 import (
    NRFeMIMORel17PortSelectionConfig,
    nr_femimo_rel17_port_selection_config,
    nr_femimo_rel17_ri_allowed,
    nr_femimo_rel17_i12_state_count,
    nr_femimo_rel17_i12_to_vector_indices,
    nr_femimo_rel17_vector_indices_to_i12,
    nr_femimo_rel17_strongest_coefficient_index,
    nr_femimo_rel17_strongest_coefficient_coordinates,
    nr_femimo_rel17_csi_coefficient_priority,
    nr_femimo_rel17_nonzero_coefficient_total,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _BATCH = 4096
comptime _FIXED_SALT = 0x38_214_17


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 4096)) * UInt64(1099511628211)


@no_inline
def _config_workload(
    iterations: Int,
    salt: Int,
    ports: Span[Int, ...],
    combinations: Span[Int, ...],
    ri_bitmaps: Span[Int, ...],
    values_of_n: Span[Int, ...],
    subband_ratios: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = (operation + salt) % len(ports)
        var port_count = ports[index]
        var combination = combinations[index]
        var ri_bitmap = ri_bitmaps[index]
        var value_of_n = values_of_n[index]
        var subband_ratio = subband_ratios[index]
        var config = nr_femimo_rel17_port_selection_config(
            black_box(port_count),
            black_box(combination),
            black_box(ri_bitmap),
            black_box(value_of_n),
            black_box(subband_ratio),
        )
        checksum = _mix(checksum, config.csi_rs_ports)
        checksum = _mix(checksum, config.param_combination)
        checksum = _mix(checksum, config.ri_restriction_bitmap)
        checksum = _mix(checksum, config.frequency_vectors)
        checksum = _mix(checksum, Int(config.alpha * 4.0))
        checksum = _mix(checksum, Int(config.beta * 4.0))
        checksum = _mix(checksum, config.value_of_n)
        checksum = _mix(
            checksum, config.pmi_subbands_per_cqi_subband
        )
        checksum = _mix(checksum, config.selected_ports)
        checksum = _mix(checksum, config.selected_vectors)
        checksum = _mix(checksum, config.per_layer_nonzero_limit)
        keep(config)
    return checksum


@no_inline
def _ri_allowed_workload(
    iterations: Int,
    salt: Int,
    configs: Span[NRFeMIMORel17PortSelectionConfig, ...],
    layers: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = (operation + salt) % len(configs)
        var config = configs[index]
        var layer_count = layers[index]
        var allowed = nr_femimo_rel17_ri_allowed(
            black_box(config), black_box(layer_count)
        )
        checksum = _mix(checksum, Int(allowed) + operation)
        keep(allowed)
    return checksum


@no_inline
def _i12_state_count_workload(
    iterations: Int,
    salt: Int,
    configs: Span[NRFeMIMORel17PortSelectionConfig, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var config = configs[(operation + salt) % len(configs)]
        var count = nr_femimo_rel17_i12_state_count(black_box(config))
        checksum = _mix(checksum, count + operation)
        keep(count)
    return checksum


@no_inline
def _i12_decode_workload(
    iterations: Int,
    salt: Int,
    config: NRFeMIMORel17PortSelectionConfig,
    i12_values: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var i12 = i12_values[(operation + salt) % len(i12_values)]
        var selected = nr_femimo_rel17_i12_to_vector_indices(
            black_box(config), black_box(i12)
        )
        checksum = _mix(checksum, len(selected))
        checksum = _mix(checksum, selected[0])
        checksum = _mix(checksum, selected[len(selected) - 1])
        keep(selected)
    return checksum


@no_inline
def _i12_encode_workload(
    iterations: Int,
    salt: Int,
    config: NRFeMIMORel17PortSelectionConfig,
    selected_vectors: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var i12 = nr_femimo_rel17_vector_indices_to_i12(
            black_box(config), selected_vectors
        )
        checksum = _mix(checksum, i12 + ((operation + salt) & 1))
        keep(i12)
    return checksum


@no_inline
def _strongest_index_workload(
    iterations: Int,
    salt: Int,
    config: NRFeMIMORel17PortSelectionConfig,
    vector_indices: Span[Int, ...],
    frequency_indices: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = (operation + salt) % len(vector_indices)
        var vector_index = vector_indices[index]
        var frequency_index = frequency_indices[index]
        var i18 = nr_femimo_rel17_strongest_coefficient_index(
            black_box(config),
            black_box(vector_index),
            black_box(frequency_index),
        )
        checksum = _mix(checksum, i18 + operation)
        keep(i18)
    return checksum


@no_inline
def _strongest_coordinates_workload(
    iterations: Int,
    salt: Int,
    config: NRFeMIMORel17PortSelectionConfig,
    i18_values: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var i18 = i18_values[(operation + salt) % len(i18_values)]
        var coordinates = nr_femimo_rel17_strongest_coefficient_coordinates(
            black_box(config), black_box(i18)
        )
        checksum = _mix(checksum, coordinates[0])
        checksum = _mix(checksum, coordinates[1])
        keep(coordinates)
    return checksum


@no_inline
def _coefficient_priority_workload(
    iterations: Int,
    salt: Int,
    config: NRFeMIMORel17PortSelectionConfig,
    layers: Span[Int, ...],
    layer_indices: Span[Int, ...],
    vector_indices: Span[Int, ...],
    frequency_indices: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var index = (operation + salt) % len(layers)
        var layer_count = layers[index]
        var layer_index = layer_indices[index]
        var vector_index = vector_indices[index]
        var frequency_index = frequency_indices[index]
        var priority = nr_femimo_rel17_csi_coefficient_priority(
            black_box(config),
            black_box(layer_count),
            black_box(layer_index),
            black_box(vector_index),
            black_box(frequency_index),
        )
        checksum = _mix(checksum, priority + operation)
        keep(priority)
    return checksum


@no_inline
def _nonzero_total_workload(
    iterations: Int,
    salt: Int,
    config: NRFeMIMORel17PortSelectionConfig,
    per_layer_counts: Span[Int, ...],
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for operation in range(iterations):
        var total = nr_femimo_rel17_nonzero_coefficient_total(
            black_box(config), per_layer_counts
        )
        checksum = _mix(checksum, total + ((operation + salt) & 1))
        keep(total)
    return checksum


def main() raises:
    # All benchmark inputs and reusable mutable-value configurations are
    # prepared before both warmup and measurement.
    var ports: List[Int] = [8, 16, 24, 32, 8, 16, 24, 24]
    var combinations: List[Int] = [1, 2, 3, 4, 5, 6, 7, 8]
    var ri_bitmaps: List[Int] = [0xF, 0xA, 0x7, 0xF, 0xF, 0xF, 0x3, 0xF]
    var values_of_n: List[Int] = [0, 0, 0, 0, 2, 4, 2, 4]
    var subband_ratios: List[Int] = [1, 1, 1, 1, 1, 2, 1, 2]
    var configs = List[NRFeMIMORel17PortSelectionConfig](capacity=8)
    for index in range(8):
        configs.append(nr_femimo_rel17_port_selection_config(
            ports[index],
            combinations[index],
            ri_bitmaps[index],
            values_of_n[index],
            subband_ratios[index],
        ))
    var ri_layers: List[Int] = [1, 2, 3, 4, 1, 2, 2, 4]

    var combinadic_config = nr_femimo_rel17_port_selection_config(
        8, 5, 0xF, 2, 1
    )
    var i12_values: List[Int] = [0, 1, 2, 3, 4, 5]
    var selected_vectors: List[Int] = [1, 3]

    var coefficient_config = nr_femimo_rel17_port_selection_config(
        16, 6, 0xF, 4, 2
    )
    var vector_indices: List[Int] = [0, 3, 7, 11]
    var frequency_indices: List[Int] = [0, 1, 0, 1]
    var i18_values: List[Int] = [0, 15, 7, 23]
    var priority_layers: List[Int] = [1, 2, 3, 4]
    var priority_layer_indices: List[Int] = [0, 1, 2, 3]
    var per_layer_counts: List[Int] = [7, 12]

    var ports_span = Span(ports)
    var combinations_span = Span(combinations)
    var ri_bitmaps_span = Span(ri_bitmaps)
    var values_of_n_span = Span(values_of_n)
    var subband_ratios_span = Span(subband_ratios)
    var configs_span = Span(configs)
    var ri_layers_span = Span(ri_layers)
    var i12_values_span = Span(i12_values)
    var selected_vectors_span = Span(selected_vectors)
    var vector_indices_span = Span(vector_indices)
    var frequency_indices_span = Span(frequency_indices)
    var i18_values_span = Span(i18_values)
    var priority_layers_span = Span(priority_layers)
    var priority_layer_indices_span = Span(priority_layer_indices)
    var per_layer_counts_span = Span(per_layer_counts)

    for _ in range(_WARMUPS):
        keep(_config_workload(
            _BATCH,
            _FIXED_SALT,
            ports_span,
            combinations_span,
            ri_bitmaps_span,
            values_of_n_span,
            subband_ratios_span,
        ))
        keep(_ri_allowed_workload(
            _BATCH, _FIXED_SALT, configs_span, ri_layers_span
        ))
        keep(_i12_state_count_workload(
            _BATCH, _FIXED_SALT, configs_span
        ))
        keep(_i12_decode_workload(
            _BATCH, _FIXED_SALT, combinadic_config, i12_values_span
        ))
        keep(_i12_encode_workload(
            _BATCH,
            _FIXED_SALT,
            combinadic_config,
            selected_vectors_span,
        ))
        keep(_strongest_index_workload(
            _BATCH,
            _FIXED_SALT,
            coefficient_config,
            vector_indices_span,
            frequency_indices_span,
        ))
        keep(_strongest_coordinates_workload(
            _BATCH, _FIXED_SALT, coefficient_config, i18_values_span
        ))
        keep(_coefficient_priority_workload(
            _BATCH,
            _FIXED_SALT,
            coefficient_config,
            priority_layers_span,
            priority_layer_indices_span,
            vector_indices_span,
            frequency_indices_span,
        ))
        keep(_nonzero_total_workload(
            _BATCH,
            _FIXED_SALT,
            coefficient_config,
            per_layer_counts_span,
        ))

    print_benchmark_metadata()
    print("nr_femimo_rel17_backend: scalar-cpu-reference")
    var total_checksum = UInt64(0)

    var config_samples = List[UInt64](capacity=_SAMPLES)
    var ri_samples = List[UInt64](capacity=_SAMPLES)
    var count_samples = List[UInt64](capacity=_SAMPLES)
    var decode_samples = List[UInt64](capacity=_SAMPLES)
    var encode_samples = List[UInt64](capacity=_SAMPLES)
    var strongest_samples = List[UInt64](capacity=_SAMPLES)
    var coordinates_samples = List[UInt64](capacity=_SAMPLES)
    var priority_samples = List[UInt64](capacity=_SAMPLES)
    var nonzero_samples = List[UInt64](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var config_checksum = _config_workload(
            _BATCH,
            _FIXED_SALT,
            ports_span,
            combinations_span,
            ri_bitmaps_span,
            values_of_n_span,
            subband_ratios_span,
        )
        config_samples.append(global_perf_counter_ns() - start)
        total_checksum ^= config_checksum
        keep(config_checksum)

        start = global_perf_counter_ns()
        var ri_checksum = _ri_allowed_workload(
            _BATCH, _FIXED_SALT, configs_span, ri_layers_span
        )
        ri_samples.append(global_perf_counter_ns() - start)
        total_checksum ^= ri_checksum
        keep(ri_checksum)

        start = global_perf_counter_ns()
        var count_checksum = _i12_state_count_workload(
            _BATCH, _FIXED_SALT, configs_span
        )
        count_samples.append(global_perf_counter_ns() - start)
        total_checksum ^= count_checksum
        keep(count_checksum)

        start = global_perf_counter_ns()
        var decode_checksum = _i12_decode_workload(
            _BATCH, _FIXED_SALT, combinadic_config, i12_values_span
        )
        decode_samples.append(global_perf_counter_ns() - start)
        total_checksum ^= decode_checksum
        keep(decode_checksum)

        start = global_perf_counter_ns()
        var encode_checksum = _i12_encode_workload(
            _BATCH,
            _FIXED_SALT,
            combinadic_config,
            selected_vectors_span,
        )
        encode_samples.append(global_perf_counter_ns() - start)
        total_checksum ^= encode_checksum
        keep(encode_checksum)

        start = global_perf_counter_ns()
        var strongest_checksum = _strongest_index_workload(
            _BATCH,
            _FIXED_SALT,
            coefficient_config,
            vector_indices_span,
            frequency_indices_span,
        )
        strongest_samples.append(global_perf_counter_ns() - start)
        total_checksum ^= strongest_checksum
        keep(strongest_checksum)

        start = global_perf_counter_ns()
        var coordinates_checksum = _strongest_coordinates_workload(
            _BATCH, _FIXED_SALT, coefficient_config, i18_values_span
        )
        coordinates_samples.append(global_perf_counter_ns() - start)
        total_checksum ^= coordinates_checksum
        keep(coordinates_checksum)

        start = global_perf_counter_ns()
        var priority_checksum = _coefficient_priority_workload(
            _BATCH,
            _FIXED_SALT,
            coefficient_config,
            priority_layers_span,
            priority_layer_indices_span,
            vector_indices_span,
            frequency_indices_span,
        )
        priority_samples.append(global_perf_counter_ns() - start)
        total_checksum ^= priority_checksum
        keep(priority_checksum)

        start = global_perf_counter_ns()
        var nonzero_checksum = _nonzero_total_workload(
            _BATCH,
            _FIXED_SALT,
            coefficient_config,
            per_layer_counts_span,
        )
        nonzero_samples.append(global_perf_counter_ns() - start)
        total_checksum ^= nonzero_checksum
        keep(nonzero_checksum)

    report_timing_samples(
        "nr_femimo_rel17_port_selection_config",
        config_samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    report_timing_samples(
        "nr_femimo_rel17_ri_allowed",
        ri_samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    report_timing_samples(
        "nr_femimo_rel17_i12_state_count",
        count_samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    report_timing_samples(
        "nr_femimo_rel17_i12_to_vector_indices",
        decode_samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    report_timing_samples(
        "nr_femimo_rel17_vector_indices_to_i12",
        encode_samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    report_timing_samples(
        "nr_femimo_rel17_strongest_coefficient_index",
        strongest_samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    report_timing_samples(
        "nr_femimo_rel17_strongest_coefficient_coordinates",
        coordinates_samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    report_timing_samples(
        "nr_femimo_rel17_csi_coefficient_priority",
        priority_samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    report_timing_samples(
        "nr_femimo_rel17_nonzero_coefficient_total",
        nonzero_samples,
        _WARMUPS,
        _BATCH,
        "api_call",
    )
    print("nr_femimo_rel17_retained_checksum:", total_checksum)
