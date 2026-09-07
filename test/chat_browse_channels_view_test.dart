import 'dart:async';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_browse_channels_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'joffreyj');
const _emptyMessage = 'No channels match these filters.';

void main() {
  group('ChatBrowseChannelsView', () {
    for (final joined in [true, false]) {
      final membership = joined ? 'Joined' : 'Not joined';

      testWidgets('$membership can reach matches after a hidden first page', (
        tester,
      ) async {
        final api = _BrowseApi(
          chatBrowsePagesByKey: {
            FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
              channels: [
                _channel(1, following: !joined),
                _channel(2, following: !joined),
              ],
              hasMore: true,
            ),
            FakeDiscourseApi.chatBrowseKey(offset: 2): ChatChannelBrowsePage(
              channels: [_channel(3, following: joined)],
            ),
          },
        );
        await _pumpBrowse(tester, api);
        await _selectMembership(tester, membership);

        expect(_card(1), findsNothing);
        expect(_card(2), findsNothing);
        expect(find.text(_emptyMessage), findsNothing);
        expect(find.text('Load more'), findsOneWidget);
        expect(_offsets(api), [0]);

        await tester.tap(find.text('Load more'));
        await tester.pumpAndSettle();

        expect(_card(3), findsOneWidget);
        expect(find.text('Load more'), findsNothing);
        expect(_offsets(api), [0, 2]);

        await _selectMembership(tester, 'All');

        expect(_card(1), findsOneWidget);
        expect(_card(2), findsOneWidget);
        expect(_card(3), findsOneWidget);
        expect(_offsets(api), [0, 2]);
      });

      testWidgets('$membership can page after changing the last visible row', (
        tester,
      ) async {
        final api = _BrowseApi(
          chatBrowsePagesByKey: {
            FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
              channels: [_channel(1, following: joined)],
              hasMore: true,
            ),
            FakeDiscourseApi.chatBrowseKey(offset: 1): ChatChannelBrowsePage(
              channels: [_channel(2, following: joined)],
            ),
          },
        );
        await _pumpBrowse(tester, api);
        await _selectMembership(tester, membership);

        await tester.tap(find.text(joined ? 'Unfollow' : 'Join'));
        await tester.pumpAndSettle();

        expect(api.chatChannelFollowsUpdated, [
          (channelId: 1, following: !joined),
        ]);
        expect(_card(1), findsNothing);
        expect(find.text('Load more'), findsOneWidget);
        expect(_offsets(api), [0]);

        await tester.tap(find.text('Load more'));
        await tester.pumpAndSettle();

        expect(_card(2), findsOneWidget);
        expect(_offsets(api), [0, 1]);
      });
    }

    testWidgets('keeps paging explicitly across consecutive hidden pages', (
      tester,
    ) async {
      final api = _BrowseApi(
        chatBrowsePagesByKey: {
          for (var offset = 0; offset < 3; offset++)
            FakeDiscourseApi.chatBrowseKey(
              offset: offset,
            ): ChatChannelBrowsePage(
              channels: [_channel(offset + 1)],
              hasMore: offset < 2,
            ),
        },
      );
      await _pumpBrowse(tester, api);
      await _selectMembership(tester, 'Joined');

      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(find.text('Load more'), findsOneWidget);
      expect(find.text(_emptyMessage), findsNothing);
      expect(_offsets(api), [0, 1]);

      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(find.text(_emptyMessage), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      expect(find.text('Try again'), findsNothing);
      expect(_offsets(api), [0, 1, 2]);
    });

    testWidgets('retries a failed hidden page at the same server offset', (
      tester,
    ) async {
      final api = _BrowseApi(
        chatBrowsePagesByKey: {
          FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
            channels: [_channel(1), _channel(2)],
            hasMore: true,
          ),
        },
      );
      await _pumpBrowse(tester, api);
      await _selectMembership(tester, 'Joined');

      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(find.text('Try again'), findsOneWidget);
      expect(find.text(_emptyMessage), findsNothing);
      expect(_offsets(api), [0, 2]);

      await _selectMembership(tester, 'All');
      expect(_card(1), findsOneWidget);
      expect(_card(2), findsOneWidget);
      await _selectMembership(tester, 'Joined');

      api.chatBrowsePagesByKey[FakeDiscourseApi.chatBrowseKey(offset: 2)] =
          ChatChannelBrowsePage(channels: [_channel(3, following: true)]);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(_card(3), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(_offsets(api), [0, 2, 2]);
    });

    testWidgets('can pull to refresh an exhausted empty filtered result', (
      tester,
    ) async {
      final api = _BrowseApi(
        chatBrowsePagesByKey: {
          FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
            channels: [_channel(1)],
          ),
        },
      );
      await _pumpBrowse(tester, api);
      await _selectMembership(tester, 'Joined');

      expect(find.text(_emptyMessage), findsOneWidget);
      expect(find.text('Load more'), findsNothing);

      api.chatBrowsePagesByKey[FakeDiscourseApi.chatBrowseKey()] =
          ChatChannelBrowsePage(channels: [_channel(2, following: true)]);
      await tester.drag(find.byType(ListView), const Offset(0, 350));
      await tester.pumpAndSettle();

      expect(_card(2), findsOneWidget);
      expect(find.text(_emptyMessage), findsNothing);
      expect(_offsets(api), [0, 0]);
    });

    testWidgets('retries an initial failure from offset zero', (tester) async {
      final api = _BrowseApi(chatBrowsePagesByKey: {});
      await _pumpBrowse(tester, api);

      expect(find.text('Try again'), findsOneWidget);
      api.chatBrowsePagesByKey[FakeDiscourseApi.chatBrowseKey()] =
          const ChatChannelBrowsePage();
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text(_emptyMessage), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Load more'), findsNothing);
      expect(_offsets(api), [0, 0]);
    });

    testWidgets('admits only one next-page request while rows are hidden', (
      tester,
    ) async {
      final api = _BrowseApi(
        chatBrowsePagesByKey: {
          FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
            channels: [_channel(1)],
            hasMore: true,
          ),
          FakeDiscourseApi.chatBrowseKey(offset: 1): ChatChannelBrowsePage(
            channels: [_channel(2, following: true)],
          ),
        },
      );
      final gate = _holdPage(api, offset: 1);
      await _pumpBrowse(tester, api);
      await _selectMembership(tester, 'Joined');

      await tester.tap(find.text('Load more'));
      await tester.tap(find.text('Load more'));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -100));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      expect(_offsets(api), [0, 1]);

      gate.complete();
      await tester.pumpAndSettle();

      expect(_card(2), findsOneWidget);
      expect(_offsets(api), [0, 1]);
    });

    testWidgets('ignores a hidden page that finishes after a filter reset', (
      tester,
    ) async {
      final api = _BrowseApi(
        chatBrowsePagesByKey: {
          FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
            channels: [_channel(1)],
            hasMore: true,
          ),
          FakeDiscourseApi.chatBrowseKey(offset: 1): ChatChannelBrowsePage(
            channels: [_channel(2, following: true)],
            hasMore: true,
          ),
          FakeDiscourseApi.chatBrowseKey(filter: 'new'): ChatChannelBrowsePage(
            channels: [_channel(3, following: true)],
          ),
        },
      );
      final gate = _holdPage(api, offset: 1);
      await _pumpBrowse(tester, api);
      await _selectMembership(tester, 'Joined');
      await tester.tap(find.text('Load more'));
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('chat-browse-filter')),
        'new',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(_card(3), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();

      expect(_card(1), findsNothing);
      expect(_card(2), findsNothing);
      expect(_card(3), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      expect(api.chatBrowseRequested, [
        for (final (filter, offset) in [('', 0), ('', 1), ('new', 0)])
          (
            filter: filter,
            status: ChatChannelBrowseStatus.all,
            offset: offset,
            limit: ChatChannelBrowsePage.pageSize,
          ),
      ]);
    });
  });
}

