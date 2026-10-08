"""Explicit layout views and owned buffers used at PHY kernel boundaries."""

from std.collections import check_bounds
from std.math import isfinite
from .complex import Complex


def _strided_extent_magnitude(length: Int, stride: Int) raises -> Int:
    """Return the maximum logical offset magnitude without Int overflow."""
    if length <= 1:
        return 0
    if stride == Int.MIN or abs(stride) > Int.MAX // (length - 1):
        raise Error("view logical offsets exceed Int range")
    return abs(stride) * (length - 1)


struct MatrixView[
    mut: Bool, //, T: AnyType, origin: Origin[mut=mut]
](ImplicitlyCopyable, Sized):
    var data: Pointer[Self.T, Self.origin]
    var rows: Int
    var columns: Int
    var row_stride: Int
    var column_stride: Int

    def __init__(
        out self, *, unsafe_ptr: Pointer[Self.T, Self.origin], rows: Int,
        columns: Int, row_stride: Int, column_stride: Int = 1,
    ) raises:
        if rows < 0 or columns < 0:
            raise Error("matrix dimensions must be non-negative")
        if rows != 0 and columns > Int.MAX // rows:
            raise Error("matrix logical element count exceeds Int range")
        var row_extent = _strided_extent_magnitude(rows, row_stride)
        var column_extent = _strided_extent_magnitude(
            columns, column_stride
        )
        if column_extent > Int.MAX - row_extent:
            raise Error("matrix logical offsets exceed Int range")
        self.data = unsafe_ptr
        self.rows = rows
        self.columns = columns
        self.row_stride = row_stride
        self.column_stride = column_stride

    def __len__(self) -> Int:
        return self.rows * self.columns

    def __getitem__(self, row: Int, column: Int) -> ref[Self.origin] Self.T:
        check_bounds(row, self.rows)
        check_bounds(column, self.columns)
        return self.data[unsafe_offset=row * self.row_stride + column * self.column_stride]


struct SplitComplexSpan[
    dtype: DType, //, real_origin: MutOrigin, imag_origin: MutOrigin,
](ImplicitlyCopyable, Sized):
    var real: Pointer[Scalar[Self.dtype], Self.real_origin]
    var imag: Pointer[Scalar[Self.dtype], Self.imag_origin]
    var length: Int
    var stride: Int

    def __init__(
        out self, *, real_ptr: Pointer[Scalar[Self.dtype], Self.real_origin],
        imag_ptr: Pointer[Scalar[Self.dtype], Self.imag_origin], length: Int,
        stride: Int = 1,
    ) raises:
        if length < 0 or stride == 0:
            raise Error("split-complex length must be non-negative and stride non-zero")
        _ = _strided_extent_magnitude(length, stride)
        self.real = real_ptr
        self.imag = imag_ptr
        self.length = length
        self.stride = stride

    def __len__(self) -> Int:
        return self.length

    def load(self, index: Int) -> Complex[Self.dtype]:
        check_bounds(index, self.length)
        return Complex[Self.dtype](
            self.real[unsafe_offset=index * self.stride],
            self.imag[unsafe_offset=index * self.stride],
        )

    def store(self, index: Int, value: Complex[Self.dtype]):
        check_bounds(index, self.length)
        self.real.unsafe_store(index * self.stride, value.re)
        self.imag.unsafe_store(index * self.stride, value.im)


struct ComplexSpan[
    dtype: DType, //, origin: MutOrigin,
](ImplicitlyCopyable, Sized):
    """Mutable interleaved-IQ view with an explicit complex-element stride."""

    var data: Pointer[Complex[Self.dtype], Self.origin]
    var length: Int
    var stride: Int

    def __init__(
        out self,
        *,
        unsafe_ptr: Pointer[Complex[Self.dtype], Self.origin],
        length: Int,
        stride: Int = 1,
    ) raises:
        if length < 0 or stride == 0:
            raise Error("complex span length must be non-negative and stride non-zero")
        _ = _strided_extent_magnitude(length, stride)
        self.data = unsafe_ptr
        self.length = length
        self.stride = stride

    def __len__(self) -> Int:
        return self.length

    def load(self, index: Int) -> Complex[Self.dtype]:
        check_bounds(index, self.length)
        return self.data[unsafe_offset=index * self.stride]

    def store(self, index: Int, value: Complex[Self.dtype]):
        check_bounds(index, self.length)
        self.data[unsafe_offset=index * self.stride] = value


