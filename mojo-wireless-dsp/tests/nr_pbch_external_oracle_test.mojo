"""Independent external E=864 oracle for the NR PBCH decoder.

Vector provenance
-----------------
The complete vector below was generated with the public ``catkira/py3gpp``
implementation at commit
``17b432b30c965ffd350257ee4b1fc4de642c8e37``:

* repository: https://github.com/catkira/py3gpp
* BCH implementation: ``py3gpp/nrBCH.py``
* physical scrambling: ``py3gpp/nrPBCHPRBS.py``
* static E=864 source oracle: the third hard-coded case in
  ``tests/test_nrBCH.py`` at that commit

The pinned generation configuration and transformation were:

```
trblk = numpy.zeros(24, dtype=int)
rate_matched = nrBCH(trblk, sfn=10, hrf=1, lssb=8,
                     idxoffset=0, ncellid=321)
physical = bitwise_xor(rate_matched, nrPBCHPRBS(321, v=6, n=864))
packed = numpy.packbits(physical, bitorder="big")
```

No production encoder from this repository participates in the vector or its
expectations.  The all-zero transport block makes py3gpp's leading
BCCH-BCH-Message choice-bit convention and this package's 24-bit MIB view
unambiguous.  Bits are packed most-significant-bit first, eight per byte.

External checkpoints:

* 864 bits, 418 one bits;
* first 64 physical bits:
  ``0110110011111011000110010111110011100110101110001110100111101100``;
* SHA-256 of the 108 packed bytes:
  ``61d5e736e9b241de83cbb75bb8ae7ad658c65c7b6697d5133f8929f01331eec3``;
* FNV-1a-64 of the packed bytes: ``0x3f22a0d8b33dfb27``.

The decoder LLR convention is positive for bit zero and negative for bit one.
The test uses a hard magnitude of 32 and a bounded deterministic perturbation
of at most 0.125, leaving a minimum sign margin of 31.875.  Since every
asserted output is discrete, the result tolerance is exact.
"""

from std.collections import Span
from std.testing import assert_equal, assert_true, TestSuite
from wireless_dsp.wireless.nr.pbch import nr_pbch_decode, nr_pbch_encode


def _external_physical_packed() -> List[UInt8]:
    # Complete E=864 vector, packed MSB-first (108 bytes).
    return [
        108, 251, 25, 124, 230, 184, 233, 236, 184, 145, 241, 152,
        88, 207, 231, 123, 133, 209, 140, 148, 38, 180, 3, 73,
        75, 17, 216, 109, 160, 45, 139, 161, 197, 146, 173, 92,
        66, 234, 34, 46, 8, 188, 24, 27, 166, 92, 25, 82,
        224, 59, 227, 128, 88, 196, 169, 170, 221, 86, 58, 198,
        183, 47, 133, 19, 160, 120, 214, 45, 145, 37, 38, 46,
        166, 254, 47, 200, 125, 16, 2, 21, 147, 171, 176, 161,
        111, 29, 120, 135, 116, 200, 25, 176, 71, 101, 213, 60,
        93, 149, 115, 237, 15, 75, 190, 16, 118, 172, 168, 242,
    ]


def _unpack_msb_first(packed: Span[UInt8, ...]) -> List[UInt8]:
    var bits = List[UInt8](capacity=8 * len(packed))
    for byte_index in range(len(packed)):
        var value = packed[byte_index]
        for bit_index in range(8):
            bits.append(
                UInt8(
                    (value >> UInt8(7 - bit_index)) & UInt8(1)
                )
            )
    return bits^


def _packed_fnv1a64(packed: Span[UInt8, ...]) -> UInt64:
    var result = UInt64(14695981039346656037)
    for index in range(len(packed)):
        result ^= UInt64(packed[index])
        result *= UInt64(1099511628211)
    return result


def _expected_information() -> List[UInt8]:
    # py3gpp encoder checkpoint after CRC24C attachment and before the Polar
    # input interleaver.  This is exactly the decoder's recovered K=56 block.
    return [
        1, 1, 1, 0, 0, 0, 0, 0,
        1, 1, 1, 0, 0, 1, 0, 1,
        0, 1, 0, 0, 1, 1, 1, 1,
        1, 0, 1, 1, 0, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1,
        1, 0, 1, 1, 1, 1, 0, 1,
        0, 0, 0, 1, 1, 1, 0, 1,
    ]


def test_nr_pbch_decode_py3gpp_external_e864_oracle() raises:
    var packed = _external_physical_packed()
    assert_equal(len(packed), 108)
    assert_equal(_packed_fnv1a64(Span(packed)), UInt64(0x3F22A0D8B33DFB27))

    var physical_bits = _unpack_msb_first(Span(packed))
    assert_equal(len(physical_bits), 864)
    var one_count = 0
    var prefix = UInt64(0)
    for index in range(len(physical_bits)):
        one_count += Int(physical_bits[index])
        if index < 64:
            prefix = (prefix << UInt64(1)) | UInt64(physical_bits[index])
    assert_equal(one_count, 418)
    assert_equal(prefix, UInt64(0x6CFB197CE6B8E9EC))

    # The same complete external vector independently fixes every encoder
    # stage through the final TS 38.211 physical scrambling boundary.
    var mib = List[UInt8](length=24, fill=UInt8(0))
    var encoded = nr_pbch_encode(Span(mib), 321, 10, 1, 6, 8)
    assert_equal(encoded.physical_channel_bits, physical_bits)

    # A fixed hard-decision magnitude with a small deterministic perturbation
    # checks amplitude tolerance while preserving an explicit 31.875 margin.
    var llrs = List[Float64](capacity=864)
    for index in range(864):
        var perturbation = Float64((index % 5) - 2) * 0.0625
        var magnitude = 32.0 + perturbation
        assert_true(magnitude >= 31.875 and magnitude <= 32.125)
        llrs.append(
            magnitude if physical_bits[index] == 0 else -magnitude
        )

    var decoded = nr_pbch_decode(Span(llrs), 321, 6, 8)
    assert_true(decoded.crc_ok)
    assert_equal(decoded.mib_bits, List[UInt8](length=24, fill=UInt8(0)))
    assert_equal(decoded.payload, [
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        1, 0, 1, 0, 1, 0, 0, 0,
    ])
    assert_equal(decoded.decoded_information, _expected_information())
    assert_equal(decoded.system_frame_number, 10)
    assert_equal(decoded.half_frame, 1)
    assert_equal(decoded.ssb_index, 6)
    assert_equal(decoded.k_ssb_msb, 0)

    # Hard-LLR scale invariance at a much larger finite magnitude guards the
    # upper practical input boundary without relying on floating-point Inf.
    for index in range(864):
        llrs[index] = 1.0e6 if physical_bits[index] == 0 else -1.0e6
    var high_magnitude = nr_pbch_decode(Span(llrs), 321, 6, 8)
    assert_true(high_magnitude.crc_ok)
    assert_equal(high_magnitude.decoded_information, _expected_information())
    assert_equal(high_magnitude.payload, decoded.payload)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
