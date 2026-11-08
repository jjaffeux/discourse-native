import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_navigation.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

void main() {
  testWidgets('returning feed switch keeps its first-frame width', (
    tester,
  ) async {
    final storage = PageStorageBucket();
    Widget page({required bool visible, double scale = 1}) => MaterialApp(
      theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: PageStorage(
          bucket: storage,
          child: Align(
            alignment: Alignment.topLeft,
            child: visible
                ? SizedBox(
                    width: 340,
                    child: TopicFeedMenu(
                      mode: TopicListMode.latest,
                      onSelected: (_) {},
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );

    final controls = find.byKey(const ValueKey('topic-list-view-switch'));
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(page(visible: true, scale: scale));
      await tester.pumpAndSettle();
      final size = tester.getSize(controls);
      await tester.pumpWidget(page(visible: false, scale: scale));
      expect(controls, findsNothing);
      await tester.pumpWidget(page(visible: true, scale: scale));
      expect(tester.getSize(controls), size);
      await tester.pumpAndSettle();
      expect(tester.getSize(controls), size);
    }
    expect(tester.takeException(), isNull);
  });

  group('a count change', () {
    final segment = find.byKey(const ValueKey('topic-list-view-newActivity'));
    final theme = AppTheme.light.copyWith(platform: TargetPlatform.macOS);

    Widget menu(int newCount, {Key? key, PageStorageBucket? bucket}) {
      final switcher = Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 900,
          child: TopicFeedMenu(
            key: key,
            mode: TopicListMode.latest,
            newCount: newCount,
            onSelected: (_) {},
          ),
        ),
      );
      return MaterialApp(
        theme: theme,
        home: bucket == null
            ? switcher
            : PageStorage(bucket: bucket, child: switcher),
      );
    }

    Finder count(Finder within, String text) =>
        find.descendant(of: within, matching: find.text(text));

    testWidgets('keeps every measured segment on its first frame', (
      tester,
    ) async {
      await tester.pumpWidget(menu(1));
      await tester.pumpAndSettle();
      final shown = _shownSegments();
      expect(shown, ['latest', 'unread', 'newActivity']);

      await tester.pumpWidget(menu(2));
      final missing = shown.toSet().difference(_shownSegments().toSet()).length;
      final measuredAgain = tester.binding.hasScheduledFrame ? 1 : 0;
      // ignore: avoid_print
      print('PERF_PROOF feed-switch segments_missing_first_frame=$missing');
      // ignore: avoid_print
      print('PERF_PROOF feed-switch second_frame_scheduled=$measuredAgain');

      expect(missing, lessThanOrEqualTo(0));
      expect(measuredAgain, lessThanOrEqualTo(0));
      expect(count(segment, '2'), findsOneWidget);
      expect(count(segment, '1'), findsNothing);
    });

    testWidgets('that widens a badge corrects the measured widths', (
      tester,
    ) async {
      await tester.pumpWidget(menu(9));
      await tester.pumpAndSettle();
      final narrow = tester.getSize(segment).width;

      await tester.pumpWidget(menu(10));
      expect(_shownSegments(), ['latest', 'unread', 'newActivity']);
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpAndSettle();
      expect(count(segment, '10'), findsOneWidget);
      final corrected = tester.getSize(segment).width;
      expect(corrected, greaterThan(narrow));

      await tester.pumpWidget(menu(10, key: UniqueKey()));
      await tester.pumpAndSettle();
      expect(tester.getSize(segment).width, corrected);
      expect(tester.takeException(), isNull);
    });

    testWidgets('that adds a badge beside a tight switch does not overflow', (
      tester,
    ) async {
      Widget tight(int newCount) => MaterialApp(
        theme: theme,
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 340,
            child: TopicFeedMenu(
              mode: TopicListMode.newActivity,
              newCount: newCount,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpWidget(tight(0));
      await tester.pumpAndSettle();
      await tester.pumpWidget(tight(1));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(count(segment, '1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('applied while away corrects the stored widths', (
      tester,
    ) async {
      final bucket = PageStorageBucket();
      await tester.pumpWidget(menu(9, bucket: bucket));
      await tester.pumpAndSettle();
      final narrow = tester.getSize(segment).width;

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: PageStorage(bucket: bucket, child: const SizedBox.shrink()),
        ),
      );
      await tester.pumpWidget(menu(10, bucket: bucket));
      expect(_shownSegments(), ['latest', 'unread', 'newActivity']);
      await tester.pumpAndSettle();
      expect(count(segment, '10'), findsOneWidget);
      expect(tester.getSize(segment).width, greaterThan(narrow));
    });

    for (final (name, size, platform, budget) in [
      ('desktop', const Size(1440, 844), TargetPlatform.macOS, 830),
      ('phone', const Size(390, 844), TargetPlatform.iOS, 130),
    ]) {
      testWidgets('from live tracking rebuilds only the switch ($name)', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const user = DiscourseUser(
          id: 7,
          username: 'reader',
          unifiedNewEnabled: true,
        );
        final controller = ShellController(
          instanceStore: FakeInstanceStore([
            instance('meta.discourse.org').copyWith(user: user),
          ]),
          api: FakeDiscourseApi(
            user: user,
            feeds: {
              '/latest.json': [
                for (var id = 1; id <= 40; id++)
                  Topic(
                    id: id,
                    title: 'Topic $id',
                    slug: 'topic-$id',
                    bumpedAt: DateTime.utc(2026, 9, 1),
                  ),
              ],
            },
          ),
          authenticator: FakeAuthenticator()
            ..keys['https://meta.discourse.org'] = 'key',
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          updateStore: FakeUpdateStore(),
          plugins: PluginInstaller.install(bundledWidgetTestManifest),
        );
        addTearDown(controller.dispose);
        await controller.load();
        await tester.pumpWidget(
          ShellScope(
            controller: controller,
            child: MaterialApp(
              theme: AppTheme.light.copyWith(platform: platform),
              home: const AdaptiveShell(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final tracker = FakeSiteTracker.built.single;
        final badgeOwner = find.byKey(
          ValueKey(
            platform == TargetPlatform.iOS
                ? 'topic-list-feed-menu'
                : 'topic-list-view-unread',
          ),
        );

        void deliver(int topicId) => tracker.deliverTopicTracking({
          'topic_id': topicId,
          'message_type': 'unread',
          'payload': {
            'highest_post_number': 50,
            'last_read_post_number': 1,
            'notification_level': 2,
          },
        });

        deliver(100);
        await tester.pumpAndSettle();
        expect(count(badgeOwner, '1'), findsOneWidget);

        var elements = 0;
        final previous = debugOnRebuildDirtyWidget;
        debugOnRebuildDirtyWidget = (element, builtOnce) {
          previous?.call(element, builtOnce);
          elements++;
        };
        addTearDown(() => debugOnRebuildDirtyWidget = previous);

        var mostElements = 0;
        for (var round = 2; round <= 4; round++) {
          elements = 0;
          deliver(99 + round);
          await tester.pumpAndSettle();
          expect(count(badgeOwner, '$round'), findsOneWidget);
          mostElements = math.max(mostElements, elements);
        }
        debugOnRebuildDirtyWidget = previous;

        // ignore: avoid_print
        print(
          'PERF_PROOF feed-switch elements_per_count_change_$name=$mostElements',
        );
        expect(mostElements, lessThanOrEqualTo(budget));

        for (var round = 5; round <= 10; round++) {
          deliver(99 + round);
          await tester.pumpAndSettle();
        }
        expect(
          count(find.byKey(const ValueKey('topic-list-feed-menu')), '10'),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  setUpAll(() async {
    if (Platform.environment['TOPIC_FEED_CAPTURE_DIR'] == null) return;
    await (FontLoader('TopicFeedReview')
          ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
        .load();
  });

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.macOS,
  ]) {
    for (final dark in [false, true]) {
      final scenario = '${platform.name}-flat-${dark ? 'dark' : 'light'}';
      testWidgets('feed menu adapts and scrolls ($scenario)', (tester) async {
        final mobile = platform != TargetPlatform.macOS;
        final size = mobile ? const Size(390, 844) : const Size(1100, 720);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
        addTearDown(tester.view.reset);
        var mode = TopicListMode.latest;
        late StateSetter rebuild;
        final base = dark ? AppTheme.dark : AppTheme.light;
        final theme = base.copyWith(
          platform: platform,
          textTheme: Platform.environment['TOPIC_FEED_CAPTURE_DIR'] == null
              ? base.textTheme
              : base.textTheme.apply(fontFamily: 'TopicFeedReview'),
        );
        final trigger = find.byKey(const ValueKey('topic-list-feed-menu'));
        final menu = find.byType(DDropdownMenuContent);

        for (final scale in [1.0, 2.0]) {
          mode = TopicListMode.latest;
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('topic-feed-capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme,
                home: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: TextScaler.linear(scale),
                    padding: const EdgeInsets.only(top: 44, bottom: 34),
                  ),
                  child: Scaffold(
                    body: StatefulBuilder(
                      builder: (context, setState) {
                        rebuild = setState;
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 130, 16, 16),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: TopicFeedMenu(
                              mode: mode,
                              maxVisibleViews: 1,
                              unifiedNew: true,
                              unreadCount: 2589,
                              newCount: 2677,
                              topicCount: 88,
                              replyCount: 2589,
                              onSelected: (value) =>
                                  rebuild(() => mode = value),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(trigger);
          await tester.pumpAndSettle();

          expect(find.text('Choose topic feed'), findsNothing);
          expect(find.byTooltip('Close'), findsNothing);
          expect(menu, findsOneWidget);
          if (mobile) {
            final sheet = find.byType(DSheetContent);
            expect(sheet, findsOneWidget);
            expect(tester.widget<DSheetContent>(sheet).side, DSheetSide.bottom);
            expect(
              tester.widget<DSheetContent>(sheet).variant,
              DSheetVariant.menu,
            );
            expect(find.byType(DSheetTitle), findsNothing);
            expect(
              tester.widget<DSheetContent>(sheet).showCloseButton,
              isFalse,
            );
            expect(
              tester
                  .getRect(find.byKey(const ValueKey('sheet-drag-handle')))
                  .bottom,
              lessThanOrEqualTo(
                tester
                    .getRect(find.byKey(const ValueKey('topic-list-latest')))
                    .top,
              ),
            );
            expect(
              tester.widget<DSheetContent>(sheet).semanticLabel,
              'Choose topic feed',
            );
            expect(
              find.byKey(const ValueKey('sheet-drag-handle')),
              findsOneWidget,
            );
            final bounds = tester.getRect(sheet);
            expect(bounds.left, 0);
            expect(bounds.right, size.width);
            expect(bounds.top, greaterThanOrEqualTo(size.height * .2 - 1));
          } else {
            expect(find.byType(DSheetContent), findsNothing);
            final bounds = tester.getRect(menu);
            expect(bounds.left, closeTo(tester.getRect(trigger).left, 1));
            expect(
              bounds.top,
              closeTo(
                tester.getRect(trigger).bottom +
                    tester.widget<DDropdownMenuContent>(menu).sideOffset,
                1,
              ),
            );
            expect(bounds.width, 304);
            expect(bounds.bottom, lessThanOrEqualTo(size.height - 34));
          }
          expect(find.byType(DDropdownMenuGroup), findsNWidgets(2));
          for (final (key, count) in [
            ('unread', '2589'),
            ('new-all', '2677'),
            ('new-topics', '88'),
            ('new-replies', '2589'),
          ]) {
            expect(
              find.descendant(
                of: find.byKey(ValueKey('topic-list-$key')),
                matching: find.text(count),
              ),
              findsOneWidget,
            );
          }
          expect(
            tester.widget<DDropdownMenuContent>(menu).semanticLabel,
            'Choose topic feed',
          );
          await _capture(tester, '$scenario-$scale');

          final allTime = find.byKey(
            const ValueKey('topic-list-top-period-all'),
          );
          if (mobile && scale == 2) {
            expect(allTime.hitTestable(), findsNothing);
            final scrollable = find.descendant(
              of: menu,
              matching: find.byType(Scrollable),
            );
            for (
              var attempt = 0;
              attempt < 4 && allTime.hitTestable().evaluate().isEmpty;
              attempt++
            ) {
              await tester.drag(scrollable, const Offset(0, -400));
              await tester.pumpAndSettle();
            }
            expect(allTime.hitTestable(), findsOneWidget);
          } else {
            await tester.ensureVisible(allTime);
            await tester.pumpAndSettle();
          }
          await _capture(tester, '$scenario-$scale-scrolled');
          await tester.tap(allTime);
          await tester.pumpAndSettle();
          expect(mode, TopicListMode.topAll);
          expect(menu, findsNothing);
          expect(tester.widget<DButton>(trigger).expanded, isFalse);
          if (!mobile) {
            expect(tester.widget<DButton>(trigger).focusNode!.hasFocus, isTrue);
          }

          // A phone's pill opens every view, Top's periods among them.
          await tester.tap(
            mobile
                ? trigger
                : find.byKey(const ValueKey('topic-list-view-top')),
          );
          await tester.pumpAndSettle();
          final check = find.descendant(
            of: allTime,
            matching: find.byType(DIcon),
          );
          expect(check, findsOneWidget);
          await tester.tapAt(Offset(size.width - 16, 80));
          await tester.pumpAndSettle();
          expect(menu, findsNothing);
          expect(mode, TopicListMode.topAll);

          await tester.tap(trigger);
          await tester.pumpAndSettle();
          if (mobile) {
            final handle = find.byKey(const ValueKey('sheet-drag-handle'));
            await tester.drag(handle, const Offset(0, 700));
            await tester.pumpAndSettle();
            expect(mode, TopicListMode.topAll);
          } else {
            await tester.sendKeyEvent(LogicalKeyboardKey.end);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(mode, TopicListMode.popular);
          }
          expect(menu, findsNothing);

          await tester.tap(trigger);
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(menu, findsNothing);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}

List<String> _shownSegments() => [
  for (final view in const [
    'latest',
    'unread',
    'newActivity',
    'unseen',
    'top',
    'trending',
  ])
    if (find.byKey(ValueKey('topic-list-view-$view')).evaluate().isNotEmpty)
      view,
];

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['TOPIC_FEED_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final image = await tester
        .renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('topic-feed-capture')),
        )
        .toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
