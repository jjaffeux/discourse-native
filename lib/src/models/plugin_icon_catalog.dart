import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/foundation.dart';

import '../theme/d_icon.dart';
import '../theme/d_icons.dart';

/// A fallback is mandatory because servers retain names from uninstalled plugins.
abstract interface class IconNameDecoder {
  DIconData iconNamed(String? name, {required DIconData fallback});
}

final class CoreIconNameDecoder implements IconNameDecoder {
  const CoreIconNameDecoder();

  @override
  DIconData iconNamed(String? name, {required DIconData fallback}) =>
      (name == null ? null : DIcons.byName[name]) ?? fallback;
}

/// Core's generated icon table contains only assets used by core. A plugin
/// keeps optional artwork beside its implementation.
@immutable
final class PluginIconCatalog {
  const PluginIconCatalog({required this.owner, required this.entries});

  final PluginId owner;
  final Map<String, DIconData> entries;

  DIconData? iconNamed(String? name) => name == null ? null : entries[name];
}
