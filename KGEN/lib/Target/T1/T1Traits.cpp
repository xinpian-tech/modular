//===----------------------------------------------------------------------===//
// Copyright (c) 2026, Xinpian Tech. All rights reserved.
//
// Licensed under the Apache License v2.0 with LLVM Exceptions:
// https://llvm.org/LICENSE.txt
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

#include "Target/T1/T1Traits.h"

namespace M::KGEN {

const T1Traits &T1Traits::get() {
  static const T1Traits instance;
  return instance;
}

namespace {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wglobal-constructors"
RegisterTargetTraits<T1Traits> registerT1Traits;
#pragma GCC diagnostic pop
} // namespace

} // namespace M::KGEN
