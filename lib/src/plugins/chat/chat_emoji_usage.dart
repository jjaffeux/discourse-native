import 'package:discourse_native/discourse_plugin_sdk.dart';

const chatEmojiUsageContext = EmojiUsageContext(
  owner: PluginId('chat'),
  name: 'message',
  legacyStorageKey: 'chat',
);
