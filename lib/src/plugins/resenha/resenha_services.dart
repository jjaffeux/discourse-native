import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'resenha_controller.dart';

const resenhaPluginId = PluginId('resenha');

const resenhaControllerService = PluginServiceKey<ResenhaController>(
  owner: resenhaPluginId,
  name: 'controller',
);
