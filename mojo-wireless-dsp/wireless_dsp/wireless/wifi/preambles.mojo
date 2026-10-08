"""20 MHz HT/VHT and HE/EHT long-training reference waveforms.

The HT/VHT sequence is indexed by k=-28..28.  The HE/EHT sequence is the
245-entry 4x HE-LTF from IEEE Std 802.11ax Equation (27-43), indexed by
k=-122..122.  IEEE 802.11be reuses that 20 MHz sequence for a 4x EHT-LTF.
These helpers deliberately implement the one-spatial-stream training row;
multi-stream P-matrix cyclic shifts are outside this minimal PHY chain.
"""

from std.collections import Span
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import ofdm_modulate, ofdm_demodulate, complex_divide
from .legacy import wifi_pilot_polarity
from .profiles import WIFI_PHY_HT, WIFI_PHY_VHT, WIFI_PHY_HE, WIFI_PHY_EHT


def _wifi_fft_bin(subcarrier: Int, fft_size: Int) -> Int:
    return subcarrier if subcarrier >= 0 else fft_size + subcarrier


def wifi_ltf_values_20mhz(family: Int) raises -> List[Int]:
    """Return the signed BPSK LTF values in increasing subcarrier order."""
    if family == WIFI_PHY_HT or family == WIFI_PHY_VHT:
        return [
            1,
            1,
            1,
            1,
            -1,
            -1,
            1,
            1,
            -1,
            1,
            -1,
            1,
            1,
            1,
            1,
            1,
            1,
            -1,
            -1,
            1,
            1,
            -1,
            1,
            -1,
            1,
            1,
            1,
            1,
            0,
            1,
            -1,
            -1,
            1,
            1,
            -1,
            1,
            -1,
            1,
            -1,
            -1,
            -1,
            -1,
            -1,
            1,
            1,
            -1,
            -1,
            1,
            -1,
            1,
            -1,
            1,
            1,
            1,
            1,
            -1,
            -1,
        ]
    if family == WIFI_PHY_HE or family == WIFI_PHY_EHT:
        # IEEE 802.11ax-2021 Eq. (27-43), k=-122..122.
        return [
            -1,
            -1,
            1,
            -1,
            1,
            -1,
            1,
            1,
            1,
            -1,
            1,
            1,
            1,
            -1,
            -1,
            1,
            -1,
            -1,
            -1,
            -1,
            -1,
            1,
            1,
            -1,
            -1,
            -1,
            -1,
            1,
            1,
            -1,
            1,
            -1,
            1,
            1,
            1,
            1,
            -1,
            1,
            -1,
            -1,
            1,
            1,
            -1,
            1,
            1,
            1,
            1,
            -1,
            -1,
            1,
            -1,
            -1,
            -1,
            1,
            1,
            1,
            1,
            -1,
            1,
            1,
            -1,
            -1,
            -1,
            -1,
            1,
            -1,
            -1,
            1,
            1,
            -1,
            1,
            -1,
            -1,
            -1,
            -1,
            1,
            -1,
            1,
            -1,
            -1,
            -1,
            -1,
            -1,
            -1,
            1,
            1,
            -1,
            -1,
            -1,
            -1,
            -1,
            1,
            -1,
            -1,
            1,
            1,
            1,
            -1,
            1,
            1,
            1,
            -1,
            1,
            -1,
            1,
            -1,
            -1,
            -1,
            -1,
            -1,
            1,
            1,
            1,
            -1,
            -1,
            -1,
            1,
            -1,
            1,
            1,
            1,
            0,
            0,
            0,
            -1,
            1,
            -1,
            1,
            -1,
            1,
            1,
            -1,
            1,
            1,
            1,
            -1,
            -1,
            1,
            -1,
            -1,
            1,
            -1,
            1,
            -1,
            1,
            1,
            1,
            -1,
            1,
            1,
            1,
            -1,
            -1,
            1,
            -1,
            -1,
            -1,
            -1,
            -1,
            1,
            1,
            -1,
            -1,
            -1,
            -1,
            -1,
            -1,
            1,
            -1,
            1,
            -1,
            -1,
            -1,
            -1,
            1,
            -1,
            1,
            1,
            -1,
            -1,
            1,
            -1,
            -1,
            -1,
            -1,
            1,
            1,
            -1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            -1,
            1,
            1,
            -1,
            -1,
            -1,
            -1,
            1,
            -1,
            -1,
            1,
            1,
            -1,
            1,
            -1,
            -1,
            -1,
            -1,
            1,
            -1,
            1,
            -1,
            -1,
            1,
            1,
            1,
            1,
            -1,
            -1,
            1,
            1,
            1,
            1,
            1,
            -1,
            1,
            1,
            -1,
            -1,
            -1,
            1,
            -1,
            -1,
            -1,
            1,
            -1,
            1,
            -1,
            1,
            1,
        ]
    raise Error("unknown Wi-Fi PHY family")


