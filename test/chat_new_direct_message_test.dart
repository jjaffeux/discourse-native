import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/chat/chat_direct_message_search.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_chatting_fixture.dart';

void main() {
  late StartChattingApi api;
  late ShellController shell;
  final dialog = find.byKey(const ValueKey('chat-new-direct-message-dialog'));
  final search = find.byKey(const ValueKey('chat-new-direct-message-search'));
  final startGroup = find.byKey(
    const ValueKey('chat-new-group-direct-message'),
  );
  final createGroup = find.byKey(
    const ValueKey('chat-create-group-direct-message'),
  );
  Finder user(String username) =>
      find.byKey(ValueKey('chat-new-direct-message-user-$username'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = StartChattingApi();
    shell = await startChattingShell(api, maximumMembers: 3);
  });
  tearDown(() async {
    shell.dispose();
    await shell.pluginTeardown;
  });

  Future<void> pump(
    WidgetTester tester, {
    double scale = 1,
    bool rtl = false,
  }) async {
    await tester.pumpWidget(
      StartChattingFixture(shell: shell, textScale: scale, rtl: rtl),
    );
    tester
        .widget<DButton>(find.byKey(const ValueKey('open-start-chatting')))
        .focusNode!
        .requestFocus();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('open-start-chatting')));
    await tester.pumpAndSettle();
  }

  Future<void> query(WidgetTester tester, String text) async {
    await tester.enterText(search, text);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  Future<void> primaryK(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'group creation comes first, then recent chats and followed channels '
    'interleaved by activity',
    (tester) async {
      await pump(tester);
      final command = tester
          .widget<DCommand<String>>(find.byType(DCommand<String>))
          .controller!;
      expect(command.value, 'new-group');
      expect(
        tester.getBottomLeft(startGroup).dy,
        lessThan(tester.getTopLeft(find.text('Recent conversations')).dy),
      );
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(command.value, 'c-55');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(command.value, 'c-60');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(command.value, 'c-56');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.id, 'chat-c-56');
      expect(api.directMessageChannelRequests, isEmpty);
      expect(dialog, findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('Escape and Cmd K dismiss and restore trigger focus', (
    tester,
  ) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(
      tester
          .widget<DButton>(find.byKey(const ValueKey('open-start-chatting')))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await primaryK(tester);
    expect(dialog, findsOneWidget);
    await primaryK(tester);
    expect(dialog, findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'server results retain ranking and disabled users are skipped by keyboard',
    (tester) async {
      api.pendingSearches['alias'] = Completer();
      await pump(tester);
      await tester.enterText(search, 'alias');
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Searching…'), findsOneWidget);
      api.pendingSearches['alias']!.complete(
        ChatDirectMessageSearchResults([
          const ChatDirectMessageUser(
            identifier: 'u-disabled',
            matchQuality: 1,
            enabled: false,
            username: 'disabled',
          ),
          startChattingPeople[1],
          startChattingPeople[0],
        ]),
      );
      await tester.pumpAndSettle();
      final command = tester
          .widget<DCommand<String>>(find.byType(DCommand<String>))
          .controller!;
      expect(command.value, 'u-3');
      expect(user('theo'), findsOneWidget);
      expect(user('maya'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(api.directMessageChannelsRequested, ['theo']);
      expect(shell.currentContent?.id, 'chat-c-57');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('search finds followed public channels and opens them', (
    tester,
  ) async {
    await pump(tester);
    await query(tester, 'general');
    expect(
      api.chatDirectMessageSearchRequests.last.includeCategoryChannels,
      isTrue,
    );
    expect(find.text('Channels'), findsOneWidget);
    final channel = find.byKey(
      const ValueKey('chat-new-direct-message-channel-60'),
    );
    expect(channel, findsOneWidget);
    expect(
      tester
          .widget<DCommand<String>>(find.byType(DCommand<String>))
          .controller!
          .value,
      'c-60',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'chat-c-60');
    expect(dialog, findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'stale search cannot replace a newer query or group composition',
    (tester) async {
      api.pendingSearches['maya'] = Completer();
      await pump(tester);
      await tester.enterText(search, 'maya');
      await tester.pump(const Duration(milliseconds: 350));
      await query(tester, 'theo');
      api.pendingSearches['maya']!.complete(
        ChatDirectMessageSearchResults([startChattingPeople[0]]),
      );
      await tester.pumpAndSettle();
      expect(user('theo'), findsOneWidget);
      expect(user('maya'), findsNothing);
      api.pendingSearches['old'] = Completer();
      await tester.enterText(search, 'old');
      await tester.pump(const Duration(milliseconds: 350));
      await query(tester, '');
      await tester.ensureVisible(startGroup);
      await tester.tap(startGroup);
      await tester.pumpAndSettle();
      api.pendingSearches['old']!.complete(
        ChatDirectMessageSearchResults([startChattingPeople[0]]),
      );
      await tester.pumpAndSettle();
      expect(user('maya'), findsNothing);
      expect(find.text('Search for people or groups to add.'), findsOneWidget);
    },
  );

  testWidgets(
    'group members clear search, enforce limits, and can be removed',
    (tester) async {
      await pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('New group chat'), findsOneWidget);
      expect(tester.widget<DButton>(createGroup).onPressed, isNull);
      await query(tester, 'design');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('3 of 3 people selected'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: search, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        isEmpty,
      );
      await query(tester, 'maya');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('3 of 3 people selected'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat-new-group-member-u-2')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('chat-new-group-member-g-8')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('1 of 3 people selected'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('chat-new-group-name')),
        'Design review',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(api.directMessageChannelRequests, isEmpty);
      await tester.tap(createGroup);
      await tester.pumpAndSettle();
      final request = api.directMessageChannelRequests.single;
      expect(request.usernames, ['maya']);
      expect(request.name, 'Design review');
      expect(request.upsert, isFalse);
      expect(shell.currentContent?.id, 'chat-c-59');
      expect(
        api.chatDirectMessageSearchRequests.every(
          (request) =>
              !request.includeDirectMessageChannels &&
              !request.includeCategoryChannels,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('failed creation retries and dismissal owns late completion', (
    tester,
  ) async {
    await pump(tester);
    await query(tester, 'maya');
    api.failCreation = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Could not start this chat.'), findsOneWidget);
    expect(user('maya'), findsOneWidget);
    api.failCreation = false;
    api.creationGate = Completer<void>();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('Opening conversation…'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(api.directMessageChannelRequests, hasLength(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    // Complete during the exit transition while the dialog is still mounted.
    await tester.pump(const Duration(milliseconds: 10));
    api.creationGate!.complete();
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(shell.currentContent?.id, isNot('chat-c-55'));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('empty and failed searches recover when typing again', (
    tester,
  ) async {
    await pump(tester);
    await query(tester, 'nobody');
    expect(
      find.text('No matches found. Try another name or username.'),
      findsOneWidget,
    );
    api.failSearch = true;
    await query(tester, 'error');
    expect(find.text('Could not search Chat.'), findsOneWidget);
    api.failSearch = false;
    await query(tester, 'maya');
    expect(user('maya'), findsOneWidget);
    expect(find.byType(DAlert), findsNothing);
  });

  testWidgets('typing never resizes or moves the dialog', (tester) async {
    await pump(tester);
    final bounds = tester.getRect(dialog);
    final input = tester.getRect(search);
    for (final text in ['m', 'maya', 'nobody', '']) {
      await tester.enterText(search, text);
      await tester.pump();
      expect(tester.getRect(dialog), bounds, reason: 'searching "$text"');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(tester.getRect(dialog), bounds, reason: 'results for "$text"');
      expect(tester.getRect(search), input, reason: 'results for "$text"');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow RTL and large text keep group controls reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(440, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pump(tester, scale: 2, rtl: true);
    await tester.ensureVisible(startGroup);
    await tester.tap(startGroup);
    await tester.pumpAndSettle();
    await query(tester, 'maya');
    await tester.tap(user('maya'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(createGroup);
    expect(tester.widget<DButton>(createGroup).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });
}
