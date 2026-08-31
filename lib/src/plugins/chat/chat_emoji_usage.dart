import 'package:discourse_plugin_api/discourse_plugin_api.dart';

import '../../plugin_api/emoji_usage.dart';

const chatEmojiUsageContext = EmojiUsageContext(
  owner: PluginId('chat'),
  name: 'message',
  legacyStorageKey: 'chat',
);
