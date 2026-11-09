import 'package:discourse_native/discourse_plugin_contracts.dart';
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
