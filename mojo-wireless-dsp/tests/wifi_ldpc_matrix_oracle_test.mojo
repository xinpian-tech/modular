"""Independent all-profile WLAN QC-LDPC matrix and codeword evidence.

The checked-in V1 fixture is generated without importing this package.  Its
2160 base shifts come from pinned BSD-3-Clause YALDPC source, while all twelve
systematic codewords are produced by the pinned MIT tavildar native C++
encoder.  This test compares every returned base entry, independently expands
every CSR row, and compares every encoder output bit.  Neither a production
checksum nor a production encode/syndrome round trip is used as the oracle.
"""

from std.collections import Span
from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)
from wireless_dsp.wireless.wifi.ldpc import (
    WifiLDPCProfile,
    wifi_ldpc_base_shifts,
    wifi_ldpc_decode,
    wifi_ldpc_encode,
    wifi_ldpc_profile,
    wifi_ldpc_rate_match_block,
    wifi_ldpc_rate_recover_block,
    wifi_ldpc_sparse_graph,
    wifi_ldpc_syndrome_ok,
)


def _read_fixture() raises -> String:
    with open(
        "mojo-wireless-dsp/tests/fixtures/wifi_ldpc_matrix_oracle_v1.tsv",
        "r",
    ) as file:
        return file.read()


def _require_ascii_lf(text: StringSlice) raises:
    if text.byte_length() == 0 or text.as_bytes()[text.byte_length() - 1] != 10:
        raise Error("Wi-Fi LDPC fixture must have one trailing LF")
    if text.byte_length() >= 2 and text.as_bytes()[text.byte_length() - 2] == 10:
        raise Error("Wi-Fi LDPC fixture must not have a trailing blank line")
    for index in range(text.byte_length()):
        var byte = UInt8(text.as_bytes()[index])
        if byte == 13 or byte > 0x7F:
            raise Error("Wi-Fi LDPC fixture must be LF-only ASCII")


def _parse_int(value: StringSlice) raises -> Int:
    if value.byte_length() == 0 or value.byte_length() > 5:
        raise Error("Wi-Fi LDPC fixture integer has an invalid width")
    var index = 0
    var negative = False
    if ord(value[byte=0]) == ord("-"):
        negative = True
        index = 1
    if index == value.byte_length():
        raise Error("Wi-Fi LDPC fixture integer is empty")
    if (
        value.byte_length() - index > 1
        and ord(value[byte=index]) == ord("0")
    ):
        raise Error("Wi-Fi LDPC fixture integer has a leading zero")
    var result = 0
    while index < value.byte_length():
        var code = ord(value[byte=index])
        if code < ord("0") or code > ord("9"):
            raise Error("Wi-Fi LDPC fixture integer is not decimal")
        result = 10 * result + code - ord("0")
        index += 1
    return -result if negative else result


def _parse_csv_ints(value: StringSlice) raises -> List[Int]:
    var fields = value.split(",")
    var result = List[Int](capacity=len(fields))
    for field in fields:
        result.append(_parse_int(field))
    return result^


def _parse_bits(value: StringSlice, expected_length: Int) raises -> List[UInt8]:
    if value.byte_length() != expected_length:
        raise Error("Wi-Fi LDPC fixture bit string has the wrong length")
    var result = List[UInt8](capacity=expected_length)
    for index in range(expected_length):
        var code = ord(value[byte=index])
        if code != ord("0") and code != ord("1"):
            raise Error("Wi-Fi LDPC fixture bit string is not binary")
        result.append(UInt8(code - ord("0")))
    return result^


def _split_owned_fields(line: StringSlice) -> List[String]:
    var slices = line.split("\t")
    var result = List[String](capacity=len(slices))
    for field in slices:
        result.append(String(field))
    return result^


def _require_record_key(
    fields: List[String],
    record: StringSlice,
    block_length: Int,
    numerator: Int,
    denominator: Int,
    row_index: Int,
) raises:
    assert_equal(len(fields), 7)
    assert_equal(fields[0], record)
    assert_equal(_parse_int(fields[1]), block_length)
    assert_equal(_parse_int(fields[2]), numerator)
    assert_equal(_parse_int(fields[3]), denominator)
    assert_equal(_parse_int(fields[4]), row_index)


