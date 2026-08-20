//===----------------------------------------------------------------------===//
// Copyright (c) 2026, Modular Inc. All rights reserved.
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

#include "KGEN/Support/CustomDevicePlugin.h"
#include "Support/SymbolExport.h"
#include "Target/TargetTraits.h"

namespace M::KGEN {
namespace {

class TestDeviceTraits final : public TargetTraits {
public:
  llvm::StringRef name() const override { return "custom-device-test"; }
  bool matches(const llvm::Triple &) const override { return true; }
  llvm::StringRef defaultCPU(const llvm::Triple &) const override {
    return "x86-64";
  }
  llvm::StringRef getAsmExtension() const override { return ".test.s"; }
  llvm::StringRef getLLVMExtension() const override { return ".test.ll"; }
  llvm::StringRef getObjectExtension() const override { return ".test.o"; }

  llvm::StringRef acceleratorSectionTitle() const override {
    return "Custom device plugin test targets:";
  }
  llvm::ArrayRef<AcceleratorArch> supportedAcceleratorArchs() const override {
    static const AcceleratorArch archs[] = {
        {"custom-device-test", "Loaded from a dynamic device plugin"},
    };
    return archs;
  }

protected:
  bool isBaseTarget() const override { return true; }
};

} // namespace
} // namespace M::KGEN

MODULAR_EXPORT const char *M_KGEN_registerCustomDevicePlugin(
    const M::KGEN::CustomDevicePluginRegistrar &registrar) {
  registrar.addTraits(new M::KGEN::TestDeviceTraits());
  return nullptr;
}
