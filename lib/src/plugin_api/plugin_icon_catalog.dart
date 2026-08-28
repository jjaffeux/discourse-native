import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/foundation.dart';

import '../theme/d_icon.dart';
import '../theme/d_icons.dart';

/// Resolves an icon name from core plus the installed owner catalogs.
///
/// Wire readers depend on this narrow contract rather than a process-global
/// registry. A fallback is mandatory because servers can retain names from a
/// plugin which is not installed in the current composition.
abstract interface class IconNameDecoder {
  DIconData iconNamed(String? name, {required DIconData fallback});
}

/// Core-only icon decoding for compositions with no optional owners.
final class CoreIconNameDecoder implements IconNameDecoder {
  const CoreIconNameDecoder();

  @override
  DIconData iconNamed(String? name, {required DIconData fallback}) =>
      (name == null ? null : DIcons.byName[name]) ?? fallback;
}

/// Names and aliases for icons owned by one optional plugin.
///
/// Core's generated icon table contains only assets used by core. A plugin
/// keeps optional artwork beside its implementation and contributes the wire
/// names which should resolve while that plugin is installed. Consumers must
/// still supply a generic fallback for unknown or uninstalled names.
@immutable
final class PluginIconCatalog {
  const PluginIconCatalog({required this.owner, required this.entries});

  final PluginId owner;
  final Map<String, DIconData> entries;

  DIconData? iconNamed(String? name) => name == null ? null : entries[name];
}
