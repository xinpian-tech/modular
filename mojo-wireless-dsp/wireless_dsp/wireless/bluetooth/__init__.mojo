"""Ratified Bluetooth Core packet, coded-FEC, HEC, and GFSK primitives."""

from .br_edr_hec import (
    bluetooth_br_edr_hec_generate,
    bluetooth_br_edr_hec_check,
)

from .le_packet import (
    BLUETOOTH_LE_PHY_1M,
    BLUETOOTH_LE_PHY_2M,
    BluetoothLEUncodedPacketEncodeResult,
    BluetoothLEUncodedPacketDecodeResult,
    bluetooth_le_crc24,
    bluetooth_le_whiten_bits,
    bluetooth_le_uncoded_packet_encode,
    bluetooth_le_uncoded_packet_decode,
)
from .le_coded import (
    BluetoothLECodedPacketEncodeResult,
    BluetoothLECodedPacketFECDecodeReferenceResult,
    bluetooth_le_coded_pattern_map,
    bluetooth_le_coded_pattern_demap_exact,
    bluetooth_le_coded_packet_encode,
    bluetooth_le_coded_packet_fec_decode_hard_reference,
)
from .gfsk import (
    BLUETOOTH_LE_GFSK_PHY_1M,
    BLUETOOTH_LE_GFSK_PHY_2M,
    BluetoothLEGFSKLimits,
    bluetooth_le_gfsk_limits,
    bluetooth_le_gfsk_modulation_index_is_compliant,
    bluetooth_le_gfsk_frequency_deviation_is_compliant,
    bluetooth_le_gfsk_timing_is_compliant,
    bluetooth_le_gfsk_bit_deviation_sign_is_compliant,
    bluetooth_le_gfsk_stable_claim_is_compliant,
)