def wifi_ltf_spectrum_20mhz(family: Int) raises -> List[Complex64]:
    """Map the one-stream LTF into the appropriate 64/256 FFT bins."""
    var values = wifi_ltf_values_20mhz(family)
    var fft_size = (
        64 if family == WIFI_PHY_HT or family == WIFI_PHY_VHT else 256
    )
    var first = -28 if fft_size == 64 else -122
    var result = List[Complex64](length=fft_size, fill=Complex64(0.0, 0.0))
    for i in range(len(values)):
        result[_wifi_fft_bin(first + i, fft_size)] = Complex64(
            Float64(values[i])
        )
    return result^


def wifi_ltf_waveform_20mhz(
    family: Int, *, cyclic_prefix_samples: Int = 16
) raises -> List[Complex64]:
    """Create one LTF OFDM symbol (4x for HE/EHT) with a selectable GI."""
    var spectrum = wifi_ltf_spectrum_20mhz(family)
    return ofdm_modulate(Span(spectrum), cyclic_prefix_samples)


def wifi_ltf_channel_estimate_20mhz(
    received: Span[Complex64, ...],
    family: Int,
    *,
    cyclic_prefix_samples: Int = 16,
) raises -> List[Complex64]:
    """FFT an LTF and return per-trained-bin least-squares channel estimates."""
    var known = wifi_ltf_spectrum_20mhz(family)
    var spectrum = ofdm_demodulate(received, len(known), cyclic_prefix_samples)
    var result = List[Complex64](length=len(known), fill=Complex64(0.0, 0.0))
    for i in range(len(known)):
        if known[i].magnitude_squared() > 0.0:
            result[i] = complex_divide(spectrum[i], known[i])
    return result^


def wifi_data_pilot_subcarriers_20mhz(family: Int) raises -> List[Int]:
    if family == WIFI_PHY_HT or family == WIFI_PHY_VHT:
        return [-21, -7, 7, 21]
    if family == WIFI_PHY_HE or family == WIFI_PHY_EHT:
        return [-116, -90, -48, -22, 22, 48, 90, 116]
    raise Error("unknown Wi-Fi PHY family")


def wifi_data_pilots_20mhz(
    family: Int, symbol_index: Int = 0
) raises -> List[Complex64]:
    """Return the one-stream pilot row for the requested symbol index.

    HT/VHT use the 127-symbol polarity.  HE uses the rotating RU table row.
    EHT applies both; callers constructing a complete PPDU add the EHT
    preamble-dependent polarity-index offset to ``symbol_index``.
    """
    if symbol_index < 0:
        raise Error("symbol index must be non-negative")
    var polarity = 1.0
    var base: List[Int]
    if family == WIFI_PHY_HT or family == WIFI_PHY_VHT:
        base = [1, 1, 1, -1]
        polarity = wifi_pilot_polarity(symbol_index)
    elif family == WIFI_PHY_HE or family == WIFI_PHY_EHT:
        # RU-242 row from Tables 27-42/27-43; cyclic rotation is by n mod 8.
        base = [1, 1, 1, -1, -1, 1, 1, 1]
    else:
        raise Error("unknown Wi-Fi PHY family")
    if family == WIFI_PHY_EHT:
        polarity = wifi_pilot_polarity(symbol_index)
    var rotation = symbol_index % len(base) if len(base) == 8 else 0
    var result = List[Complex64](capacity=len(base))
    for i in range(len(base)):
        result.append(
            Complex64(polarity * Float64(base[(i + rotation) % len(base)]))
        )
    return result^
