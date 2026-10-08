"""Standards-oriented NR PRACH construction and detection.

This module implements the sequence-generation part of 3GPP TS 38.211
V18.9.0 clause 6.3.3.1: preamble-format parameters, all logical-root mappings,
the N_CS tables, unrestricted and restricted-set cyclic shifts, and allocation
of the 64 preambles across consecutive logical roots. The V18.8.0/V18.9.0
table transcriptions were rechecked unchanged against this default baseline.
The normalized waveform helper keeps CP and
repetition boundaries visible at sequence-sample resolution; the exact
N_u/N_CP values in units of kappa remain available in ``NRPRACHFormat`` for
a radio-rate resampler/OFDM front end.

The very large occasion tables in 38.211 clause 6.3.3.2 are deliberately
layered. ``nr_prach_representative_occasion`` contains exact representative
rows from each FR1/FR2 table and advertises that scope in its name instead of
silently claiming all 256+ configuration indices.
"""

from std.collections import Span
from std.math import cos, isfinite, sin
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import dft_reference, normalized_correlation_at
from wireless_dsp.testing.checkpoint import (
    CheckpointMetadata,
    checkpoint_metadata_1d,
)


comptime _PI = 3.1415926535897932384626433832795


comptime PRACH_SET_UNRESTRICTED = 0
comptime PRACH_SET_RESTRICTED_A = 1
comptime PRACH_SET_RESTRICTED_B = 2

comptime PRACH_FORMAT_0 = 0
comptime PRACH_FORMAT_1 = 1
comptime PRACH_FORMAT_2 = 2
comptime PRACH_FORMAT_3 = 3
comptime PRACH_FORMAT_A1 = 4
comptime PRACH_FORMAT_A2 = 5
comptime PRACH_FORMAT_A3 = 6
comptime PRACH_FORMAT_B1 = 7
comptime PRACH_FORMAT_B2 = 8
comptime PRACH_FORMAT_B3 = 9
comptime PRACH_FORMAT_B4 = 10
comptime PRACH_FORMAT_C0 = 11
comptime PRACH_FORMAT_C2 = 12

comptime PRACH_REGION_FR1 = 1
comptime PRACH_REGION_FR2 = 2
comptime PRACH_SPECTRUM_PAIRED = 0
comptime PRACH_SPECTRUM_UNPAIRED = 1


def _validate_finite_prach_samples(
    values: Span[Complex64, ...]
) raises:
    for index in range(len(values)):
        if not isfinite(values[index].re) or not isfinite(values[index].im):
            raise Error("PRACH samples must be finite")