struct IQBuffer[dtype: DType](Movable, Sized):
    """Owned interleaved complex samples with explicit alignment metadata.

    ``List`` owns the storage; ``alignment_bytes`` is descriptive contract and
    checkpoint metadata.  It does not claim that ``List`` used a custom
    over-aligned allocator.  A downstream kernel that requires more than the
    platform's natural ``List`` alignment must validate or copy the storage.
    """

    var samples: List[Complex[Self.dtype]]
    var alignment_bytes: Int

    def __init__(
        out self,
        var samples: List[Complex[Self.dtype]],
        alignment_bytes: Int = 1,
    ) raises:
        if (
            alignment_bytes < 1
            or (alignment_bytes & (alignment_bytes - 1)) != 0
        ):
            raise Error("IQ buffer alignment must be a positive power of two")
        self.samples = samples^
        self.alignment_bytes = alignment_bytes

    def __len__(self) -> Int:
        return len(self.samples)

    def load(self, index: Int) -> Complex[Self.dtype]:
        check_bounds(index, len(self.samples))
        return self.samples[index]

    def store(mut self, index: Int, value: Complex[Self.dtype]):
        check_bounds(index, len(self.samples))
        self.samples[index] = value


struct BitSpan[
    origin: MutOrigin, //,
](ImplicitlyCopyable, Sized):
    """Bit-packed view with explicit bit offset and LSB/MSB-first ordering."""
    var data: Pointer[UInt8, Self.origin]
    var bit_length: Int
    var bit_offset: Int
    var lsb_first: Bool

    def __init__(
        out self, *, unsafe_ptr: Pointer[UInt8, Self.origin], bit_length: Int,
        bit_offset: Int = 0, lsb_first: Bool = True,
    ) raises:
        if bit_length < 0 or bit_offset < 0:
            raise Error("bit span length and offset must be non-negative")
        if bit_length > Int.MAX - bit_offset:
            raise Error("bit span offset plus length exceeds Int range")
        self.data = unsafe_ptr
        self.bit_length = bit_length
        self.bit_offset = bit_offset
        self.lsb_first = lsb_first

    def __len__(self) -> Int:
        return self.bit_length

    def __getitem__(self, index: Int) -> UInt8:
        check_bounds(index, self.bit_length)
        var absolute = self.bit_offset + index
        var within = absolute % 8
        var shift = within if self.lsb_first else 7 - within
        return (self.data[unsafe_offset=absolute // 8] >> UInt8(shift)) & 1

    def set(self, index: Int, value: UInt8) raises:
        check_bounds(index, self.bit_length)
        if value > 1:
            raise Error("bit value must be zero or one")
        var absolute = self.bit_offset + index
        var within = absolute % 8
        var shift = within if self.lsb_first else 7 - within
        var mask = UInt8(1) << UInt8(shift)
        var byte_index = absolute // 8
        var current = self.data[unsafe_offset=byte_index]
        if value == 1:
            self.data.unsafe_store(byte_index, current | mask)
        else:
            self.data.unsafe_store(byte_index, current & ~mask)


struct LLRBuffer(Movable):
    """Owned quantized LLRs with a finite positive scale and symmetric clip."""
    var values: List[Int]
    var scale: Float64
    var clip: Int

    def __init__(out self, var values: List[Int], scale: Float64, clip: Int) raises:
        if not isfinite(scale) or scale <= 0.0 or clip < 1:
            raise Error("LLR scale must be finite and positive; clip must be positive")
        for value in values:
            if value < -clip or value > clip:
                raise Error("LLR value exceeds declared clip")
        self.values = values^
        self.scale = scale
        self.clip = clip

    def dequantize(self) -> List[Float64]:
        var result = List[Float64](capacity=len(self.values))
        for value in self.values:
            result.append(Float64(value) / self.scale)
        return result^
