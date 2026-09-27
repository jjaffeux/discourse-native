import 'dart:async';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_threads_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_metrics.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');
const _channelId = 9;
const _channel = ChatChannel(
  id: _channelId,
  title: 'Support',
  kind: ChatChannelKind.category,
  membership: ChatMembership(following: true),
  threadingEnabled: true,
);

void main() {
  testWidgets('a failed page waits for Try again instead of scrolling', (
    tester,
  ) async {
    final firstPage = FakeDiscourseApi.chatChannelThreadPageKey(_channelId, 0);
    final api = FakeDiscourseApi(
      user: _user,
      chatChannelsBySite: {
        _site: const ChatChannels(
          public: [
            ChatChannel(
              id: _channelId,
              title: 'Support',
              kind: ChatChannelKind.category,
              membership: ChatMembership(following: true),
              threadingEnabled: true,
            ),
          ],
        ),
      },
      chatChannelThreadPagesByKey: {
        firstPage: ChatThreadPage(
          threads: [for (var id = 1; id <= 20; id++) _thread(id)],
          hasMore: true,
        ),
      },
    );
    await _pump(tester, api);
    Iterable<int> offsets() =>
        api.chatChannelThreadPagesRequested.map((request) => request.offset);
    expect(offsets(), [0]);

    final list = find.byKey(
      const PageStorageKey<String>('chat-channel-$_channelId-threads'),
    );
    await tester.fling(list, const Offset(0, -6000), 6000);
    await tester.pumpAndSettle();
    for (var drag = 0; drag < 5; drag++) {
      await tester.drag(list, const Offset(0, 40));
      await tester.drag(list, const Offset(0, -40));
      await tester.pumpAndSettle();
    }

    expect(offsets(), [0, 20]);
    expect(find.text('Could not load this channel’s threads.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(offsets(), [0, 20, 20]);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('reopening the list adds new threads behind the held rows', (
    tester,
  ) async {
    final firstPage = FakeDiscourseApi.chatChannelThreadPageKey(_channelId, 0);
    final pages = {
      firstPage: ChatThreadPage(threads: [_thread(1)], hasMore: true),
      FakeDiscourseApi.chatChannelThreadPageKey(_channelId, 1): ChatThreadPage(
        threads: [_thread(2)],
      ),
    };
    final api = _GatedThreadsApi(
      user: _user,
      chatChannelsBySite: {
        _site: const ChatChannels(public: [_channel]),
      },
      chatChannelThreadPagesByKey: pages,
    );
    final controller = await _pump(tester, api);
    Iterable<int> offsets() =>
        api.chatChannelThreadPagesRequested.map((request) => request.offset);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(offsets(), [0, 1]);
    expect(find.text('Thread 2'), findsOneWidget);

    await _mount(tester, controller, shown: false);
    pages[firstPage] = ChatThreadPage(
      threads: [_thread(3), _thread(1)],
      hasMore: true,
    );
    final gate = api.pageGate = Completer<void>();
    await _mount(tester, controller);
    await tester.pump();

    expect(offsets(), [0, 1, 0]);
    expect(find.text('Thread 1'), findsOneWidget);
    expect(find.text('Thread 2'), findsOneWidget);
    expect(find.text('Thread 3'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Thread 1'), findsOneWidget);
    expect(find.text('Thread 2'), findsOneWidget);
    expect(find.text('Thread 3'), findsOneWidget);
  });

  testWidgets('a failed refresh on reopening keeps the held rows quietly', (
    tester,
  ) async {
    final firstPage = FakeDiscourseApi.chatChannelThreadPageKey(_channelId, 0);
    final pages = {
      firstPage: ChatThreadPage(threads: [_thread(1)]),
    };
    final api = FakeDiscourseApi(
      user: _user,
      chatChannelsBySite: {
        _site: const ChatChannels(public: [_channel]),
      },
      chatChannelThreadPagesByKey: pages,
    );
    final controller = await _pump(tester, api);
    Iterable<int> offsets() =>
        api.chatChannelThreadPagesRequested.map((request) => request.offset);

    await _mount(tester, controller, shown: false);
    pages.remove(firstPage);
    await _mount(tester, controller);
    await tester.pumpAndSettle();

    expect(offsets(), [0, 0]);
    expect(find.text('Thread 1'), findsOneWidget);
    expect(find.text('Could not load this channel’s threads.'), findsNothing);
    expect(find.text('Try again'), findsNothing);
  });

  group('on a narrow phone', () {
    for (final scale in [1.0, 1.5, 2.0, 3.0]) {
      testWidgets(
        'the Threads header fits its channel line at ${scale}x text',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _pumpMobileThreads(tester);

          expect(tester.takeException(), isNull);
          final header = tester.getRect(
            find.byKey(const ValueKey('content-header')),
          );
          final title = tester.getRect(find.text('Threads'));
          final channel = tester.getRect(find.text('Support'));
          if (scale == 1) expect(header.height, shellHeaderHeight);
          expect(title.height, greaterThanOrEqualTo(_titleLine(scale) - 1));
          expect(title.bottom, channel.top);
          expect(title.top, greaterThan(header.top));
          expect(channel.bottom, lessThan(header.bottom));
          expect(
            title.top - header.top,
            closeTo(header.bottom - channel.bottom, 1),
          );
          expect(
            tester.getRect(find.text('Thread 1')).top,
            greaterThan(header.bottom),
          );
        },
        variant: const TargetPlatformVariant({
          TargetPlatform.iOS,
          TargetPlatform.android,
        }),
      );
    }
  });
}

ChatThread _thread(int id) => ChatThread(
  id: id,
  channelId: _channelId,
  status: 'open',
  replyCount: 1,
  title: 'Thread $id',
  originalMessage: ChatThreadOriginalMessage(
    id: id * 10,
    channelId: _channelId,
    author: const ChatMessageAuthor(id: 2, username: 'sam'),
    excerpt: 'Original $id',
  ),
);

/// The production mobile shell on a 320x720 phone, on a channel's threads.
Future<void> _pumpMobileThreads(WidgetTester tester) async {
  final user = DiscourseUser(
    id: _user.id,
    username: _user.username,
    plugins: PluginData.none.withValue(
      chatCurrentUserDataKey,
      const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
    ),
  );
  final config = SiteConfig(
    plugins: PluginData.none.withValue(
      chatSettingsDataKey,
      const ChatSettings(chatEnabled: true, publicChannelsEnabled: true),
    ),
  );
  await pumpShell(
    tester,
    const Size(320, 720),
    instances: [
      instance(
        'meta.discourse.org',
        title: 'Meta',
      ).copyWith(user: user, config: config),
    ],
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    api: FakeDiscourseApi(
      user: user,
      totals: chatNotificationTotals(),
      siteConfigs: {_site: config},
      feeds: const {'/latest.json': []},
      chatChannelsBySite: {
        _site: const ChatChannels(
          public: [
            ChatChannel(
              id: _channelId,
              title: 'Support',
              kind: ChatChannelKind.category,
              membership: ChatMembership(following: true),
              threadingEnabled: true,
            ),
          ],
        ),
      },
      chatMessagesByKey: {
        FakeDiscourseApi.chatMessagesKey(_channelId): (
          messages: const <ChatMessage>[],
          canLoadMorePast: false,
          canLoadMoreFuture: false,
          targetMessageId: null,
        ),
      },
      chatChannelThreadPagesByKey: {
        FakeDiscourseApi.chatChannelThreadPageKey(_channelId, 0):
            ChatThreadPage(threads: [_thread(1)]),
      },
    ),
  );
  final shell = ShellScope.read(tester.element(find.byType(MainContent)));
  await shell.pluginSession.require(chatControllerService).loadChannels(_site);
  final chat = shell.pluginSession.require(chatShellService);
  expect(chat.openChannel(_channelId), isTrue);
  await tester.pumpAndSettle();
  expect(
    chat.openChannelThreads(siteUrl: _site, channelId: _channelId),
    isTrue,
  );
  await tester.pumpAndSettle();
  expect(
    shell.currentContent?.id,
    ChatPlugin.channelThreadsRouteId(_channelId),
  );
}

Future<ShellController> _pump(WidgetTester tester, FakeDiscourseApi api) async {
  final controller = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(controller.dispose);
  await controller.load();
  await controller.pluginSession
      .require(chatControllerService)
      .loadChannels(_site);
  await _mount(tester, controller);
  await tester.pumpAndSettle();
  return controller;
}

/// Mounts the threads list under [controller], or unmounts it while keeping
/// the controller's chat state.
Future<void> _mount(
  WidgetTester tester,
  ShellController controller, {
  bool shown = true,
}) => tester.pumpWidget(
  ShellScope(
    controller: controller,
    child: PluginUiScope.own(
      chatPluginId,
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: shown
              ? const ChatChannelThreadsView(
                  siteUrl: _site,
                  channelId: _channelId,
                )
              : const SizedBox.shrink(),
        ),
      ),
    ),
  ),
);

/// Holds channel thread pages behind [pageGate] while one is set, so a test
/// can look at the list while a refresh is in flight.
final class _GatedThreadsApi extends FakeDiscourseApi {
  _GatedThreadsApi({
    super.user,
    super.chatChannelsBySite,
    super.chatChannelThreadPagesByKey,
  });

  Completer<void>? pageGate;

  @override
  Future<ChatThreadPage> chatChannelThreads({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    int offset = 0,
    int limit = ChatThreadPage.pageSize,
    String? clientId,
  }) async {
    final page = await super.chatChannelThreads(
      siteUrl: siteUrl,
      apiKey: apiKey,
      channelId: channelId,
      offset: offset,
      limit: limit,
      clientId: clientId,
    );
    if (pageGate case final held?) await held.future;
    return page;
  }
}

/// The title's whole line box at [scale], so a clipped title cannot pass.
double _titleLine(double scale) {
  final style = AppTheme.light.textTheme.titleSmall!;
  return style.fontSize! * scale * style.height!;
}
