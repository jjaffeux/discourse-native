import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://chat.example';

void main() {
  testWidgets('stays pinned while the message stream scrolls', (tester) async {
    final messages = [for (var id = 1; id <= 80; id++) _message(id)];
    final fixture = await _fixture(
      pages: {
        FakeDiscourseApi.chatMessagesKey(9): (
          messages: messages,
          canLoadMorePast: false,
          canLoadMoreFuture: false,
        ),
      },
    );
    addTearDown(fixture.shell.dispose);
    await tester.pumpWidget(_TestView(shell: fixture.shell));
    await tester.pumpAndSettle();

    final bar = find.byKey(const ValueKey('chat-composer'));
    expect(find.byTooltip('Add to message'), findsNothing);
    expect(find.byTooltip('Add emoji'), findsNothing);
    expect(find.byKey(const ValueKey('chat-composer-send')), findsOneWidget);
    final before = tester.getRect(bar);
    final scrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.up,
    );
    expect(scrollable, findsOneWidget);

    await tester.drag(scrollable, const Offset(0, 400));
    await tester.pump();

    expect(tester.getRect(bar), before);
    expect(before.bottom, closeTo(588, 1));
  });

  testWidgets('sends markdown and starts a clean document', (tester) async {
    final fixture = await _fixture(
      pages: {
        FakeDiscourseApi.chatMessagesKey(9): _emptyPage,
        FakeDiscourseApi.chatMessagesLatestKey(9): (
          messages: [_message(1)],
          canLoadMorePast: false,
          canLoadMoreFuture: false,
        ),
      },
    );
    addTearDown(fixture.shell.dispose);
    await tester.pumpWidget(_TestView(shell: fixture.shell));
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    await tester.enterText(field, '**hello** chat');
    await tester.pump();
    final send = find.byKey(const ValueKey('chat-composer-send'));
    expect(tester.widget<IconButton>(send).onPressed, isNotNull);
    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(fixture.api.chatMessagesSent, [
      (siteUrl: _site, channelId: 9, message: '**hello** chat', threadId: null),
    ]);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(fixture.shell.chat.stream(_site, 9).messageIds, [1]);
  });

  testWidgets('shares the selection formatting menu with topics', (
    tester,
  ) async {
    final fixture = await _fixture(
      pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
    );
    addTearDown(fixture.shell.dispose);
    await tester.pumpWidget(_TestView(shell: fixture.shell));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Bold'), findsNothing);
    expect(find.byTooltip('Italic'), findsNothing);

    final field = tester.widget<TextField>(find.byType(TextField));
    field.controller!.value = const TextEditingValue(
      text: 'format me',
      selection: TextSelection(baseOffset: 0, extentOffset: 6),
    );
    field.focusNode!.requestFocus();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('composer-selection-toolbar')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Italic'));
    await tester.pump();

    expect(field.controller!.text, '*format* me');
  });
}

const ChatMessagePage _emptyPage = (
  messages: [],
  canLoadMorePast: false,
  canLoadMoreFuture: false,
);

ChatMessage _message(int id) => ChatMessage(
  id: id,
  channelId: 9,
  cooked: '<p>Message $id</p>',
  author: const ChatMessageAuthor(id: 2, username: 'sam'),
  createdAt: DateTime.utc(2026, 8, 11, 0, 0, id),
);

Future<({ShellController shell, FakeDiscourseApi api})> _fixture({
  required Map<String, ChatMessagePage> pages,
}) async {
  final api = FakeDiscourseApi(chatMessagesByKey: pages);
  final authenticator = FakeAuthenticator()..keys[_site] = 'key';
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      const DiscourseInstance(url: _site, title: 'Chat', apiVersion: 4),
    ]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  shell.store.put(
    _site,
    const ChatChannel(
      id: 9,
      title: 'design',
      kind: ChatChannelKind.category,
      membership: ChatMembership(following: true),
    ),
  );
  return (shell: shell, api: api);
}

final class _TestView extends StatelessWidget {
  const _TestView({required this.shell});

  final ShellController shell;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: shell,
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: ChatChannelView(channelId: 9)),
    ),
  );
}
