import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/discourse_ui.dart';
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
  for (final size in [desktop, phone]) {
    for (final next in [false, true]) {
      testWidgets(
        'G ${next ? 'J' : 'K'} opens the first listed topic from an unlisted topic at ${size.width}px',
        (tester) async {
          final setup = await _setup(tester, size: size);
          final unlisted = setup.api.feeds['/latest.json?page=1']!.single;
          setup.shell.openTopic(unlisted);
          await tester.pumpAndSettle();
          final source = setup.shell.topicListContent;
          expect(
            setup.shell.currentFeed!.topicIds,
            isNot(contains(unlisted.id)),
          );

          await _openAdjacent(tester, next: next);

          expect(setup.shell.currentContent?.topicId, 1);
          expect(setup.shell.currentContent?.postNumber, 2);
          expect(setup.shell.topicListContent, source);
          expect(setup.shell.contentStack, hasLength(2));
          expect(_selectedPosts(tester), isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('G J and G K open adjacent topics at ${size.width}px', (
      tester,
    ) async {
      final setup = await _setup(tester, size: size);
      setup.shell.openTopicFromList(setup.api.feeds['/latest.json']!.first);
      await tester.pumpAndSettle();
      final source = setup.shell.topicListContent;

      await _openAdjacent(tester, next: true);
      expect(setup.shell.currentContent?.topicId, 2);
      expect(setup.shell.currentContent?.postNumber, 2);
      expect(setup.shell.topicListContent, source);
      expect(setup.shell.contentStack, hasLength(2));
      expect(_selectedPosts(tester), isEmpty);

      await _openAdjacent(tester, next: false);
      expect(setup.shell.currentContent?.topicId, 1);
      await _openAdjacent(tester, next: false);
      expect(setup.shell.currentContent?.topicId, 1);
      expect(_selectedPosts(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final next in [false, true]) {
    testWidgets(
      '${next ? 'Next' : 'Previous'} button opens the first listed topic from an unlisted topic',
      (tester) async {
        final setup = await _setup(tester);
        setup.shell.openTopic(setup.api.feeds['/latest.json?page=1']!.single);
        await tester.pumpAndSettle();
        final source = setup.shell.topicListContent;
        final previousButton = find.byKey(
          const ValueKey('inbox-previous-topic'),
        );
        final nextButton = find.byKey(const ValueKey('inbox-next-topic'));
        expect(tester.widget<DButton>(previousButton).onPressed, isNotNull);
        expect(tester.widget<DButton>(nextButton).onPressed, isNotNull);

        await tester.tap(next ? nextButton : previousButton);
        await tester.pumpAndSettle();

        expect(setup.shell.currentContent?.topicId, 1);
        expect(setup.shell.currentContent?.postNumber, 2);
        expect(setup.shell.topicListContent, source);
        expect(setup.shell.contentStack, hasLength(2));
        expect(tester.widget<DButton>(previousButton).onPressed, isNull);
        expect(tester.widget<DButton>(nextButton).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'topic arrows and shortcuts follow empty and refreshed source lists',
    (tester) async {
      final setup = await _setup(tester);
      final first = setup.api.feeds['/latest.json']!.first;
      setup.shell.openTopic(setup.api.feeds['/latest.json?page=1']!.single);
      setup.api.feeds['/latest.json'] = [];
      setup.api.nextPages.remove('/latest.json');
      await setup.shell.loadFeed(setup.shell.currentFeedId!, force: true);
      await tester.pumpAndSettle();
      expect(setup.shell.currentFeed!.topicIds, isEmpty);
      for (final key in ['inbox-previous-topic', 'inbox-next-topic']) {
        expect(
          tester.widget<DButton>(find.byKey(ValueKey(key))).onPressed,
          isNull,
        );
      }

      await _openAdjacent(tester, next: false);
      await _openAdjacent(tester, next: true);

      expect(setup.shell.currentContent?.topicId, 31);
      expect(_selectedPosts(tester), isEmpty);

      setup.api.feeds['/latest.json'] = [first];
      await setup.shell.loadFeed(setup.shell.currentFeedId!, force: true);
      await tester.pumpAndSettle();
      expect(setup.shell.currentFeed!.topicIds, [1]);
      for (final key in ['inbox-previous-topic', 'inbox-next-topic']) {
        expect(
          tester.widget<DButton>(find.byKey(ValueKey(key))).onPressed,
          isNotNull,
        );
      }
      await tester.tap(find.byKey(const ValueKey('inbox-previous-topic')));
      await tester.pumpAndSettle();
      expect(setup.shell.currentContent?.topicId, 1);
      for (final key in ['inbox-previous-topic', 'inbox-next-topic']) {
        expect(
          tester.widget<DButton>(find.byKey(ValueKey(key))).onPressed,
          isNull,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expired and interrupted topic sequences leave J as a post command',
    (tester) async {
      final setup = await _setup(tester);
      setup.shell.openTopicFromList(setup.api.feeds['/latest.json']!.first);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pumpAndSettle();
      expect(setup.shell.currentContent?.topicId, 1);
      expect(_selectedPosts(tester), isNotEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pumpAndSettle();
      expect(setup.shell.currentContent?.topicId, 1);
      await _openAdjacent(tester, next: true);
      expect(setup.shell.currentContent?.topicId, 2);
    },
  );

  testWidgets('a topic sequence is cancelled when another topic opens', (
    tester,
  ) async {
    final setup = await _setup(tester);
    final rows = setup.api.feeds['/latest.json']!;
    setup.shell.openTopicFromList(rows.first);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    setup.shell.openTopicFromList(rows[1]);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    expect(setup.shell.currentContent?.topicId, 2);
    expect(_selectedPosts(tester), isNotEmpty);
  });

  testWidgets(
    'holding a completed topic sequence does not repeat or move posts',
    (tester) async {
      final setup = await _setup(tester);
      setup.shell.openTopicFromList(setup.api.feeds['/latest.json']!.first);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyJ);
      await tester.pumpAndSettle();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyJ);
      await tester.pumpAndSettle();
      expect(setup.shell.currentContent?.topicId, 2);
      expect(_selectedPosts(tester), isEmpty);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pumpAndSettle();
      expect(_selectedPosts(tester), isNotEmpty);
    },
  );

  for (final outcome in [
    'finish',
    'change topic',
    'change tab',
    'return to tab',
    'focus search',
  ]) {
    testWidgets('adjacent topic pagination respects $outcome', (tester) async {
      final gate = Completer<void>();
      final setup = await _setup(tester, nextPageGate: gate);
      final rows = setup.api.feeds['/latest.json']!;
      final originalTab = setup.shell.activeTabId!;
      setup.shell.openTopicFromList(rows.last);
      await tester.pumpAndSettle();
      await _openAdjacent(tester, next: true, settle: false);
      await _openAdjacent(tester, next: true, settle: false);
      expect(
        setup.api.feedPaths.where((path) => path == '/latest.json?page=1'),
        hasLength(1),
      );
      if (outcome == 'change topic') {
        setup.shell.openTopicFromList(rows.first);
      } else if (outcome == 'change tab') {
        setup.shell.createTab();
      } else if (outcome == 'return to tab') {
        setup.shell.createTab();
        setup.shell.selectTab(originalTab);
      } else if (outcome == 'focus search') {
        await tester.tap(find.byType(EditableText).first);
      }
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      expect(setup.shell.currentContent?.topicId, switch (outcome) {
        'finish' => 31,
        'change topic' => 1,
        'change tab' => null,
        _ => 30,
      });
      if (outcome == 'finish') {
        await _openAdjacent(tester, next: true);
        expect(setup.shell.currentContent?.topicId, 31);
        expect(_selectedPosts(tester), isEmpty);
      }
      expect(tester.takeException(), isNull);
    }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));
  }
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
          expect(_selectedTopics(tester), isEmpty);

          await _moveTopic(tester, next: true, shift: false);
          expect(_selectedTopics(tester), [1]);
          await _moveTopic(tester, next: true, shift: false);
          expect(_selectedTopics(tester), [2]);
          await _moveTopic(tester, next: false, shift: false);
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
          await _moveTopic(tester, next: true, shift: false);
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
      LogicalKeyboardKey.keyG,
      LogicalKeyboardKey.keyJ,
      LogicalKeyboardKey.keyG,
      LogicalKeyboardKey.keyK,
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
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(setup.shell.currentContent?.topicId, 1);
    expect(_selectedTopics(tester), [1]);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('keyboard-shortcuts-help')), findsNothing);
  });

  testWidgets('list J/K shortcuts pause for search and dialogs', (
    tester,
  ) async {
    final setup = await _setup(tester);
    await _moveTopic(tester, next: true, shift: false);
    await _moveTopic(tester, next: true, shift: false);

    await tester.tap(find.byType(EditableText).first);
    await tester.pump();
    for (final key in [LogicalKeyboardKey.keyJ, LogicalKeyboardKey.keyK]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(_selectedTopics(tester), [2]);
    }

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('keyboard-shortcuts-help')),
      findsOneWidget,
    );
    for (final key in [LogicalKeyboardKey.keyJ, LogicalKeyboardKey.keyK]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(_selectedTopics(tester), [2]);
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await _moveTopic(tester, next: false, shift: false);
    expect(_selectedTopics(tester), [1]);
    expect(setup.api.topicsOpened, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final afterRequest in ['finish', 'open topic', 'focus search']) {
    testWidgets('a pending page respects $afterRequest', (tester) async {
      final gate = Completer<void>();
      final setup = await _setup(tester, nextPageGate: gate);
      for (var i = 0; i < 31; i++) {
        await _moveTopic(tester, next: true, shift: false, settle: false);
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

Future<void> _openAdjacent(
  WidgetTester tester, {
  required bool next,
  bool settle = true,
}) async {
  expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyG), isTrue);
  expect(
    await tester.sendKeyEvent(
      next ? LogicalKeyboardKey.keyJ : LogicalKeyboardKey.keyK,
    ),
    isTrue,
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _moveTopic(
  WidgetTester tester, {
  required bool next,
  bool shift = true,
  bool handled = true,
  bool settle = true,
}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  expect(
    await tester.sendKeyEvent(
      next ? LogicalKeyboardKey.keyJ : LogicalKeyboardKey.keyK,
    ),
    handled,
  );
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
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
    nextPages: {'/latest.json': '/latest.json?page=1'},
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
