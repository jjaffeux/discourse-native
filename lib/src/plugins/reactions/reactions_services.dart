import '../../plugin_api/plugin_manifest.dart';
import 'reactions_controller.dart';

const reactionsPluginId = PluginId('discourse-reactions');

const reactionsControllerService = PluginServiceKey<ReactionsController>(
  owner: reactionsPluginId,
  name: 'controller',
);
