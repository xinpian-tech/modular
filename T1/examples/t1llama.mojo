# ===----------------------------------------------------------------------=== #
# Copyright (c) 2026, Xinpian Tech. All rights reserved.
#
# Licensed under the Apache License v2.0 with LLVM Exceptions:
# https://llvm.org/LICENSE.txt
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ===----------------------------------------------------------------------=== #
# Llama-architecture inference (llama2.c .bin format) written entirely in
# Mojo, with every transformer computation executed on the T1 RVV
# accelerator through the standard DeviceContext API.
#
# Works for any llama2.c legacy-format model; validated against llama2.c
# run.c (greedy) with:
#   - karpathy/tinyllamas stories15M
#   - TinyLlama/TinyLlama-1.1B-Chat-v1.0 (converted with a numpy exporter)
#
# Weights are streamed from disk one layer per launch (the device window
# cannot hold 1.1B fp32 parameters at once); the residual stream, the KV
# cache, and the logits live in device buffers across launches.
#
#   mojo build --target-accelerator=t1 t1llama.mojo -o t1llama
#   ./t1llama model.bin tokenizer.bin "prompt" 12
# ===----------------------------------------------------------------------=== #

from max.gpu.host import DeviceContext, DeviceBuffer
from std.collections import Dict
from std.io.file import FileHandle
from std.math import cos, exp, log, sin, sqrt
from std.sys import argv, inlined_assembly
from std.sys.info import simd_width_of
from std.time import perf_counter_ns

comptime F32Ptr = Pointer[Float32, MutAnyOrigin]
comptime I32Ptr = Pointer[Int32, MutAnyOrigin]


# ===----------------------------------------------------------------------=== #
# Device kernels
# ===----------------------------------------------------------------------=== #


comptime _VCLOB2 = (
    "~{v0},~{v1},~{v2},~{v3},~{v4},~{v5},~{v6},~{v7},~{v8},~{v9},~{v10},"
    "~{v11},~{v12},~{v13},~{v14},~{v15},~{v16},~{v17},~{v18},~{v19},~{v20},"
    "~{v21},~{v22},~{v23},~{v24},~{v25},~{v26},~{v27},~{v28},~{v29},~{v30},"
    "~{v31},~{t0},~{t1},~{t2},~{t3},~{t4},~{t5},~{t6},~{a4},~{a5},~{s2},"
    "~{s3},~{s4},~{s5},~{s6},~{s7},~{ft0},~{memory}"
)

comptime _VCLOB = (
    "~{v0},~{v1},~{v2},~{v3},~{v4},~{v5},~{v6},~{v7},~{v8},~{v9},~{v10},"
    "~{v11},~{v12},~{v13},~{v14},~{v15},~{v16},~{v17},~{v18},~{v19},~{v20},"
    "~{v21},~{v22},~{v23},~{v24},~{v25},~{v26},~{v27},~{v28},~{v29},~{v30},"
    "~{v31},~{t0},~{t1},~{t2},~{t3},~{t4},~{t5},~{t6},~{ft0},~{memory}"
)


