import 'dart:async';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_browse_channels_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_threads_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_my_threads_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _channelId = 9;

enum _Directory { channels, myThreads, channelThreads }

void main() {
  for (final directory in _Directory.values) {
    for (final disposeOld in [false, true]) {
      testWidgets(
        '${directory.name} rebinds retained state to replacement services '
        'with old owner disposed $disposeOld',
        (tester) async {
          final first = await _fixture('Old');
          final second = await _fixture('New');
          await _mount(tester, first, directory);
          await tester.pumpAndSettle();
          final view = find.byKey(ValueKey(directory));
          final state = tester.state(view);
          final oldLabel = directory == _Directory.channels
              ? 'Old channel'
              : 'Old thread';
          final newLabel = directory == _Directory.channels
              ? 'New channel'
              : 'New thread';
          expect(find.text(oldLabel), findsWidgets);
          if (directory == _Directory.channelThreads) {
            expect(
              first.shell.pluginSession
                  .require(chatControllerService)
                  .channel(_site, _channelId)
                  ?.membership
                  .lastViewedAt,
              isNotNull,
            );
          }
          if (disposeOld) first.dispose();

          await _mount(tester, second, directory);
          await tester.pumpAndSettle();
          expect(tester.state(view), same(state));
          expect(find.text(oldLabel), findsNothing);
          expect(find.text(newLabel), findsWidgets);
          if (directory == _Directory.channels) {
            expect(
              tester
                  .widget<TextField>(
                    find.descendant(
                      of: find.byKey(const ValueKey('chat-browse-filter')),
                      matching: find.byType(TextField),
                    ),
                  )
                  .controller!
                  .text,
              'new',
            );
          }
          if (directory == _Directory.channelThreads) {
            expect(
              second.shell.pluginSession
                  .require(chatControllerService)
                  .channel(_site, _channelId)
                  ?.membership
                  .lastViewedAt,
              isNotNull,
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('a retired browse response cannot replace the new owner rows', (
    tester,
  ) async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final first = await _fixture('Old', browseGate: gate);
    final second = await _fixture('New');
    await _mount(tester, first, _Directory.channels);
    await tester.pump(const Duration(milliseconds: 50));
    final view = find.byKey(const ValueKey(_Directory.channels));
    final state = tester.state(view);

    await _mount(tester, second, _Directory.channels);
    await tester.pumpAndSettle();
    expect(tester.state(view), same(state));
    expect(find.text('New channel'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('New channel'), findsOneWidget);
    expect(find.text('Old channel'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<_Fixture> _fixture(String label, {Completer<void>? browseGate}) async {
  final user = DiscourseUser(
    id: label == 'Old' ? 7 : 8,
    username: label.toLowerCase(),
    plugins: PluginData.none.withValue(
      chatCurrentUserDataKey,
      const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
    ),
  );
  final config = SiteConfig(
    plugins: PluginData.none.withValue(
      chatSettingsDataKey,
      const ChatSettings(
        chatEnabled: true,
        publicChannelsEnabled: true,
        threadsEnabled: true,
      ),
    ),
  );
  final channel = ChatChannel(
    id: _channelId,
    title: '$label channel',
    kind: ChatChannelKind.category,
    membership: const ChatMembership(following: true),
    threadingEnabled: true,
  );
  final api = FakeDiscourseApi(
    user: user,
    totals: chatNotificationTotals(),
    siteConfigs: {_site: config},
    feeds: const {'/latest.json': []},
    chatChannelsBySite: {
      _site: ChatChannels(public: [channel]),
    },
    chatBrowsePagesByKey: {
      FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
        channels: [channel],
      ),
      FakeDiscourseApi.chatBrowseKey(filter: label.toLowerCase()):
          ChatChannelBrowsePage(channels: [channel]),
    },
    chatBrowseGate: browseGate,
    chatChannelThreadPagesByKey: {
      FakeDiscourseApi.chatChannelThreadPageKey(_channelId, 0): ChatThreadPage(
        threads: [
          ChatThread(
            id: 1,
            channelId: _channelId,
            title: '$label thread',
            status: 'open',
            replyCount: 1,
            originalMessage: const ChatThreadOriginalMessage(
              id: 10,
              channelId: _channelId,
              author: ChatMessageAuthor(id: 2, username: 'sam'),
              excerpt: 'Original message',
            ),
          ),
        ],
      ),
    },
  );
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: user, config: config),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  final fixture = _Fixture(shell);
  addTearDown(fixture.dispose);
  await shell.load();
  final chat = shell.pluginSession.require(chatControllerService);
  await chat.loadChannels(_site);
  chat.inboxFilters.browseFor(_site).query = label.toLowerCase();
  return fixture;
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture,
  _Directory directory,
) => tester.pumpWidget(
  ShellScope(
    controller: fixture.shell,
    child: PluginUiScope.own(
      chatPluginId,
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: switch (directory) {
            _Directory.channels => ChatBrowseChannelsView(
              key: ValueKey(directory),
              siteUrl: _site,
            ),
            _Directory.myThreads => ChatMyThreadsView(
              key: ValueKey(directory),
              siteUrl: _site,
            ),
            _Directory.channelThreads => ChatChannelThreadsView(
              key: ValueKey(directory),
              siteUrl: _site,
              channelId: _channelId,
            ),
          },
        ),
      ),
    ),
  ),
);

class _Fixture {
  _Fixture(this.shell);

  final ShellController shell;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    shell.dispose();
  }
}
