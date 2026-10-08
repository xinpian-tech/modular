"""3GPP TS 38.212 Polar construction and rate-matching reference.

The routines in this module are channel agnostic.  They implement the
universal reliability sequence, input/sub-block/bit interleavers, mother-code
selection, frozen-set construction, rate matching, rate recovery, dynamic
parity-check construction, and successive-cancellation reference paths with
or without the five-state parity rule.
"""

from std.collections import Span
from std.math import isfinite
from .polar import polar_transform, polar_encode, polar_decode_sc


struct Polar5GParityConstruction(Movable):
    """Frozen and dynamic parity-check positions for one Polar block."""

    var frozen: List[UInt8]
    var parity_check: List[UInt8]
    var exponent: Int

    def __init__(
        out self,
        var frozen: List[UInt8],
        var parity_check: List[UInt8],
        exponent: Int,
    ):
        self.frozen = frozen^
        self.parity_check = parity_check^
        self.exponent = exponent


struct Polar5GParityDecodeResult(Movable):
    """SC decisions with the dynamic parity constraint status."""

    var bits: List[UInt8]
    var parity_ok: Bool

    def __init__(out self, var bits: List[UInt8], parity_ok: Bool):
        self.bits = bits^
        self.parity_ok = parity_ok


def polar_5g_reliability_sequence() -> List[Int]:
    """TS 38.212 Table 5.3.1.2-1, least to most reliable (Nmax=1024)."""
    var sequence: List[Int] = [
        0, 1, 2, 4, 8, 16, 32, 3, 5, 64, 9, 6, 17, 10, 18, 128,
        12, 33, 65, 20, 256, 34, 24, 36, 7, 129, 66, 512, 11, 40, 68, 130,
        19, 13, 48, 14, 72, 257, 21, 132, 35, 258, 26, 513, 80, 37, 25, 22,
        136, 260, 264, 38, 514, 96, 67, 41, 144, 28, 69, 42, 516, 49, 74, 272,
        160, 520, 288, 528, 192, 544, 70, 44, 131, 81, 50, 73, 15, 320, 133, 52,
        23, 134, 384, 76, 137, 82, 56, 27, 97, 39, 259, 84, 138, 145, 261, 29,
        43, 98, 515, 88, 140, 30, 146, 71, 262, 265, 161, 576, 45, 100, 640, 51,
        148, 46, 75, 266, 273, 517, 104, 162, 53, 193, 152, 77, 164, 768, 268, 274,
        518, 54, 83, 57, 521, 112, 135, 78, 289, 194, 85, 276, 522, 58, 168, 139,
        99, 86, 60, 280, 89, 290, 529, 524, 196, 141, 101, 147, 176, 142, 530, 321,
        31, 200, 90, 545, 292, 322, 532, 263, 149, 102, 105, 304, 296, 163, 92, 47,
        267, 385, 546, 324, 208, 386, 150, 153, 165, 106, 55, 328, 536, 577, 548, 113,
        154, 79, 269, 108, 578, 224, 166, 519, 552, 195, 270, 641, 523, 275, 580, 291,
        59, 169, 560, 114, 277, 156, 87, 197, 116, 170, 61, 531, 525, 642, 281, 278,
        526, 177, 293, 388, 91, 584, 769, 198, 172, 120, 201, 336, 62, 282, 143, 103,
        178, 294, 93, 644, 202, 592, 323, 392, 297, 770, 107, 180, 151, 209, 284, 648,
        94, 204, 298, 400, 608, 352, 325, 533, 155, 210, 305, 547, 300, 109, 184, 534,
        537, 115, 167, 225, 326, 306, 772, 157, 656, 329, 110, 117, 212, 171, 776, 330,
        226, 549, 538, 387, 308, 216, 416, 271, 279, 158, 337, 550, 672, 118, 332, 579,
        540, 389, 173, 121, 553, 199, 784, 179, 228, 338, 312, 704, 390, 174, 554, 581,
        393, 283, 122, 448, 353, 561, 203, 63, 340, 394, 527, 582, 556, 181, 295, 285,
        232, 124, 205, 182, 643, 562, 286, 585, 299, 354, 211, 401, 185, 396, 344, 586,
        645, 593, 535, 240, 206, 95, 327, 564, 800, 402, 356, 307, 301, 417, 213, 568,
        832, 588, 186, 646, 404, 227, 896, 594, 418, 302, 649, 771, 360, 539, 111, 331,
        214, 309, 188, 449, 217, 408, 609, 596, 551, 650, 229, 159, 420, 310, 541, 773,
        610, 657, 333, 119, 600, 339, 218, 368, 652, 230, 391, 313, 450, 542, 334, 233,
        555, 774, 175, 123, 658, 612, 341, 777, 220, 314, 424, 395, 673, 583, 355, 287,
        183, 234, 125, 557, 660, 616, 342, 316, 241, 778, 563, 345, 452, 397, 403, 207,
        674, 558, 785, 432, 357, 187, 236, 664, 624, 587, 780, 705, 126, 242, 565, 398,
        346, 456, 358, 405, 303, 569, 244, 595, 189, 566, 676, 361, 706, 589, 215, 786,
        647, 348, 419, 406, 464, 680, 801, 362, 590, 409, 570, 788, 597, 572, 219, 311,
        708, 598, 601, 651, 421, 792, 802, 611, 602, 410, 231, 688, 653, 248, 369, 190,
        364, 654, 659, 335, 480, 315, 221, 370, 613, 422, 425, 451, 614, 543, 235, 412,
        343, 372, 775, 317, 222, 426, 453, 237, 559, 833, 804, 712, 834, 661, 808, 779,
        617, 604, 433, 720, 816, 836, 347, 897, 243, 662, 454, 318, 675, 618, 898, 781,
        376, 428, 665, 736, 567, 840, 625, 238, 359, 457, 399, 787, 591, 678, 434, 677,
        349, 245, 458, 666, 620, 363, 127, 191, 782, 407, 436, 626, 571, 465, 681, 246,
        707, 350, 599, 668, 790, 460, 249, 682, 573, 411, 803, 789, 709, 365, 440, 628,
        689, 374, 423, 466, 793, 250, 371, 481, 574, 413, 603, 366, 468, 655, 900, 805,
        615, 684, 710, 429, 794, 252, 373, 605, 848, 690, 713, 632, 482, 806, 427, 904,
        414, 223, 663, 692, 835, 619, 472, 455, 796, 809, 714, 721, 837, 716, 864, 810,
        606, 912, 722, 696, 377, 435, 817, 319, 621, 812, 484, 430, 838, 667, 488, 239,
        378, 459, 622, 627, 437, 380, 818, 461, 496, 669, 679, 724, 841, 629, 351, 467,
        438, 737, 251, 462, 442, 441, 469, 247, 683, 842, 738, 899, 670, 783, 849, 820,
        728, 928, 791, 367, 901, 630, 685, 844, 633, 711, 253, 691, 824, 902, 686, 740,
        850, 375, 444, 470, 483, 415, 485, 905, 795, 473, 634, 744, 852, 960, 865, 693,
        797, 906, 715, 807, 474, 636, 694, 254, 717, 575, 913, 798, 811, 379, 697, 431,
        607, 489, 866, 723, 486, 908, 718, 813, 476, 856, 839, 725, 698, 914, 752, 868,
        819, 814, 439, 929, 490, 623, 671, 739, 916, 463, 843, 381, 497, 930, 821, 726,
        961, 872, 492, 631, 729, 700, 443, 741, 845, 920, 382, 822, 851, 730, 498, 880,
        742, 445, 471, 635, 932, 687, 903, 825, 500, 846, 745, 826, 732, 446, 962, 936,
        475, 853, 867, 637, 907, 487, 695, 746, 828, 753, 854, 857, 504, 799, 255, 964,
        909, 719, 477, 915, 638, 748, 944, 869, 491, 699, 754, 858, 478, 968, 383, 910,
        815, 976, 870, 917, 727, 493, 873, 701, 931, 756, 860, 499, 731, 823, 922, 874,
        918, 502, 933, 743, 760, 881, 494, 702, 921, 501, 876, 847, 992, 447, 733, 827,
        934, 882, 937, 963, 747, 505, 855, 924, 734, 829, 965, 938, 884, 506, 749, 945,
        966, 755, 859, 940, 830, 911, 871, 639, 888, 479, 946, 750, 969, 508, 861, 757,
        970, 919, 875, 862, 758, 948, 977, 923, 972, 761, 877, 952, 495, 703, 935, 978,
        883, 762, 503, 925, 878, 735, 993, 885, 939, 994, 980, 926, 764, 941, 967, 886,
        831, 947, 507, 889, 984, 751, 942, 996, 971, 890, 509, 949, 973, 1000, 892, 950,
        863, 759, 1008, 510, 979, 953, 763, 974, 954, 879, 981, 982, 927, 995, 765, 956,
        887, 985, 997, 986, 943, 891, 998, 766, 511, 988, 1001, 951, 1002, 893, 975, 894,
        1009, 955, 1004, 1010, 957, 983, 958, 987, 1012, 999, 1016, 767, 989, 1003, 990, 1005,
        959, 1011, 1013, 895, 1006, 1014, 1017, 1018, 991, 1020, 1007, 1015, 1019, 1021, 1022, 1023,
    ]
    return sequence^


