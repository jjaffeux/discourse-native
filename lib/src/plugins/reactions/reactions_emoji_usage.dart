import 'package:discourse_plugin_api/discourse_plugin_api.dart';

import '../../plugin_api/emoji_usage.dart';

/// Recent emoji used for post reactions owned by discourse-reactions.
///
/// Older builds stored these picks under the unnamespaced `postReactions`
/// key. The preference store adopts that history on the first mutation.
const reactionsEmojiUsageContext = EmojiUsageContext(
  owner: PluginId('discourse-reactions'),
  name: 'post-reactions',
  legacyStorageKey: 'postReactions',
);
