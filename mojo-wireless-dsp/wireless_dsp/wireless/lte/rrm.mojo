"""Exact non-eDRX LTE serving-cell RRM arithmetic.

This bounded CPU module implements only the deterministic part of 3GPP
TS 36.133 V18.14.0 clause 4.2.2.1 and Table 4.2.2.1-1 for a UE that is
not configured with ``eDRX_IDLE``:

* all four published DRX-cycle to ``Nserv`` rows;
* the minimum spacing of one half DRX cycle between two serving-cell
  RSRP/RSRQ measurements used for filtering; and
* the threshold for initiating measurements of all indicated neighbour cells
  after consecutive serving-cell selection-criterion failures.

Normative published source:

* https://www.3gpp.org/ftp/Specs/archive/36_series/36.133/36133-ie0.zip
  (SHA-256 045289aa94bcd39e184d46044eda30319f84907bdb814ca91fe91b4b51e9a6bd)

The caller owns RSRP/RSRQ acquisition, the cell-selection criterion, the
consecutive-failure state, neighbour lists and RRC state.  eDRX/PTW tables,
cell search/reselection, inter-frequency/inter-RAT timing, calibrated RF and
conformance execution are outside this closed arithmetic slice.
"""


comptime LTE_RRM_NON_EDRX_DRX_ROW_COUNT = 4
comptime LTE_RRM_DRX_320_MS = 320
comptime LTE_RRM_DRX_640_MS = 640
comptime LTE_RRM_DRX_1280_MS = 1280
comptime LTE_RRM_DRX_2560_MS = 2560


struct LTERRMServingCellConfig(ImplicitlyCopyable, Equatable):
    """Caller-decoded non-eDRX serving-cell DRX configuration.

    The field remains public and mutable.  Every public algorithm revalidates
    it so mutation cannot bypass the four-row standardized domain.
    """

    var drx_cycle_ms: Int

    def __init__(out self, drx_cycle_ms: Int) raises:
        self.drx_cycle_ms = drx_cycle_ms
        self.validate()

    def validate(self) raises:
        if (
            self.drx_cycle_ms != LTE_RRM_DRX_320_MS
            and self.drx_cycle_ms != LTE_RRM_DRX_640_MS
            and self.drx_cycle_ms != LTE_RRM_DRX_1280_MS
            and self.drx_cycle_ms != LTE_RRM_DRX_2560_MS
        ):
            raise Error(
                "LTE non-eDRX serving-cell DRX cycle must be 320, 640, "
                "1280 or 2560 ms"
            )


def lte_rrm_serving_cell_nserv(config: LTERRMServingCellConfig) raises -> Int:
    """Return complete Table 4.2.2.1-1 ``Nserv`` for ``config``."""
    config.validate()
    if (
        config.drx_cycle_ms == LTE_RRM_DRX_320_MS
        or config.drx_cycle_ms == LTE_RRM_DRX_640_MS
    ):
        return 4
    return 2


def lte_rrm_minimum_filter_spacing_ms(
    config: LTERRMServingCellConfig,
) raises -> Int:
    """Return the exact minimum spacing of half one DRX cycle in ms."""
    config.validate()
    return config.drx_cycle_ms // 2


def lte_rrm_all_neighbour_measurements_required(
    config: LTERRMServingCellConfig,
    consecutive_failed_cycles: Int,
) raises -> Bool:
    """Evaluate the standardized consecutive-failure ``Nserv`` threshold."""
    config.validate()
    if consecutive_failed_cycles < 0:
        raise Error("LTE serving-cell consecutive-failure count cannot be negative")
    return consecutive_failed_cycles >= lte_rrm_serving_cell_nserv(config)