# Four rows of a row-major matvec in one hand-written RVV loop: one m4 x-chunk
# load is shared by four w rows (4x less x traffic), the strip-mined `vsetvli`
# handles any n without a scalar tail (tail-undisturbed keeps the zeroed lanes
# of the accumulators intact), and each row ends in a single *unordered*
# `vfredusum` instead of the log2 slide/add tree the generic reduction lowers
# to.  VLEN=2048: m4 = 256 f32 lanes per group.
@always_inline
def _mv(w: F32Ptr, x: F32Ptr, n: Int, rows: Int, out_ptr: F32Ptr):
    """All full 6-row groups of a row-major matvec in one asm block: the row
    loop lives inside the asm (no per-group call glue), six m4 accumulators
    share each x chunk load, the first chunk initializes accumulators with
    `vfmul` (no zero-fill), full chunks run under a hoisted vl and the tail
    is one `tu` chunk.  Contract: n >= 256, rows >= 6 (caller handles the
    row remainder with `_mv1`)."""
    inlined_assembly[
        """
        mv s2, $3
        mv s3, $0
        mv s4, $1
        mv s5, $4
        slli s6, $2, 2
        li s7, 6
        li t0, 256
        vsetvli zero, t0, e32, m4, ta, ma
        4:
        mv t2, s4
        mv t3, s3
        add t4, t3, s6
        add t5, t4, s6
        add t6, t5, s6
        add a4, t6, s6
        add a5, a4, s6
        add s3, a5, s6
        mv t1, $2
        vle32.v v4, (t2)
        vle32.v v0, (t3)
        vfmul.vv v8, v4, v0
        vle32.v v0, (t4)
        vfmul.vv v12, v4, v0
        vle32.v v0, (t5)
        vfmul.vv v16, v4, v0
        vle32.v v0, (t6)
        vfmul.vv v20, v4, v0
        vle32.v v0, (a4)
        vfmul.vv v24, v4, v0
        vle32.v v0, (a5)
        vfmul.vv v28, v4, v0
        addi t1, t1, -256
        addi t2, t2, 1024
        addi t3, t3, 1024
        addi t4, t4, 1024
        addi t5, t5, 1024
        addi t6, t6, 1024
        addi a4, a4, 1024
        addi a5, a5, 1024
        bltu t1, t0, 2f
        1:
        vle32.v v4, (t2)
        vle32.v v0, (t3)
        vfmacc.vv v8, v4, v0
        vle32.v v0, (t4)
        vfmacc.vv v12, v4, v0
        vle32.v v0, (t5)
        vfmacc.vv v16, v4, v0
        vle32.v v0, (t6)
        vfmacc.vv v20, v4, v0
        vle32.v v0, (a4)
        vfmacc.vv v24, v4, v0
        vle32.v v0, (a5)
        vfmacc.vv v28, v4, v0
        addi t1, t1, -256
        addi t2, t2, 1024
        addi t3, t3, 1024
        addi t4, t4, 1024
        addi t5, t5, 1024
        addi t6, t6, 1024
        addi a4, a4, 1024
        addi a5, a5, 1024
        bgeu t1, t0, 1b
        2:
        beqz t1, 3f
        vsetvli t0, t1, e32, m4, tu, ma
        vle32.v v4, (t2)
        vle32.v v0, (t3)
        vfmacc.vv v8, v4, v0
        vle32.v v0, (t4)
        vfmacc.vv v12, v4, v0
        vle32.v v0, (t5)
        vfmacc.vv v16, v4, v0
        vle32.v v0, (t6)
        vfmacc.vv v20, v4, v0
        vle32.v v0, (a4)
        vfmacc.vv v24, v4, v0
        vle32.v v0, (a5)
        vfmacc.vv v28, v4, v0
        li t0, 256
        vsetvli zero, t0, e32, m4, ta, ma
        3:
        vmv.s.x v4, zero
        li t0, 128
        vsetvli zero, t0, e32, m2, ta, ma
        vfadd.vv v8, v8, v10
        vfadd.vv v12, v12, v14
        vfadd.vv v16, v16, v18
        vfadd.vv v20, v20, v22
        vfadd.vv v24, v24, v26
        vfadd.vv v28, v28, v30
        li t0, 64
        vsetvli zero, t0, e32, m1, ta, ma
        vfadd.vv v8, v8, v9
        vfadd.vv v12, v12, v13
        vfadd.vv v16, v16, v17
        vfadd.vv v20, v20, v21
        vfadd.vv v24, v24, v25
        vfadd.vv v28, v28, v29
        vfredusum.vs v0, v8, v4
        vfredusum.vs v1, v12, v4
        vfredusum.vs v2, v16, v4
        vfredusum.vs v3, v20, v4
        vfredusum.vs v5, v24, v4
        vfredusum.vs v6, v28, v4
        vsetivli zero, 2, e32, m1, tu, ma
        vslideup.vi v0, v1, 1
        vsetivli zero, 3, e32, m1, tu, ma
        vslideup.vi v0, v2, 2
        vsetivli zero, 4, e32, m1, tu, ma
        vslideup.vi v0, v3, 3
        vsetivli zero, 5, e32, m1, tu, ma
        vslideup.vi v0, v5, 4
        vsetivli zero, 6, e32, m1, tu, ma
        vslideup.vi v0, v6, 5
        vse32.v v0, (s5)
        li t0, 256
        vsetvli zero, t0, e32, m4, ta, ma
        addi s5, s5, 24
        addi s2, s2, -6
        bgeu s2, s7, 4b
        """,
        NoneType,
        constraints="r,r,r,r,r," + _VCLOB2,
    ](w, x, n, rows, out_ptr)


