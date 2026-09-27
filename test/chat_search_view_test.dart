import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_search.dart';
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
}

ChatSearchHit _hit(int id) => ChatSearchHit(
  message: ChatMessage(
    id: id,
    channelId: 9,
    cooked: '<p>deploy $id</p>',
    author: const ChatMessageAuthor(id: 2, username: 'sam'),
    createdAt: DateTime.utc(2026, 8, 25, 10),
  ),
  channel: const ChatChannel(
    id: 9,
    title: 'Ops',
    kind: ChatChannelKind.category,
  ),
  excerpt: 'deploy $id',
);

Future<void> _pump(WidgetTester tester, FakeDiscourseApi api) async {
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
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
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
}