def test_all_profiles_external_matrix_graph_and_codeword_oracle() raises:
    var fixture = _read_fixture()
    _require_ascii_lf(StringSlice(fixture))
    var lines = fixture.split("\n")
    assert_equal(len(lines), 190)
    assert_equal(lines[0], "# MWDSP-WIFI-LDPC-MATRIX-ORACLE-V1")
    assert_equal(
        lines[1],
        "# generator_sha256=c31d17ea7b39f77b61bf2b9fe26df2ecc9a591ce691ad825e6bbb1417a1c9ef8",
    )
    assert_equal(
        lines[4],
        "# yaldpc_commit=7ac1cd6261e485b3cd91b2a1da5728c17d2bb50f",
    )
    assert_equal(
        lines[6],
        "# yaldpc_matrix_sha256=35b8dd95ad08f1aaa8a5dd7f659711a391562c0537adb8e5b99f6fd25c57d7b4",
    )
    assert_equal(
        lines[7],
        "# yaldpc_license=BSD-3-Clause;license_sha256=832953db1090569f874669ff8ca9889dd9206b4575a4997075c84d78b1111334",
    )
    assert_equal(
        lines[9],
        "# tavildar_commit=05ee7f4af36ed5dacf52861315af68b8a17e71e0",
    )
    assert_equal(
        lines[11],
        "# tavildar_matrix_sha256=b2a6e22dce37ab57c883503f7078feb16fcc8e5dc029efc7bc596c10de196934",
    )
    assert_equal(
        lines[14],
        "# tavildar_license=MIT;license_sha256=d4fbfb1aeca7504abd6d64bce60d18e02d116a3a46addb13b14441bb4ad5cfe5",
    )
    assert_equal(
        lines[15],
        "# oracle_role=independent_differential_only_not_normative_authority",
    )
    assert_equal(
        lines[18],
        "# corpus=12_profiles;2160_base_entries;90_base_rows;12_codewords;55620_expanded_edges",
    )
    assert_equal(
        lines[19],
        "# canonical_records_sha256=f763bd8e0e101e10dff3d4f353ba196d1352a0f83135d156e1503e25146b12ac",
    )
    assert_equal(lines[20], "# yaldpc_bsd3_license_text_begin")
    assert_equal(lines[50], "# yaldpc_bsd3_license_text_end")
    assert_equal(lines[51], "# tavildar_mit_license_text_begin")
    assert_equal(lines[73], "# tavildar_mit_license_text_end")
    assert_equal(
        lines[74],
        "record\tblock_length\trate_numerator\trate_denominator\trow_index\tvalues\tauxiliary",
    )
    assert_equal(lines[189], "")

    var record_index = 75
    var profile_count = 0
    var base_entry_count = 0
    var expanded_edge_count = 0
    for block_length in [648, 1296, 1944]:
        for numerator, denominator, expected_block_rows in [
            (1, 2, 12),
            (2, 3, 8),
            (3, 4, 6),
            (5, 6, 4),
        ]:
            var profile_fields = _split_owned_fields(lines[record_index])
            _require_record_key(
                profile_fields,
                "profile",
                block_length,
                numerator,
                denominator,
                -1,
            )
            assert_equal(profile_fields[6], "-")
            var dimensions = _parse_csv_ints(profile_fields[5])
            assert_equal(len(dimensions), 6)
            var lifting_size = block_length // 24
            var parity_length = expected_block_rows * lifting_size
            var information_length = block_length - parity_length
            assert_equal(dimensions[0], lifting_size)
            assert_equal(dimensions[1], expected_block_rows)
            assert_equal(dimensions[2], information_length)
            assert_equal(dimensions[3], parity_length)
            record_index += 1
            profile_count += 1

            var profile = wifi_ldpc_profile(
                block_length, numerator, denominator
            )
            var actual_shifts = wifi_ldpc_base_shifts(profile)
            var expected_shifts = List[Int](
                capacity=expected_block_rows * 24
            )
            var nonzero_blocks = 0
            for block_row in range(expected_block_rows):
                var base_fields = _split_owned_fields(lines[record_index])
                _require_record_key(
                    base_fields,
                    "base",
                    block_length,
                    numerator,
                    denominator,
                    block_row,
                )
                assert_equal(base_fields[6], "-")
                var row = _parse_csv_ints(base_fields[5])
                assert_equal(len(row), 24)
                for block_column in range(24):
                    var shift = row[block_column]
                    assert_true(
                        shift == -1
                        or (shift >= 0 and shift < lifting_size)
                    )
                    expected_shifts.append(shift)
                    assert_equal(
                        actual_shifts[block_row * 24 + block_column],
                        shift,
                    )
                    if shift >= 0:
                        nonzero_blocks += 1
                    base_entry_count += 1
                record_index += 1
            assert_equal(dimensions[4], nonzero_blocks)
            if (
                block_length == 1296
                and numerator == 2
                and denominator == 3
            ):
                # The previously mistyped row-3/column-10 (flat 82) entry.
                assert_equal(expected_shifts[82], 22)

            # This is a test-owned expansion of the independently fixed base
            # rows.  It does not call the production base-table API.
            var expected_offsets = List[Int](capacity=parity_length + 1)
            var expected_columns = List[Int]()
            expected_offsets.append(0)
            for block_row in range(expected_block_rows):
                for local_row in range(lifting_size):
                    for block_column in range(24):
                        var shift = expected_shifts[
                            block_row * 24 + block_column
                        ]
                        if shift >= 0:
                            expected_columns.append(
                                block_column * lifting_size
                                + (local_row + shift) % lifting_size
                            )
                    expected_offsets.append(len(expected_columns))
            assert_equal(dimensions[5], len(expected_columns))
            expanded_edge_count += len(expected_columns)
            var actual_graph = wifi_ldpc_sparse_graph(profile)
            assert_equal(actual_graph.row_offsets, expected_offsets)
            assert_equal(actual_graph.columns, expected_columns)

            var codeword_fields = _split_owned_fields(lines[record_index])
            _require_record_key(
                codeword_fields,
                "codeword",
                block_length,
                numerator,
                denominator,
                -1,
            )
            var information = _parse_bits(
                codeword_fields[5], information_length
            )
            var expected_codeword = _parse_bits(
                codeword_fields[6], block_length
            )
            assert_equal(
                wifi_ldpc_encode(Span(information), profile),
                expected_codeword,
            )
            assert_true(
                wifi_ldpc_syndrome_ok(Span(expected_codeword), profile)
            )
            record_index += 1

    assert_equal(record_index, 189)
    assert_equal(profile_count, 12)
    assert_equal(base_entry_count, 2160)
    assert_equal(expanded_edge_count, 55620)


