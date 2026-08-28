import 'package:flutter/widgets.dart';

import '../../models/bookmark.dart';
import '../../plugin_api/bookmark_host.dart';
import '../../shell/bookmark_ui.dart';

Future<void> showChatMessageBookmarkMenu({
  required BuildContext context,
  required PluginBookmarkHost host,
  required String siteUrl,
  required int messageId,
  required Bookmark? bookmark,
  required String cooked,
}) => showPluginBookmarkMenu(
  context: context,
  controller: host,
  siteUrl: siteUrl,
  targetId: messageId,
  bookmark: bookmark,
  cooked: cooked,
  createTitle: 'Bookmark chat message',
  existingTitle: 'Chat message bookmark',
);
