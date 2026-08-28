import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import 'reactions_controller.dart';

const reactionsPluginId = PluginId('discourse-reactions');

const reactionsControllerService = PluginServiceKey<ReactionsController>(
  owner: reactionsPluginId,
  name: 'controller',
);

const reactionsEmojiHostService = PluginServiceKey<PluginEmojiHost>(
  owner: reactionsPluginId,
  name: 'emoji-host',
);