ChatChannel _channel(int id, {bool following = false}) => ChatChannel(
  id: id,
  title: 'Channel $id',
  kind: ChatChannelKind.category,
  canJoin: true,
  membership: ChatMembership(following: following),
);

Finder _card(int id) => find.byKey(ValueKey('chat-browse-channel-$id'));

Iterable<int> _offsets(FakeDiscourseApi api) =>
    api.chatBrowseRequested.map((request) => request.offset);

Future<void> _selectMembership(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('chat-browse-joined')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _pumpBrowse(WidgetTester tester, FakeDiscourseApi api) async {
  final authenticator = FakeAuthenticator()..keys[_site] = 'key';
  final controller = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _user),
    ]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(controller.dispose);
  await controller.load();
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: PluginUiScope.own(
        chatPluginId,
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: ChatBrowseChannelsView(siteUrl: _site)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Completer<void> _holdPage(_BrowseApi api, {required int offset}) {
  final gate = Completer<void>();
  api.gates[FakeDiscourseApi.chatBrowseKey(offset: offset)] = gate;
  addTearDown(() {
    if (!gate.isCompleted) gate.complete();
  });
  return gate;
}

class _BrowseApi extends FakeDiscourseApi {
  _BrowseApi({required super.chatBrowsePagesByKey}) : super(user: _user);

  final gates = <String, Completer<void>>{};

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
    final page = await super.browseChatChannels(
      siteUrl: siteUrl,
      apiKey: apiKey,
      filter: filter,
      status: status,
      offset: offset,
      limit: limit,
      clientId: clientId,
    );
    await gates[FakeDiscourseApi.chatBrowseKey(
          filter: filter,
          status: status,
          offset: offset,
        )]
        ?.future;
    return page;
  }
}
