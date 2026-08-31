import 'package:discourse_plugin_api/discourse_plugin_api.dart';

import '../../plugin_api/emoji_usage.dart';

/// Adopts the legacy unnamespaced `postReactions` preference on first mutation.
const reactionsEmojiUsageContext = EmojiUsageContext(
  owner: PluginId('discourse-reactions'),
  name: 'post-reactions',
  legacyStorageKey: 'postReactions',
);
