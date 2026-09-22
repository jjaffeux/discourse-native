import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:flutter/foundation.dart';

import 'plugin_contracts.dart';
import 'plugin_data.dart';

/// Native owner of app-bundled compiler behavior. Projection runs on the host;
/// only the returned finite JSON snapshot crosses the worker boundary.
abstract interface class CookingPlugin implements PluginCapability {
  List<CookingModule> get cookingModules;
  List<CookingProfile> get cookingProfiles;
  Map<String, Object?> projectCookingContext(CookingPluginData data);
}

/// Restricts a projector to the native module's own typed settings namespace.
final class CookingPluginData {
  const CookingPluginData(this.owner, this._data);
  final String owner;
  final PluginData _data;

  T? read<T extends Object>(PluginDataKey<T> key) {
    if (key.owner != owner) {
      throw StateError(
        '$owner cannot project cooking settings for ${key.owner}',
      );
    }
    return _data.get(key);
  }
}

/// Captured by the registrar once, using its validated descriptor owner.
final class InstalledCookingPlugin implements CookingPlugin {
  InstalledCookingPlugin(String owner, CookingPlugin source)
    : name = owner,
      cookingModules = List.unmodifiable(source.cookingModules),
      cookingProfiles = List.unmodifiable(source.cookingProfiles),
      _project = source.projectCookingContext {
    if (cookingModules.any((module) => module.owner != owner)) {
      throw ArgumentError('$owner registered foreign cooking modules');
    }
  }
  @override
  final String name;
  @override
  final List<CookingModule> cookingModules;
  @override
  final List<CookingProfile> cookingProfiles;
  final Map<String, Object?> Function(CookingPluginData) _project;
  @override
  Map<String, Object?> projectCookingContext(CookingPluginData data) =>
      _project(data);
}

CookingConfiguration cookingConfiguration(Iterable<CookingPlugin> plugins) {
  final contributions = plugins.toList(growable: false);
  final owners = <String>{};
  for (final plugin in contributions) {
    if (!owners.add(plugin.name)) {
      throw ArgumentError('Duplicate cooking owner ${plugin.name}');
    }
  }
  return CookingConfiguration(
    modules: [for (final p in contributions) ...p.cookingModules],
    profiles: [
      CookingProfile.post,
      for (final p in contributions) ...p.cookingProfiles,
    ],
    installedOwners: owners,
  );
}

/// Narrow host port; consumers cannot dispose/reconfigure the shared runtime.
final class PluginCookingHost {
  const PluginCookingHost({
    required this.request,
    required this.cook,
    this.isCurrent = _alwaysCurrent,
    this.watch = _noWatch,
  });
  final CookingRequest Function({
    required String siteUrl,
    required String raw,
    CookingProfile profile,
    CookingContext context,
    CookingCachedMetadata? cachedMetadata,
  })
  request;
  final Future<CookingResult> Function(CookingRequest request) cook;

  /// Checks the original request without rebuilding its frozen snapshot.
  final bool Function(CookingRequest request) isCurrent;

  /// Observes cached context for this source. The returned callback retires the
  /// subscription, including any queued notification. Subscription is silent.
  final VoidCallback Function({
    required String siteUrl,
    required String raw,
    required VoidCallback onChanged,
  })
  watch;

  static bool _alwaysCurrent(CookingRequest _) => true;
  static VoidCallback _noWatch({
    required String siteUrl,
    required String raw,
    required VoidCallback onChanged,
  }) => _noop;
  static void _noop() {}
}

const corePluginCookingPort = PluginHostPortKey<PluginCookingHost>(
  owner: PluginId('core'),
  name: 'cooking',
);