def _polar_5g_input_pattern() -> List[Int]:
    var pattern: List[Int] = [
        0, 2, 4, 7, 9, 14, 19, 20, 24, 25, 26, 28, 31, 34, 42, 45,
        49, 50, 51, 53, 54, 56, 58, 59, 61, 62, 65, 66, 67, 69, 70, 71,
        72, 76, 77, 81, 82, 83, 87, 88, 89, 91, 93, 95, 98, 101, 104, 106,
        108, 110, 111, 113, 115, 118, 119, 120, 122, 123, 126, 127, 129, 132, 134, 138,
        139, 140, 1, 3, 5, 8, 10, 15, 21, 27, 29, 32, 35, 43, 46, 52,
        55, 57, 60, 63, 68, 73, 78, 84, 90, 92, 94, 96, 99, 102, 105, 107,
        109, 112, 114, 116, 121, 124, 128, 130, 133, 135, 141, 6, 11, 16, 22, 30,
        33, 36, 44, 47, 64, 74, 79, 85, 97, 100, 103, 117, 125, 131, 136, 142,
        12, 17, 23, 37, 48, 75, 80, 86, 137, 143, 13, 18, 38, 144, 39, 145,
        40, 146, 41, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159,
        160, 161, 162, 163,
    ]
    return pattern^


