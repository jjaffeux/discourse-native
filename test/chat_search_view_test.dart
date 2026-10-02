import 'dart:async';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_threads_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_my_threads_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_route.dart';
import 'package:discourse_native/src/plugins/chat/chat_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_search_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');

void main() {
  testWidgets('a failed page waits for Try again instead of scrolling', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      user: _user,
      chatSearchPagesByKey: {
        FakeDiscourseApi.chatSearchKey('deploy'): ChatSearchPage(
          hits: [for (var id = 1; id <= 20; id++) _hit(id)],
          hasMore: true,
        ),
      },
    );
    await _pump(tester, api);
    await tester.enterText(
      find.byKey(const ValueKey('chat-search-field')),
      'deploy',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    Iterable<int> offsets() =>
        api.chatSearchesRequested.map((request) => request.offset);
    expect(offsets(), [0]);

    final list = find.byKey(const PageStorageKey('chat-search-results'));
    await tester.fling(list, const Offset(0, -6000), 6000);
    await tester.pumpAndSettle();
    for (var drag = 0; drag < 5; drag++) {
      await tester.drag(list, const Offset(0, 40));
      await tester.drag(list, const Offset(0, -40));
      await tester.pumpAndSettle();
    }

    expect(offsets(), [0, 20]);
    expect(find.text('Could not load more chat results.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(offsets(), [0, 20, 20]);
    expect(find.text('Try again'), findsOneWidget);
  });

  for (final threaded in [false, true]) {
    for (final replacement in ['none', 'open', 'disposed']) {
      testWidgets(
        'a held ${threaded ? 'thread' : 'channel'} result opens only with its '
        'source owner ($replacement)',
        (tester) async {
          final gate = Completer<void>();
          addTearDown(() {
            if (!gate.isCompleted) gate.complete();
          });
          final hit = ChatSearchHit(
            message: _hit(1, threadId: threaded ? 12 : null).message,
            channel: _hit(1).channel,
            excerpt: 'deploy 1',
          );
          final api = _DelayedChannelApi(gate, hit);
          final original = await _createController(api);
          final other = await _createController(
            FakeDiscourseApi(
              user: const DiscourseUser(id: 8, username: 'replacement'),
              chatChannelsBySite: const {
                _site: ChatChannels(public: [_replacementChannel]),
              },
            ),
            user: const DiscourseUser(id: 8, username: 'replacement'),
          );
          await other.pluginSession
              .require(chatControllerService)
              .loadChannels(_site);
          await tester.pumpWidget(_searchWidget(original));
          await tester.pumpAndSettle();
          final state = tester.state(find.byType(ChatSearchView));
          await tester.enterText(
            find.byKey(const ValueKey('chat-search-field')),
            'deploy',
          );
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Ops'));
          await tester.pump();
          expect(api.chatChannelDetailsRequested, [9]);
          final sourceShell = original.pluginSession.require(chatShellService);
          final replacementShell = other.pluginSession.require(
            chatShellService,
          );
          expect(sourceShell.fullPageChatActive, isFalse);

          if (replacement != 'none') {
            await tester.pumpWidget(_searchWidget(other));
            await tester.pumpAndSettle();
            expect(tester.state(find.byType(ChatSearchView)), same(state));
            if (replacement == 'disposed') await original.pluginSession.close();
          }
          gate.complete();
          await tester.pumpAndSettle();

          expect(replacementShell.fullPageChatActive, isFalse);
          expect(sourceShell.fullPageChatActive, replacement == 'none');
          if (replacement == 'none') {
            expect(sourceShell.visibleChannelId, 9);
            expect(
              ChatRoute.parse(sourceShell.currentContent?.id ?? '')?.threadId,
              threaded ? 12 : null,
            );
          }
          expect(find.text('Could not open this chat message.'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final replacement in ['none', 'open', 'disposed']) {
    testWidgets(
      'a retained channel thread row keeps its activation owner ($replacement)',
      (tester) async {
        final gate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        final api = _DelayedChannelApi(gate, _hit(1), threads: true);
        final original = await _createController(api);
        final other = await _createController(
          FakeDiscourseApi(
            user: _user,
            chatChannelsBySite: const {
              _site: ChatChannels(public: [_replacementChannel]),
            },
            chatChannelThreadPagesByKey: _threadPages,
          ),
        );
        final sourceChat = original.pluginSession.require(
          chatControllerService,
        );
        final otherChat = other.pluginSession.require(chatControllerService);
        await otherChat.loadChannels(_site);
        await otherChat.loadChannelThreads(_site, 9);
        await sourceChat.loadChannelThreads(
          _site,
          9,
          directoryChannel: _hit(1).channel,
        );
        expect(api.chatChannelThreadPagesRequested, isNotEmpty);
        expect(sourceChat.channelThreads(_site, 9), hasLength(1));
        await tester.pumpWidget(_threadWidget(original));
        await tester.pumpAndSettle();
        final row = find.byType(ChatThreadListRow);
        final rowElement = tester.element(row);
        await tester.tap(find.byKey(const ValueKey('chat-channel-thread-12')));
        await tester.pump();
        expect(api.chatChannelDetailsRequested, [9]);
        final sourceShell = original.pluginSession.require(chatShellService);
        final replacementShell = other.pluginSession.require(chatShellService);
        if (replacement != 'none') {
          await tester.pumpWidget(_threadWidget(other));
          await tester.pumpAndSettle();
          expect(tester.element(row), same(rowElement));
          if (replacement == 'disposed') await original.pluginSession.close();
        }
        gate.complete();
        await tester.pumpAndSettle();
        expect(replacementShell.fullPageChatActive, isFalse);
        expect(sourceShell.fullPageChatActive, replacement == 'none');
        if (replacement == 'none') {
          expect(sourceShell.currentContent?.id, 'chat-c-9-t-12');
          expect(sourceChat.channel(_site, 9), isNotNull);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final closeOriginal in [false, true]) {
    testWidgets(
      'same-site search rebinds its retained State while the old session is '
      '${closeOriginal ? 'closed' : 'open'}',
      (tester) async {
        final originalApi = FakeDiscourseApi(
          user: _user,
          chatSearchPagesByKey: {
            FakeDiscourseApi.chatSearchKey('deploy'): ChatSearchPage(
              hits: [_hit(1)],
            ),
          },
        );
        final replacementApi = FakeDiscourseApi(
          user: _user,
          chatSearchPagesByKey: {
            FakeDiscourseApi.chatSearchKey('saved'): ChatSearchPage(
              hits: [_hit(2)],
            ),
            FakeDiscourseApi.chatSearchKey('next'): ChatSearchPage(
              hits: [_hit(3)],
            ),
          },
        );
        final original = await _createController(originalApi);
        final replacement = await _createController(replacementApi);
        final selected = ValueNotifier(original);
        addTearDown(selected.dispose);
        await tester.pumpWidget(
          ValueListenableBuilder<ShellController>(
            valueListenable: selected,
            builder: (_, shell, _) => _searchWidget(shell),
          ),
        );
        await tester.pumpAndSettle();
        final viewState = tester.state(find.byType(ChatSearchView));
        final field = find.byKey(const ValueKey('chat-search-field'));
        await tester.enterText(field, 'deploy');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(find.text('deploy 1', findRichText: true), findsOneWidget);

        final search = replacement.pluginSession.require(
          chatSearchControllerService,
        );
        search.setGlobalQuery(_site, 'saved');
        selected.value = replacement;
        await tester.pumpAndSettle();
        if (closeOriginal) await original.pluginSession.close();
        expect(tester.state(find.byType(ChatSearchView)), same(viewState));
        final editor = find.descendant(
          of: field,
          matching: find.byType(EditableText),
        );
        final reboundQuery = tester
            .widget<EditableText>(editor)
            .controller
            .text;

        await tester.enterText(field, 'next');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(search.globalState(_site).query, 'next');
        expect(reboundQuery, 'saved');
        expect(search.globalState(_site).hits.map((hit) => hit.message.id), [
          3,
        ]);
        expect(find.text('deploy 1', findRichText: true), findsNothing);
        expect(find.text('deploy 3', findRichText: true), findsOneWidget);
        expect(originalApi.chatSearchesRequested.map((query) => query.query), [
          'deploy',
        ]);

        final requests = replacementApi.chatSearchesRequested.length;
        await replacement.pluginSession
            .require(chatShellService)
            .hydratePluginRoute(_site, ChatPlugin.searchRouteId, force: true);
        await tester.pumpAndSettle();
        expect(replacementApi.chatSearchesRequested, hasLength(requests + 1));
        expect(replacementApi.chatSearchesRequested.last.query, 'next');
        if (!closeOriginal) {
          await original.pluginSession
              .require(chatShellService)
              .hydratePluginRoute(_site, ChatPlugin.searchRouteId, force: true);
          expect(originalApi.chatSearchesRequested, hasLength(1));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

ChatSearchHit _hit(int id, {int? threadId}) => ChatSearchHit(
  message: ChatMessage(
    id: id,
    channelId: 9,
    threadId: threadId,
    cooked: '<p>deploy $id</p>',
    author: const ChatMessageAuthor(id: 2, username: 'sam'),
    createdAt: DateTime.utc(2026, 8, 25, 10),
  ),
  channel: const ChatChannel(
    id: 9,
    title: 'Ops',
    kind: ChatChannelKind.category,
    threadingEnabled: true,
  ),
  excerpt: 'deploy $id',
);

Future<ShellController> _createController(
  FakeDiscourseApi api, {
  DiscourseUser user = _user,
}) async {
  final controller = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(controller.dispose);
  await controller.load();
  return controller;
}

Widget _searchWidget(ShellController controller) => ShellScope(
  controller: controller,
  child: PluginUiScope.own(
    chatPluginId,
    MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: ChatSearchView(siteUrl: _site)),
    ),
  ),
);

Future<void> _pump(WidgetTester tester, FakeDiscourseApi api) async {
  final controller = await _createController(api);
  await tester.pumpWidget(_searchWidget(controller));
  await tester.pumpAndSettle();
}

const _replacementChannel = ChatChannel(
  id: 9,
  title: 'Replacement channel',
  kind: ChatChannelKind.category,
  threadingEnabled: true,
  membership: ChatMembership(following: true),
);

class _DelayedChannelApi extends FakeDiscourseApi {
  _DelayedChannelApi(this.completion, ChatSearchHit hit, {bool threads = false})
    : super(
        user: _user,
        chatSearchPagesByKey: {
          FakeDiscourseApi.chatSearchKey('deploy'): ChatSearchPage(hits: [hit]),
        },
        chatChannelsById: {9: hit.channel},
        chatChannelsBySite: const {_site: ChatChannels()},
        chatChannelThreadPagesByKey: threads ? _threadPages : const {},
      );

  final Completer<void> completion;

  @override
  Future<ChatChannel> chatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  }) async {
    final channel = await super.chatChannel(
      siteUrl: siteUrl,
      apiKey: apiKey,
      channelId: channelId,
      clientId: clientId,
    );
    await completion.future;
    return channel;
  }
}

final _threadPages = {
  FakeDiscourseApi.chatChannelThreadPageKey(9, 0): const ChatThreadPage(
    threads: [
      ChatThread(
        id: 12,
        channelId: 9,
        title: 'Thread result',
        originalMessage: ChatThreadOriginalMessage(
          id: 100,
          channelId: 9,
          author: ChatMessageAuthor(id: 2, username: 'sam'),
          excerpt: 'Original message',
        ),
        status: 'open',
        replyCount: 1,
      ),
    ],
  ),
};

Widget _threadWidget(ShellController controller) => ShellScope(
  controller: controller,
  child: PluginUiScope.own(
    chatPluginId,
    MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: ChatChannelThreadsView(siteUrl: _site, channelId: 9),
      ),
    ),
  ),
);
