import 'plugin_manifest.dart';

/// The build profile containing only Discourse core.
///
/// It is intentionally empty: installing it proves the shell has no hidden
/// dependency on a bundled optional feature.
const PluginManifest corePluginManifest = PluginManifest([]);
