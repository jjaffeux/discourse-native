import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/keyboard_navigation.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';
import 'support/topic_post_list.dart';

const _unlistedTopic = Topic(id: 32, title: 'Unlisted topic', slug: 'unlisted');

void main() {
  for (final size in [desktop, laptop, phone]) {
    testWidgets('J/K page through a long post in both directions at $size', (
      tester,
    ) async {
      final setup = await _setup(tester, size: size, longPosts: {2});
      setup.shell.openTopicFromList(setup.api.feeds['/latest.json']!.first);
      await tester.pumpAndSettle();
      final scroll = topicPostList(tester).controller!;
      final post = find.byKey(const ValueKey('topic-post-keyboard-102'));
      Rect viewport() => tester.getRect(topicPostListFinder());
      expect(tester.getSize(post).height, greaterThan(viewport().height * 2));

      var pages = 0;
      while (tester.getRect(post).bottom > viewport().bottom + 0.5) {
        final before = scroll.offset;
        final pageHeight = viewport().height;
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyJ), isTrue);
        await tester.pumpAndSettle();
        expect(_selectedPosts(tester), [102]);
        expect(scroll.offset - before, greaterThan(0));
        expect(scroll.offset - before, lessThan(pageHeight));
        expect(++pages, lessThan(20));
      }
      expect(pages, greaterThan(1));

      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pumpAndSettle();
      expect(_selectedPosts(tester), [103]);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();
      expect(_selectedPosts(tester), [102]);
      expect(tester.getRect(post).bottom, closeTo(viewport().bottom, 0.5));

      pages = 0;
      while (tester.getRect(post).top < viewport().top - 0.5) {
        final before = scroll.offset;
        final pageHeight = viewport().height;
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyK), isTrue);
        await tester.pumpAndSettle();
        expect(_selectedPosts(tester), [102]);
        expect(before - scroll.offset, greaterThan(0));
        expect(before - scroll.offset, lessThan(pageHeight));
        expect(++pages, lessThan(20));
      }
      expect(pages, greaterThan(1));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();
      expect(_selectedPosts(tester), [101]);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  testWidgets('repeating J pages within the selected reply target', (
    tester,
  ) async {
    final setup = await _setup(tester, longPosts: {2});
    setup.shell.openTopicFromList(setup.api.feeds['/latest.json']!.first);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    final scroll = topicPostList(tester).controller!;
    final before = scroll.offset;
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(before));
    expect(_selectedPosts(tester), [102]);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pumpAndSettle();
    expect(setup.shell.visibleComposer?.target.replyToPostNumber, 2);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('short posts still change selection with one keypress', (
    tester,
  ) async {
    final setup = await _setup(tester, longPosts: {});
    await _readBeside(
      tester,
      setup.shell,
      setup.api.feeds['/latest.json']!.first,
    );
    final post = find.byKey(const ValueKey('topic-post-keyboard-102'));
    expect(
      tester.getSize(post).height,
      lessThan(tester.getSize(topicPostListFinder()).height),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    expect(_selectedPosts(tester), [103]);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();
    expect(_selectedPosts(tester), [102]);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  for (final postNumber in [1, 4]) {
    testWidgets('J/K page inside boundary post $postNumber', (tester) async {
      final setup = await _setup(tester, longPosts: {postNumber});
      setup.shell.openTopicFromList(setup.api.feeds['/latest.json']!.first);
      await tester.pumpAndSettle();
      setup.shell.openCurrentTopicPost(postNumber);
      await tester.pumpAndSettle();
      final postId = 100 + postNumber;
      final post = find.byKey(ValueKey('topic-post-keyboard-$postId'));
      Rect viewport() => tester.getRect(topicPostListFinder());
      var pages = 0;
      while (tester.getRect(post).bottom > viewport().bottom + 0.5) {
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyJ), isTrue);
        await tester.pumpAndSettle();
        expect(_selectedPosts(tester), [postId]);
        expect(++pages, lessThan(20));
      }
      expect(pages, greaterThan(1));
      if (postNumber == 4) {
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyJ), isFalse);
      }
      pages = 0;
      while (tester.getRect(post).top < viewport().top - 0.5) {
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyK), isTrue);
        await tester.pumpAndSettle();
        expect(_selectedPosts(tester), [postId]);
        expect(++pages, lessThan(20));
      }
      expect(pages, greaterThan(1));
      if (postNumber == 1) {
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyK), isFalse);
      }
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  testWidgets('K enters the last page after a long post finishes rendering', (
    tester,
  ) async {
    final setup = await _setup(tester, longPosts: {2}, longPostParagraphs: 450);
    setup.shell.openTopic(
      const Topic(
        id: 1,
        title: 'Keyboard topic 1',
        slug: 'keyboard-1',
        lastReadPostNumber: 2,
        highestPostNumber: 4,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    final lastParagraph = renderedText('Paragraph 449.');
    for (var i = 0; i < 100 && lastParagraph.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(lastParagraph, findsOneWidget);
    expect(_selectedPosts(tester), [102]);
    final post = find.byKey(const ValueKey('topic-post-keyboard-102'));
    expect(
      tester.getRect(post).bottom,
      closeTo(tester.getRect(topicPostListFinder()).bottom, 0.5),
    );
    final scroll = topicPostList(tester).controller!;
    final before = scroll.offset;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();
    expect(scroll.offset, lessThan(before));
    expect(_selectedPosts(tester), [102]);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  for (final size in [desktop, laptop]) {
    testWidgets('mouse-opened topic loses its outline when closed at $size', (
      tester,
    ) async {
      final setup = await _setup(tester, size: size);
      await tester.tap(find.text('Keyboard topic 1'));
      await tester.pumpAndSettle();
      expect(setup.shell.currentContent?.topicId, 1);

      setup.shell.closeTopic();
      await tester.pumpAndSettle();
      expect(setup.shell.currentContent?.isTopic, isFalse);
      expect(_selectedTopics(tester), isEmpty);
      expect(_topicItem(tester, 1).selected, isFalse);

      await _moveTopic(tester, next: true);
      expect(_selectedTopics(tester), [2]);
      expect(_topicItem(tester, 2).selected, isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  for (final size in [desktop, phone]) {
    testWidgets(
      'B bookmarks the open topic and advertises the footer shortcut at $size',
      (tester) async {
        final setup = await _setup(tester, size: size);
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyB), isFalse);
        expect(setup.api.createdBookmarks, isEmpty);
        setup.shell.openTopicFromList(setup.api.feeds['/latest.json']!.first);
        await tester.pumpAndSettle();

        // The reader header carries the topic's only bookmark control.
        final button = find.byKey(
          const ValueKey('topic-header-bookmark-button'),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(button));
        await tester.pumpAndSettle(const Duration(milliseconds: 200));
        expect(find.text('Bookmark this topic'), findsOneWidget);
        expect(find.widgetWithText(DKbd, 'B'), findsOneWidget);
        await mouse.moveTo(Offset.zero);
        await tester.pumpAndSettle();

        for (final modifier in [
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.altLeft,
        ]) {
          await tester.sendKeyDownEvent(modifier);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
          await tester.sendKeyUpEvent(modifier);
        }
        expect(setup.api.createdBookmarks, isEmpty);
        final payload = setup.api.topics[1]!;
        // The post-write refresh reads the newly saved bookmark from the server.
        setup.api.topics[1] = (
          detail: payload.detail.copyWith(
            bookmarks: const [
              Bookmark(id: 1000, bookmarkableId: 1, bookmarkableType: 'Topic'),
            ],
          ),
          posts: payload.posts,
        );
        expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB), isTrue);
        await tester.pumpAndSettle();
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyB);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
        await tester.pumpAndSettle();
        expect(setup.api.createdBookmarks, hasLength(1));
        expect(
          setup.api.createdBookmarks.single.targetType,
          BookmarkTargetType.topic,
        );
        expect(setup.api.createdBookmarks.single.targetId, 1);
        expect(setup.shell.currentTopic?.topicBookmark, isNotNull);
        expect(find.text('Bookmarked!'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyB), isTrue);
        await tester.pumpAndSettle();
        expect(find.text('Topic bookmark'), findsOneWidget);
        expect(find.text('Delete bookmark'), findsOneWidget);
        expect(setup.api.createdBookmarks, hasLength(1));
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }),
    );
  }

  testWidgets('B does not bookmark a topic while signed out', (tester) async {
    final setup = await _setup(tester, signedIn: false);
    setup.shell.openTopicFromList(setup.api.feeds['/latest.json']!.first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('topic-bookmark-button')), findsNothing);
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyB), isFalse);
    await tester.pumpAndSettle();
    expect(setup.api.createdBookmarks, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  for (final menu in ['category', 'tag']) {
    testWidgets(
      'topic sequences work after closing the $menu filter and opening a topic page',
      (tester) async {
        final setup = await _setup(tester);
        final filter = find.byKey(ValueKey('topic-list-$menu-filter'));
        final trigger = find.descendant(
          of: filter,
          matching: find.byType(DButton),
        );
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        final input = find.descendant(
          of: find.byType(DComboboxContent),
          matching: find.byType(EditableText),
        );
        expect(tester.widget<EditableText>(input).focusNode.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
        await tester.pump(const Duration(milliseconds: 150));
        await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
        await tester.pumpAndSettle();
        expect(setup.shell.currentContent?.isTopicList, isTrue);
        expect(_selectedPosts(tester), isEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(DComboboxContent), findsNothing);
        expect(
          tester.widget<DButton>(trigger).focusNode!.hasPrimaryFocus,
          isTrue,
        );

        setup.shell.openTopicFromList(setup.api.feeds['/latest.json']![19]);
        await tester.pumpAndSettle();

        for (final next in [true, false]) {
          await _openAdjacent(tester, next: next);
          final target = next ? 21 : 20;
          expect(setup.shell.currentContent?.topicId, target);
          expect(
            find.byKey(const ValueKey('topic-content-header')),
            findsOneWidget,
          );
          expect(_selectedPosts(tester), isEmpty);
        }
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({TargetPlatform.macOS}),
    );
  }

  for (final size in [desktop, phone]) {
    for (final next in [false, true]) {
      testWidgets(
        'G ${next ? 'J' : 'K'} opens the first listed topic from an unlisted topic at ${size.width}px',
        (tester) async {
          final setup = await _setup(tester, size: size);
          if (size == desktop) {
            await _readBeside(tester, setup.shell, _unlistedTopic);
          } else {
            setup.shell.openTopic(_unlistedTopic);
            await tester.pumpAndSettle();
          }
          if (size == desktop) {
            _scrollable(
              tester,
              find.byType(TopicListView),
            ).controller!.jumpTo(500);
            await tester.pumpAndSettle();
          }
          final source = setup.shell.topicListContent;
          expect(
            setup.shell.currentFeed!.topicIds,
            isNot(contains(_unlistedTopic.id)),
          );

          await _openAdjacent(tester, next: next);

          expect(setup.shell.currentContent?.topicId, 1);
          expect(setup.shell.currentContent?.postNumber, 2);
          expect(setup.shell.topicListContent, source);
          expect(setup.shell.contentStack, hasLength(2));
          expect(_selectedPosts(tester), isEmpty);
          if (size == phone) {
            await tester.tap(find.byTooltip('Back'));
            await tester.pumpAndSettle();
          }
          _expectTopicVisible(tester, 1);
          expect(_selectedTopics(tester), size == phone ? isEmpty : [1]);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(
          size == phone ? TargetPlatform.android : TargetPlatform.linux,
        ),
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
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  for (final next in [false, true]) {
    testWidgets(
      '${next ? 'Next' : 'Previous'} button opens the first listed topic from an unlisted topic',
      (tester) async {
        final setup = await _setup(tester);
        await _readBeside(tester, setup.shell, _unlistedTopic);
        _scrollable(tester, find.byType(TopicListView)).controller!.jumpTo(500);
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
        _expectTopicVisible(tester, 1);
        expect(_selectedTopics(tester), [1]);
        expect(tester.widget<DButton>(previousButton).onPressed, isNull);
        expect(tester.widget<DButton>(nextButton).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }

  for (final keyboard in [false, true]) {
    for (final next in [false, true]) {
      testWidgets(
        '${keyboard ? 'Shortcut' : 'Button'} scrolls to the ${next ? 'next' : 'previous'} topic outside the viewport',
        (tester) async {
          final setup = await _setup(tester);
          await _readBeside(
            tester,
            setup.shell,
            setup.api.feeds['/latest.json']![19],
          );
          final list = _scrollable(tester, find.byType(TopicListView));
          list.controller!.jumpTo(0);
          await tester.pumpAndSettle();

          if (keyboard) {
            await _openAdjacent(tester, next: next);
          } else {
            await tester.tap(
              find.byKey(ValueKey('inbox-${next ? 'next' : 'previous'}-topic')),
            );
            await tester.pumpAndSettle();
          }

          final target = next ? 21 : 19;
          expect(setup.shell.currentContent?.topicId, target);
          _expectTopicVisible(tester, target);
          expect(_selectedTopics(tester), [target]);
          expect(list.controller!.offset, greaterThan(0));
          await _moveTopic(tester, next: true);
          expect(_selectedTopics(tester), [target + 1]);
          expect(setup.shell.readingTopicId, target);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
      );
    }
  }

  testWidgets('clicking topic rows preserves the list scroll position', (
    tester,
  ) async {
    final setup = await _setup(tester);
    await _openBeside(tester, find.text('Keyboard topic 1'));
    final list = _scrollable(tester, find.byType(TopicListView));
    list.controller!.jumpTo(200);
    await tester.pumpAndSettle();
    final offset = list.controller!.offset;

    await _openBeside(tester, find.text('Keyboard topic 5'));

    expect(setup.shell.currentContent?.topicId, 5);
    expect(list.controller!.offset, offset);
    expect(_selectedTopics(tester), [5]);
    await _openAdjacent(tester, next: true);
    _expectTopicVisible(tester, 6);
    final keyboardOffset = list.controller!.offset;
    await _openBeside(tester, find.text('Keyboard topic 7'));
    expect(list.controller!.offset, keyboardOffset);
    await _openAdjacent(tester, next: false);
    _expectTopicVisible(tester, 6);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'topic arrows and shortcuts follow empty and refreshed source lists',
    (tester) async {
      final setup = await _setup(tester);
      final first = setup.api.feeds['/latest.json']!.first;
      await _readBeside(
        tester,
        setup.shell,
        setup.api.feeds['/latest.json?page=1']!.single,
      );
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
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
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
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
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
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
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
      setup.shell.openTopicFromList(rows.last);
      final originalTab = setup.shell.activeTabId!;
      // Revealing the last row starts the gated page prefetch and its spinner.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
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

  // The keyboard opens a topic in the list's own tab, so only a reader opened
  // beside the list leaves a list whose cursor can move.
  testWidgets(
    'opening a topic with the mouse retains its selection as the cursor moves',
    (tester) async {
      final setup = await _setup(tester);
      await _openBeside(tester, find.text('Keyboard topic 1'));
      expect(setup.shell.currentContent?.topicId, 1);
      expect(_topicItem(tester, 1).selected, isTrue);

      await _moveTopic(tester, next: true);
      _scrollable(tester, find.byType(TopicListView)).controller!.jumpTo(0);
      await tester.pumpAndSettle();
      expect(setup.shell.readingTopicId, 1);
      expect(_topicItem(tester, 1).selected, isTrue);
      expect(_topicItem(tester, 2).selected, isTrue);
      expect(_topicItem(tester, 2).variant, DItemVariant.standard);
      // The list lane beside the reader is narrow, so rows use the compact
      // card's fill rather than the wide row's leading accent.
      expect(_topicItem(tester, 2).selectionStyle, DItemSelectionStyle.filled);
      expect(_selectedTopics(tester), [2]);

      await _moveTopic(tester, next: false);
      expect(_topicItem(tester, 1).selected, isTrue);
      expect(_topicItem(tester, 1).variant, DItemVariant.standard);
      expect(_topicItem(tester, 2).selected, isFalse);
      expect(_selectedTopics(tester), [1]);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  for (final size in [desktop, laptop]) {
    for (final openKey in [LogicalKeyboardKey.keyO, LogicalKeyboardKey.enter]) {
      testWidgets(
        '${size.width} ${openKey.keyLabel} reads, replies, and resumes keyboard selection in the list',
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
          // The reader replaces the list in its tab, so list moves are off.
          await _moveTopic(tester, next: true, handled: false);
          expect(shell.currentContent?.topicId, 2);

          await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
          await tester.pumpAndSettle();
          final selectedPost = _selectedPosts(tester).single;
          expect(selectedPost, 202);
          expect(shell.currentContent?.topicId, 2);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
          await tester.pumpAndSettle();
          expect(shell.visibleComposer?.target.replyToPostNumber, 2);
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
          expect(setup.api.created.single['replyToPostNumber'], 2);
          expect(shell.visibleComposer, isNull);

          expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyU), isTrue);
          await tester.pumpAndSettle();
          expect(shell.currentContent?.isTopic, isFalse);
          // The list returns with the keyboard selection on the topic read.
          expect(_selectedTopics(tester), [2]);
          await _moveTopic(tester, next: true, shift: false);
          expect(_selectedTopics(tester), [3]);
          await tester.sendKeyEvent(openKey);
          await tester.pumpAndSettle();
          expect(shell.currentContent?.topicId, 3);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
      );
    }
  }

  testWidgets(
    'list and reader commands keep independent selections in split view',
    (tester) async {
      final setup = await _setup(tester);
      await _readBeside(
        tester,
        setup.shell,
        setup.api.feeds['/latest.json']!.first,
      );
      expect(_selectedTopics(tester), [1]);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pumpAndSettle();
      final posts = _selectedPosts(tester);
      expect(posts, isNotEmpty);
      final reader = _scrollable(tester, find.byType(TopicView));
      final offset = reader.controller!.offset;

      // Moving the list cursor focuses the list's panel, not the reader.
      await _moveTopic(tester, next: true);
      expect(_selectedTopics(tester), [2]);
      expect(_selectedPosts(tester), posts);
      expect(setup.shell.readingTopicId, 1);
      expect(reader.controller!.offset, offset);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isTrue);
      await tester.pumpAndSettle();
      expect(setup.shell.currentContent?.topicId, 2);
      expect(setup.shell.contentStack, hasLength(2));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
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
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
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
      LogicalKeyboardKey.keyB,
    ]) {
      await tester.sendKeyEvent(key);
    }
    expect(setup.shell.currentContent?.topicId, 1);
    expect(setup.shell.visibleComposer?.target.replyToPostNumber, isNull);
    expect(setup.api.createdBookmarks, isEmpty);

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
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pumpAndSettle();
    expect(setup.shell.currentContent?.topicId, 1);
    expect(setup.api.createdBookmarks, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('keyboard-shortcuts-help')), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
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
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
      // An opened topic reads in the list's own tab, replacing the list.
      expect(_selectedTopics(tester), switch (afterRequest) {
        'finish' => [31],
        'open topic' => isEmpty,
        _ => [30],
      });
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
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
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
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'each tab restores its own list cursor',
    (tester) async {
      final setup = await _setup(tester);
      final originalTab = setup.shell.activeTabId!;
      await _moveTopic(tester, next: true);
      await _moveTopic(tester, next: true);
      _createTopicsTab(setup.shell);
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
    expect(_selectedPosts(tester), [102]);
    await tester.drag(find.byType(TopicView), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(_selectedPosts(tester), isEmpty);
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyR), isFalse);
    expect(setup.shell.visibleComposer, isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}

// Desktop panels keep the list beside its reader only when the reader opens
// in the secondary panel; an ordinary open reads in the list's own tab.
Future<void> _readBeside(
  WidgetTester tester,
  ShellController shell,
  Topic topic,
) async {
  shell.openLinkInPanel(
    '/t/${topic.slug}/${topic.id}/${topic.lastUnreadPostNumber ?? 1}',
    title: topic.title,
    panel: ForumPanel.secondary,
  );
  await tester.pumpAndSettle();
}

// A shift-click is the pointer's way to read beside the list.
Future<void> _openBeside(WidgetTester tester, Finder row) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
  await tester.tap(row, warnIfMissed: false);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

// A new tab opens on the Start page; show the forum's topics in it.
void _createTopicsTab(ShellController shell) {
  shell.createTab();
  shell.selectDestination(shell.currentInstance!.defaultDestination);
}

DItem _topicItem(WidgetTester tester, int topicId) =>
    tester.widget<DItem>(find.byKey(ValueKey('topic-card-$topicId')));

void _expectTopicVisible(WidgetTester tester, int topicId) {
  final row = find.byKey(ValueKey('topic-list-keyboard-$topicId'));
  expect(row.hitTestable(), findsOneWidget);
  final viewport = tester.getRect(find.byType(TopicListView));
  final bounds = tester.getRect(row);
  expect(bounds.top, greaterThanOrEqualTo(viewport.top));
  expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom));
}

Future<void> _openAdjacent(
  WidgetTester tester, {
  required bool next,
  bool settle = true,
}) async {
  expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyG), isTrue);
  await tester.pump(const Duration(milliseconds: 100));
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

ScrollView _scrollable(WidgetTester tester, Finder root) =>
    tester.widget<ScrollView>(
      find.descendant(
        of: root,
        matching: find.byWidgetPredicate(
          (widget) => widget is SuperListView || widget is CustomScrollView,
        ),
      ),
    );

Future<({ShellController shell, FakeDiscourseApi api})> _setup(
  WidgetTester tester, {
  Size size = desktop,
  Completer<void>? nextPageGate,
  bool signedIn = true,
  Set<int>? longPosts,
  int longPostParagraphs = 60,
}) async {
  final user = signedIn ? const DiscourseUser(id: 7, username: 'sam') : null;
  final site = instance('meta.example').copyWith(user: user);
  final rows = [
    for (var id = 1; id <= 32; id++)
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
      '/latest.json?page=1': [rows[30]],
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
                cooked: longPosts == null
                    ? '<p>Post $n</p><p>${List.filled(110, 'A readable topic with several posts.').join(' ')}</p>'
                    : '<p>Post $n</p>${List.generate(longPosts.contains(n) ? longPostParagraphs : 7, (i) => '<p>A readable topic with several posts. Paragraph $i.</p>').join()}',
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
    authenticator: FakeAuthenticator()
      ..keys.addAll({if (signedIn) site.url: 'key'}),
  );
  final shell = ShellScope.read(tester.element(find.byType(AdaptiveShell)));
  return (shell: shell, api: api);
}