@always_inline
def _mv1(w: F32Ptr, x: F32Ptr, n: Int, out_ptr: F32Ptr):
    """Single-row remainder of `_matvec`; same n >= 256 contract as `_mv4`."""
    inlined_assembly[
        """
        mv t1, $2
        mv t2, $1
        mv t3, $0
        li t0, 256
        vsetvli zero, t0, e32, m4, ta, ma
        vmv.s.x v1, zero
        vle32.v v4, (t2)
        vle32.v v24, (t3)
        vfmul.vv v8, v4, v24
        addi t1, t1, -256
        addi t2, t2, 1024
        addi t3, t3, 1024
        bltu t1, t0, 2f
        1:
        vle32.v v4, (t2)
        vle32.v v24, (t3)
        vfmacc.vv v8, v4, v24
        addi t1, t1, -256
        addi t2, t2, 1024
        addi t3, t3, 1024
        bgeu t1, t0, 1b
        2:
        beqz t1, 3f
        vsetvli t0, t1, e32, m4, tu, ma
        vle32.v v4, (t2)
        vle32.v v24, (t3)
        vfmacc.vv v8, v4, v24
        li t0, 256
        vsetvli zero, t0, e32, m4, ta, ma
        3:
        li t0, 128
        vsetvli zero, t0, e32, m2, ta, ma
        vfadd.vv v8, v8, v10
        li t0, 64
        vsetvli zero, t0, e32, m1, ta, ma
        vfadd.vv v8, v8, v9
        vfredusum.vs v0, v8, v1
        vfmv.f.s ft0, v0
        fsw ft0, 0($3)
        """,
        NoneType,
        constraints="r,r,r,r," + _VCLOB,
    ](w, x, n, out_ptr)


@always_inline
def _matvec(out_ptr: F32Ptr, w: F32Ptr, x: F32Ptr, m: Int, n: Int):
    """out[i] = dot(w[i, :], x) for a row-major w[m, n] (n >= 256)."""
    var groups = m - m % 6
    if groups > 0:
        _mv(w, x, n, groups, out_ptr)
    var i = groups
    while i < m:
        _mv1(w.unsafe_offset(i * n), x, n, out_ptr.unsafe_offset(i))
        i += 1


# dot(a[0..n), b[0..n)) for n <= 64 lanes (one m1 register at VLEN=2048).
@always_inline
def _dot(a: F32Ptr, b: F32Ptr, n: Int) -> Float32:
    return inlined_assembly[
        """
        vsetvli t0, $3, e32, m1, ta, ma
        vle32.v v8, ($1)
        vle32.v v9, ($2)
        vfmul.vv v8, v8, v9
        vmv.s.x v10, zero
        vfredusum.vs v10, v8, v10
        vfmv.f.s $0, v10
        """,
        Float32,
        constraints="=f,r,r,r," + _VCLOB,
    ](a, b, n)


# acc[0..n) += a * v[0..n) for n <= 64.
@always_inline
def _axpy(acc: F32Ptr, v: F32Ptr, a: Float32, n: Int):
    inlined_assembly[
        """
        vsetvli t0, $3, e32, m1, ta, ma
        vle32.v v8, ($1)
        vle32.v v9, ($0)
        vfmacc.vf v9, $2, v8
        vse32.v v9, ($0)
        """,
        NoneType,
        constraints="r,r,f,r," + _VCLOB,
    ](acc, v, a, n)


# acc[0..n) = a * v[0..n) (first position: no read, no zero-fill).
@always_inline
def _axpy_first(acc: F32Ptr, v: F32Ptr, a: Float32, n: Int):
    inlined_assembly[
        """
        vsetvli t0, $3, e32, m1, ta, ma
        vle32.v v8, ($1)
        vfmul.vf v8, v8, $2
        vse32.v v8, ($0)
        """,
        NoneType,
        constraints="r,r,f,r," + _VCLOB,
    ](acc, v, a, n)


# Strip-mined m8 sum of squares (unordered reduce).
@always_inline
def _ssq(x: F32Ptr, n: Int) -> Float32:
    return inlined_assembly[
        """
        li t0, 512
        vsetvli zero, t0, e32, m8, ta, ma
        vmv.v.i v8, 0
        mv t1, $2
        mv t2, $1
        1:
        vsetvli t0, t1, e32, m8, tu, ma
        vle32.v v16, (t2)
        vfmacc.vv v8, v16, v16
        slli t0, t0, 2
        add t2, t2, t0
        srli t0, t0, 2
        sub t1, t1, t0
        bnez t1, 1b
        li t0, 512
        vsetvli zero, t0, e32, m8, ta, ma
        vmv.s.x v0, zero
        vfredusum.vs v0, v8, v0
        vfmv.f.s $0, v0
        """,
        Float32,
        constraints="=f,r,r," + _VCLOB,
    ](x, n)


# out[j] = g[j] * (x[j] * inv), strip-mined m8.
@always_inline
def _scale(out_ptr: F32Ptr, x: F32Ptr, g: F32Ptr, inv: Float32, n: Int):
    inlined_assembly[
        """
        mv t1, $4
        mv t2, $1
        mv t3, $2
        mv t4, $0
        1:
        vsetvli t0, t1, e32, m8, ta, ma
        vle32.v v8, (t2)
        vle32.v v16, (t3)
        vfmul.vf v8, v8, $3
        vfmul.vv v8, v8, v16
        vse32.v v8, (t4)
        slli t0, t0, 2
        add t2, t2, t0
        add t3, t3, t0
        add t4, t4, t0
        srli t0, t0, 2
        sub t1, t1, t0
        bnez t1, 1b
        """,
        NoneType,
        constraints="r,r,r,f,r," + _VCLOB,
    ](out_ptr, x, g, inv, n)


