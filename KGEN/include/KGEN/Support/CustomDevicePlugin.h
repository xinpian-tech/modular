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

#ifndef KGEN_SUPPORT_CUSTOMDEVICEPLUGIN_H
#define KGEN_SUPPORT_CUSTOMDEVICEPLUGIN_H

#include "Support/ErrorOr.h"

namespace M::KGEN {

class TargetBackend;
class TargetLowering;
class TargetTraits;

/// Host callbacks exposed to a custom device compiler plugin.
///
/// Each non-null pointer passed to a callback transfers ownership to the Mojo
/// compiler. Plugins are loaded permanently, so implementations and their
/// vtables remain resident for the lifetime of the compiler process.
/// The registrar is valid only for the duration of the plugin entry-point
/// call; a plugin must invoke its callbacks synchronously and must not retain
/// a pointer or reference to it.
///
/// This is deliberately a minimal C++ extension point. Plugins build against
/// the exposed target interface headers.
struct CustomDevicePluginRegistrar {
  void (*addTraits)(TargetTraits *);
  void (*addLowering)(TargetLowering *);
  void (*addBackend)(TargetBackend *);
};

/// Entry point that every custom device compiler plugin must export.
///
/// The function registers any target components supplied by the plugin and
/// returns null on success, or a pointer to a persistent error string.
using RegisterCustomDevicePluginFn =
    const char *(*)(const CustomDevicePluginRegistrar &registrar);

inline constexpr char customDevicePluginEntryPoint[] =
    "M_KGEN_registerCustomDevicePlugin";

/// Loads and registers the custom device plugins configured for Mojo.
///
/// Paths come from the semicolon-separated `mojo-max.mojo_plugin_paths`
/// configuration, including its `MODULAR_MOJO_MAX_MOJO_PLUGIN_PATHS`
/// environment override.
ErrorOrSuccess loadCustomDevicePlugins();

} // namespace M::KGEN

#endif // KGEN_SUPPORT_CUSTOMDEVICEPLUGIN_H
