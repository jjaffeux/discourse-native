import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/shell/topic_feed_menu.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _switch = find.byKey(const ValueKey('topic-list-view-switch'));
final _more = find.byKey(const ValueKey('topic-list-feed-menu'));
Finder _segment(String view) => find.byKey(ValueKey('topic-list-view-$view'));
Finder _entry(String id) => find.byKey(ValueKey('topic-list-$id'));

void main() {
  setUpAll(() async {
    if (Platform.environment['TOPIC_FEED_CAPTURE_DIR'] == null) return;
    await (FontLoader('TopicFeedReview')
          ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
        .load();
  });

  testWidgets('desktop shows three views and only hidden views in overflow', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.pump(tester);
    expect(find.byType(DToggle), findsNWidgets(3));
    expect(_segment('latest'), findsOneWidget);
    expect(_segment('unread'), findsOneWidget);
    expect(_segment('newActivity'), findsOneWidget);
    expect(_segment('unseen'), findsNothing);
    await _capture(tester, 'desktop-three-views');
    await tester.tap(_segment('unread'));
    await tester.pumpAndSettle();
    expect(fixture.mode, TopicListMode.unread);
    expect(tester.widget<DToggle>(_segment('unread')).pressed, isTrue);
    await tester.tap(_more);
    await tester.pumpAndSettle();
    expect(_entry('latest'), findsNothing);
    expect(_entry('unread'), findsNothing);
    expect(_entry('new-all'), findsNothing);
    expect(_entry('unseen'), findsOneWidget);
    expect(_entry('popular'), findsOneWidget);
    await _capture(tester, 'desktop-overflow');
    await tester.tap(_entry('popular'));
    await tester.pumpAndSettle();
    expect(fixture.mode, TopicListMode.popular);
    expect(tester.widget<DToggle>(_segment('trending')).pressed, isTrue);
    expect(find.byType(DToggle), findsNWidgets(3));
    expect(find.byType(DDropdownMenuContent), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final unified in [false, true]) {
    testWidgets('overflow deduplicates counted views (unified $unified)', (
      tester,
    ) async {
      final fixture = _Fixture(
        unified: unified,
        width: 150,
        mode: TopicListMode.topYearly,
      );
      await fixture.pump(tester);
      expect(_segment('top'), findsOneWidget);
      // Unified New's seven already include the four replies. Legacy New's
      // three topics are disjoint from Unread's four replies.
      expect(
        find.descendant(of: _more, matching: find.text('7')),
        findsOneWidget,
      );
      expect(find.byType(DToggle), findsOneWidget);
      fixture.width = 1000;
      fixture.rebuild(() {});
      await tester.pumpAndSettle();
      expect(find.byType(DToggle), findsNWidgets(3));
      expect(_segment('latest'), findsOneWidget);
      expect(_segment('unread'), findsOneWidget);
      expect(_segment('top'), findsOneWidget);
      expect(
        find.descendant(of: _more, matching: find.text(unified ? '7' : '3')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('New subsets and every Top period return the real feed mode', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.pump(tester);
    for (final (id, mode) in [
      ('new-topics', TopicListMode.newTopics),
      ('new-replies', TopicListMode.newReplies),
      ('new-all', TopicListMode.newActivity),
    ]) {
      await tester.tap(_segment('newActivity'));
      await tester.pumpAndSettle();
      await tester.tap(_entry(id));
      await tester.pumpAndSettle();
      expect(fixture.mode, mode);
      expect(tester.widget<DToggle>(_segment('newActivity')).pressed, isTrue);
    }
    await tester.tap(_more);
    await tester.pumpAndSettle();
    await tester.tap(_entry('top-period-yearly'));
    await tester.pumpAndSettle();
    for (final period in TopPeriod.values) {
      await tester.tap(_segment('top'));
      await tester.pumpAndSettle();
      final choice = _entry('top-period-${period.queryValue}');
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(fixture.mode, TopicListMode.top(period));
    }
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final dark in [false, true]) {
      testWidgets(
        'phone overflow includes all views and counts ($platform $dark)',
        (tester) async {
          final fixture = _Fixture(
            platform: platform,
            dark: dark,
            width: 358,
            mode: TopicListMode.newTopics,
          );
          await fixture.pump(tester);
          await _capture(
            tester,
            '${platform.name}-${dark ? 'dark' : 'light'}-switch',
          );
          await tester.tap(_more);
          await tester.pumpAndSettle();
          expect(find.byType(DSheetContent), findsOneWidget);
          expect(find.byType(DDropdownMenuGroup), findsNWidgets(2));
          for (final (id, count) in [
            ('unread', '4'),
            ('new-all', '7'),
            ('new-topics', '3'),
            ('new-replies', '4'),
          ]) {
            expect(
              find.descendant(of: _entry(id), matching: find.text(count)),
              findsOneWidget,
            );
          }
          expect(
            find.descendant(
              of: _entry('new-topics'),
              matching: find.byType(DIcon),
            ),
            findsOneWidget,
          );
          await _capture(
            tester,
            '${platform.name}-${dark ? 'dark' : 'light'}-overflow',
          );
          await tester.drag(
            find.byKey(const ValueKey('sheet-drag-handle')),
            const Offset(0, -350),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(_entry('popular'));
          await tester.tap(_entry('popular'));
          await tester.pumpAndSettle();
          expect(fixture.mode, TopicListMode.popular);
          expect(find.byType(DSheetContent), findsNothing);
          fixture.mode = TopicListMode.topYearly;
          fixture.width = 150;
          fixture.rebuild(() {});
          await tester.pumpAndSettle();
          expect(
            find.descendant(of: _more, matching: find.text('7')),
            findsOneWidget,
          );
          await _capture(
            tester,
            '${platform.name}-${dark ? 'dark' : 'light'}-hidden-counts',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('large text and compact labels keep the current view in bounds', (
    tester,
  ) async {
    final fixture = _Fixture(
      width: 280,
      mode: TopicListMode.newReplies,
      scale: 2,
    );
    await fixture.pump(tester);
    expect(_segment('newActivity'), findsOneWidget);
    expect(tester.getRect(_switch).width, lessThanOrEqualTo(280));
    expect(tester.takeException(), isNull);
    fixture.compact = true;
    fixture.rebuild(() {});
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(find.bySemanticsLabel('New · Replies, 4 topics'), findsOneWidget);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('signed out choices and legacy New preserve server semantics', (
    tester,
  ) async {
    final fixture = _Fixture(signedIn: false);
    await fixture.pump(tester);
    expect(find.byType(DToggle), findsNWidgets(3));
    expect(_more, findsNothing);
    fixture.width = tester.getSize(_switch).width + 1;
    fixture.rebuild(() {});
    await tester.pumpAndSettle();
    expect(find.byType(DToggle), findsNWidgets(3));
    expect(_more, findsNothing);
    expect(_segment('unread'), findsNothing);
    fixture.signedIn = true;
    fixture.unified = false;
    fixture.width = 1000;
    fixture.rebuild(() {});
    await tester.pumpAndSettle();
    await tester.tap(_segment('newActivity'));
    await tester.pumpAndSettle();
    expect(fixture.mode, TopicListMode.newActivity);
    expect(find.byType(DDropdownMenuContent), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _Fixture {
  _Fixture({
    this.platform = TargetPlatform.macOS,
    this.dark = false,
    this.mode = TopicListMode.latest,
    this.width = 1000,
    this.unified = true,
    this.signedIn = true,
    this.scale = 1,
  });
  final TargetPlatform platform;
  final bool dark;
  final double scale;
  TopicListMode mode;
  double width;
  bool unified, signedIn;
  bool compact = false;
  late StateSetter rebuild;

  Future<void> pump(WidgetTester tester) async {
    final mobile = platform != TargetPlatform.macOS;
    final size = mobile ? const Size(390, 844) : const Size(1100, 720);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final base = dark ? AppTheme.dark : AppTheme.light;
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('topic-feed-capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: base.copyWith(
            platform: platform,
            textTheme: Platform.environment['TOPIC_FEED_CAPTURE_DIR'] == null
                ? base.textTheme
                : base.textTheme.apply(fontFamily: 'TopicFeedReview'),
          ),
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
              padding: EdgeInsets.only(
                top: mobile ? 44 : 0,
                bottom: mobile ? 34 : 0,
              ),
            ),
            child: DTouchTargets(
              child: Scaffold(
                body: SafeArea(
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      rebuild = setState;
                      return DPageSurface.headed(
                        title: const Text('Topics'),
                        controls: Wrap(
                          spacing: DSpacing.sm,
                          runSpacing: DSpacing.sm,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: width),
                              child: TopicFeedMenu(
                                mode: mode,
                                unifiedNew: unified,
                                signedIn: signedIn,
                                unreadCount: 4,
                                newCount: unified ? 7 : 3,
                                topicCount: 3,
                                replyCount: 4,
                                compact: compact,
                                onSelected: (value) =>
                                    rebuild(() => mode = value),
                              ),
                            ),
                            DButton(
                              size: DButtonSize.filter,
                              variant: DButtonVariant.quiet,
                              label: const Text('General'),
                              onPressed: () {},
                            ),
                            DButton(
                              size: DButtonSize.filter,
                              variant: DButtonVariant.quiet,
                              label: const Text('All tags'),
                              onPressed: () {},
                            ),
                          ],
                        ),
                        child: DItemGroup(
                          children: [
                            for (final title in [
                              'Welcome to the community',
                              'Share what you are working on',
                              'A guide to getting started',
                              'Community ideas for the next release',
                            ])
                              DItem(
                                children: [
                                  DItemContent(
                                    children: [
                                      DItemTitle(child: Text(title)),
                                      const DItemDescription(
                                        child: Text(
                                          'General · community discussion',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

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
