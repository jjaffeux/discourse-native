import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_my_threads_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
final _user = const DiscourseUser(id: 7, username: 'reader').withPlugins(
  PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true),
  ),
);
ChatChannel _channel(int id) => ChatChannel(
  id: id,
  title: 'Channel $id',
  kind: ChatChannelKind.category,
  threadingEnabled: true,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final held in [false, true]) {
    for (final change in [
      'connect rollback',
      'disconnect rollback',
      'counts',
    ]) {
      final rollback = change != 'counts';
      testWidgets(
        'Browse threads ${held ? 'pending' : 'loaded'} directory '
        '${rollback ? 'reloads after failed' : 'keeps its request after'} $change',
        (tester) async {
          final api = _DirectoryApi(held: held);
          final store = _FailingStore();
          final shell = ShellController(
            plugins: installedPlugins,
            instanceStore: store,
            api: api,
            authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
            drafts: FakeDraftStore(),
            trackers: FakeSiteTracker.reset(),
            updater: FakeUpdater(),
            updateStore: FakeUpdateStore(),
            ownsApi: false,
          );
          addTearDown(shell.dispose);
          addTearDown(() {
            if (!api.release.isCompleted) api.release.complete();
          });
          await shell.load();
          await shell.chat.loadChannels(_site);
          shell.accountActivity.applyCounts(
            _site,
            (_) => chatNotificationTotals(),
          );
          shell.selectDestination(
            const SidebarDestination(
              id: ChatPlugin.myThreadsRouteId,
              label: 'Threads',
              icon: DIcons.comments,
            ),
          );
          final width = defaultTargetPlatform == TargetPlatform.iOS
              ? 390.0
              : 1000.0;
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            ShellScope(
              controller: shell,
              child: MaterialApp(
                theme: AppTheme.light.copyWith(platform: defaultTargetPlatform),
                home: Scaffold(
                  body: MainContent(layout: ShellLayout.forWidth(width)),
                ),
              ),
            ),
          );
          await _pump(tester);
          final state = tester.state(find.byType(ChatMyThreadsView));
          final session = shell.chat.captureSession(_site);
          expect(api.browseReads, 1);
          if (held) {
            expect(find.byType(DSkeletonRegion), findsOneWidget);
          } else {
            expect(find.text('Old thread'), findsOneWidget);
          }
          store.failSignedOut = rollback;
          if (!rollback) {
            FakeSiteTracker.built.last.deliverNotification(const {
              'all_unread_notifications_count': 4,
            });
          } else if (change == 'disconnect rollback') {
            expect(
              await tester.runAsync(() => shell.disconnectInstance(_site)),
              isFalse,
            );
          } else {
            await tester.runAsync(shell.connectCurrentInstance);
          }
          expect(session.isCurrent, !rollback);
          expect(shell.currentInstance?.user?.id, _user.id);
          expect(shell.currentContent?.id, ChatPlugin.myThreadsRouteId);
          if (rollback) {
            await shell.chat.loadChannels(_site);
            shell.accountActivity.applyCounts(
              _site,
              (_) => chatNotificationTotals(),
            );
          }
          await _pump(tester);
          expect(tester.state(find.byType(ChatMyThreadsView)), same(state));
          if (!api.release.isCompleted) api.release.complete();
          await _pump(tester);
          expect(api.browseReads, rollback ? 2 : 1);
          expect(
            find.text('Old thread'),
            rollback ? findsNothing : findsOneWidget,
          );
          expect(
            find.text('Replacement thread'),
            rollback ? findsOneWidget : findsNothing,
          );
          expect(find.text('No chat threads yet'), findsNothing);
          expect(find.byType(DSkeletonRegion), findsNothing);
          expect(tester.takeException(), isNull);
        },
        variant: const TargetPlatformVariant({
          TargetPlatform.macOS,
          TargetPlatform.iOS,
        }),
      );
    }
  }
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

class _FailingStore extends FakeInstanceStore {
  _FailingStore()
    : super([instance('meta.discourse.org').copyWith(user: _user)]);
  bool failSignedOut = false;
  @override
  Future<void> save(List<DiscourseInstance> instances) {
    if (failSignedOut && instances.any((site) => site.user == null)) {
      return Future.error(StateError('Account snapshot storage unavailable'));
    }
    return super.save(instances);
  }
}

class _DirectoryApi extends FakeDiscourseApi {
  _DirectoryApi({required this.held})
    : super(
        user: _user,
        totals: chatNotificationTotals(),
        feeds: const {'/latest.json': []},
        chatChannelsBySite: {
          _site: ChatChannels(public: [_channel(9)]),
        },
      );
  final bool held;
  final release = Completer<void>();
  int browseReads = 0;
  @override
  Future<ChatChannelBrowsePage> browseChatChannels({
    required String siteUrl,
    required String apiKey,
    String filter = '',
    ChatChannelBrowseStatus status = ChatChannelBrowseStatus.all,
    int offset = 0,
    int limit = ChatChannelBrowsePage.pageSize,
    String? clientId,
  }) async {
    final read = ++browseReads;
    if (read == 1 && held) await release.future;
    return ChatChannelBrowsePage(channels: [_channel(read == 1 ? 9 : 12)]);
  }

  @override
  Future<ChatThreadPage> chatChannelThreads({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    int offset = 0,
    int limit = ChatThreadPage.pageSize,
    String? clientId,
  }) async => ChatThreadPage(
    threads: [
      ChatThread(
        id: channelId,
        channelId: channelId,
        status: 'open',
        replyCount: 1,
        lastMessageId: channelId * 10 + 1,
        originalMessage: ChatThreadOriginalMessage(
          id: channelId * 10,
          channelId: channelId,
          author: const ChatMessageAuthor(id: 2, username: 'sam'),
          excerpt: 'A useful answer',
        ),
        title: channelId == 9 ? 'Old thread' : 'Replacement thread',
      ),
    ],
  );
}
