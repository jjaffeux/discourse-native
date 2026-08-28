import 'package:discourse_plugin_api/discourse_plugin_api.dart';

import '../../plugin_api/emoji_usage.dart';

/// Chat keeps composer and message-reaction usage in one shared history.
const chatEmojiUsageContext = EmojiUsageContext(
  owner: PluginId('chat'),
  name: 'message',
  legacyStorageKey: 'chat',
);