def _polar_5g_subblock_pattern() -> List[Int]:
    var pattern: List[Int] = [
        0, 1, 2, 4, 3, 5, 6, 7, 8, 16, 9, 17, 10, 18, 11, 19,
        12, 20, 13, 21, 14, 22, 15, 23, 24, 25, 26, 28, 27, 29, 30, 31,
    ]
    return pattern^


def _ceil_log2_positive(value: Int) -> Int:
    # ceil(log2(value)) == bit_length(value - 1).  Shifting the remainder
    # cannot overflow, unlike repeatedly doubling a signed Int near Int.MAX.
    var remainder = value - 1
    var exponent = 0
    while remainder > 0:
        remainder >>= 1
        exponent += 1
    return exponent


def polar_5g_mother_code_length(k: Int, e: Int, *, n_max: Int = 10) raises -> Int:
    """Return N from TS 38.212 5.3.1 for information length K and output E."""
    if k < 1 or e < 1 or n_max < 5 or n_max > 10 or k > e:
        raise Error("invalid 5G Polar construction dimensions")
    var ceil_log_e = _ceil_log2_positive(e)
    var n1 = ceil_log_e
    if (
        ceil_log_e > 0
        and Int128(8) * Int128(e)
        <= Int128(9) * (Int128(1) << Int128(ceil_log_e - 1))
        and Int128(16) * Int128(k) < Int128(9) * Int128(e)
    ):
        n1 -= 1
    var n2 = _ceil_log2_positive(k) + 3
    var n = min(n1, min(n2, n_max))
    return max(n, 5)


