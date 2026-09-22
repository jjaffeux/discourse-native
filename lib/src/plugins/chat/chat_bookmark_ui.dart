import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/widgets.dart';

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
