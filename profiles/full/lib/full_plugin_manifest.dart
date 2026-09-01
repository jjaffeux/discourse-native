import 'package:discourse_native/discourse_bundled.dart';

/// Compatibility alias for the former optional full profile.
///
/// The main package now always bundles Voice, so every application entry
/// point uses the same feature graph.
final PluginManifest fullPluginManifest = bundledPluginManifest;
