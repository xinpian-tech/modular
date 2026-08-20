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
# ===----------------------------------------------------------------------=== #
# SAXPY on the T1 RVV accelerator, written the standard Mojo way:
# DeviceContext + enqueue_create_buffer + enqueue_function + map_to_host.
# ===----------------------------------------------------------------------=== #

from max.gpu.host import DeviceContext
from std.sys.info import simd_width_of
from t1 import api, target


def saxpy(
    x: Pointer[Float32, MutAnyOrigin],
    y: Pointer[Float32, MutAnyOrigin],
    out_ptr: Pointer[Float32, MutAnyOrigin],
    a: Float32,
    n: Int32,
):
    comptime W = simd_width_of[DType.float32]()
    var i: Int = 0
    while i + W <= Int(n):
        var xv = x.unsafe_load[width=W](i)
        var yv = y.unsafe_load[width=W](i)
        out_ptr.unsafe_store(i, xv * a + yv)
        i += W
    while i < Int(n):
        out_ptr.unsafe_store(i, x.unsafe_load(i) * a + y.unsafe_load(i))
        i += 1


def main() raises:
    comptime n = 64
    var a = Float32(2.5)

    var ctx = DeviceContext(api=api)
    print("device:", ctx.name(), "api:", ctx.api())

    var x = ctx.enqueue_create_buffer[DType.float32](n)
    var y = ctx.enqueue_create_buffer[DType.float32](n)
    var out = ctx.enqueue_create_buffer[DType.float32](n)

    with x.map_to_host() as hx:
        for i in range(n):
            hx[i] = Float32(i)
    with y.map_to_host() as hy:
        for i in range(n):
            hy[i] = Float32(100 + i)

    var kernel = ctx.compile_function[saxpy, target=target()]()

    @__parameter
    @__copy_capture(x, y, out, a)
    def launch() raises:
        ctx.enqueue_function(
            kernel,
            x, y, out, a, Int32(n), grid_dim=1, block_dim=1
        )

    var cycles = ctx.execution_time[launch](1)

    ctx.synchronize()

    var bad = 0
    with out.map_to_host() as ho:
        for i in range(n):
            var want = a * Float32(i) + Float32(100 + i)
            if ho[i] != want:
                if bad < 5:
                    print("MISMATCH [", i, "]: got", ho[i], "want", want)
                bad += 1
    if bad != 0:
        raise Error("SAXPY mismatches: " + String(bad))
    print("SAXPY OK on T1 (standard Mojo): n =", n, ", kernel cycles =", cycles)
