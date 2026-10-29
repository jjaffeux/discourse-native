import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;
import 'support/fakes.dart';
import 'support/topic_post_list.dart';

const _barTitle = ValueKey('mobile-page-title');

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('captureMockupParity')) return;
  await tester.runAsync(() async {
    final builder = ui.SceneBuilder();
    tester.binding.renderViews.first.debugLayer!.addToScene(builder);
    final scene = builder.build();
    final image = await scene.toImage(390, 844);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '/private/tmp/native-mockup-$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    scene.dispose();
  });
}

void main() {
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
    if (const bool.fromEnvironment('captureMockupParity')) {
      final manifest =
          jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
      for (final entry in manifest.cast<Map<String, dynamic>>()) {
        final loader = FontLoader(entry['family'] as String);
        for (final face
            in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
          loader.addFont(rootBundle.load(face['asset'] as String));
        }
        await loader.load();
      }
    }
  });
  tearDownAll(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          null,
        ),
  );
  testWidgets('phone topic raises its sheet, yields its title and floats tools', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(
      tester,
      topic: topicPayload(
        id: 7,
        title: 'A closed community discussion',
        closed: true,
        posts: [
          for (var id = 1; id <= 30; id++)
            Post(
              id: id,
              postNumber: id,
              username: 'reader',
              createdAt: DateTime.utc(2026, 10, 29),
              cooked:
                  '<p>${List.filled(30, 'A community discussion.').join(' ')}</p>',
            ),
        ],
      ),
    );
    if (const bool.fromEnvironment('captureMockupParity')) {
      await shell.forumSettings.setShared(
        shell.forumSettings.shared.copyWith(
          font: ForumFont.lato,
          interfaceFont: ForumFont.lato,
        ),
      );
      await tester.pumpAndSettle();
    }
    expect(find.byKey(_barTitle).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('topic-card-7')));
    await tester.pumpAndSettle();
    final sheet = find.byType(DSheetContent);
    final handle = find.byKey(const ValueKey('sheet-drag-handle'));
    expect(tester.getRect(sheet).top, 8);
    expect(tester.getRect(handle).top, 15);
    expect(find.byKey(_barTitle).hitTestable(), findsNothing);
    expect(
      find.byKey(const ValueKey('topic-header-compact-layout')),
      findsNothing,
    );
    final tools = find.byKey(const ValueKey('topic-more-actions'));
    final progress = find.byKey(const ValueKey('topic-progress-button'));
    expect(tester.getSize(tools), const Size(40, 40));
    expect(tester.getSize(progress).height, 40);
    expect(tester.getRect(tools).top, greaterThan(650));
    await _capture(tester, 'topic-open');
    final scroll = topicPostList(tester).controller!;
    final firstPost = find.byKey(const ValueKey(1));
    final firstTop = tester.getTopLeft(firstPost).dy;
    scroll.jumpTo(20);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(firstPost).dy, closeTo(firstTop - 20, .1));
    expect(tester.getRect(handle).top, 35);
    await _capture(tester, 'topic-partial');
    scroll.jumpTo(600);
    await tester.pumpAndSettle();
    await _capture(tester, 'topic-scrolled');
    expect(find.byKey(_barTitle).hitTestable(), findsOneWidget);
    expect(
      tester.getRect(handle).top,
      tester.getRect(find.byKey(const ValueKey('mobile-header'))).bottom + 13,
    );
    final pull = await tester.startGesture(tester.getCenter(handle));
    await pull.moveBy(const Offset(0, 20));
    await pull.moveBy(const Offset(0, 90));
    await tester.pump();
    final barContext = tester.element(find.byKey(_barTitle));
    expect(
      DSheetDragScope.dismissProgressOf(barContext)!.value,
      inExclusiveRange(0, 1),
    );
    expect(DPageHeaderHost.previousTitleOf(barContext)?.title, 'Latest topics');
    await _capture(tester, 'topic-pull');
    await pull.cancel();
    await tester.pumpAndSettle();
    expect(DSheetDragScope.dismissProgressOf(barContext)!.value, 0);
    await tester.tap(find.byKey(_barTitle));
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(tester.getRect(handle).top, 15);
    scroll.jumpTo(600);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-home-button')));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'latest');
    expect(sheet, findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('forum mark clears filters and then scrolls Latest to its top', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(
      tester,
      topics: [
        for (var id = 1; id <= 60; id++)
          Topic(id: id, title: 'Discussion $id', slug: 'discussion-$id'),
      ],
    );
    shell.selectTopicListCategory(
      const TopicCategory(
        id: 5,
        name: 'Support',
        slug: 'support',
        color: '0088cc',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-home-button')));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'latest');
    expect(shell.currentContent?.topicFilterQuery, isEmpty);
    final list = find.byType(TopicListView);
    await tester.drag(list, const Offset(0, -500));
    await tester.pumpAndSettle();
    final scroll = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position;
    expect(scroll.pixels, greaterThan(0));
    await tester.tap(find.byKey(const ValueKey('mobile-home-button')));
    await tester.pumpAndSettle();
    expect(scroll.pixels, 0);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