def _require_mutated_profile_rejected(profile: WifiLDPCProfile) raises:
    # These have the exact valid shapes and values for the canonical
    # 648-bit rate-1/2 profile.  A rejection therefore cannot be caused by a
    # deliberately invalid payload hiding a missing profile revalidation.
    var information = List[UInt8](length=324, fill=UInt8(0))
    var codeword = List[UInt8](length=648, fill=UInt8(0))
    var llrs = List[Float64](length=648, fill=1.0)
    with assert_raises():
        _ = wifi_ldpc_base_shifts(profile)
    with assert_raises():
        _ = wifi_ldpc_sparse_graph(profile)
    with assert_raises():
        _ = wifi_ldpc_syndrome_ok(Span(codeword), profile)
    with assert_raises():
        _ = wifi_ldpc_encode(Span(information), profile)
    with assert_raises():
        _ = wifi_ldpc_decode(Span(llrs), profile)
    with assert_raises():
        _ = wifi_ldpc_rate_match_block(Span(information), profile)
    with assert_raises():
        _ = wifi_ldpc_rate_recover_block(Span(llrs), profile)


def test_profile_integer_factory_and_mutation_edges() raises:
    for invalid_length in [Int.MIN, -1, 0, 647, 649, Int.MAX]:
        with assert_raises():
            _ = wifi_ldpc_profile(invalid_length, 1, 2)
    for numerator, denominator in [
        (Int.MIN, 2),
        (0, 1),
        (1, 0),
        (4, 5),
        (Int.MAX, 6),
        (5, Int.MAX),
    ]:
        with assert_raises():
            _ = wifi_ldpc_profile(648, numerator, denominator)

    # Prove that the exact fixtures used by every mutation assertion are a
    # successful input to all seven profile-consuming public APIs.
    var canonical = wifi_ldpc_profile(648, 1, 2)
    var canonical_information = List[UInt8](length=324, fill=UInt8(0))
    var canonical_codeword = List[UInt8](length=648, fill=UInt8(0))
    var canonical_llrs = List[Float64](length=648, fill=1.0)
    assert_equal(len(wifi_ldpc_base_shifts(canonical)), 288)
    var canonical_graph = wifi_ldpc_sparse_graph(canonical)
    assert_equal(len(canonical_graph.row_offsets), 325)
    assert_true(wifi_ldpc_syndrome_ok(Span(canonical_codeword), canonical))
    assert_equal(
        wifi_ldpc_encode(Span(canonical_information), canonical),
        canonical_codeword,
    )
    var canonical_decoded = wifi_ldpc_decode(
        Span(canonical_llrs), canonical
    )
    assert_true(canonical_decoded.converged)
    assert_equal(canonical_decoded.codeword_bits, canonical_codeword)
    assert_equal(
        wifi_ldpc_rate_match_block(Span(canonical_information), canonical),
        canonical_codeword,
    )
    assert_equal(
        wifi_ldpc_rate_recover_block(Span(canonical_llrs), canonical),
        canonical_llrs,
    )

    var invalid = wifi_ldpc_profile(648, 1, 2)
    invalid.block_length = Int.MIN
    _require_mutated_profile_rejected(invalid)

    invalid = wifi_ldpc_profile(648, 1, 2)
    invalid.information_length = Int.MIN
    _require_mutated_profile_rejected(invalid)

    invalid = wifi_ldpc_profile(648, 1, 2)
    invalid.parity_length = Int.MAX
    _require_mutated_profile_rejected(invalid)

    invalid = wifi_ldpc_profile(648, 1, 2)
    invalid.lifting_size = 0
    _require_mutated_profile_rejected(invalid)

    invalid = wifi_ldpc_profile(648, 1, 2)
    invalid.block_rows = Int.MAX
    _require_mutated_profile_rejected(invalid)

    invalid = wifi_ldpc_profile(648, 1, 2)
    invalid.rate_numerator = Int.MAX
    _require_mutated_profile_rejected(invalid)

    invalid = wifi_ldpc_profile(648, 1, 2)
    invalid.rate_denominator = Int.MIN
    _require_mutated_profile_rejected(invalid)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