def _subblock_source_index(index: Int, n: Int) raises -> Int:
    if n < 32 or (n & (n - 1)) != 0:
        raise Error("5G Polar sub-block length must be a power of two at least 32")
    var block_size = n // 32
    var pattern = _polar_5g_subblock_pattern()
    return pattern[index // block_size] * block_size + index % block_size


def _row_weight_exponent(index: Int) -> Int:
    """Return popcount(index), which orders rows by Polar row weight."""
    var value = index
    var count = 0
    while value != 0:
        count += value & 1
        value >>= 1
    return count


def polar_5g_parity_construction(
    k: Int,
    e: Int,
    *,
    n_pc: Int = 0,
    n_pc_wm: Int = 0,
    n_max: Int = 10,
) raises -> Polar5GParityConstruction:
    """Construct Q_I, Q_F, and Q_PC from TS 38.212 clauses 5.3.1/5.4.1.

    ``k`` is the number of delivered information bits; dynamic parity-check
    positions are additional members of Q_I.  ``n_pc_wm`` selects parity
    positions by minimum Polar-generator row weight as specified for short
    UCI blocks.
    """
    if n_pc < 0 or n_pc_wm < 0 or n_pc_wm > n_pc:
        raise Error("invalid 5G Polar parity-check configuration")
    if k + n_pc > e:
        raise Error("5G Polar information and parity bits exceed E")
    var exponent = polar_5g_mother_code_length(k, e, n_max=n_max)
    var n = 1 << exponent
    var forbidden = List[UInt8](length=n, fill=UInt8(0))
    if e < n:
        if 16 * k <= 7 * e:  # puncturing
            for index in range(n - e):
                forbidden[_subblock_source_index(index, n)] = 1
            # ceil(3N/4-E/2), or ceil(9N/16-E/4).
            var extra = (
                (3 * n - 2 * e + 3) // 4
                if 4 * e >= 3 * n
                else (9 * n - 4 * e + 15) // 16
            )
            for index in range(max(extra, 0)):
                forbidden[index] = 1
        else:  # shortening
            for index in range(e, n):
                forbidden[_subblock_source_index(index, n)] = 1

    var reliability = polar_5g_reliability_sequence()
    var eligible = List[Int]()
    for value in reliability:
        if value < n and forbidden[value] == 0:
            eligible.append(value)
    var selected_count = k + n_pc
    if len(eligible) < selected_count:
        raise Error("not enough eligible 5G Polar information positions")
    var frozen = List[UInt8](length=n, fill=UInt8(1))
    var selected = List[Int](capacity=selected_count)
    for offset in range(selected_count):
        var position = eligible[len(eligible) - selected_count + offset]
        selected.append(position)
        frozen[position] = 0

    var parity_check = List[UInt8](length=n, fill=UInt8(0))
    for offset in range(n_pc - n_pc_wm):
        parity_check[selected[offset]] = 1
    # Q_I_tilde is the K most reliable part of Q_I.  For equal row weight,
    # iterating from low to high reliability and replacing on equality picks
    # the most reliable candidate, exactly as the specification requires.
    for _ in range(n_pc_wm):
        var best_position = -1
        var best_weight = 1000
        for offset in range(n_pc, len(selected)):
            var position = selected[offset]
            if parity_check[position] == 0:
                var weight = _row_weight_exponent(position)
                if weight <= best_weight:
                    best_weight = weight
                    best_position = position
        if best_position < 0:
            raise Error("unable to place 5G Polar row-weight parity bit")
        parity_check[best_position] = 1
    return Polar5GParityConstruction(
        frozen^, parity_check^, exponent
    )


def polar_5g_frozen_mask(k: Int, e: Int, *, n_max: Int = 10) raises -> List[UInt8]:
    """Construct Q_I/Q_F for nPC=0; zero entries identify information bits."""
    var construction = polar_5g_parity_construction(k, e, n_max=n_max)
    var result = List[UInt8](capacity=len(construction.frozen))
    for index in range(len(construction.frozen)):
        result.append(construction.frozen[index])
    return result^


def polar_5g_input_interleave(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    """TS 38.212 5.3.1.1 input interleaver (I_IL=1)."""
    if len(bits) > 164:
        raise Error("5G Polar input interleaving supports at most 164 bits")
    var pattern = _polar_5g_input_pattern()
    var threshold = 164 - len(bits)
    var result = List[UInt8](capacity=len(bits))
    for source in pattern:
        if source >= threshold:
            var index = source - threshold
            if bits[index] > 1:
                raise Error("bits must be zero or one")
            result.append(bits[index])
    return result^


def polar_5g_input_deinterleave(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    """Inverse of :func:`polar_5g_input_interleave`."""
    if len(bits) > 164:
        raise Error("5G Polar input interleaving supports at most 164 bits")
    var pattern = _polar_5g_input_pattern()
    var threshold = 164 - len(bits)
    var result = List[UInt8](length=len(bits), fill=UInt8(0))
    var source_index = 0
    for source in pattern:
        if source >= threshold:
            if bits[source_index] > 1:
                raise Error("bits must be zero or one")
            result[source - threshold] = bits[source_index]
            source_index += 1
    return result^


def polar_5g_subblock_interleave(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    var result = List[UInt8](capacity=len(bits))
    for index in range(len(bits)):
        var bit = bits[_subblock_source_index(index, len(bits))]
        if bit > 1:
            raise Error("bits must be zero or one")
        result.append(bit)
    return result^


def polar_5g_subblock_deinterleave_llrs(llrs: Span[Float64, ...]) raises -> List[Float64]:
    var result = List[Float64](length=len(llrs), fill=0.0)
    for index in range(len(llrs)):
        if not isfinite(llrs[index]):
            raise Error("5G Polar LLRs must be finite")
        result[_subblock_source_index(index, len(llrs))] = llrs[index]
    return result^


def _polar_5g_bit_interleave_indices(e: Int) raises -> List[Int]:
    if e < 1 or e > 8192:
        raise Error("5G Polar bit interleaver length must be in [1,8192]")
    var t = 1
    while t * (t + 1) // 2 < e:
        t += 1
    var matrix = List[Int](length=t * t, fill=-1)
    var source = 0
    for row in range(t):
        for column in range(t - row):
            if source < e:
                matrix[row * t + column] = source
                source += 1
    var indices = List[Int](capacity=e)
    for column in range(t):
        for row in range(t - column):
            var index = matrix[row * t + column]
            if index >= 0:
                indices.append(index)
    return indices^


def polar_5g_rate_match(
    coded: Span[UInt8, ...], e: Int, k: Int, *, bit_interleave: Bool = False,
) raises -> List[UInt8]:
    """TS 38.212 5.4.1 sub-block interleaving and bit selection."""
    if e < 1 or k < 1 or k > e:
        raise Error("invalid 5G Polar rate-matching dimensions")
    var y = polar_5g_subblock_interleave(coded)
    var selected = List[UInt8](capacity=e)
    if e >= len(y):
        for index in range(e):
            selected.append(y[index % len(y)])
    elif 16 * k <= 7 * e:
        for index in range(e):
            selected.append(y[len(y) - e + index])
    else:
        for index in range(e):
            selected.append(y[index])
    if not bit_interleave:
        return selected^
    var indices = _polar_5g_bit_interleave_indices(e)
    var result = List[UInt8](capacity=e)
    for source in indices:
        result.append(selected[source])
    return result^


def polar_5g_rate_recover_llrs(
    received: Span[Float64, ...], n: Int, k: Int,
    *, bit_interleave: Bool = False, shortening_llr: Float64 = 1.0e9,
) raises -> List[Float64]:
    """Inverse bit selection/sub-block interleaving with repetition combining."""
    var e = len(received)
    if (
        e < 1
        or k < 1
        or k > e
        or n < 32
        or (n & (n - 1)) != 0
        or not isfinite(shortening_llr)
        or shortening_llr <= 0.0
    ):
        raise Error("invalid 5G Polar rate-recovery dimensions")
    for index in range(e):
        if not isfinite(received[index]):
            raise Error("5G Polar received LLRs must be finite")
    var selected = List[Float64](length=e, fill=0.0)
    if bit_interleave:
        var indices = _polar_5g_bit_interleave_indices(e)
        for index in range(e):
            selected[indices[index]] = received[index]
    else:
        for index in range(e):
            selected[index] = received[index]

    var y = List[Float64](length=n, fill=0.0)
    if e >= n:
        for index in range(e):
            y[index % n] += selected[index]
    elif 16 * k <= 7 * e:
        for index in range(e):
            y[n - e + index] = selected[index]
    else:
        for index in range(e):
            y[index] = selected[index]
        for index in range(e, n):
            y[index] = shortening_llr
    return polar_5g_subblock_deinterleave_llrs(Span(y))


def polar_5g_encode(
    information: Span[UInt8, ...], e: Int, *, n_max: Int = 10,
    input_interleave: Bool = False, bit_interleave: Bool = False,
) raises -> List[UInt8]:
    """Construct, encode, and rate-match a 5G Polar block (nPC=0)."""
    var ordered = List[UInt8](capacity=len(information))
    if input_interleave:
        ordered = polar_5g_input_interleave(information)
    else:
        for index in range(len(information)):
            var bit = information[index]
            if bit > 1:
                raise Error("bits must be zero or one")
            ordered.append(bit)
    var frozen = polar_5g_frozen_mask(len(information), e, n_max=n_max)
    var coded = polar_encode(Span(ordered), Span(frozen))
    return polar_5g_rate_match(
        Span(coded), e, len(information), bit_interleave=bit_interleave
    )


def polar_5g_decode_sc(
    llrs: Span[Float64, ...], k: Int, *, n_max: Int = 10,
    input_interleave: Bool = False, bit_interleave: Bool = False,
) raises -> List[UInt8]:
    """Rate-recover and SC-decode a 5G Polar block (reference, nPC=0)."""
    var exponent = polar_5g_mother_code_length(k, len(llrs), n_max=n_max)
    var n = 1 << exponent
    var recovered = polar_5g_rate_recover_llrs(
        llrs, n, k, bit_interleave=bit_interleave
    )
    var frozen = polar_5g_frozen_mask(k, len(llrs), n_max=n_max)
    var ordered = polar_decode_sc(Span(recovered), Span(frozen))
    if input_interleave:
        return polar_5g_input_deinterleave(Span(ordered))
    return ordered^


def polar_5g_encode_with_parity(
    information: Span[UInt8, ...],
    e: Int,
    *,
    n_pc: Int,
    n_pc_wm: Int = 0,
    n_max: Int = 10,
    input_interleave: Bool = False,
    bit_interleave: Bool = False,
) raises -> List[UInt8]:
    """Encode a 5G Polar block with the five-state dynamic PC rule."""
    var ordered = List[UInt8](capacity=len(information))
    if input_interleave:
        ordered = polar_5g_input_interleave(information)
    else:
        for index in range(len(information)):
            if information[index] > 1:
                raise Error("bits must be zero or one")
            ordered.append(information[index])
    var construction = polar_5g_parity_construction(
        len(information), e, n_pc=n_pc, n_pc_wm=n_pc_wm,
        n_max=n_max,
    )
    var n = 1 << construction.exponent
    var values = List[UInt8](length=n, fill=UInt8(0))
    var information_index = 0
    var y0 = UInt8(0)
    var y1 = UInt8(0)
    var y2 = UInt8(0)
    var y3 = UInt8(0)
    var y4 = UInt8(0)
    for index in range(n):
        var temporary = y0
        y0 = y1
        y1 = y2
        y2 = y3
        y3 = y4
        y4 = temporary
        if construction.frozen[index] == 0:
            if construction.parity_check[index] == 1:
                values[index] = y0
            else:
                values[index] = ordered[information_index]
                information_index += 1
                y0 ^= values[index]
    if information_index != len(ordered):
        raise Error("5G Polar parity construction consumed wrong bit count")
    polar_transform(values)
    return polar_5g_rate_match(
        Span(values), e, len(information), bit_interleave=bit_interleave
    )


def polar_5g_decode_sc_with_parity(
    llrs: Span[Float64, ...],
    k: Int,
    *,
    n_pc: Int,
    n_pc_wm: Int = 0,
    n_max: Int = 10,
    input_interleave: Bool = False,
    bit_interleave: Bool = False,
) raises -> Polar5GParityDecodeResult:
    """SC-decode and verify the five-state dynamic parity constraints."""
    var construction = polar_5g_parity_construction(
        k, len(llrs), n_pc=n_pc, n_pc_wm=n_pc_wm, n_max=n_max
    )
    var n = 1 << construction.exponent
    var recovered = polar_5g_rate_recover_llrs(
        llrs, n, k, bit_interleave=bit_interleave
    )
    var decoded = polar_decode_sc(Span(recovered), Span(construction.frozen))
    var result = List[UInt8](capacity=k)
    var decision_index = 0
    var parity_ok = True
    var y0 = UInt8(0)
    var y1 = UInt8(0)
    var y2 = UInt8(0)
    var y3 = UInt8(0)
    var y4 = UInt8(0)
    for index in range(n):
        var temporary = y0
        y0 = y1
        y1 = y2
        y2 = y3
        y3 = y4
        y4 = temporary
        if construction.frozen[index] == 0:
            var bit = decoded[decision_index]
            decision_index += 1
            if construction.parity_check[index] == 1:
                parity_ok = parity_ok and bit == y0
            else:
                result.append(bit)
                y0 ^= bit
    if decision_index != len(decoded) or len(result) != k:
        raise Error("5G Polar parity decoder produced wrong bit count")
    if input_interleave:
        result = polar_5g_input_deinterleave(Span(result))
    return Polar5GParityDecodeResult(result^, parity_ok)
