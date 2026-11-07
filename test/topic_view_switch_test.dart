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

  for (final dark in [false, true]) {
    testWidgets('desktop feed consumes Native inset segment geometry ($dark)', (
      tester,
    ) async {
      final fixture = _Fixture(dark: dark, mode: TopicListMode.newTopics);
      await fixture.pump(tester);
      final selected = _segment('newActivity');
      expect(tester.widget<DButtonGroup>(_switch).inset, isTrue);
      expect(tester.getSize(_switch).height, 30);
      expect(tester.getSize(selected).height, 26);
      expect(tester.getTopLeft(selected).dy - tester.getTopLeft(_switch).dy, 2);
      final artwork = tester.widget<AnimatedContainer>(
        find
            .descendant(of: selected, matching: find.byType(AnimatedContainer))
            .first,
      );
      final surface = artwork.decoration! as BoxDecoration;
      expect(surface.borderRadius, BorderRadius.circular(999));
      expect(surface.color, Colors.transparent);
      final indicator = find.byKey(
        const ValueKey('toggle-group-sliding-indicator'),
      );
      expect(indicator, findsOneWidget);
      expect(tester.getRect(indicator), tester.getRect(selected));
      final tint = tester.widget<DecoratedBox>(
        find.descendant(of: indicator, matching: find.byType(DecoratedBox)),
      );
      expect(
        (tint.decoration as BoxDecoration).color,
        DTokens.of(tester.element(selected)).foreground.withValues(alpha: .16),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final dark in [false, true]) {
      testWidgets('a phone view is one quiet pill ($platform, dark $dark)', (
        tester,
      ) async {
        final fixture = _Fixture(
          platform: platform,
          dark: dark,
          mode: TopicListMode.newTopics,
        );
        await fixture.pump(tester);
        await _capture(tester, '${platform.name}-${dark ? 'dark' : 'light'}');
        expect(_switch, findsNothing);
        expect(find.byType(DToggle), findsNothing);
        final pill = tester.widget<DButton>(_more);
        expect(pill.variant, DButtonVariant.quiet);
        expect(pill.size, DButtonSize.filter);
        final bounds = tester.getRect(_more);
        // As tall as the filter pills beside it.
        expect(
          bounds.height,
          tester
              .getSize(
                find.ancestor(
                  of: find.text('General'),
                  matching: find.byType(DButton),
                ),
              )
              .height,
        );
        final name = find.descendant(
          of: _more,
          matching: find.text('New · Topics'),
        );
        final count = find.descendant(of: _more, matching: find.text('3'));
        expect(tester.getRect(name).left - bounds.left, 12);
        final badge = find.ancestor(of: count, matching: find.byType(DBadge));
        expect(tester.getRect(badge).left - tester.getRect(name).right, 7);
        expect(bounds.right - tester.getRect(badge).right, 12);
        expect(_baseline(tester, count), _baseline(tester, name));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a phone pill counts its own view, else what waits elsewhere', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final fixture = _Fixture(platform: TargetPlatform.iOS);
    await fixture.pump(tester);
    Iterable<String> drawn() => tester
        .widgetList<Text>(
          find.descendant(of: _more, matching: find.byType(Text)),
        )
        .map((text) => text.data!);
    // Unified New's seven already include Unread's four replies.
    expect(drawn(), ['Latest', '7']);
    expect(
      find.bySemanticsLabel('View: Latest, 7 more in other views'),
      findsOneWidget,
    );
    for (final (mode, name, count) in [
      (TopicListMode.unread, 'Unread', '4'),
      (TopicListMode.newTopics, 'New · Topics', '3'),
      (TopicListMode.newActivity, 'New', '7'),
    ]) {
      fixture.rebuild(() => fixture.mode = mode);
      await tester.pumpAndSettle();
      expect(drawn(), [name, count]);
      expect(
        find.bySemanticsLabel('View: $name, $count topics'),
        findsOneWidget,
      );
    }
    fixture.rebuild(() {
      fixture.mode = TopicListMode.topYearly;
      fixture.unified = false;
    });
    await tester.pumpAndSettle();
    // Legacy New's three topics are disjoint from Unread's four replies.
    expect(drawn(), ['Top · Year', '7']);
    expect(
      find.bySemanticsLabel('View: Top · Year, 7 more in other views'),
      findsOneWidget,
    );
    fixture.rebuild(() {
      fixture.mode = TopicListMode.latest;
      fixture.signedIn = false;
    });
    await tester.pumpAndSettle();
    expect(drawn(), ['Latest']);
    expect(find.bySemanticsLabel('View: Latest'), findsOneWidget);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('New, Top and overflow keep independent keyboard menu focus', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.pump(tester);
    final fresh = _segment('newActivity');
    tester.widget<DToggle>(fresh).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(fixture.mode, TopicListMode.newTopics);
    expect(tester.widget<DToggle>(fresh).focusNode!.hasFocus, isTrue);

    await tester.tap(_more);
    await tester.pumpAndSettle();
    await tester.tap(_entry('top-period-yearly'));
    await tester.pumpAndSettle();
    final top = _segment('top');
    tester.widget<DToggle>(top).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(fixture.mode, TopicListMode.topWeekly);
    expect(tester.widget<DToggle>(top).focusNode!.hasFocus, isTrue);

    tester.widget<DButton>(_more).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(fixture.mode, TopicListMode.popular);
    expect(tester.widget<DButton>(_more).focusNode!.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
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
        'the phone pill opens every view as a sheet ($platform $dark)',
        (tester) async {
          final fixture = _Fixture(
            platform: platform,
            dark: dark,
            width: 358,
            phoneHeight: 780,
            mode: TopicListMode.newTopics,
          );
          await fixture.pump(tester);
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
            const Offset(0, -500),
          );
          await tester.pumpAndSettle();
          for (final id in [
            'latest',
            'unread',
            'new-all',
            'new-topics',
            'new-replies',
            'unseen',
            'top-period-yearly',
            'top-period-quarterly',
            'top-period-monthly',
            'top-period-weekly',
            'top-period-daily',
            'top-period-all',
            'popular',
          ]) {
            await tester.ensureVisible(_entry(id));
            await tester.pumpAndSettle();
            expect(_entry(id).hitTestable(), findsOneWidget, reason: id);
          }
          await tester.tap(_entry('popular'));
          await tester.pumpAndSettle();
          expect(fixture.mode, TopicListMode.popular);
          expect(find.byType(DSheetContent), findsNothing);
          expect(
            find.descendant(of: _more, matching: find.text('Trending')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('a rebuild that changes no view leaves the views as built', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.pump(tester);
    var rebuilt = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is DToggle) rebuilt++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);

    fixture.rebuild(() => fixture.generation++);
    await tester.pump();
    expect(rebuilt, 0);

    // A tap reaches the callback of the latest build.
    await tester.tap(_segment('unread'));
    await tester.pumpAndSettle();
    expect(fixture.picks, [(1, TopicListMode.unread)]);

    // A count the views show builds them again.
    fixture.rebuild(() => fixture.unread = 9);
    await tester.pump();
    expect(rebuilt, greaterThan(0));
    expect(
      find.descendant(of: _segment('unread'), matching: find.text('9')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text keeps the current view in bounds', (tester) async {
    final fixture = _Fixture(
      width: 280,
      mode: TopicListMode.newReplies,
      scale: 2,
    );
    await fixture.pump(tester);
    expect(_segment('newActivity'), findsOneWidget);
    expect(tester.getRect(_switch).width, lessThanOrEqualTo(280));
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
    this.phoneHeight = 844,
  });
  final TargetPlatform platform;
  final bool dark;
  final double scale;
  final double phoneHeight;
  TopicListMode mode;
  double width;
  bool unified, signedIn;
  int unread = 4;
  int generation = 0;
  final picks = <(int, TopicListMode)>[];
  late StateSetter rebuild;

  Future<void> pump(WidgetTester tester) async {
    final mobile = platform != TargetPlatform.macOS;
    final size = mobile ? Size(390, phoneHeight) : const Size(1100, 720);
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
                      final generation = this.generation;
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
                                unreadCount: unread,
                                newCount: unified ? 7 : 3,
                                topicCount: 3,
                                replyCount: 4,
                                onSelected: (value) {
                                  picks.add((generation, value));
                                  rebuild(() => mode = value);
                                },
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

double _baseline(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderBox>(text);
  final ascent = paragraph.getDryBaseline(
    BoxConstraints.loose(paragraph.size),
    TextBaseline.alphabetic,
  )!;
  return paragraph.localToGlobal(Offset(0, ascent)).dy;
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