def _checked_prach_product(lhs: Int, rhs: Int) raises -> Int:
    if lhs < 0 or rhs < 0 or (rhs != 0 and lhs > Int.MAX // rhs):
        raise Error("PRACH dimensions overflow Int")
    return lhs * rhs


struct NRPRACHFormat(ImplicitlyCopyable):
    """One row of TS 38.211 Tables 6.3.3.1-1/2.

    ``useful_samples_kappa`` and ``cp_samples_kappa`` are expressed in the
    standard basic time unit kappa.  They can be fractional only because the
    short-format tables multiply both by ``2**(-mu)``.
    """

    var format: Int
    var sequence_length: Int
    var numerology: Int
    var subcarrier_spacing_hz: Int
    var useful_samples_kappa: Float64
    var cp_samples_kappa: Float64
    var repetitions: Int
    var supports_restricted_sets: Bool

    def __init__(
        out self,
        format: Int,
        sequence_length: Int,
        numerology: Int,
        subcarrier_spacing_hz: Int,
        useful_samples_kappa: Float64,
        cp_samples_kappa: Float64,
        repetitions: Int,
        supports_restricted_sets: Bool,
    ):
        self.format = format
        self.sequence_length = sequence_length
        self.numerology = numerology
        self.subcarrier_spacing_hz = subcarrier_spacing_hz
        self.useful_samples_kappa = useful_samples_kappa
        self.cp_samples_kappa = cp_samples_kappa
        self.repetitions = repetitions
        self.supports_restricted_sets = supports_restricted_sets


def _power_of_two(exponent: Int) -> Int:
    var value = 1
    for _ in range(exponent):
        value *= 2
    return value


def nr_prach_format_parameters(
    format: Int, *, numerology: Int = 0, sequence_length: Int = 139
) raises -> NRPRACHFormat:
    """Return exact preamble timing parameters from Tables 6.3.3.1-1/2.

    Rel-18 introduced the 571/1151 alternatives for short formats.  Their
    allowed numerologies are checked here: 139 supports mu={0,1,2,3,5,6},
    1151 supports mu={0,3}, and 571 supports mu={1,3,5}.
    """
    if format >= PRACH_FORMAT_0 and format <= PRACH_FORMAT_3:
        if sequence_length != 839:
            raise Error("long PRACH formats require L_RA=839")
        if format == PRACH_FORMAT_0:
            return NRPRACHFormat(format, 839, -1, 1250, 24576.0, 3168.0, 1, True)
        if format == PRACH_FORMAT_1:
            return NRPRACHFormat(format, 839, -1, 1250, 49152.0, 21024.0, 2, True)
        if format == PRACH_FORMAT_2:
            return NRPRACHFormat(format, 839, -1, 1250, 98304.0, 4688.0, 4, True)
        return NRPRACHFormat(format, 839, -1, 5000, 24576.0, 3168.0, 4, True)

    if format < PRACH_FORMAT_A1 or format > PRACH_FORMAT_C2:
        raise Error("unknown NR PRACH preamble format")
    if numerology < 0 or numerology > 6 or numerology == 4:
        raise Error("short PRACH numerology must be one of 0,1,2,3,5,6")
    if sequence_length == 139:
        pass
    elif sequence_length == 1151:
        if numerology != 0 and numerology != 3:
            raise Error("L_RA=1151 is specified only for mu=0 or mu=3")
    elif sequence_length == 571:
        if numerology != 1 and numerology != 3 and numerology != 5:
            raise Error("L_RA=571 is specified only for mu=1,3,5")
    else:
        raise Error("short PRACH L_RA must be 139, 571, or 1151")

    var repetitions: Int
    var cp_base: Int
    if format == PRACH_FORMAT_A1:
        repetitions = 2
        cp_base = 288
    elif format == PRACH_FORMAT_A2:
        repetitions = 4
        cp_base = 576
    elif format == PRACH_FORMAT_A3:
        repetitions = 6
        cp_base = 864
    elif format == PRACH_FORMAT_B1:
        repetitions = 2
        cp_base = 216
    elif format == PRACH_FORMAT_B2:
        repetitions = 4
        cp_base = 360
    elif format == PRACH_FORMAT_B3:
        repetitions = 6
        cp_base = 504
    elif format == PRACH_FORMAT_B4:
        repetitions = 12
        cp_base = 936
    elif format == PRACH_FORMAT_C0:
        repetitions = 1
        cp_base = 1240
    else:
        repetitions = 4
        cp_base = 2048
    var scale = Float64(_power_of_two(numerology))
    return NRPRACHFormat(
        format,
        sequence_length,
        numerology,
        15000 * _power_of_two(numerology),
        Float64(repetitions * 2048) / scale,
        Float64(cp_base) / scale,
        repetitions,
        False,
    )


def _logical_roots_839() -> List[Int]:
    """TS 38.211 Table 6.3.3.1-3, indexed by logical root index."""
    return [
        129, 710, 140, 699, 120, 719, 210, 629, 168, 671, 84, 755, 105, 734, 93, 746,
        70, 769, 60, 779, 2, 837, 1, 838, 56, 783, 112, 727, 148, 691, 80, 759,
        42, 797, 40, 799, 35, 804, 73, 766, 146, 693, 31, 808, 28, 811, 30, 809,
        27, 812, 29, 810, 24, 815, 48, 791, 68, 771, 74, 765, 178, 661, 136, 703,
        86, 753, 78, 761, 43, 796, 39, 800, 20, 819, 21, 818, 95, 744, 202, 637,
        190, 649, 181, 658, 137, 702, 125, 714, 151, 688, 217, 622, 128, 711, 142, 697,
        122, 717, 203, 636, 118, 721, 110, 729, 89, 750, 103, 736, 61, 778, 55, 784,
        15, 824, 14, 825, 12, 827, 23, 816, 34, 805, 37, 802, 46, 793, 207, 632,
        179, 660, 145, 694, 130, 709, 223, 616, 228, 611, 227, 612, 132, 707, 133, 706,
        143, 696, 135, 704, 161, 678, 201, 638, 173, 666, 106, 733, 83, 756, 91, 748,
        66, 773, 53, 786, 10, 829, 9, 830, 7, 832, 8, 831, 16, 823, 47, 792,
        64, 775, 57, 782, 104, 735, 101, 738, 108, 731, 208, 631, 184, 655, 197, 642,
        191, 648, 121, 718, 141, 698, 149, 690, 216, 623, 218, 621, 152, 687, 144, 695,
        134, 705, 138, 701, 199, 640, 162, 677, 176, 663, 119, 720, 158, 681, 164, 675,
        174, 665, 171, 668, 170, 669, 87, 752, 169, 670, 88, 751, 107, 732, 81, 758,
        82, 757, 100, 739, 98, 741, 71, 768, 59, 780, 65, 774, 50, 789, 49, 790,
        26, 813, 17, 822, 13, 826, 6, 833, 5, 834, 33, 806, 51, 788, 75, 764,
        99, 740, 96, 743, 97, 742, 166, 673, 172, 667, 175, 664, 187, 652, 163, 676,
        185, 654, 200, 639, 114, 725, 189, 650, 115, 724, 194, 645, 195, 644, 192, 647,
        182, 657, 157, 682, 156, 683, 211, 628, 154, 685, 123, 716, 139, 700, 212, 627,
        153, 686, 213, 626, 215, 624, 150, 689, 225, 614, 224, 615, 221, 618, 220, 619,
        127, 712, 147, 692, 124, 715, 193, 646, 205, 634, 206, 633, 116, 723, 160, 679,
        186, 653, 167, 672, 79, 760, 85, 754, 77, 762, 92, 747, 58, 781, 62, 777,
        69, 770, 54, 785, 36, 803, 32, 807, 25, 814, 18, 821, 11, 828, 4, 835,
        3, 836, 19, 820, 22, 817, 41, 798, 38, 801, 44, 795, 52, 787, 45, 794,
        63, 776, 67, 772, 72, 767, 76, 763, 94, 745, 102, 737, 90, 749, 109, 730,
        165, 674, 111, 728, 209, 630, 204, 635, 117, 722, 188, 651, 159, 680, 198, 641,
        113, 726, 183, 656, 180, 659, 177, 662, 196, 643, 155, 684, 214, 625, 126, 713,
        131, 708, 219, 620, 222, 617, 226, 613, 230, 609, 232, 607, 262, 577, 252, 587,
        418, 421, 416, 423, 413, 426, 411, 428, 376, 463, 395, 444, 283, 556, 285, 554,
        379, 460, 390, 449, 363, 476, 384, 455, 388, 451, 386, 453, 361, 478, 387, 452,
        360, 479, 310, 529, 354, 485, 328, 511, 315, 524, 337, 502, 349, 490, 335, 504,
        324, 515, 323, 516, 320, 519, 334, 505, 359, 480, 295, 544, 385, 454, 292, 547,
        291, 548, 381, 458, 399, 440, 380, 459, 397, 442, 369, 470, 377, 462, 410, 429,
        407, 432, 281, 558, 414, 425, 247, 592, 277, 562, 271, 568, 272, 567, 264, 575,
        259, 580, 237, 602, 239, 600, 244, 595, 243, 596, 275, 564, 278, 561, 250, 589,
        246, 593, 417, 422, 248, 591, 394, 445, 393, 446, 370, 469, 365, 474, 300, 539,
        299, 540, 364, 475, 362, 477, 298, 541, 312, 527, 313, 526, 314, 525, 353, 486,
        352, 487, 343, 496, 327, 512, 350, 489, 326, 513, 319, 520, 332, 507, 333, 506,
        348, 491, 347, 492, 322, 517, 330, 509, 338, 501, 341, 498, 340, 499, 342, 497,
        301, 538, 366, 473, 401, 438, 371, 468, 408, 431, 375, 464, 249, 590, 269, 570,
        238, 601, 234, 605, 257, 582, 273, 566, 255, 584, 254, 585, 245, 594, 251, 588,
        412, 427, 372, 467, 282, 557, 403, 436, 396, 443, 392, 447, 391, 448, 382, 457,
        389, 450, 294, 545, 297, 542, 311, 528, 344, 495, 345, 494, 318, 521, 331, 508,
        325, 514, 321, 518, 346, 493, 339, 500, 351, 488, 306, 533, 289, 550, 400, 439,
        378, 461, 374, 465, 415, 424, 270, 569, 241, 598, 231, 608, 260, 579, 268, 571,
        276, 563, 409, 430, 398, 441, 290, 549, 304, 535, 308, 531, 358, 481, 316, 523,
        293, 546, 288, 551, 284, 555, 368, 471, 253, 586, 256, 583, 263, 576, 242, 597,
        274, 565, 402, 437, 383, 456, 357, 482, 329, 510, 317, 522, 307, 532, 286, 553,
        287, 552, 266, 573, 261, 578, 236, 603, 303, 536, 356, 483, 355, 484, 405, 434,
        404, 435, 406, 433, 235, 604, 267, 572, 302, 537, 309, 530, 265, 574, 233, 606,
        367, 472, 296, 543, 336, 503, 305, 534, 373, 466, 280, 559, 279, 560, 419, 420,
        240, 599, 258, 581, 229, 610,
    ]


def nr_prach_logical_root_count(sequence_length: Int) raises -> Int:
    if (
        sequence_length != 139
        and sequence_length != 571
        and sequence_length != 839
        and sequence_length != 1151
    ):
        raise Error("unsupported PRACH root-sequence length")
    return sequence_length - 1


def nr_prach_logical_root_u(
    logical_index: Int, sequence_length: Int
) raises -> Int:
    """Map every valid logical root index to u (Tables 6.3.3.1-3..4B)."""
    var count = nr_prach_logical_root_count(sequence_length)
    if logical_index < 0 or logical_index >= count:
        raise Error("logical PRACH root index is out of range")
    if sequence_length == 839:
        var roots = _logical_roots_839()
        return roots[logical_index]
    # Tables 6.3.3.1-4/4A/4B alternate 1,L-1,2,L-2,... exactly.
    if logical_index % 2 == 0:
        return logical_index // 2 + 1
    return sequence_length - (logical_index + 1) // 2


def _greatest_common_divisor(lhs: Int, rhs: Int) -> Int:
    var a = abs(lhs)
    var b = abs(rhs)
    while b != 0:
        var remainder = a % b
        a = b
        b = remainder
    return a


def nr_prach_root_sequence_standard(
    root_u: Int, sequence_length: Int
) raises -> List[Complex64]:
    """Generate x_u for every V18.9.0 L_RA in 38.211 clause 6.3.3.1."""
    _ = nr_prach_logical_root_count(sequence_length)
    if (
        root_u < 1
        or root_u >= sequence_length
        or _greatest_common_divisor(root_u, sequence_length) != 1
    ):
        raise Error("PRACH root must be coprime and inside L_RA")
    var result = List[Complex64](capacity=sequence_length)
    for n in range(sequence_length):
        var angle = (
            -_PI * Float64(root_u * n * (n + 1))
            / Float64(sequence_length)
        )
        result.append(Complex64(cos(angle), sin(angle)))
    return result^


def nr_prach_sequence_standard(
    root_u: Int, sequence_length: Int, cyclic_shift: Int
) raises -> List[Complex64]:
    """Generate x_u,v(n)=x_u((n+C_v) mod L_RA) for all four lengths."""
    if cyclic_shift < 0 or cyclic_shift >= sequence_length:
        raise Error("PRACH cyclic shift is outside L_RA")
    var root = nr_prach_root_sequence_standard(root_u, sequence_length)
    var result = List[Complex64](capacity=sequence_length)
    for n in range(sequence_length):
        result.append(root[(n + cyclic_shift) % sequence_length])
    return result^


def nr_prach_n_cs(
    zero_correlation_zone_config: Int,
    sequence_length: Int,
    subcarrier_spacing_hz: Int,
    set_type: Int = PRACH_SET_UNRESTRICTED,
) raises -> Int:
    """Lookup N_CS from TS 38.211 Tables 6.3.3.1-5 through 6.3.3.1-7."""
    if zero_correlation_zone_config < 0 or zero_correlation_zone_config > 15:
        raise Error("zeroCorrelationZoneConfig must be in [0,15]")
    if (
        set_type != PRACH_SET_UNRESTRICTED
        and set_type != PRACH_SET_RESTRICTED_A
        and set_type != PRACH_SET_RESTRICTED_B
    ):
        raise Error("unknown PRACH restricted-set type")

    var values: List[Int]
    if sequence_length == 839:
        if subcarrier_spacing_hz == 1250:
            if set_type == PRACH_SET_UNRESTRICTED:
                values = [0,13,15,18,22,26,32,38,46,59,76,93,119,167,279,419]
            elif set_type == PRACH_SET_RESTRICTED_A:
                values = [15,18,22,26,32,38,46,55,68,82,100,128,158,202,237,-1]
            else:
                values = [15,18,22,26,32,38,46,55,68,82,100,118,137,-1,-1,-1]
        elif subcarrier_spacing_hz == 5000:
            if set_type == PRACH_SET_UNRESTRICTED:
                values = [0,13,26,33,38,41,49,55,64,76,93,119,139,209,279,419]
            elif set_type == PRACH_SET_RESTRICTED_A:
                values = [36,57,72,81,89,94,103,112,121,132,137,152,173,195,216,237]
            else:
                values = [36,57,60,63,65,68,71,77,81,85,97,109,122,137,-1,-1]
        else:
            raise Error("L_RA=839 supports PRACH SCS 1.25 or 5 kHz")
    else:
        if set_type != PRACH_SET_UNRESTRICTED:
            raise Error("short PRACH formats do not support restricted sets")
        if sequence_length == 139:
            values = [0,2,4,6,8,10,12,13,15,17,19,23,27,34,46,69]
        elif sequence_length == 571:
            values = [0,8,10,12,15,17,21,25,31,40,51,63,81,114,190,285]
        elif sequence_length == 1151:
            values = [0,17,21,25,30,35,44,52,63,82,104,127,164,230,383,575]
        else:
            raise Error("unsupported short PRACH sequence length")
        var valid_scs: Bool
        if sequence_length == 139:
            valid_scs = subcarrier_spacing_hz in (15000,30000,60000,120000,480000,960000)
        elif sequence_length == 571:
            valid_scs = subcarrier_spacing_hz in (30000,120000,480000)
        else:
            valid_scs = subcarrier_spacing_hz == 15000 or subcarrier_spacing_hz == 120000
        if not valid_scs:
            raise Error("unsupported SCS for this short PRACH sequence length")

    var result = values[zero_correlation_zone_config]
    if result < 0:
        raise Error("zeroCorrelationZoneConfig is reserved for this set type")
    return result


def _modular_inverse(value: Int, modulus: Int) raises -> Int:
    for candidate in range(1, modulus):
        if (candidate * value) % modulus == 1:
            return candidate
    raise Error("PRACH root has no modular inverse")


def nr_prach_d_u(root_u: Int, sequence_length: Int) raises -> Int:
    if root_u < 1 or root_u >= sequence_length:
        raise Error("PRACH root u is out of range")
    var q = _modular_inverse(root_u, sequence_length)
    return q if 2 * q < sequence_length else sequence_length - q


struct NRPRACHRestrictedParameters(ImplicitlyCopyable):
    """Intermediate integer parameters in 38.211 restricted-set equations."""

    var valid: Bool
    var d_u: Int
    var n_shift: Int
    var d_start: Int
    var n_group: Int
    var n_shift_bar: Int
    var d_start_double_bar: Int
    var d_start_triple_bar: Int
    var n_shift_double_bar: Int
    var n_shift_triple_bar: Int

    def __init__(
        out self,
        valid: Bool,
        d_u: Int,
        n_shift: Int = 0,
        d_start: Int = 0,
        n_group: Int = 0,
        n_shift_bar: Int = 0,
        d_start_double_bar: Int = 0,
        d_start_triple_bar: Int = 0,
        n_shift_double_bar: Int = 0,
        n_shift_triple_bar: Int = 0,
    ):
        self.valid = valid
        self.d_u = d_u
        self.n_shift = n_shift
        self.d_start = d_start
        self.n_group = n_group
        self.n_shift_bar = n_shift_bar
        self.d_start_double_bar = d_start_double_bar
        self.d_start_triple_bar = d_start_triple_bar
        self.n_shift_double_bar = n_shift_double_bar
        self.n_shift_triple_bar = n_shift_triple_bar

    @always_inline
    def count(self) -> Int:
        if not self.valid:
            return 0
        return (
            self.n_shift * self.n_group
            + self.n_shift_bar
            + self.n_shift_double_bar
            + self.n_shift_triple_bar
        )


@always_inline
def _max_zero(value: Int) -> Int:
    return value if value > 0 else 0


@always_inline
def _min_int(lhs: Int, rhs: Int) -> Int:
    return lhs if lhs < rhs else rhs


def nr_prach_restricted_parameters(
    root_u: Int, sequence_length: Int, n_cs: Int, set_type: Int
) raises -> NRPRACHRestrictedParameters:
    """Evaluate every type-A/type-B d_u branch in TS 38.211 6.3.3.1."""
    if sequence_length != 839:
        raise Error("restricted PRACH sets are supported only for L_RA=839")
    if n_cs <= 0 or n_cs >= sequence_length:
        raise Error("restricted PRACH N_CS must be in (0,L_RA)")
    if set_type != PRACH_SET_RESTRICTED_A and set_type != PRACH_SET_RESTRICTED_B:
        raise Error("restricted parameters require set type A or B")
    var d_u = nr_prach_d_u(root_u, sequence_length)
    var n_shift: Int
    var d_start: Int
    var n_group: Int
    var n_shift_bar: Int
    var d_start_double_bar = 0
    var d_start_triple_bar = 0
    var n_shift_double_bar = 0
    var n_shift_triple_bar = 0

    if set_type == PRACH_SET_RESTRICTED_A:
        if n_cs <= d_u and 3 * d_u < sequence_length:
            n_shift = d_u // n_cs
            d_start = 2 * d_u + n_shift * n_cs
            n_group = sequence_length // d_start
            n_shift_bar = _max_zero(
                (sequence_length - 2 * d_u - n_group * d_start) // n_cs
            )
        elif 3 * d_u >= sequence_length and 2 * d_u <= sequence_length - n_cs:
            n_shift = (sequence_length - 2 * d_u) // n_cs
            d_start = sequence_length - 2 * d_u + n_shift * n_cs
            n_group = d_u // d_start
            n_shift_bar = _min_int(
                _max_zero((d_u - n_group * d_start) // n_cs), n_shift
            )
        else:
            return NRPRACHRestrictedParameters(False, d_u)
    else:
        if n_cs <= d_u and 5 * d_u < sequence_length:
            n_shift = d_u // n_cs
            d_start = 4 * d_u + n_shift * n_cs
            n_group = sequence_length // d_start
            n_shift_bar = _max_zero(
                (sequence_length - 4 * d_u - n_group * d_start) // n_cs
            )
        elif 5 * d_u >= sequence_length and 4 * d_u <= sequence_length - n_cs:
            n_shift = (sequence_length - 4 * d_u) // n_cs
            d_start = sequence_length - 4 * d_u + n_shift * n_cs
            n_group = d_u // d_start
            n_shift_bar = _min_int(
                _max_zero((d_u - n_group * d_start) // n_cs), n_shift
            )
        elif 4 * d_u >= sequence_length + n_cs and 7 * d_u < 2 * sequence_length:
            n_shift = (4 * d_u - sequence_length) // n_cs
            d_start = 4 * d_u - sequence_length + n_shift * n_cs
            n_group = d_u // d_start
            n_shift_bar = _max_zero(
                (sequence_length - 3 * d_u - n_group * d_start) // n_cs
            )
            d_start_double_bar = (
                sequence_length - 3 * d_u + n_group * d_start + n_shift_bar * n_cs
            )
            d_start_triple_bar = (
                sequence_length - 2 * d_u + n_group * d_start + n_shift_bar * n_cs
            )
            n_shift_double_bar = _min_int(
                d_u - n_group * d_start,
                4 * d_u - sequence_length - n_shift_bar * n_cs,
            ) // n_cs
            n_shift_triple_bar = (
                (
                    (1 - _min_int(1, n_shift_bar)) * (d_u - n_group * d_start)
                    + _min_int(1, n_shift_bar)
                    * (4 * d_u - sequence_length - n_shift_bar * n_cs)
                )
                // n_cs
                - n_shift_double_bar
            )
        elif 7 * d_u >= 2 * sequence_length and 3 * d_u <= sequence_length - n_cs:
            n_shift = (sequence_length - 3 * d_u) // n_cs
            d_start = sequence_length - 3 * d_u + n_shift * n_cs
            n_group = d_u // d_start
            n_shift_bar = _max_zero(
                (4 * d_u - sequence_length - n_group * d_start) // n_cs
            )
            d_start_double_bar = d_u + n_group * d_start + n_shift_bar * n_cs
            n_shift_double_bar = _min_int(
                d_u - n_group * d_start,
                sequence_length - 3 * d_u - n_shift_bar * n_cs,
            ) // n_cs
        elif 3 * d_u >= sequence_length + n_cs and 5 * d_u < 2 * sequence_length:
            n_shift = (3 * d_u - sequence_length) // n_cs
            d_start = 3 * d_u - sequence_length + n_shift * n_cs
            n_group = d_u // d_start
            n_shift_bar = _max_zero(
                (sequence_length - 2 * d_u - n_group * d_start) // n_cs
            )
        elif 5 * d_u >= 2 * sequence_length and 2 * d_u <= sequence_length - n_cs:
            n_shift = (sequence_length - 2 * d_u) // n_cs
            d_start = 2 * (sequence_length - 2 * d_u) + n_shift * n_cs
            n_group = (sequence_length - d_u) // d_start
            n_shift_bar = _max_zero(
                (3 * d_u - sequence_length - n_group * d_start) // n_cs
            )
        else:
            return NRPRACHRestrictedParameters(False, d_u)

    if n_shift <= 0 or d_start <= 0:
        return NRPRACHRestrictedParameters(False, d_u)
    return NRPRACHRestrictedParameters(
        True,
        d_u,
        n_shift,
        d_start,
        n_group,
        n_shift_bar,
        d_start_double_bar,
        d_start_triple_bar,
        n_shift_double_bar,
        n_shift_triple_bar,
    )


def nr_prach_cyclic_shifts(
    root_u: Int, sequence_length: Int, n_cs: Int, set_type: Int
) raises -> List[Int]:
    """Return all standard cyclic shifts offered by one root, in v order."""
    if set_type == PRACH_SET_UNRESTRICTED:
        if n_cs < 0 or n_cs >= sequence_length:
            raise Error("unrestricted PRACH N_CS is outside the sequence")
        if n_cs == 0:
            return [0]
        var result = List[Int](capacity=sequence_length // n_cs)
        for v in range(sequence_length // n_cs):
            result.append(v * n_cs)
        return result^
    var parameters = nr_prach_restricted_parameters(
        root_u, sequence_length, n_cs, set_type
    )
    if not parameters.valid:
        return List[Int]()
    var result = List[Int](capacity=parameters.count())
    var w = parameters.n_shift * parameters.n_group + parameters.n_shift_bar
    for v in range(w):
        result.append(
            parameters.d_start * (v // parameters.n_shift)
            + (v % parameters.n_shift) * n_cs
        )
    for v in range(parameters.n_shift_double_bar):
        result.append(parameters.d_start_double_bar + v * n_cs)
    for v in range(parameters.n_shift_triple_bar):
        result.append(parameters.d_start_triple_bar + v * n_cs)
    return result^


struct NRPRACHPreamble(ImplicitlyCopyable):
    var preamble_index: Int
    var logical_root_index: Int
    var root_u: Int
    var cyclic_shift: Int

    def __init__(
        out self,
        preamble_index: Int,
        logical_root_index: Int,
        root_u: Int,
        cyclic_shift: Int,
    ):
        self.preamble_index = preamble_index
        self.logical_root_index = logical_root_index
        self.root_u = root_u
        self.cyclic_shift = cyclic_shift


def nr_prach_allocate_preambles(
    starting_logical_root_index: Int,
    sequence_length: Int,
    n_cs: Int,
    set_type: Int,
    preamble_count: Int = 64,
) raises -> List[NRPRACHPreamble]:
    """Allocate up to the standard 64 preambles, crossing/wrapping roots."""
    var root_count = nr_prach_logical_root_count(sequence_length)
    if starting_logical_root_index < 0 or starting_logical_root_index >= root_count:
        raise Error("starting logical PRACH root index is out of range")
    if preamble_count < 1 or preamble_count > 64:
        raise Error("a PRACH occasion contains between 1 and 64 preambles")
    var result = List[NRPRACHPreamble](capacity=preamble_count)
    var root_offset = 0
    while len(result) < preamble_count and root_offset < root_count:
        var logical_index = (starting_logical_root_index + root_offset) % root_count
        var root_u = nr_prach_logical_root_u(logical_index, sequence_length)
        var shifts = nr_prach_cyclic_shifts(root_u, sequence_length, n_cs, set_type)
        for shift in shifts:
            if len(result) == preamble_count:
                break
            result.append(
                NRPRACHPreamble(len(result), logical_index, root_u, shift)
            )
        root_offset += 1
    if len(result) != preamble_count:
        raise Error("configured roots cannot provide the requested PRACH preambles")
    return result^


def nr_prach_preamble_sequence(
    allocation: NRPRACHPreamble, sequence_length: Int
) raises -> List[Complex64]:
    return nr_prach_sequence_standard(
        allocation.root_u, sequence_length, allocation.cyclic_shift
    )


def nr_prach_frequency_sequence(
    time_sequence: Span[Complex64, ...]
) raises -> List[Complex64]:
    """Generate y_u,v(n), the unnormalised DFT specified by 38.211 6.3.3.1."""
    if len(time_sequence) not in (139, 571, 839, 1151):
        raise Error("invalid PRACH time-sequence length")
    _validate_finite_prach_samples(time_sequence)
    var result = dft_reference(time_sequence)
    _validate_finite_prach_samples(Span(result))
    return result^


def nr_prach_normalized_cp_samples(
    parameters: NRPRACHFormat
) raises -> Int:
    """CP length on the readable one-sample-per-ZC-chip waveform grid."""
    if (
        parameters.sequence_length not in (139, 571, 839, 1151)
        or parameters.repetitions < 1
        or not isfinite(parameters.useful_samples_kappa)
        or parameters.useful_samples_kappa <= 0.0
        or not isfinite(parameters.cp_samples_kappa)
        or parameters.cp_samples_kappa < 0.0
    ):
        raise Error("invalid normalized PRACH format parameters")
    var one_repetition_kappa = (
        parameters.useful_samples_kappa / Float64(parameters.repetitions)
    )
    if not isfinite(one_repetition_kappa) or one_repetition_kappa <= 0.0:
        raise Error("invalid normalized PRACH useful duration")
    var cp_samples = (
        parameters.cp_samples_kappa / one_repetition_kappa
        * Float64(parameters.sequence_length)
    )
    if (
        not isfinite(cp_samples)
        or cp_samples < 0.0
        or cp_samples > Float64(Int.MAX - 1)
    ):
        raise Error("normalized PRACH CP length overflows Int")
    return Int(cp_samples + 0.5)


def nr_prach_normalized_waveform(
    sequence: Span[Complex64, ...], parameters: NRPRACHFormat
) raises -> List[Complex64]:
    """Prepend CP and repeat x_u,v at one sample per ZC chip.

    This deliberately readable representation preserves the exact CP/useful
    time ratio and repetition count.  It is not a substitute for the final
    radio-rate frequency mapping in clause 6.3.3.2.
    """
    if len(sequence) != parameters.sequence_length:
        raise Error("PRACH sequence and format lengths do not match")
    _validate_finite_prach_samples(sequence)
    var cp = nr_prach_normalized_cp_samples(parameters)
    var useful = _checked_prach_product(
        parameters.repetitions, parameters.sequence_length
    )
    if cp > Int.MAX - useful:
        raise Error("normalized PRACH waveform length overflows Int")
    var result = List[Complex64](
        capacity=cp + useful
    )
    for i in range(cp):
        var source = (parameters.sequence_length - cp + i) % parameters.sequence_length
        if source < 0:
            source += parameters.sequence_length
        result.append(sequence[source])
    for _ in range(parameters.repetitions):
        for i in range(len(sequence)):
            result.append(sequence[i])
    return result^


struct NRPRACHMultiRootDetection(ImplicitlyCopyable):
    var preamble_index: Int
    var logical_root_index: Int
    var root_u: Int
    var cyclic_shift: Int
    var metric: Float64

    def __init__(
        out self,
        preamble_index: Int,
        logical_root_index: Int,
        root_u: Int,
        cyclic_shift: Int,
        metric: Float64,
    ):
        self.preamble_index = preamble_index
        self.logical_root_index = logical_root_index
        self.root_u = root_u
        self.cyclic_shift = cyclic_shift
        self.metric = metric


def nr_detect_prach_multi_root(
    received: Span[Complex64, ...],
    starting_logical_root_index: Int,
    n_cs: Int,
    set_type: Int,
    preamble_count: Int = 64,
) raises -> NRPRACHMultiRootDetection:
    """Exhaustive normalized sequence-domain detector across logical roots."""
    var sequence_length = len(received)
    _validate_finite_prach_samples(received)
    var candidates = nr_prach_allocate_preambles(
        starting_logical_root_index,
        sequence_length,
        n_cs,
        set_type,
        preamble_count,
    )
    var maximum_component = 0.0
    for index in range(sequence_length):
        maximum_component = max(
            maximum_component,
            max(abs(received[index].re), abs(received[index].im)),
        )
    var scale = maximum_component if maximum_component > 0.0 else 1.0
    var scaled_received = List[Complex64](capacity=sequence_length)
    for index in range(sequence_length):
        scaled_received.append(Complex64(
            received[index].re / scale, received[index].im / scale
        ))
    var best = NRPRACHMultiRootDetection(0, 0, 0, 0, -1.0)
    for candidate in candidates:
        var reference = nr_prach_preamble_sequence(candidate, sequence_length)
        var correlation = normalized_correlation_at(
            Span(scaled_received), Span(reference), 0
        )
        var metric = correlation.magnitude_squared()
        if (
            not isfinite(correlation.re)
            or not isfinite(correlation.im)
            or not isfinite(metric)
        ):
            raise Error("PRACH detector correlation must remain finite")
        if metric > best.metric:
            best = NRPRACHMultiRootDetection(
                candidate.preamble_index,
                candidate.logical_root_index,
                candidate.root_u,
                candidate.cyclic_shift,
                metric,
            )
    return best


struct NRPRACHNormalizedCompositeResult(Movable):
    """Owned checkpoints for one bounded normalized PRACH loopback.

    This result describes the sequence-sample representation implemented by
    ``nr_prach_normalized_waveform``.  It deliberately does not claim radio-rate
    frequency placement or complete clause 6.3.3.2 occasion coverage.
    """

    var parameters: NRPRACHFormat
    var allocation: NRPRACHPreamble
    var normalized_cp_samples: Int
    var root_sequence: List[Complex64]
    var preamble_sequence: List[Complex64]
    var frequency_sequence: List[Complex64]
    var normalized_waveform: List[Complex64]
    var detector_input: List[Complex64]
    var detection: NRPRACHMultiRootDetection
    var checkpoint_metadata: List[CheckpointMetadata]

    def __init__(
        out self,
        parameters: NRPRACHFormat,
        allocation: NRPRACHPreamble,
        normalized_cp_samples: Int,
        var root_sequence: List[Complex64],
        var preamble_sequence: List[Complex64],
        var frequency_sequence: List[Complex64],
        var normalized_waveform: List[Complex64],
        var detector_input: List[Complex64],
        detection: NRPRACHMultiRootDetection,
        var checkpoint_metadata: List[CheckpointMetadata],
    ):
        self.parameters = parameters
        self.allocation = allocation
        self.normalized_cp_samples = normalized_cp_samples
        self.root_sequence = root_sequence^
        self.preamble_sequence = preamble_sequence^
        self.frequency_sequence = frequency_sequence^
        self.normalized_waveform = normalized_waveform^
        self.detector_input = detector_input^
        self.detection = detection
        self.checkpoint_metadata = checkpoint_metadata^


def _nr_prach_normalized_composite_checkpoint_metadata(
    testcase_id: StringSlice,
    sequence_length: Int,
    waveform_length: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=9)
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "allocated-preamble",
        "int",
        4,
        q_format="integer",
        layout=(
            "preamble-index-logical-root-index-root-u-cyclic-shift"
        ),
    ))
    for stage in ["root-sequence", "preamble-sequence", "frequency-sequence"]:
        result.append(checkpoint_metadata_1d(
            testcase_id,
            stage,
            "complex64",
            sequence_length,
            layout="iq-interleaved",
        ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "normalized-waveform",
        "complex64",
        waveform_length,
        layout="cp-then-repeated-iq",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "detector-input",
        "complex64",
        sequence_length,
        layout="first-useful-repetition-iq",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "normalized-cp-samples",
        "int",
        1,
        q_format="integer",
        layout="scalar",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "detected-preamble-index",
        "int",
        1,
        q_format="integer",
        layout="scalar",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "detection-metric",
        "float64",
        1,
        layout="scalar",
    ))
    return result^


def nr_prach_normalized_composite(
    parameters: NRPRACHFormat,
    starting_logical_root_index: Int,
    n_cs: Int,
    set_type: Int,
    preamble_index: Int,
    *,
    preamble_count: Int = 64,
    testcase_id: StringSlice = "nr-prach-normalized-composite",
) raises -> NRPRACHNormalizedCompositeResult:
    """Generate, waveform-map, and detect one representative PRACH preamble.

    Detection consumes the first useful repetition extracted from the owned
    normalized waveform, so the composite crosses the CP/repetition boundary.
    Existing allocation, waveform, and detector APIs remain unchanged.
    """
    if preamble_index < 0 or preamble_index >= preamble_count:
        raise Error("selected PRACH preamble index is outside the candidate set")
    var allocations = nr_prach_allocate_preambles(
        starting_logical_root_index,
        parameters.sequence_length,
        n_cs,
        set_type,
        preamble_count,
    )
    var allocation = allocations[preamble_index]
    var root = nr_prach_root_sequence_standard(
        allocation.root_u, parameters.sequence_length
    )
    var preamble = nr_prach_preamble_sequence(
        allocation, parameters.sequence_length
    )
    var frequency = nr_prach_frequency_sequence(Span(preamble))
    var waveform = nr_prach_normalized_waveform(Span(preamble), parameters)
    var cp_samples = nr_prach_normalized_cp_samples(parameters)
    var detector_input = List[Complex64](
        capacity=parameters.sequence_length
    )
    for index in range(parameters.sequence_length):
        detector_input.append(waveform[cp_samples + index])
    var detection = nr_detect_prach_multi_root(
        Span(detector_input),
        starting_logical_root_index,
        n_cs,
        set_type,
        preamble_count,
    )
    var metadata = _nr_prach_normalized_composite_checkpoint_metadata(
        testcase_id, parameters.sequence_length, len(waveform)
    )
    return NRPRACHNormalizedCompositeResult(
        parameters,
        allocation,
        cp_samples,
        root^,
        preamble^,
        frequency^,
        waveform^,
        detector_input^,
        detection,
        metadata^,
    )


struct NRPRACHOccasion(ImplicitlyCopyable):
    """Exact row subset from the large 6.3.3.2 occasion tables.

    ``frame_offset_mask`` encodes y in ``SFN mod x = y``. ``time_unit_mask``
    encodes FR1 subframes 0..9 or FR2 60-kHz slots 0..39.
    """

    var region: Int
    var spectrum: Int
    var configuration_index: Int
    var format: Int
    var frame_period: Int
    var frame_offset_mask: UInt16
    var time_unit_mask: UInt64
    var starting_symbol: Int
    var prach_slots_per_unit: Int
    var occasions_per_slot: Int
    var duration_symbols: Int

    def __init__(
        out self,
        region: Int,
        spectrum: Int,
        configuration_index: Int,
        format: Int,
        frame_period: Int,
        frame_offset_mask: UInt16,
        time_unit_mask: UInt64,
        starting_symbol: Int,
        prach_slots_per_unit: Int,
        occasions_per_slot: Int,
        duration_symbols: Int,
    ):
        self.region = region
        self.spectrum = spectrum
        self.configuration_index = configuration_index
        self.format = format
        self.frame_period = frame_period
        self.frame_offset_mask = frame_offset_mask
        self.time_unit_mask = time_unit_mask
        self.starting_symbol = starting_symbol
        self.prach_slots_per_unit = prach_slots_per_unit
        self.occasions_per_slot = occasions_per_slot
        self.duration_symbols = duration_symbols


def _unit_mask(values: Span[Int, ...]) -> UInt64:
    var result = UInt64(0)
    for i in range(len(values)):
        result |= UInt64(1) << UInt64(values[i])
    return result


def nr_prach_representative_occasion(
    region: Int, spectrum: Int, configuration_index: Int
) raises -> NRPRACHOccasion:
    """Return audited representative rows of Tables 6.3.3.2-2/3/4.

    This is intentionally not a lossy fallback: an index outside the explicit
    representative layer raises.  A future generated-data layer can extend
    this stable row type to the full tables without changing callers.
    """
    if region == PRACH_REGION_FR1 and spectrum == PRACH_SPECTRUM_PAIRED:
        if configuration_index == 0:
            return NRPRACHOccasion(region, spectrum, 0, PRACH_FORMAT_0, 16, UInt16(2), _unit_mask(Span([1])), 0, 0, 0, 0)
        if configuration_index == 27:
            return NRPRACHOccasion(region, spectrum, 27, PRACH_FORMAT_0, 1, UInt16(1), _unit_mask(Span([0,1,2,3,4,5,6,7,8,9])), 0, 0, 0, 0)
        if configuration_index == 87:
            return NRPRACHOccasion(region, spectrum, 87, PRACH_FORMAT_A1, 16, UInt16(1), _unit_mask(Span([4,9])), 0, 1, 6, 2)
    elif region == PRACH_REGION_FR1 and spectrum == PRACH_SPECTRUM_UNPAIRED:
        if configuration_index == 0:
            return NRPRACHOccasion(region, spectrum, 0, PRACH_FORMAT_0, 16, UInt16(2), _unit_mask(Span([9])), 0, 0, 0, 0)
        if configuration_index == 67:
            return NRPRACHOccasion(region, spectrum, 67, PRACH_FORMAT_A1, 16, UInt16(2), _unit_mask(Span([9])), 0, 2, 6, 2)
        if configuration_index == 133:
            return NRPRACHOccasion(region, spectrum, 133, PRACH_FORMAT_B1, 4, UInt16(2), _unit_mask(Span([9])), 2, 1, 6, 2)
    elif region == PRACH_REGION_FR2 and spectrum == PRACH_SPECTRUM_UNPAIRED:
        var standard_slots = _unit_mask(Span([4,9,14,19,24,29,34,39]))
        if configuration_index == 0:
            return NRPRACHOccasion(region, spectrum, 0, PRACH_FORMAT_A1, 16, UInt16(2), standard_slots, 0, 2, 6, 2)
        if configuration_index == 29:
            return NRPRACHOccasion(region, spectrum, 29, PRACH_FORMAT_A2, 16, UInt16(2), standard_slots, 0, 2, 3, 4)
        if configuration_index == 89:
            return NRPRACHOccasion(region, spectrum, 89, PRACH_FORMAT_B1, 16, UInt16(2), standard_slots, 2, 2, 6, 2)
        if configuration_index == 112:
            return NRPRACHOccasion(region, spectrum, 112, PRACH_FORMAT_B4, 16, UInt16(6), standard_slots, 0, 2, 1, 12)
        if configuration_index == 144:
            return NRPRACHOccasion(region, spectrum, 144, PRACH_FORMAT_C0, 16, UInt16(2), standard_slots, 0, 2, 7, 2)
        if configuration_index == 173:
            return NRPRACHOccasion(region, spectrum, 173, PRACH_FORMAT_C2, 16, UInt16(2), standard_slots, 0, 2, 2, 6)
    raise Error("PRACH configuration index is outside the representative table layer")


def nr_prach_occasion_is_active(
    occasion: NRPRACHOccasion, system_frame_number: Int, time_unit: Int
) raises -> Bool:
    if (
        system_frame_number < 0
        or time_unit < 0
        or time_unit >= 64
        or occasion.frame_period < 1
        or occasion.frame_period > 16
    ):
        raise Error("invalid PRACH occasion time")
    var residue = system_frame_number % occasion.frame_period
    var frame_active = (
        (occasion.frame_offset_mask & (UInt16(1) << UInt16(residue))) != UInt16(0)
    )
    var unit_active = (
        (occasion.time_unit_mask & (UInt64(1) << UInt64(time_unit))) != UInt64(0)
    )
    return frame_active and unit_active
