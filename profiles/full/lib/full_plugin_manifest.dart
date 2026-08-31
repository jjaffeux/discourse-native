import 'package:discourse_native/discourse_bundled.dart';
import 'package:discourse_resenha/discourse_resenha.dart';

/// This composition root keeps Resenha's native SDKs out of core's package graph.
final PluginManifest fullPluginManifest = PluginManifest([
  ...bundledPluginManifest.modules,
  resenhaModule,
]);
