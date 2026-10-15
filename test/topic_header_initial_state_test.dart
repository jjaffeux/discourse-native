import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/topic_post_list.dart';

const _capture = ValueKey('initial-header-capture');
final _compact = find.byKey(const ValueKey('topic-header-compact-layout'));

Future<void> _frames(WidgetTester tester, [int count = 32]) async {
  for (var frame = 0; frame < count; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _export(WidgetTester tester, String name) async {
  final directory = Platform.environment['TOPIC_HEADER_EXPORT_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await Directory(directory).create(recursive: true);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'HeaderReview',
    )..addFont(rootBundle.load('assets/fonts/OpenSans.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final source in [
    'route',
    'anchor',
    'row',
    'detail',
    'first',
    'unknown',
  ]) {
    testWidgets(
      'opening header uses $source through loading and restoration',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final gate = Completer<void>();
        final payload = topicPayload(
          id: 7,
          title: 'Returning to a familiar discussion',
          posts: [
            for (var number = 1; number <= 30; number++)
              Post(
                id: number,
                postNumber: number,
                username: 'reader',
                cooked: List.filled(
                  5,
                  '<p>Post $number: keeping our place in the discussion.</p>',
                ).join(),
              ),
          ],
        );
        final detail = TopicDetail(
          id: 7,
          title: payload.detail.title,
          stream: payload.detail.stream,
          postsCount: payload.posts.length,
          lastReadPostNumber: 12,
        );
        final site = instance(
          'scroll.example',
        ).copyWith(user: const DiscourseUser(id: 7, username: 'reader'));
        final api = FakeDiscourseApi(
          topicGate: gate,
          topics: {7: (detail: detail, posts: payload.posts)},
        );
        final controller = ShellController(
          mobileNavigationEnabled: true,
          instanceStore: FakeInstanceStore([site]),
          api: api,
          authenticator: FakeAuthenticator()..keys[site.url] = 'key',
          drafts: FakeDraftStore(),
          forumTabs: FakeForumTabStore(),
          trackers: FakeSiteTracker.reset(),
          updateStore: FakeUpdateStore(),
        );
        addTearDown(controller.dispose);
        await controller.load();
        if (source == 'detail') {
          controller.store
            ..put(site.url, detail)
            ..putAll(site.url, payload.posts);
        }
        if (source == 'row' || source == 'first') {
          controller.store.put(
            controller.currentInstance!.url,
            const Topic(
              id: 7,
              title: 'Returning to a familiar discussion',
              slug: 'returning',
              highestPostNumber: 30,
              lastReadPostNumber: 12,
            ),
          );
        }
        controller.pushContent(
          ContentRoute.topic(
            topicId: 7,
            slug: 'returning',
            title: 'Returning to a familiar discussion',
            postNumber: source == 'route'
                ? 12
                : source == 'first'
                ? 1
                : null,
          ),
        );
        if (source == 'anchor') controller.saveTopicScrollPost(7, 12);
        final loading = controller.loadTopic(7, 'returning');
        final theme = AppTheme.light;
        await tester.pumpWidget(
          ShellScope(
            controller: controller,
            child: RepaintBoundary(
              key: _capture,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme.copyWith(
                  textTheme: theme.textTheme.apply(fontFamily: 'HeaderReview'),
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(source == 'anchor' ? 2 : 1),
                  ),
                  child: child!,
                ),
                home: Scaffold(
                  body: DScrollChrome(
                    identity: 'reader',
                    footerBuilder: (_) => const SizedBox(height: 50),
                    child: TopicView(
                      inbox: true,
                      route: controller.currentContent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final initiallyCompact = [
          'route',
          'anchor',
          'row',
          'detail',
        ].contains(source);
        void expectOpeningLayout() =>
            expect(_compact, initiallyCompact ? findsOneWidget : findsNothing);
        expectOpeningLayout();
        await _frames(tester, 12);
        expectOpeningLayout();
        final openingTitle = initiallyCompact
            ? tester.getRect(
                find.byKey(const ValueKey('topic-header-compact-title')),
              )
            : null;
        await _export(tester, '$source-loading');

        gate.complete();
        await loading;
        for (var frame = 0; frame < 48; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expectOpeningLayout();
        }
        expect(topicPostListFinder(), findsOneWidget);
        if (openingTitle != null) {
          expect(
            tester.getRect(
              find.byKey(const ValueKey('topic-header-compact-title')),
            ),
            openingTitle,
          );
        }
        final position = topicPostList(tester).controller!.position;
        if (source == 'route' || source == 'anchor') {
          expect(find.byKey(const ValueKey(12)), findsOneWidget);
          expect(api.topicPostNumbersOpened, [12]);
        } else if (source == 'first') {
          expect(api.topicPostNumbersOpened, [1]);
        } else if (source == 'detail') {
          expect(api.topicPostNumbersOpened, isEmpty);
        } else {
          // The returned window already includes the resume post. Choosing
          // a header must not add a request to the existing load.
          expect(api.topicPostNumbersOpened, [null]);
        }
        await _export(tester, '$source-loaded');

        position.jumpTo(600);
        await _frames(tester);
        expectOpeningLayout();
        // Actual wheel input releases the initial choice, including when the
        // chrome controller owns header motion.
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: topicReadingViewportRect(tester).center,
            scrollDelta: const Offset(0, 20),
          ),
        );
        await _frames(tester);
        expect(_compact, findsOneWidget);

        position.jumpTo(0);
        await _frames(tester);
        expect(_compact, findsNothing);
        await _export(tester, '$source-top');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }
}
