import 'package:discourse_native/discourse_bundled.dart';
import 'package:discourse_resenha/discourse_resenha.dart';

/// The full application composition.
///
/// The core package deliberately cannot import Resenha: doing so would put its
/// native SDKs back into every core package graph. The full application is the
/// outer composition root which joins the two sibling dependencies.
final PluginManifest fullPluginManifest = PluginManifest([
  ...bundledPluginManifest.modules,
  resenhaModule,
]);