# x[i] += r[i], strip-mined m8.
@always_inline
def _vadd(x: F32Ptr, r: F32Ptr, n: Int):
    inlined_assembly[
        """
        mv t1, $2
        mv t2, $0
        mv t3, $1
        1:
        vsetvli t0, t1, e32, m8, ta, ma
        vle32.v v8, (t2)
        vle32.v v16, (t3)
        vfadd.vv v8, v8, v16
        vse32.v v8, (t2)
        slli t0, t0, 2
        add t2, t2, t0
        add t3, t3, t0
        srli t0, t0, 2
        sub t1, t1, t0
        bnez t1, 1b
        """,
        NoneType,
        constraints="r,r,r," + _VCLOB,
    ](x, r, n)


@always_inline
def _rmsnorm(out_ptr: F32Ptr, x: F32Ptr, g: F32Ptr, n: Int):
    var ss = _ssq(x, n)
    var inv = Float32(1.0) / sqrt(ss / Float32(n) + Float32(1e-5))
    _scale(out_ptr, x, g, inv, n)


# Rotate one head's (even, odd) pairs by (cos, sin): segment loads split the
# interleaved pairs, `rope` is interleaved (cos, sin) per pair.  hs/2 <= 32.
@always_inline
def _rope_head(q: F32Ptr, rope: F32Ptr, hs: Int):
    inlined_assembly[
        """
        srli t1, $2, 1
        vsetvli t0, t1, e32, m1, ta, ma
        vlseg2e32.v v8, ($1)
        vlseg2e32.v v10, ($0)
        vfmul.vv v12, v10, v8
        vfmul.vv v13, v11, v9
        vfsub.vv v12, v12, v13
        vfmul.vv v14, v10, v9
        vfmul.vv v15, v11, v8
        vfadd.vv v13, v14, v15
        vmv.v.v v10, v12
        vmv.v.v v11, v13
        vsseg2e32.v v10, ($0)
        """,
        NoneType,
        constraints="r,r,r," + _VCLOB,
    ](q, rope, hs)


