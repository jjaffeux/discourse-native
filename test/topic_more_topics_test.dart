import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary_plugin.dart';
import 'package:discourse_native/src/shell/app_settings_controller.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_progress.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/topic_post_list.dart';

const _capture = ValueKey('more-topics-capture');
final _panel = find.byKey(const ValueKey('topic-end-more-topics-panel'));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    if (Platform.environment['MORE_TOPICS_RENDER_DIR'] == null) return;
    for (final (family, path) in [
      ('Lato', 'assets/fonts/Lato-Regular.ttf'),
      ('Open Sans', 'assets/fonts/OpenSans.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(path))).load();
    }
  });

  for (final inbox in [false, true]) {
    testWidgets(
      'panel enters naturally and releases topic chrome (inbox: $inbox)',
      (tester) async {
        await _pump(tester, inbox: inbox);
        final scroll = topicPostList(tester).controller!;
        final viewport = topicPostListFinder();
        final geometry = DPageSurface.headerGeometryOf(
          tester.element(viewport),
        )!;
        final extent = scroll.position.viewportDimension;
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        final initialExtent = scroll.position.maxScrollExtent;
        final panelTop = tester.getTopLeft(_panel).dy;
        final panelOffset =
            panelTop - tester.getTopLeft(viewport).dy + scroll.offset;
        expect(
          tester.getSize(_panel).width,
          tester.getSize(viewport).width - 16,
        );
        expect(
          tester.widget<DCard>(_panel).borderRadius,
          BorderRadius.circular(14),
        );

        scroll.jumpTo(panelOffset - extent * .75);
        await tester.pumpAndSettle();
        expect(geometry.visibleExtent, greaterThan(0));
        // Topic completion is independent of the recommendation list's height.
        final progress = tester.widget<TopicProgressPopover>(
          find.byType(TopicProgressPopover),
        );
        expect(progress.position, progress.total);
        await _render(tester, 'desktop-entry-${inbox ? 'inbox' : 'topic'}');
        final atRest = scroll.offset;
        await tester.pump(const Duration(seconds: 1));
        expect(scroll.offset, atRest); // No superseded snapping or pause gate.

        scroll.jumpTo(panelOffset - extent * .45);
        await tester.pumpAndSettle();
        expect(geometry.visibleExtent, 0);
        expect(geometry.naturalExtent, greaterThan(0));
        expect(scroll.position.maxScrollExtent, closeTo(initialExtent, .1));
        expect(find.byType(TopicProgressPopover).hitTestable(), findsNothing);
        await _render(tester, 'desktop-panel-${inbox ? 'inbox' : 'topic'}');

        scroll.jumpTo(panelOffset - extent * .75);
        await tester.pumpAndSettle();
        expect(geometry.visibleExtent, greaterThan(0));
        expect(find.byType(TopicProgressPopover).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }

  testWidgets('short topic retains its header until scrolled', (tester) async {
    await _pump(tester, short: true);
    final scroll = topicPostList(tester).controller!;
    final geometry = DPageSurface.headerGeometryOf(
      tester.element(topicPostListFinder()),
    )!;
    expect(scroll.offset, 0);
    expect(geometry.visibleExtent, greaterThan(0));
    expect(
      tester.getTopLeft(_panel).dy,
      lessThan(scroll.position.viewportDimension),
    );
    await _render(tester, 'short-topic');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  for (final scale in [1.0, 2.0]) {
    testWidgets('phone panel adapts at ${scale}x with reduced motion', (
      tester,
    ) async {
      await _pump(
        tester,
        size: const Size(390, 844),
        scale: scale,
        dark: true,
        reduced: true,
        inbox: true,
      );
      final scroll = topicPostList(tester).controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final related = find.byKey(
        const ValueKey('topic-recommendations-tab-discourse-ai/related'),
      );
      await tester.ensureVisible(related);
      await tester.pumpAndSettle();
      await tester.tap(related);
      await tester.pumpAndSettle();
      expect(find.text('Related discussion 1'), findsOneWidget);
      final switcher = find.byKey(
        const ValueKey('topic-recommendations-switch'),
      );
      expect(
        find.descendant(of: switcher, matching: find.byType(DToggle)),
        findsNWidgets(2),
      );
      await tester.tap(related);
      await tester.pumpAndSettle();
      expect(find.text('Related discussion 1'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('topic-recommendations-tab-core/suggested')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Suggested discussion 1'), findsOneWidget);
      await tester.tap(related);
      await tester.pumpAndSettle();
      expect(scroll.position.isScrollingNotifier.value, isFalse);
      await _render(tester, 'phone-${scale}x-dark');
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('panel follows the reading width preference', (tester) async {
    await _pump(
      tester,
      short: true,
      limited: true,
      size: const Size(1200, 800),
    );
    expect(tester.getSize(_panel).width, 825);
    expect(tester.getCenter(_panel).dx, 600);
    await _render(tester, 'desktop-limited-width');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('no panel before the real final post window', (tester) async {
    await _pump(tester, hasMore: true);
    expect(_panel, findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  bool inbox = false,
  bool short = false,
  Size size = const Size(1000, 800),
  double scale = 1,
  bool dark = false,
  bool reduced = false,
  bool hasMore = false,
  bool limited = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final settings = AppSettingsController(
    store: AppSettingsStore(persistence: MemoryAppSettingsPersistence()),
  );
  addTearDown(settings.dispose);
  await settings.setLimitContentSize(limited);
  final site = instance('meta.example');
  final posts = [
    for (var id = 1; id <= (short ? 1 : 3); id++)
      Post(
        id: id,
        postNumber: id,
        username: 'reader',
        cooked: List.filled(
          short ? 1 : 8,
          '<p>We are discussing a real reading experience. The topic ends before the next set of conversations begins.</p>',
        ).join(),
        createdAt: DateTime.utc(2026, 10, 8, 12, id),
      ),
  ];
  final controller = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(controller.dispose);
  await controller.load();
  controller.store
    ..put(
      site.url,
      TopicDetail(
        id: 1,
        title: 'A conversation worth reading',
        stream: [for (final post in posts) post.id, if (hasMore) 4],
        postsCount: posts.length + (hasMore ? 1 : 0),
        recommendations: TopicRecommendations(
          sources: [
            TopicRecommendationSource(
              definition: coreSuggestedTopicRecommendationSource,
              topics: [
                for (var id = 1; id <= 6; id++)
                  Topic(
                    id: 100 + id,
                    title: 'Suggested discussion $id',
                    slug: 'suggested-$id',
                    excerpt:
                        'Continue with another conversation from this forum.',
                    postsCount: 12 + id,
                  ),
              ],
            ),
            TopicRecommendationSource(
              definition: discourseAiRelatedTopicRecommendationSource,
              topics: [
                for (var id = 1; id <= 6; id++)
                  Topic(
                    id: 200 + id,
                    title: 'Related discussion $id',
                    slug: 'related-$id',
                    postsCount: 10 + id,
                  ),
              ],
            ),
          ],
        ),
      ),
    )
    ..putAll(site.url, posts);
  controller.pushContent(
    ContentRoute.topic(
      topicId: 1,
      slug: 'conversation',
      title: 'A conversation worth reading',
    ),
  );
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
          textTheme: (dark ? AppTheme.dark : AppTheme.light).textTheme.apply(
            fontFamily: 'Lato',
          ),
        ),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduced,
          ),
          child: RepaintBoundary(
            key: _capture,
            child: ContentSettingsScope(
              controller: settings,
              child: Scaffold(body: TopicView(inbox: inbox)),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _render(WidgetTester tester, String name) async {
  final output = Platform.environment['MORE_TOPICS_RENDER_DIR'];
  if (output == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
