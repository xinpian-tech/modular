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

#include "KGEN/Compiler/Target/TargetBackend.h"
#include "KGEN/Support/Configuration.h"
#include "Target/TargetLowering.h"
#include "Target/TargetTraits.h"

#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/DynamicLibrary.h"

#include <memory>
#include <string>

namespace M::KGEN {
namespace {

SmallVector<std::string> getConfiguredPluginPaths() {
  if (ErrorOr<MojoConfig> configOr = MojoConfig::open(); !configOr.isError())
    return configOr->getPluginPaths();
  return {};
}

} // namespace

ErrorOrSuccess loadCustomDevicePlugins() {
  const CustomDevicePluginRegistrar registrar{
      [](TargetTraits *traits) {
        if (traits)
          TargetTraitsRegistry::get().addPlugin(
              std::unique_ptr<TargetTraits>(traits));
      },
      [](TargetLowering *lowering) {
        if (lowering)
          TargetLoweringRegistry::get().addPlugin(
              std::unique_ptr<TargetLowering>(lowering));
      },
      [](TargetBackend *backend) {
        if (backend)
          TargetBackendRegistry::get().addPlugin(
              std::unique_ptr<TargetBackend>(backend));
      },
  };

  for (const std::string &path : getConfiguredPluginPaths()) {
    std::string loaderError;
    llvm::sys::DynamicLibrary library =
        llvm::sys::DynamicLibrary::getPermanentLibrary(path.c_str(),
                                                       &loaderError);
    if (!library.isValid())
      return Error("failed to load custom device plugin '" + path + "': " +
                   loaderError);

    void *symbol = library.getAddressOfSymbol(customDevicePluginEntryPoint);
    if (!symbol)
      return Error("custom device plugin '" + path + "' does not export " +
                   customDevicePluginEntryPoint);

    auto registerPlugin =
        reinterpret_cast<RegisterCustomDevicePluginFn>(symbol);
    if (const char *pluginError = registerPlugin(registrar))
      return Error("failed to register custom device plugin '" + path +
                   "': " + pluginError);
  }
  return success();
}

} // namespace M::KGEN