def t1_layer(hdr: I32Ptr, rope: F32Ptr, x: F32Ptr, w: F32Ptr, kv: F32Ptr, sc: F32Ptr):
    """One transformer layer for one token position.

    hdr:  [pos, dim, hidden, n_heads, n_kv_heads, head_size, seq_cap, vocab]
    rope: [head_size] floats: cos/sin interleaved for the current position
    x:    [dim] residual stream (device resident across launches)
    w:    this layer's weights: rms_att, wq, wk, wv, wo, rms_ffn, w1, w2, w3
    kv:   this layer's cache: k[seq_cap][kv_dim] then v[seq_cap][kv_dim]
    sc:   scratch: xb[dim], q[dim], hb[hidden], hb2[hidden], att[seq_cap]
    """
    comptime W = simd_width_of[DType.float32]()
    var pos = Int(hdr.unsafe_load(0))
    var dim = Int(hdr.unsafe_load(1))
    var hidden = Int(hdr.unsafe_load(2))
    var n_heads = Int(hdr.unsafe_load(3))
    var n_kv = Int(hdr.unsafe_load(4))
    var hs = Int(hdr.unsafe_load(5))
    var seq_cap = Int(hdr.unsafe_load(6))
    var kv_dim = n_kv * hs
    var kv_mul = n_heads // n_kv

    var o_wq = dim
    var o_wk = o_wq + dim * dim
    var o_wv = o_wk + kv_dim * dim
    var o_wo = o_wv + kv_dim * dim
    var o_rms_ffn = o_wo + dim * dim
    var o_w1 = o_rms_ffn + dim
    var o_w2 = o_w1 + hidden * dim
    var o_w3 = o_w2 + dim * hidden

    var xb = sc
    var q = sc.unsafe_offset(dim)
    var hb = sc.unsafe_offset(2 * dim)
    var hb2 = sc.unsafe_offset(2 * dim + hidden)
    var att = sc.unsafe_offset(2 * dim + 2 * hidden)

    var krow = kv.unsafe_offset(pos * kv_dim)
    var vbase = kv.unsafe_offset(seq_cap * kv_dim)

    # Attention block.
    _rmsnorm(xb, x, w, dim)
    _matvec(q, w.unsafe_offset(o_wq), xb, dim, dim)
    _matvec(krow, w.unsafe_offset(o_wk), xb, kv_dim, dim)
    _matvec(vbase.unsafe_offset(pos * kv_dim), w.unsafe_offset(o_wv), xb, kv_dim, dim)

    # RoPE: rotate adjacent pairs (llama2.c convention), one head at a time
    # via segment loads (the rope buffer is interleaved cos/sin per pair).
    var h0 = 0
    while h0 < n_heads:
        _rope_head(q.unsafe_offset(h0 * hs), rope, hs)
        h0 += 1
    h0 = 0
    while h0 < n_kv:
        _rope_head(krow.unsafe_offset(h0 * hs), rope, hs)
        h0 += 1

    var scale = Float32(1.0) / sqrt(Float32(hs))
    var h = 0
    while h < n_heads:
        var qo = h * hs
        var kvo = (h // kv_mul) * hs
        # Scores (vector dot per cached position).
        var t = 0
        while t <= pos:
            var s = _dot(
                q.unsafe_offset(qo), kv.unsafe_offset(t * kv_dim + kvo), hs
            )
            att.unsafe_store(t, s * scale)
            t += 1
        # Softmax over att[0..=pos].
        var mx = att.unsafe_load(0)
        t = 1
        while t <= pos:
            var a = att.unsafe_load(t)
            if a > mx:
                mx = a
            t += 1
        var sum = Float32(0)
        t = 0
        while t <= pos:
            var e = exp(att.unsafe_load(t) - mx)
            att.unsafe_store(t, e)
            sum += e
            t += 1
        var isum = Float32(1.0) / sum
        # Weighted sum of values into xb[head]: the first position writes
        # (no zero-fill pass), the rest accumulate.
        _axpy_first(
            xb.unsafe_offset(qo), vbase.unsafe_offset(kvo),
            att.unsafe_load(0) * isum, hs,
        )
        t = 1
        while t <= pos:
            var a = att.unsafe_load(t) * isum
            _axpy(
                xb.unsafe_offset(qo),
                vbase.unsafe_offset(t * kv_dim + kvo),
                a, hs,
            )
            t += 1
        h += 1

    # Output projection + residual (q reused as temporary).
    _matvec(q, w.unsafe_offset(o_wo), xb, dim, dim)
    _vadd(x, q, dim)

    # FFN: SwiGLU.
    _rmsnorm(xb, x, w.unsafe_offset(o_rms_ffn), dim)
    _matvec(hb, w.unsafe_offset(o_w1), xb, hidden, dim)
    _matvec(hb2, w.unsafe_offset(o_w3), xb, hidden, dim)
    var j = 0
    while j + W <= hidden:
        var g = hb.unsafe_load[width=W](j)
        var u = hb2.unsafe_load[width=W](j)
        var s = g / (SIMD[DType.float32, W](1) + exp(-g))
        hb.unsafe_store(j, s * u)
        j += W
    while j < hidden:
        var g = hb.unsafe_load(j)
        hb.unsafe_store(j, g / (Float32(1) + exp(-g)) * hb2.unsafe_load(j))
        j += 1
    _matvec(xb, w.unsafe_offset(o_w2), hb, dim, hidden)
    _vadd(x, xb, dim)


def t1_head(hdr: I32Ptr, x: F32Ptr, w: F32Ptr, logits: F32Ptr, sc: F32Ptr):
    """Final RMSNorm + classifier matvec. w = rms_final[dim], wcls[vocab*dim]."""
    var dim = Int(hdr.unsafe_load(1))
    var vocab = Int(hdr.unsafe_load(7))
    _rmsnorm(sc, x, w, dim)
    _matvec(logits, w.unsafe_offset(dim), sc, vocab, dim)


# ===----------------------------------------------------------------------=== #
# Host side
# ===----------------------------------------------------------------------=== #


def _read_i32(b: Pointer[UInt8, _], off: Int) -> Int32:
    var u = (
        UInt32(Int(b[off]))
        | (UInt32(Int(b[off + 1])) << 8)
        | (UInt32(Int(b[off + 2])) << 16)
        | (UInt32(Int(b[off + 3])) << 24)
    )
    return Int32(from_bits=u)


def _read_f32(b: Pointer[UInt8, _], off: Int) -> Float32:
    var u = (
        UInt32(Int(b[off]))
        | (UInt32(Int(b[off + 1])) << 8)
        | (UInt32(Int(b[off + 2])) << 16)
        | (UInt32(Int(b[off + 3])) << 24)
    )
    return Float32(from_bits=u)


def _read_full(f: FileHandle, ptr: Pointer[mut=True, Float32, _], n: Int) raises:
    """Reads exactly n Float32 elements at the current file position."""
    var got = 0
    while got < n:
        var bytes_read = f.read(
            Span(unsafe_ptr=ptr.unsafe_offset(got), length=n - got)
        )
        if bytes_read == 0:
            raise Error("t1llama: unexpected EOF in model file")
        got += bytes_read // 4


@fieldwise_init
struct Config(Copyable, Movable):
    var dim: Int
    var hidden: Int
    var n_layers: Int
    var n_heads: Int
    var n_kv: Int
    var vocab: Int
    var seq_len: Int
    var shared_classifier: Bool
    var head_size: Int
    var kv_dim: Int


struct Tokenizer:
    var pieces: List[String]
    var scores: List[Float32]
    var lookup: Dict[String, Int]

    def __init__(out self, path: String) raises:
        self.pieces = List[String]()
        self.scores = List[Float32]()
        self.lookup = Dict[String, Int]()
        var raw = open(path, "r").read_bytes()
        var b = raw.unsafe_ptr()
        var off = 4  # skip max_token_length
        var idx = 0
        while off < len(raw):
            var score = _read_f32(b, off)
            var n = Int(_read_i32(b, off + 4))
            off += 8
            var piece = String(
                StringSlice(
                    unsafe_from_utf8=Span(unsafe_ptr=b.unsafe_offset(off), length=n)
                )
            )
            off += n
            self.scores.append(score)
            self.pieces.append(piece)
            self.lookup[piece] = idx
            idx += 1

    def find(self, s: String) -> Int:
        try:
            return self.lookup[s]
        except:
            return -1

    def encode(self, text: String) -> List[Int]:
        """BOS + sentencepiece-style BPE, ported from llama2.c encode()."""
        var toks = List[Int]()
        toks.append(1)  # BOS
        if text.byte_length() == 0:
            return toks^
        var dummy = self.find(" ")
        if dummy >= 0:
            toks.append(dummy)
        var tb = text.as_bytes()
        var i = 0
        while i < len(tb):
            # Group one UTF-8 codepoint.
            var j = i + 1
            while j < len(tb) and (Int(tb[j]) & 0xC0) == 0x80 and j - i < 4:
                j += 1
            var cp = String(
                StringSlice(
                    unsafe_from_utf8=Span(
                        unsafe_ptr=tb.unsafe_ptr().unsafe_offset(i), length=j - i
                    )
                )
            )
            var id = self.find(cp)
            if id >= 0:
                toks.append(id)
            else:
                var k = i
                while k < j:
                    toks.append(Int(tb[k]) + 3)  # byte-fallback tokens
                    k += 1
            i = j
        # Merge loop: repeatedly fuse the best-scoring adjacent pair.
        while True:
            var best_score = Float32(-1e10)
            var best_id = -1
            var best_idx = -1
            var t = 0
            while t + 1 < len(toks):
                var merged = self.pieces[toks[t]] + self.pieces[toks[t + 1]]
                var id = self.find(merged)
                if id >= 0 and self.scores[id] > best_score:
                    best_score = self.scores[id]
                    best_id = id
                    best_idx = t
                t += 1
            if best_idx < 0:
                break
            toks[best_idx] = best_id
            _ = toks.pop(best_idx + 1)
        return toks^

    def decode(self, prev: Int, token: Int) -> String:
        var piece = self.pieces[token]
        if prev == 1 and piece.startswith(" "):
            var trimmed = String(piece[byte=1:])
            piece = trimmed^
        # Raw-byte tokens are stored as "<0xXX>".
        if (
            piece.byte_length() == 6
            and piece.startswith("<0x")
            and piece.endswith(">")
        ):
            var hex = String(piece[byte=3:5])
            var v = 0
            for ch in hex.codepoint_slices():
                var c = Int(ord(ch))
                v = v * 16 + (
                    c - 48 if c < 58 else (c | 32) - 97 + 10
                )
            var bytes = List[UInt8]()
            bytes.append(UInt8(v))
            return String(
                StringSlice(unsafe_from_utf8=Span(bytes))
            )
        return piece


def main() raises:
    var args = argv()
    if len(args) < 3:
        print("usage: t1llama <model.bin> <tokenizer.bin> [prompt] [steps]")
        return
    var model_path = String(args[1])
    var tok_path = String(args[2])
    var prompt = String(args[3]) if len(args) > 3 else String("")
    var steps = Int(String(args[4])) if len(args) > 4 else 64

    # --- Model header -----------------------------------------------------
    var f = open(model_path, "r")
    var hdr_raw = f.read_bytes(28)
    var hb = hdr_raw.unsafe_ptr()
    var vocab_raw = Int(_read_i32(hb, 20))
    var cfg = Config(
        dim=Int(_read_i32(hb, 0)),
        hidden=Int(_read_i32(hb, 4)),
        n_layers=Int(_read_i32(hb, 8)),
        n_heads=Int(_read_i32(hb, 12)),
        n_kv=Int(_read_i32(hb, 16)),
        vocab=vocab_raw if vocab_raw > 0 else -vocab_raw,
        seq_len=Int(_read_i32(hb, 24)),
        shared_classifier=vocab_raw > 0,
        head_size=0,
        kv_dim=0,
    )
    cfg.head_size = cfg.dim // cfg.n_heads
    cfg.kv_dim = cfg.n_kv * cfg.head_size
    print(
        "t1llama:", model_path, "dim", cfg.dim, "hidden", cfg.hidden,
        "layers", cfg.n_layers, "heads", cfg.n_heads, "kv", cfg.n_kv,
        "vocab", cfg.vocab, "seq", cfg.seq_len,
    )

    var tok = Tokenizer(tok_path)
    var prompt_toks = tok.encode(prompt)
    if steps > cfg.seq_len:
        steps = cfg.seq_len
    var seq_cap = steps + 1

    # --- File offsets (bytes) of each grouped tensor ----------------------
    var L = cfg.n_layers
    var emb_off = 28
    var rms_att_off = emb_off + 4 * cfg.vocab * cfg.dim
    var wq_off = rms_att_off + 4 * L * cfg.dim
    var wk_off = wq_off + 4 * L * cfg.dim * cfg.dim
    var wv_off = wk_off + 4 * L * cfg.dim * cfg.kv_dim
    var wo_off = wv_off + 4 * L * cfg.dim * cfg.kv_dim
    var rms_ffn_off = wo_off + 4 * L * cfg.dim * cfg.dim
    var w1_off = rms_ffn_off + 4 * L * cfg.dim
    var w2_off = w1_off + 4 * L * cfg.dim * cfg.hidden
    var w3_off = w2_off + 4 * L * cfg.dim * cfg.hidden
    var rms_final_off = w3_off + 4 * L * cfg.dim * cfg.hidden
    var freq_off = rms_final_off + 4 * cfg.dim
    var wcls_off = freq_off + 4 * cfg.seq_len * cfg.head_size
    if cfg.shared_classifier:
        wcls_off = emb_off

    var layer_words = (
        cfg.dim + cfg.dim * cfg.dim + 2 * cfg.kv_dim * cfg.dim
        + cfg.dim * cfg.dim + cfg.dim + 3 * cfg.dim * cfg.hidden
    )
    var head_words = cfg.dim + cfg.vocab * cfg.dim
    var sc_words = 2 * cfg.dim + 2 * cfg.hidden + seq_cap

    # --- Device setup (standard Mojo DeviceContext API) -------------------
    var ctx = DeviceContext(api="t1")
    print("device:", ctx.name(), "api:", ctx.api())
    # The streamed weight buffers are allocated first so that the small,
    # kernel-written buffers form one compact arena range (cheap readback).
    var wl_b = ctx.enqueue_create_buffer[DType.float32](layer_words)
    var wh_b = ctx.enqueue_create_buffer[DType.float32](head_words)
    var hdr_b = ctx.enqueue_create_buffer[DType.int32](8)
    var rope_b = ctx.enqueue_create_buffer[DType.float32](cfg.head_size)
    var x_b = ctx.enqueue_create_buffer[DType.float32](cfg.dim)
    var sc_b = ctx.enqueue_create_buffer[DType.float32](sc_words)
    var logits_b = ctx.enqueue_create_buffer[DType.float32](cfg.vocab)
    var kv_bufs = List[DeviceBuffer[DType.float32]]()
    for _ in range(L):
        kv_bufs.append(
            ctx.enqueue_create_buffer[DType.float32](
                2 * seq_cap * cfg.kv_dim
            )
        )

    # Head weights never change: load them once.
    var staging = List[Float32](length=head_words, fill=0)
    var sp = staging.unsafe_ptr()
    _ = f.seek(rms_final_off)
    _read_full(f, sp, cfg.dim)
    _ = f.seek(wcls_off)
    _read_full(f, sp.unsafe_offset(cfg.dim), cfg.vocab * cfg.dim)
    wh_b.enqueue_copy_from(sp)

    var hdr_host = List[Int32](length=8, fill=0)
    hdr_host[1] = Int32(cfg.dim)
    hdr_host[2] = Int32(cfg.hidden)
    hdr_host[3] = Int32(cfg.n_heads)
    hdr_host[4] = Int32(cfg.n_kv)
    hdr_host[5] = Int32(cfg.head_size)
    hdr_host[6] = Int32(seq_cap)
    hdr_host[7] = Int32(cfg.vocab)
    var rope_host = List[Float32](length=cfg.head_size, fill=0)
    var emb_host = List[Float32](length=cfg.dim, fill=0)

    # --- Generation loop --------------------------------------------------
    print("prompt tokens:", len(prompt_toks), " steps:", steps)
    var token = prompt_toks[0]
    var pos = 0
    var out_text = String("")
    var t_start = perf_counter_ns()
    while pos < steps:
        var t0 = perf_counter_ns()

        # Embedding row -> x (host lookup, device write).
        _ = f.seek(emb_off + 4 * token * cfg.dim)
        _read_full(f, emb_host.unsafe_ptr(), cfg.dim)
        x_b.enqueue_copy_from(emb_host.unsafe_ptr())

        # Position-dependent inputs.
        hdr_host[0] = Int32(pos)
        hdr_b.enqueue_copy_from(hdr_host.unsafe_ptr())
        var hd = 0
        while hd < cfg.head_size:
            var freq = exp(
                -log(Float32(10000.0)) * Float32(hd) / Float32(cfg.head_size)
            )
            var val = Float32(pos) * freq
            rope_host[hd] = cos(val)
            rope_host[hd + 1] = sin(val)
            hd += 2
        rope_b.enqueue_copy_from(rope_host.unsafe_ptr())

        # One launch per layer; weights streamed from disk.
        for l in range(L):
            var o = 0
            _ = f.seek(rms_att_off + 4 * l * cfg.dim)
            _read_full(f, sp.unsafe_offset(o), cfg.dim)
            o += cfg.dim
            _ = f.seek(wq_off + 4 * l * cfg.dim * cfg.dim)
            _read_full(f, sp.unsafe_offset(o), cfg.dim * cfg.dim)
            o += cfg.dim * cfg.dim
            _ = f.seek(wk_off + 4 * l * cfg.dim * cfg.kv_dim)
            _read_full(f, sp.unsafe_offset(o), cfg.dim * cfg.kv_dim)
            o += cfg.dim * cfg.kv_dim
            _ = f.seek(wv_off + 4 * l * cfg.dim * cfg.kv_dim)
            _read_full(f, sp.unsafe_offset(o), cfg.dim * cfg.kv_dim)
            o += cfg.dim * cfg.kv_dim
            _ = f.seek(wo_off + 4 * l * cfg.dim * cfg.dim)
            _read_full(f, sp.unsafe_offset(o), cfg.dim * cfg.dim)
            o += cfg.dim * cfg.dim
            _ = f.seek(rms_ffn_off + 4 * l * cfg.dim)
            _read_full(f, sp.unsafe_offset(o), cfg.dim)
            o += cfg.dim
            _ = f.seek(w1_off + 4 * l * cfg.dim * cfg.hidden)
            _read_full(f, sp.unsafe_offset(o), cfg.dim * cfg.hidden)
            o += cfg.dim * cfg.hidden
            _ = f.seek(w2_off + 4 * l * cfg.dim * cfg.hidden)
            _read_full(f, sp.unsafe_offset(o), cfg.dim * cfg.hidden)
            o += cfg.dim * cfg.hidden
            _ = f.seek(w3_off + 4 * l * cfg.dim * cfg.hidden)
            _read_full(f, sp.unsafe_offset(o), cfg.dim * cfg.hidden)
            wl_b.enqueue_copy_from(sp)
            ctx.enqueue_function[t1_layer](
                hdr_b, rope_b, x_b, wl_b, kv_bufs[l], sc_b,
                grid_dim=1, block_dim=1,
            )

        ctx.enqueue_function[t1_head](
            hdr_b, x_b, wh_b, logits_b, sc_b, grid_dim=1, block_dim=1
        )
        ctx.synchronize()

        # Next token: forced while consuming the prompt, then greedy argmax.
        var next_tok: Int
        if pos + 1 < len(prompt_toks):
            next_tok = prompt_toks[pos + 1]
        else:
            var best = 0
            var best_v = Float32(-1e30)
            with logits_b.map_to_host() as hl:
                for i in range(cfg.vocab):
                    if hl[i] > best_v:
                        best_v = hl[i]
                        best = i
            next_tok = best
        if next_tok == 1:
            break

        var piece = tok.decode(token, next_tok)
        # Only generated tokens go into the transcript; forced prompt
        # tokens are already part of the prompt text.
        if pos + 1 >= len(prompt_toks):
            out_text += piece
        var ms = (perf_counter_ns() - t0) // 1_000_000
        print(
            "[pos", pos, "->", next_tok, "|", ms, "ms]", piece,
        )
        token = next_tok
        pos += 1

    var total_s = (perf_counter_ns() - t_start) // 1_000_000_000
    print("")
    print("=== T1 output ===")
    print(prompt + out_text)
    print("=== ", pos, "positions in", total_s, "s ===")
