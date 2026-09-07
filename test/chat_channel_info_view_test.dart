import 'dart:async';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_info_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_route.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'joffreyj');
const _memberError = "Couldn't load this channel's members.";

void main() {
  group('ChatChannelInfoView members', () {
    testWidgets('advances by server rows after filtering malformed members', (
      tester,
    ) async {
      final api = _MemberApi({
        _pageKey(): _page([1], rowCount: 20, more: true),
        _pageKey(offset: 20): _page([21]),
      });
      await _pumpMembers(tester, api);

      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(_requests(api), [('', 0), ('', 20)]);
      expect(_visibleMembers(tester), ['member1', 'member21']);
      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('pages and retries while all received members are filtered', (
      tester,
    ) async {
      final api = _MemberApi({
        _pageKey(): _page([], rowCount: 20, more: true),
        _pageKey(offset: 20): _page([], rowCount: 20, more: true),
        _pageKey(offset: 40): _page([41]),
      })..failures[_pageKey(offset: 20)] = StateError('offline');
      await _pumpMembers(tester, api);

      expect(find.text('No members.'), findsNothing);
      expect(find.text('Load more').hitTestable(), findsOneWidget);
      expect(_requests(api), [('', 0)]);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(find.text(_memberError), findsOneWidget);
      expect(find.text('Retry').hitTestable(), findsOneWidget);
      expect(_requests(api), [('', 0), ('', 20)]);
      api.failures.clear();
      final gate = _holdPage(api, offset: 20);
      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(find.text(_memberError), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_requests(api), [('', 0), ('', 20), ('', 20)]);
      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('No members.'), findsNothing);
      expect(find.text('Load more').hitTestable(), findsOneWidget);
      expect(_requests(api), [('', 0), ('', 20), ('', 20)]);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(_visibleMembers(tester), ['member41']);
      expect(find.text('Load more'), findsNothing);
      expect(_requests(api), [('', 0), ('', 20), ('', 20), ('', 40)]);
    });

    for (final terminal in [
      (rowCount: 1, more: false),
      (rowCount: 0, more: true),
    ]) {
      testWidgets('stops an initially empty page with $terminal', (
        tester,
      ) async {
        final api = _MemberApi({
          _pageKey(): _page(
            [],
            rowCount: terminal.rowCount,
            more: terminal.more,
          ),
        });
        await _pumpMembers(tester, api);

        expect(find.text('No members.'), findsOneWidget);
        expect(find.text('Load more'), findsNothing);
        expect(find.text('Retry'), findsNothing);
        expect(_requests(api), [('', 0)]);
      });
    }

    testWidgets('advances past overlapping and all-duplicate pages', (
      tester,
    ) async {
      final api = _MemberApi({
        _pageKey(): _page(_ids(1, 20), more: true),
        _pageKey(offset: 20): _page(_ids(11, 30), more: true),
        _pageKey(offset: 40): _page(_ids(11, 30), more: true),
        _pageKey(offset: 60): _page([31]),
      });
      await _pumpMembers(tester, api, size: const Size(1000, 800));

      await _scrollToEnd(tester);
      expect(_requests(api), [('', 0), ('', 20)]);
      await _scrollToEnd(tester);
      expect(_requests(api), [('', 0), ('', 20), ('', 40)]);
      expect(find.text('Load more').hitTestable(), findsOneWidget);

      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(_requests(api), [('', 0), ('', 20), ('', 40), ('', 60)]);

      tester.view.physicalSize = const Size(1000, 2400);
      await tester.pumpAndSettle();
      expect(_visibleMembers(tester), _names(1, 31));
      expect(find.text('Load more'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('can load a full page fitting a tall viewport only once', (
      tester,
    ) async {
      final api = _MemberApi({
        _pageKey(): _page(_ids(1, 20), more: true),
        _pageKey(offset: 20): _page([21]),
      });
      final gate = _holdPage(api, offset: 20);
      await _pumpMembers(tester, api);

      expect(_visibleMembers(tester), _names(1, 20));
      expect(find.text('Load more').hitTestable(), findsOneWidget);
      expect(_requests(api), [('', 0)]);

      await tester.tap(find.text('Load more'));
      await tester.tap(find.text('Load more'));
      await tester.pump();
      expect(_requests(api), [('', 0), ('', 20)]);
      expect(_visibleMembers(tester), _names(1, 20));
      expect(find.text('Load more'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(_visibleMembers(tester), _names(1, 21));
      expect(find.text('Load more'), findsNothing);
      expect(_requests(api), [('', 0), ('', 20)]);
    });

    testWidgets('retains rows and retries a failed page at the same offset', (
      tester,
    ) async {
      final api = _MemberApi({
        _pageKey(): _page(_ids(1, 20), more: true),
        _pageKey(offset: 20): _page([21]),
      })..failures[_pageKey(offset: 20)] = StateError('offline');
      await _pumpMembers(tester, api, size: const Size(1000, 800));

      await _scrollToEnd(tester);
      tester.view.physicalSize = const Size(1000, 2400);
      await tester.pumpAndSettle();
      expect(_visibleMembers(tester), _names(1, 20));
      expect(find.text(_memberError), findsOneWidget);
      expect(find.text('Retry').hitTestable(), findsOneWidget);

      tester.view.physicalSize = const Size(1000, 650);
      await tester.pumpAndSettle();
      await _scrollToEnd(tester);
      await tester.ensureVisible(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Retry').hitTestable(), findsOneWidget);
      expect(_requests(api), [('', 0), ('', 20)]);

      api.failures.clear();
      final gate = _holdPage(api, offset: 20);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(find.text(_memberError), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(_requests(api), [('', 0), ('', 20), ('', 20)]);

      gate.complete();
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1000, 2400);
      await tester.pumpAndSettle();
      expect(_visibleMembers(tester), _names(1, 21));
      expect(find.text(_memberError), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Load more'), findsNothing);
    });

    for (final staleFailure in [false, true]) {
      final outcome = staleFailure ? 'failure' : 'success';
      testWidgets('search resets paging and ignores an older page $outcome', (
        tester,
      ) async {
        final api = _MemberApi({
          _pageKey(): _page(_ids(1, 20), more: true),
          _pageKey(offset: 20): _page([21]),
          _pageKey(username: 'new'): _page(List.filled(20, 90), more: true),
          _pageKey(username: 'new', offset: 20): _page([91]),
        });
        if (staleFailure) {
          api.failures[_pageKey(offset: 20)] = StateError('offline');
        }
        final gate = _holdPage(api, offset: 20);
        await _pumpMembers(tester, api);

        await tester.tap(find.text('Load more'));
        await tester.pump();
        await tester.enterText(_filter, ' new ');
        await tester.pump(const Duration(milliseconds: 299));
        expect(_requests(api), [('', 0), ('', 20)]);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pumpAndSettle();
        expect(_visibleMembers(tester), ['member90']);

        gate.complete();
        await tester.pumpAndSettle();
        expect(_visibleMembers(tester), ['member90']);
        expect(find.text(_memberError), findsNothing);
        expect(find.text('Load more').hitTestable(), findsOneWidget);

        await tester.tap(find.text('Load more'));
        await tester.pumpAndSettle();
        expect(_visibleMembers(tester), ['member90', 'member91']);
        expect(find.text('Load more'), findsNothing);

        await tester.enterText(_filter, '');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(_visibleMembers(tester), _names(1, 20));
        expect(find.text('Load more').hitTestable(), findsOneWidget);
        expect(_requests(api), [
          ('', 0),
          ('', 20),
          ('new', 0),
          ('new', 20),
          ('', 0),
        ]);
      });
    }

    for (final countChanged in [false, true]) {
      final trigger = countChanged
          ? 'membership count change'
          : 'route refresh';
      testWidgets('$trigger restarts the active filter at offset zero', (
        tester,
      ) async {
        final api = _MemberApi({
          _pageKey(): _page([1]),
          _pageKey(username: 'new'): _page(List.filled(20, 90), more: true),
          _pageKey(username: 'new', offset: 20): _page([91]),
        });
        final shell = await _pumpMembers(tester, api);
        await tester.enterText(_filter, 'new');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Load more'));
        await tester.pumpAndSettle();

        api.chatChannelMemberPagesByKey[_pageKey(username: 'new')] = _page([
          92,
        ]);
        if (countChanged) {
          shell.chatRecords.put(_site, _channel(membershipsCount: 101));
        } else {
          await shell.pluginSession
              .require(chatShellService)
              .hydratePluginRoute(
                _site,
                ChatRoute.info(
                  channelId: 9,
                  tab: ChatChannelInfoTab.members,
                ).routeId,
                force: true,
              );
        }
        await tester.pumpAndSettle();

        expect(_visibleMembers(tester), ['member92']);
        expect(find.text('Load more'), findsNothing);
        expect(_requests(api), [('', 0), ('new', 0), ('new', 20), ('new', 0)]);
      });
    }

    testWidgets(
      'retries an initial failure and shows a terminal empty result',
      (tester) async {
        final api = _MemberApi({_pageKey(): _page([])})
          ..failures[_pageKey()] = StateError('offline');
        await _pumpMembers(tester, api);

        expect(find.text(_memberError), findsOneWidget);
        expect(find.text('Retry').hitTestable(), findsOneWidget);
        expect(find.text('No members.'), findsNothing);
        api.failures.clear();
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();

        expect(find.text('No members.'), findsOneWidget);
        expect(find.text('Retry'), findsNothing);
        expect(find.text('Load more'), findsNothing);
        expect(_requests(api), [('', 0), ('', 0)]);
      },
    );

    for (final terminal in [
      (label: 'short', ids: [21], more: false),
      (label: 'full marked terminal', ids: _ids(21, 40), more: false),
      (label: 'empty marked nonterminal', ids: <int>[], more: true),
    ]) {
      testWidgets('stops paging when the next page is ${terminal.label}', (
        tester,
      ) async {
        final api = _MemberApi({
          _pageKey(): _page(_ids(1, 20), more: true),
          _pageKey(offset: 20): _page(terminal.ids, more: terminal.more),
        });
        await _pumpMembers(tester, api);
        await tester.tap(find.text('Load more'));
        await tester.pumpAndSettle();

        expect(_visibleMembers(tester), [
          ..._names(1, 20),
          for (final id in terminal.ids) 'member$id',
        ]);
        expect(find.text('Load more'), findsNothing);
        expect(find.text('Retry'), findsNothing);
        tester.view.physicalSize = const Size(1000, 800);
        await tester.pumpAndSettle();
        await _scrollToEnd(tester);
        expect(_requests(api), [('', 0), ('', 20)]);
      });
    }
  });
}

Finder get _filter => find.byKey(const ValueKey('chat-channel-member-filter'));

List<int> _ids(int first, int last) => [
  for (var id = first; id <= last; id++) id,
];

List<String> _names(int first, int last) => [
  for (final id in _ids(first, last)) 'member$id',
];

Iterable<String?> _visibleMembers(WidgetTester tester) => tester
    .widgetList<Text>(find.textContaining(RegExp(r'^member\d+$')))
    .map((text) => text.data);

Iterable<(String, int)> _requests(FakeDiscourseApi api) => api
    .chatChannelMembersRequested
    .map((request) => (request.username, request.offset));

String _pageKey({String username = '', int offset = 0}) =>
    FakeDiscourseApi.chatChannelMembersKey(
      9,
      username: username,
      offset: offset,
    );

ChatChannelMembersPage _page(
  List<int> ids, {
  int? rowCount,
  bool more = false,
}) => (
  members: [for (final id in ids) ChatUser(id: id, username: 'member$id')],
  rowCount: rowCount ?? ids.length,
  totalRows: 100,
  canLoadMore: more,
);

ChatChannel _channel({int membershipsCount = 100}) => ChatChannel(
  id: 9,
  title: 'Bugs',
  kind: ChatChannelKind.category,
  membership: const ChatMembership(following: true),
  membershipsCount: membershipsCount,
);

Future<void> _scrollToEnd(WidgetTester tester) async {
  final list = tester.widget<ListView>(
    find.byKey(const ValueKey('chat-channel-member-list')),
  );
  final scroll = list.controller!;
  scroll.jumpTo(scroll.position.maxScrollExtent);
  await tester.pumpAndSettle();
}

Future<ShellController> _pumpMembers(
  WidgetTester tester,
  _MemberApi api, {
  Size size = const Size(1000, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
  await controller.chat.loadChannels(_site);
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: PluginUiScope.own(
        chatPluginId,
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ChatChannelInfoView(
              key: const ValueKey('$_site/9/members'),
              siteUrl: _site,
              channelId: 9,
              tab: ChatChannelInfoTab.members,
              chat: controller.chat,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Completer<void> _holdPage(_MemberApi api, {required int offset}) {
  final gate = Completer<void>();
  api.gates[_pageKey(offset: offset)] = gate;
  addTearDown(() {
    if (!gate.isCompleted) gate.complete();
  });
  return gate;
}

class _MemberApi extends FakeDiscourseApi {
  _MemberApi(Map<String, ChatChannelMembersPage> pages)
    : super(
        user: _user,
        chatChannelsBySite: {
          _site: ChatChannels(public: [_channel()]),
        },
        chatChannelMemberPagesByKey: pages,
      );

  final gates = <String, Completer<void>>{};
  final failures = <String, Object>{};

  @override
  Future<ChatChannelMembersPage> chatChannelMembers({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String username = '',
    int offset = 0,
    int limit = 20,
    String? clientId,
  }) async {
    final page = await super.chatChannelMembers(
      siteUrl: siteUrl,
      apiKey: apiKey,
      channelId: channelId,
      username: username,
      offset: offset,
      limit: limit,
      clientId: clientId,
    );
    final key = _pageKey(username: username, offset: offset);
    await gates[key]?.future;
    if (failures[key] case final error?) throw error;
    return page;
  }
}
