import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/keyboard_navigation.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

void main() {
  for (final openWithKeyboard in [false, true]) {
    testWidgets(
      'opening a topic with ${openWithKeyboard ? 'the keyboard' : 'the mouse'} keeps one row border as the cursor moves',
      (tester) async {
        final setup = await _setup(tester);
        if (openWithKeyboard) {
          await _moveTopic(tester, next: true);
          expect(_topicBorders(tester, 1), hasLength(1));
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          await tester.tap(find.text('Keyboard topic 1'));
        }
        await tester.pumpAndSettle();
        expect(setup.shell.currentContent?.topicId, 1);
        expect(_topicBorders(tester, 1), hasLength(1));
        expect(_topicBorders(tester, 1).single.width, 2);

        await _moveTopic(tester, next: true);
        expect(setup.shell.currentContent?.topicId, 1);
        _scrollable(tester, find.byType(TopicListView)).controller!.jumpTo(0);
        await tester.pumpAndSettle();
        expect(_topicBorders(tester, 1), hasLength(1));
        expect(_topicBorders(tester, 1).single.width, 1);
        expect(_topicBorders(tester, 2), hasLength(1));
        expect(_topicBorders(tester, 2).single.width, 2);

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer();
        addTearDown(mouse.removePointer);
        await mouse.moveTo(
          tester.getCenter(find.byKey(const ValueKey('inbox-row-2'))),
        );
        await tester.pumpAndSettle();
        expect(_topicBorders(tester, 2), hasLength(1));

        await _moveTopic(tester, next: false);
        expect(_topicBorders(tester, 1), hasLength(1));
        expect(_topicBorders(tester, 1).single.width, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [desktop, laptop]) {
    for (final openKey in [LogicalKeyboardKey.keyO, LogicalKeyboardKey.enter]) {
      testWidgets(
        '${size.width} ${openKey.keyLabel} reads, replies, returns, and selects the next topic',
        (tester) async {
          final setup = await _setup(tester, size: size);
          final shell = setup.shell;
          expect(shell.currentContent?.isTopic, isFalse);
          expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyJ), isFalse);
          expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyK), isFalse);
          expect(_selectedTopics(tester), isEmpty);

          await _moveTopic(tester, next: true);
          expect(_selectedTopics(tester), [1]);
          await _moveTopic(tester, next: true);
          expect(_selectedTopics(tester), [2]);
          expect(setup.api.topicsOpened, isEmpty);
          expect(await tester.sendKeyEvent(openKey), isTrue);
          await tester.pumpAndSettle();
          expect(shell.currentContent?.topicId, 2);
          expect(setup.api.topicPostNumbersOpened.last, 2);
          if (size == laptop) {
            await _moveTopic(tester, next: true, handled: false);
            expect(shell.currentContent?.topicId, 2);
          }

          await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
          await tester.pumpAndSettle();
          final selectedPost = _selectedPosts(tester).single;
          expect(selectedPost, 203);
          expect(shell.currentContent?.topicId, 2);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
          await tester.pumpAndSettle();
          expect(shell.visibleComposer?.target.replyToPostNumber, 3);
          expect(shell.visibleComposer?.focus.hasFocus, isTrue);

          final editor = find.descendant(
            of: find.byType(ComposerPanel),
            matching: find.byType(TextField),
          );
          await tester.enterText(
            editor,
            'A keyboard reply with enough detail.',
          );
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pumpAndSettle();
          expect(setup.api.created.single['topicId'], 2);
          expect(setup.api.created.single['replyToPostNumber'], 3);
          expect(shell.visibleComposer, isNull);

          expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyU), isTrue);
          await tester.pumpAndSettle();
          expect(shell.currentContent?.isTopic, isFalse);
          expect(_selectedTopics(tester), [2]);
          expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyJ), isFalse);
          await _moveTopic(tester, next: true);
          expect(_selectedTopics(tester), [3]);
          await tester.sendKeyEvent(openKey);
          await tester.pumpAndSettle();
          expect(shell.currentContent?.topicId, 3);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'list and reader commands keep independent selections in split view',
    (tester) async {
      final setup = await _setup(tester);
      await _moveTopic(tester, next: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pumpAndSettle();
      final posts = _selectedPosts(tester);
      final reader = _scrollable(tester, find.byType(TopicView));
      final offset = reader.controller!.offset;

      await _moveTopic(tester, next: true);
      expect(_selectedTopics(tester), [2]);
      expect(_selectedPosts(tester), posts);
      expect(setup.shell.currentContent?.topicId, 1);
      expect(reader.controller!.offset, offset);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();
      expect(_selectedTopics(tester), [2]);
      expect(_selectedPosts(tester), [102]);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isTrue);
      await tester.pumpAndSettle();
      expect(setup.shell.currentContent?.topicId, 2);
      expect(setup.shell.contentStack, hasLength(2));
    },
  );

  testWidgets(
    'topic selection reaches virtualized rows and continues into the next page',
    (tester) async {
      final setup = await _setup(tester);
      for (var i = 0; i < 31; i++) {
        await _moveTopic(tester, next: true);
      }
      expect(_selectedTopics(tester), [31]);
      expect(
        setup.api.feedPaths.where((path) => path == '/latest.json?page=1'),
        hasLength(1),
      );
      expect(setup.api.topicsOpened, isEmpty);
      expect(
        find.byKey(const ValueKey('topic-list-keyboard-31')).hitTestable(),
        findsOneWidget,
      );
      await _moveTopic(tester, next: true);
      expect(_selectedTopics(tester), [31]);
      await _moveTopic(tester, next: false);
      expect(_selectedTopics(tester), [30]);
    },
  );

  testWidgets('typing and modal focus suspend navigation and help', (
    tester,
  ) async {
    final setup = await _setup(tester);
    await _moveTopic(tester, next: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(setup.shell.visibleComposer?.focus.hasFocus, isTrue);
    await _moveTopic(tester, next: true, handled: false);
    for (final key in [
      LogicalKeyboardKey.keyO,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.keyU,
      LogicalKeyboardKey.keyJ,
      LogicalKeyboardKey.keyR,
    ]) {
      await tester.sendKeyEvent(key);
    }
    expect(setup.shell.currentContent?.topicId, 1);
    expect(_selectedTopics(tester), [1]);
    expect(setup.shell.visibleComposer?.target.replyToPostNumber, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('keyboard-shortcuts-help')),
      findsOneWidget,
    );
    await _moveTopic(tester, next: true, handled: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(setup.shell.currentContent?.topicId, 1);
    expect(_selectedTopics(tester), [1]);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('keyboard-shortcuts-help')), findsNothing);
  });
  for (final afterRequest in ['finish', 'open topic', 'focus search']) {
    testWidgets('a pending page respects $afterRequest', (tester) async {
      final gate = Completer<void>();
      final setup = await _setup(tester, nextPageGate: gate);
      for (var i = 0; i < 31; i++) {
        await _moveTopic(tester, next: true, settle: false);
      }
      expect(_selectedTopics(tester), [30]);
      expect(
        setup.api.feedPaths.where((path) => path == '/latest.json?page=1'),
        hasLength(1),
      );
      if (afterRequest == 'open topic') {
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyO), isTrue);
        await tester.pump();
      } else if (afterRequest == 'focus search') {
        await tester.tap(find.byType(EditableText).first);
        await tester.pump();
      }
      gate.complete();
      await tester.pumpAndSettle();
      expect(_selectedTopics(tester), [afterRequest == 'finish' ? 31 : 30]);
      expect(
        setup.shell.currentContent?.topicId,
        afterRequest == 'open topic' ? 30 : null,
      );
      if (afterRequest == 'focus search') {
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText).first)
              .focusNode
              .hasFocus,
          isTrue,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'a refreshed list preserves topic identity and does not skip a removed row',
    (tester) async {
      final setup = await _setup(tester);
      await _moveTopic(tester, next: true);
      await _moveTopic(tester, next: true);
      final original = setup.api.feeds['/latest.json']!;
      setup.api.feeds['/latest.json'] = [
        original[4],
        ...original.where((topic) => topic.id != 5),
      ];
      await setup.shell.loadFeed('latest', force: true);
      await tester.pumpAndSettle();
      expect(_selectedTopics(tester), [2]);
      await _moveTopic(tester, next: true);
      expect(_selectedTopics(tester), [3]);
      setup.api.feeds['/latest.json'] = setup.api.feeds['/latest.json']!
          .where((topic) => topic.id != 3)
          .toList();
      await setup.shell.loadFeed('latest', force: true);
      await tester.pumpAndSettle();
      await _moveTopic(tester, next: true);
      expect(_selectedTopics(tester), [4]);
    },
  );

  testWidgets(
    'each tab restores its own list cursor',
    (tester) async {
      final setup = await _setup(tester);
      final originalTab = setup.shell.activeTabId!;
      await _moveTopic(tester, next: true);
      await _moveTopic(tester, next: true);
      setup.shell.createTab();
      await tester.pumpAndSettle();
      final secondTab = setup.shell.activeTabId!;
      expect(secondTab, isNot(originalTab));
      expect(_selectedTopics(tester), isEmpty);
      await _moveTopic(tester, next: true);
      expect(_selectedTopics(tester), [1]);
      setup.shell.selectTab(originalTab);
      await tester.pumpAndSettle();
      expect(_selectedTopics(tester), [2]);
      setup.shell.selectTab(secondTab);
      await tester.pumpAndSettle();
      expect(_selectedTopics(tester), [1]);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.linux,
    }),
  );

  testWidgets('a pending page cannot move the cursor in another tab', (
    tester,
  ) async {
    final gate = Completer<void>();
    final setup = await _setup(tester, nextPageGate: gate);
    final originalTab = setup.shell.activeTabId!;
    for (var i = 0; i < 31; i++) {
      await _moveTopic(tester, next: true, settle: false);
    }
    expect(_selectedTopics(tester), [30]);
    setup.shell.createTab();
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(_selectedTopics(tester), isEmpty);
    setup.shell.selectTab(originalTab);
    await tester.pumpAndSettle();
    expect(_selectedTopics(tester), [30]);
    await _moveTopic(tester, next: true);
    expect(_selectedTopics(tester), [31]);
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets('manual post scrolling clears the reply target', (tester) async {
    final setup = await _setup(tester);
    await _moveTopic(tester, next: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    expect(_selectedPosts(tester), [103]);
    await tester.drag(find.byType(TopicView), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(_selectedPosts(tester), isEmpty);
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyR), isFalse);
    expect(setup.shell.visibleComposer, isNull);
  });
}

Iterable<BorderSide> _topicBorders(WidgetTester tester, int topicId) sync* {
  final row = find.byKey(ValueKey('topic-list-keyboard-$topicId'));
  for (final widget in tester.widgetList<Widget>(
    find.descendant(
      of: row,
      matching: find.byWidgetPredicate(
        (widget) => widget is Material || widget is DecoratedBox,
      ),
    ),
  )) {
    final side = switch (widget) {
      Material(shape: RoundedRectangleBorder(:final side)) => side,
      DecoratedBox(decoration: BoxDecoration(border: Border(:final top))) =>
        top,
      _ => null,
    };
    if (side != null && side.style == BorderStyle.solid && side.color.a > 0) {
      yield side;
    }
  }
}

Future<void> _moveTopic(
  WidgetTester tester, {
  required bool next,
  bool handled = true,
  bool settle = true,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  expect(
    await tester.sendKeyEvent(
      next ? LogicalKeyboardKey.keyJ : LogicalKeyboardKey.keyK,
    ),
    handled,
  );
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
}

List<int> _selection(WidgetTester tester, String prefix) => [
  for (final widget in tester.widgetList<KeyboardSelection>(
    find.byType(KeyboardSelection),
  ))
    if (widget.selected)
      if (widget.key case ValueKey<String>(
        value: final key,
      ) when key.startsWith(prefix))
        int.parse(key.substring(prefix.length)),
];

List<int> _selectedTopics(WidgetTester tester) =>
    _selection(tester, 'topic-list-keyboard-');
List<int> _selectedPosts(WidgetTester tester) =>
    _selection(tester, 'topic-post-keyboard-');

SuperListView _scrollable(WidgetTester tester, Finder root) =>
    tester.widget<SuperListView>(
      find.descendant(of: root, matching: find.byType(SuperListView)),
    );

Future<({ShellController shell, FakeDiscourseApi api})> _setup(
  WidgetTester tester, {
  Size size = desktop,
  Completer<void>? nextPageGate,
}) async {
  const user = DiscourseUser(id: 7, username: 'sam');
  final site = instance('meta.example').copyWith(user: user);
  final rows = [
    for (var id = 1; id <= 31; id++)
      Topic(
        id: id,
        title: 'Keyboard topic $id',
        slug: 'keyboard-$id',
        lastReadPostNumber: 1,
        highestPostNumber: 4,
        unreadPosts: 3,
      ),
  ];
  final api = FakeDiscourseApi(
    user: user,
    feedGates: {'/latest.json?page=1': ?nextPageGate},
    feeds: {
      '/latest.json': rows.take(30).toList(),
      '/latest.json?page=1': [rows.last],
    },
    nextPages: const {'/latest.json': '/latest.json?page=1'},
    topics: {
      for (final row in rows)
        row.id: (
          detail: TopicDetail(
            id: row.id,
            title: row.title,
            stream: [for (var n = 1; n <= 4; n++) row.id * 100 + n],
            postsCount: 4,
            canCreatePost: true,
          ),
          posts: [
            for (var n = 1; n <= 4; n++)
              Post(
                id: row.id * 100 + n,
                postNumber: n,
                username: 'sam',
                cooked:
                    '<p>Post $n</p><p>${List.filled(110, 'A readable topic with several posts.').join(' ')}</p>',
              ),
          ],
        ),
    },
  );
  await pumpShell(
    tester,
    size,
    api: api,
    instances: [site],
    authenticator: FakeAuthenticator()..keys[site.url] = 'key',
  );
  final shell = ShellScope.read(tester.element(find.byType(AdaptiveShell)));
  return (shell: shell, api: api);
}
