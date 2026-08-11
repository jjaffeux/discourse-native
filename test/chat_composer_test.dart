import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
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

  testWidgets('focuses the field from any non-button composer space', (
    tester,
  ) async {
    final fixture = await _fixture(
      pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
    );
    addTearDown(fixture.shell.dispose);
    await tester.pumpWidget(_TestView(shell: fixture.shell));
    await tester.pumpAndSettle();

    final fieldFinder = find.byType(TextField);
    final sendFinder = find.byKey(const ValueKey('chat-composer-send'));
    final field = tester.widget<TextField>(fieldFinder);
    field.focusNode!.unfocus();
    await tester.pump();

    final bar = tester.getRect(find.byKey(const ValueKey('chat-composer')));
    final chromeTarget = bar.topLeft + const Offset(8, 8);
    expect(tester.getRect(fieldFinder).contains(chromeTarget), isFalse);
    expect(tester.getRect(sendFinder).contains(chromeTarget), isFalse);
    await tester.tapAt(chromeTarget);
    await tester.pump();

    expect(field.focusNode!.hasFocus, isTrue);

    field.focusNode!.unfocus();
    await tester.pump();
    final trailingTarget = Offset(bar.right - 2, bar.center.dy);
    expect(tester.getRect(fieldFinder).contains(trailingTarget), isFalse);
    expect(tester.getRect(sendFinder).contains(trailingTarget), isFalse);
    await tester.tapAt(trailingTarget);
    await tester.pump();

    expect(field.focusNode!.hasFocus, isTrue);

    field.focusNode!.unfocus();
    await tester.pump();
    expect(tester.widget<IconButton>(sendFinder).onPressed, isNull);
    await tester.tap(sendFinder);
    await tester.pump();

    expect(field.focusNode!.hasFocus, isFalse);
  });

  testWidgets('sends markdown and starts a clean, focused document', (
    tester,
  ) async {
    final fixture = await _fixture(
      pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
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

    final sent = fixture.api.chatMessagesSent.single;
    expect(sent.siteUrl, _site);
    expect(sent.channelId, 9);
    expect(sent.message, '**hello** chat');
    expect(sent.threadId, isNull);
    expect(sent.stagedId, startsWith('native-'));
    expect(sent.clientCreatedAt, isNotNull);
    expect(sent.clientCreatedAt!.isUtc, isTrue);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(fixture.shell.chat.stream(_site, 9).messageIds, isEmpty);
    expect(fixture.shell.chat.stream(_site, 9).localMessageIds, hasLength(1));
    expect(fixture.api.chatMessagesRequested, hasLength(1));
  });

  testWidgets('stages immediately without clearing the next draft', (
    tester,
  ) async {
    final sendGate = Completer<void>();
    final fixture = await _fixture(
      pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
      sendGate: sendGate,
      sentMessageId: 42,
    );
    addTearDown(fixture.shell.dispose);
    await tester.pumpWidget(_TestView(shell: fixture.shell));
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    await tester.enterText(field, 'first message');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
    await tester.pump();

    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(find.text('first message'), findsOneWidget);
    expect(find.text('Sending…'), findsOneWidget);
    expect(fixture.shell.chat.stream(_site, 9).localMessageIds, hasLength(1));
    expect(fixture.api.chatMessagesRequested, hasLength(1));

    await tester.enterText(field, 'next draft');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, 'next draft');

    sendGate.complete();
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(field).controller!.text, 'next draft');
    expect(fixture.api.chatMessagesRequested, hasLength(1));
    expect(fixture.api.chatMessagesSent, hasLength(1));
    expect(fixture.api.chatMessagesSent.single.stagedId, startsWith('native-'));
    expect(fixture.api.chatMessagesSent.single.clientCreatedAt, isNotNull);
  });

  testWidgets(
    'keeps an uncertain network failure on the row without resending',
    (tester) async {
      const failure = WriteException(WriteFailure.unreachable);
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
        sendFailure: failure,
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      final field = find.byType(TextField);
      await tester.enterText(field, 'keep me visible');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(find.text('keep me visible'), findsOneWidget);
      expect(find.text(failure.message), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(fixture.api.chatMessagesSent, hasLength(1));
    },
  );

  testWidgets('does not offer retry for a definitive refusal', (tester) async {
    const failure = WriteException(
      WriteFailure.validation,
      errors: ['That message is not allowed.'],
    );
    final fixture = await _fixture(
      pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
      sendFailure: failure,
    );
    addTearDown(fixture.shell.dispose);
    await tester.pumpWidget(_TestView(shell: fixture.shell));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'not allowed');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
    await tester.pumpAndSettle();

    expect(find.text(failure.message), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
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
  Completer<void>? sendGate,
  WriteException? sendFailure,
  int? sentMessageId,
}) async {
  final api = FakeDiscourseApi(
    chatMessagesByKey: pages,
    chatSendGate: sendGate,
    chatSendFailure: sendFailure,
    chatSentMessageId: sentMessageId ?? 1,
  );
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
