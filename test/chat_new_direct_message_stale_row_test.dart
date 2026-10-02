import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/chat/chat_direct_message_search.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_chatting_fixture.dart';

final _search = find.byKey(const ValueKey('chat-new-direct-message-search'));
final _createGroup = find.byKey(
  const ValueKey('chat-create-group-direct-message'),
);
final _newGroup = find.byKey(const ValueKey('chat-new-group-direct-message'));
Finder _user(String name) =>
    find.byKey(ValueKey('chat-new-direct-message-user-$name'));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final group in [false, true]) {
    for (final nextQuery in ['theo', '']) {
      testWidgets(
        'a ${group ? 'group' : 'direct'} recipient row cannot accept after changing query to "$nextQuery" before repaint',
        (tester) async {
          final api = StartChattingApi();
          final shell = await startChattingShell(api);
          addTearDown(shell.dispose);
          _size(tester);
          await tester.pumpWidget(StartChattingFixture(shell: shell));
          await tester.tap(find.byKey(const ValueKey('open-start-chatting')));
          await tester.pumpAndSettle();
          if (group) {
            await tester.tap(_newGroup);
            await tester.pumpAndSettle();
          }
          await _query(tester, 'maya');
          final retained = _item(tester, 'u-2').onSelected!;
          api.pendingSearches['theo'] = Completer();
          await tester.enterText(_search, nextQuery);
          // The old Native surface is still mounted until this frame paints.
          expect(_user('maya'), findsOneWidget);
          await tester.tap(_user('maya'));
          await tester.pump();
          if (group) {
            await tester.tap(_createGroup);
            await tester.pump();
          }
          expect(api.directMessageChannelRequests, isEmpty);
          expect(
            tester.widget<DCommandInput<String>>(_search).controller!.text,
            nextQuery,
          );
          expect(
            find.byKey(const ValueKey('chat-new-group-member-u-2')),
            findsNothing,
          );
          if (nextQuery.isEmpty) await tester.enterText(_search, 'theo');
          await tester.pump(const Duration(milliseconds: 350));
          // A retained row callback must also remain ineligible after repaint,
          // while the new lookup is pending and after its answer has arrived.
          retained('u-2');
          api.pendingSearches['theo']!.complete(
            ChatDirectMessageSearchResults([startChattingPeople[1]]),
          );
          await tester.pumpAndSettle();
          retained('u-2');
          await tester.pumpAndSettle();
          expect(api.directMessageChannelRequests, isEmpty);
          expect(
            tester.widget<DCommandInput<String>>(_search).controller!.text,
            'theo',
          );
          await tester.tap(_user('theo'));
          await tester.pumpAndSettle();
          if (group) {
            await tester.tap(_createGroup);
            await tester.pumpAndSettle();
          }
          expect(api.directMessageChannelRequests.single.usernames, ['theo']);
          expect(shell.currentContent?.id, group ? 'chat-c-59' : 'chat-c-57');
          expect(tester.takeException(), isNull);
        },
        variant: const TargetPlatformVariant({
          TargetPlatform.macOS,
          TargetPlatform.iOS,
        }),
      );
    }
  }

  testWidgets(
    'intentional group members remain selected across recipient queries',
    (tester) async {
      final api = StartChattingApi();
      final shell = await startChattingShell(api);
      addTearDown(shell.dispose);
      _size(tester);
      await tester.pumpWidget(StartChattingFixture(shell: shell));
      await tester.tap(find.byKey(const ValueKey('open-start-chatting')));
      await tester.pumpAndSettle();
      await tester.tap(_newGroup);
      await tester.pumpAndSettle();
      await _query(tester, 'maya');
      await tester.tap(_user('maya'));
      await tester.pumpAndSettle();
      await _query(tester, 'theo');
      expect(
        find.byKey(const ValueKey('chat-new-group-member-u-2')),
        findsOneWidget,
      );
      await tester.tap(_user('theo'));
      await tester.pumpAndSettle();
      await tester.tap(_createGroup);
      await tester.pumpAndSettle();
      expect(api.directMessageChannelRequests.single.usernames, [
        'maya',
        'theo',
      ]);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'a recent channel row cannot open after a new query before repaint',
    (tester) async {
      final api = StartChattingApi();
      final shell = await startChattingShell(api);
      addTearDown(shell.dispose);
      _size(tester);
      await tester.pumpWidget(StartChattingFixture(shell: shell));
      await tester.tap(find.byKey(const ValueKey('open-start-chatting')));
      await tester.pumpAndSettle();
      final channel = find.byKey(
        const ValueKey('chat-new-direct-message-channel-60'),
      );
      await tester.enterText(_search, 'theo');
      expect(channel, findsOneWidget);
      await tester.tap(channel);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.id, isNot('chat-c-60'));
      expect(
        tester.widget<DCommandInput<String>>(_search).controller!.text,
        'theo',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(_user('theo'));
      await tester.pumpAndSettle();
      expect(api.directMessageChannelRequests.single.usernames, ['theo']);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'the old New group row cannot discard a new query before repaint',
    (tester) async {
      final api = StartChattingApi();
      final shell = await startChattingShell(api);
      addTearDown(shell.dispose);
      _size(tester);
      await tester.pumpWidget(StartChattingFixture(shell: shell));
      await tester.tap(find.byKey(const ValueKey('open-start-chatting')));
      await tester.pumpAndSettle();
      await tester.enterText(_search, 'maya');
      expect(_newGroup, findsOneWidget);
      await tester.tap(_newGroup);
      await tester.pump();
      expect(_createGroup, findsNothing);
      expect(
        tester.widget<DCommandInput<String>>(_search).controller!.text,
        'maya',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(_user('maya'));
      await tester.pumpAndSettle();
      expect(api.directMessageChannelRequests.single.usernames, ['maya']);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.iOS,
    }),
  );
}

void _size(WidgetTester tester) {
  tester.view.physicalSize = defaultTargetPlatform == TargetPlatform.iOS
      ? const Size(390, 844)
      : const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _query(WidgetTester tester, String query) async {
  await tester.enterText(_search, query);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

DCommandItem<String> _item(WidgetTester tester, String value) => tester
    .widget<DCommandList<String>>(
      find.byKey(const ValueKey('chat-new-direct-message-results')),
    )
    .children
    .whereType<DCommandGroup<String>>()
    .expand((group) => group.items)
    .singleWhere((item) => item.value == value);
