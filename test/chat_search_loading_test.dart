import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_search_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_search_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');
const _mobile = TargetPlatformVariant({
  TargetPlatform.iOS,
  TargetPlatform.android,
});
final _field = find.byKey(const ValueKey('chat-search-field'));

void main() {
  testWidgets(
    'mobile chat search shows a skeleton during debounce and first page',
    (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final api = _LoadingApi(gate, heldOffset: 0);
      final shell = await _pump(tester, api);
      final search = shell.pluginSession.require(chatSearchControllerService);
      final semantics = tester.ensureSemantics();
      try {
        await tester.enterText(_field, 'deploy');
        await tester.pump(const Duration(milliseconds: 50));
        expect(search.globalState(_site).phase, ChatSearchPhase.waiting);
        expect(find.byType(DSkeletonRegion), findsOneWidget);
        expect(find.bySemanticsLabel('Searching…'), findsOneWidget);
      } finally {
        semantics.dispose();
      }

      await tester.pump(const Duration(milliseconds: 400));
      expect(api.chatSearchesRequested.map((query) => query.offset), [0]);
      expect(search.globalState(_site).phase, ChatSearchPhase.loading);
      expect(find.byType(DSkeleton), findsWidgets);
      expect(find.byType(DSpinner), findsNothing);
      expect(_field.hitTestable(), findsOneWidget);
      final skeleton = tester.getRect(find.byType(DSkeletonRegion));
      expect(skeleton.top, greaterThan(tester.getRect(_field).bottom));
      expect(skeleton.height, greaterThan(300));
      expect(skeleton.width, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(DSkeletonRegion), findsNothing);
      expect(find.text('deploy 1', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: _mobile,
  );

  testWidgets('mobile chat search keeps results and shows a paging skeleton', (
    tester,
  ) async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final api = _LoadingApi(gate, heldOffset: 2);
    final shell = await _pump(tester, api);
    await tester.enterText(_field, 'deploy');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    final search = shell.pluginSession.require(chatSearchControllerService);
    expect(search.globalState(_site).hits, hasLength(2));
    await tester.tap(find.widgetWithText(DButton, 'Load more'));
    await tester.pump();
    expect(api.chatSearchesRequested.map((query) => query.offset), [0, 2]);
    expect(search.globalState(_site).loadingMore, isTrue);
    expect(find.text('deploy 1', findRichText: true), findsOneWidget);
    expect(find.text('deploy 2', findRichText: true), findsOneWidget);
    expect(find.byType(DSkeletonRegion), findsOneWidget);
    expect(find.byType(DSkeleton), findsWidgets);
    expect(find.widgetWithText(DButton, 'Load more'), findsNothing);
    expect(tester.takeException(), isNull);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(DSkeletonRegion), findsNothing);
    expect(search.globalState(_site).hits, hasLength(3));
    expect(find.text('deploy 1', findRichText: true), findsOneWidget);
    expect(find.text('deploy 3', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _mobile);
}

ChatSearchHit _hit(int id) => ChatSearchHit(
  message: ChatMessage(
    id: id,
    channelId: 9,
    cooked: '<p>deploy $id</p>',
    author: const ChatMessageAuthor(id: 2, username: 'sam'),
    createdAt: DateTime.utc(2026, 10, 2),
  ),
  channel: const ChatChannel(
    id: 9,
    title: 'Ops',
    kind: ChatChannelKind.category,
  ),
  excerpt: 'deploy $id',
);

Future<ShellController> _pump(WidgetTester tester, FakeDiscourseApi api) async {
  tester.view.physicalSize = const Size(320, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: PluginUiScope.own(
        chatPluginId,
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: ChatSearchView(siteUrl: _site)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return shell;
}

class _LoadingApi extends FakeDiscourseApi {
  _LoadingApi(this.completion, {required this.heldOffset})
    : super(
        user: _user,
        chatSearchPagesByKey: {
          FakeDiscourseApi.chatSearchKey('deploy'): ChatSearchPage(
            hits: [_hit(1), _hit(2)],
            hasMore: true,
          ),
          FakeDiscourseApi.chatSearchKey('deploy', offset: 2): ChatSearchPage(
            hits: [_hit(3)],
          ),
        },
      );
  final Completer<void> completion;
  final int heldOffset;

  @override
  Future<ChatSearchPage> searchChatMessages({
    required String siteUrl,
    required String apiKey,
    required String query,
    int? channelId,
    ChatSearchSort sort = ChatSearchSort.relevance,
    int offset = 0,
    int limit = ChatSearchPage.defaultPageSize,
    bool excludeThreads = false,
    String? clientId,
  }) async {
    final page = await super.searchChatMessages(
      siteUrl: siteUrl,
      apiKey: apiKey,
      query: query,
      channelId: channelId,
      sort: sort,
      offset: offset,
      limit: limit,
      excludeThreads: excludeThreads,
      clientId: clientId,
    );
    if (offset == heldOffset) await completion.future;
    return page;
  }
}
