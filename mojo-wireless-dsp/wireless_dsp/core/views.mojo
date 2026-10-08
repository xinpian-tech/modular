"""Non-owning views used at kernel boundaries."""

from std.collections import check_bounds


@always_inline
def _strided_extent_fits(length: Int, stride: Int) -> Bool:
    """Return whether every logical strided offset fits in ``Int``."""
    if length <= 1:
        return True
    if stride == Int.MIN:
        return False
    return abs(stride) <= Int.MAX // (length - 1)


struct StridedSpan[
    mut: Bool,
    //,
    T: AnyType,
    origin: Origin[mut=mut],
](ImplicitlyCopyable, Sized):
    """A lifetime-tracked non-owning one-dimensional strided view.

    Stride is measured in elements. A negative stride is valid when ``data``
    points at the first logical element. Construction is intentionally marked
    unsafe because the caller owns the proof that all addressed elements are
    within one live allocation.
    """

    var data: Pointer[Self.T, Self.origin]
    var length: Int
    var stride: Int

    @always_inline
    def __init__(
        out self,
        *,
        unsafe_ptr: Pointer[Self.T, Self.origin],
        length: Int,
        stride: Int,
    ) raises:
        if length < 0:
            raise Error("StridedSpan length must be non-negative")
        if stride == 0:
            raise Error("StridedSpan stride must be non-zero")
        if not _strided_extent_fits(length, stride):
            raise Error("StridedSpan logical offsets exceed Int range")
        self.data = unsafe_ptr
        self.length = length
        self.stride = stride

    @always_inline
    def __len__(self) -> Int:
        return self.length

    @always_inline
    def __getitem__(self, index: Int) -> ref[Self.origin] Self.T:
        check_bounds(index, self.length)
        return self.data[unsafe_offset=index * self.stride]
