import 'package:discourse_native/src/plugin_api/plugin_manifest.dart';
import 'resenha_controller.dart';

const resenhaPluginId = PluginId('resenha');

const resenhaControllerService = PluginServiceKey<ResenhaController>(
  owner: resenhaPluginId,
  name: 'controller',
);
