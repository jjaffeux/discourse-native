import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import 'bundled_plugins.dart';
import 'chat_shell.dart';
import 'fakes.dart';

const chatScrollSite = 'https://scroll.example';

Future<ShellController> chatScrollController({int count = 500}) async {
  final controller = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([instance('scroll.example')]),
    api: FakeDiscourseApi(
      chatMessagesByKey: {
        '9': (
          messages: [
            for (var id = 1; id <= count; id++)
              ChatMessage(
                id: id,
                channelId: 9,
                cooked: switch (id % 4) {
                  0 =>
                    '<p>Message $id with <strong>formatted text</strong> '
                        'and a longer paragraph that wraps in a narrow channel. '
                        'Reading history should keep the visible messages stable.</p>',
                  1 =>
                    '<p>Message $id</p><ul><li>First point</li>'
                        '<li>Second point with <code>inline code</code></li></ul>',
                  _ => '<p>Message $id: a short reply.</p>',
                },
                author: ChatMessageAuthor(
                  id: (id ~/ 3) % 4 + 1,
                  username: 'reader${(id ~/ 3) % 4 + 1}',
                ),
                createdAt: DateTime(
                  2026,
                  8,
                  1,
                ).add(Duration(days: (id - 1) ~/ 12, minutes: id % 12)),
              ),
          ],
          canLoadMorePast: false,
          canLoadMoreFuture: false,
          targetMessageId: null,
        ),
      },
    ),
    authenticator: FakeAuthenticator()..keys[chatScrollSite] = 'fixture-key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await controller.load();
  controller.chatRecords.put(
    chatScrollSite,
    ChatChannel(
      id: 9,
      title: 'Scroll profiling',
      kind: ChatChannelKind.category,
      membership: ChatMembership(following: true, lastReadMessageId: count),
    ),
  );
  await controller.chat.openChannel(chatScrollSite, 9);
  return controller;
}

class ChatScrollFixture extends StatelessWidget {
  const ChatScrollFixture({
    super.key,
    required this.controller,
    required this.diagnostics,
    this.width = 800,
    this.dark = false,
  });

  final ShellController controller;
  final DiagnosticsController diagnostics;
  final double width;
  final bool dark;

  @override
  Widget build(BuildContext context) => DiagnosticsScope(
    controller: diagnostics,
    child: ShellScope(
      controller: controller,
      child: PluginUiScope.own(
        chatPluginId,
        MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => DToaster(child: child!),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: 600,
                child: const ChatChannelView(channelId: 9),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
