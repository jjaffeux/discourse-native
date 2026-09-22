import 'package:discourse_native/discourse_plugin_sdk.dart';

/// Adopts the legacy unnamespaced `postReactions` preference on first mutation.
const reactionsEmojiUsageContext = EmojiUsageContext(
  owner: PluginId('discourse-reactions'),
  name: 'post-reactions',
  legacyStorageKey: 'postReactions',
);
