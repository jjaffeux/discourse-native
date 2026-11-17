import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/foundation/icons/d_native_icons.dart';
import 'package:discourse_native/src/shell/topic_progress.dart';
import 'package:discourse_native/src/ui/foundation/control_artwork.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_topic_layout_test.dart' show pumpMobileTopicFixture;
import 'support/load_test_fonts.dart';

const _capture = String.fromEnvironment('TOPIC_FOOT_CAPTURE_DIR');

void main() {
  setUpAll(() async {
    if (_capture.isEmpty) return;
    await loadTestFonts();
    final system = File('/System/Library/Fonts/SFNS.ttf').readAsBytesSync();
    for (final family in [
      '.AppleSystemUIFont',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
    ]) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(system)))).load();
    }
  });
  const platforms = TargetPlatformVariant({
    TargetPlatform.iOS,
    TargetPlatform.android,
  });

  Finder surface(Finder control) =>
      find.descendant(of: control, matching: find.byType(DControlArtwork));
  Iterable<DIconData> icons(WidgetTester tester, Finder control) => tester
      .widgetList<DIcon>(
        find.descendant(of: control, matching: find.byType(DIcon)),
      )
      .map((icon) => icon.icon);

  testWidgets('the topic foot says its tools and count as the mockup does', (
    tester,
  ) async {
    await pumpMobileTopicFixture(tester);
    final bookmark = find.byKey(const ValueKey('topic-header-bookmark-button'));
    final level = find.byKey(
      const ValueKey('topic-header-notification-button'),
    );
    final more = find.byKey(const ValueKey('topic-more-actions'));
    final progress = find.byKey(const ValueKey('topic-progress-button'));

    // What acts on the topic at once shares one pill, the level button no
    // longer saying it opens with a chevron.
    final pill = find.ancestor(
      of: bookmark,
      matching: find.byType(DButtonGroup),
    );
    expect(find.descendant(of: pill, matching: level), findsOneWidget);
    expect(icons(tester, level), isNot(contains(DNativeIcons.filterChevron)));
    expect(
      tester.getRect(surface(level)).left,
      tester.getRect(surface(bookmark)).right,
    );

    // The pill's ends stand further in, so each glyph looks centred in the
    // curve: the bookmark 15 from the pill's start, the level 12 from its
    // part's start and 15 from the pill's end, at the reference's 40 at
    // least.
    Rect glyph(Finder control) => tester.getRect(
      find.descendant(of: control, matching: find.byType(DIcon)).first,
    );
    expect(glyph(bookmark).left - tester.getRect(surface(bookmark)).left, 15);
    expect(tester.getRect(surface(bookmark)).size, const Size(40, 40));
    final levelSurface = tester.getRect(surface(level));
    expect(glyph(level).left - levelSurface.left, 12);
    expect(levelSurface.height, 40);
    expect(
      levelSurface.width,
      moreOrLessEquals(
        (12 + glyph(level).width + 15).clamp(40, double.infinity),
      ),
    );

    // The menu of more is a circle of its own, its ellipsis upright.
    expect(icons(tester, more), [DIcons.ellipsisVertical]);
    expect(tester.getRect(surface(more)).size, const Size(40, 40));
    expect(find.descendant(of: pill, matching: more), findsNothing);
    for (final icon in [bookmark, level, more]) {
      expect(
        tester
            .getSize(find.descendant(of: icon, matching: find.byType(DIcon)))
            .height,
        15,
      );
    }

    // Where you are is a pill as tall as the dock's circle, 18 in at either
    // side, and the tools stand centred on it.
    final countPill = tester.getRect(surface(progress));
    final countText = tester.getRect(
      find.descendant(of: progress, matching: find.byType(TopicPostCount)),
    );
    expect(
      countPill.height,
      moreOrLessEquals(
        DMobileDockGeometry.of(
          tester.element(find.byKey(const ValueKey('mobile-bottom-bar'))),
        ).circle,
      ),
    );
    expect(countText.left - countPill.left, moreOrLessEquals(18));
    expect(countPill.right - countText.right, moreOrLessEquals(18));
    for (final tool in [bookmark, more]) {
      expect(
        tester.getRect(surface(tool)).center.dy,
        moreOrLessEquals(countPill.center.dy),
      );
    }

    // The count reads as the timeline says it: where you are large and
    // strong, out of how many small and quiet, in tabular figures.
    final count = find.descendant(
      of: progress,
      matching: find.byType(TopicPostCount),
    );
    expect(count, findsOneWidget);
    final text = tester.widget<RichText>(
      find.descendant(of: count, matching: find.byType(RichText)),
    );
    expect(text.text.toPlainText(), '1 / 4');
    final span = (text.text as TextSpan).children!.single as TextSpan;
    expect(span.style!.fontSize, 17);
    expect(span.style!.fontWeight, FontWeight.w700);
    final total = span.children!.single as TextSpan;
    expect(total.style!.fontSize, 13);
    expect(total.style!.fontWeight, FontWeight.w400);
    expect(total.style!.color, isNot(span.style!.color));
    expect(
      text.text.style!.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );

    expect(tester.takeException(), isNull);
    if (_capture.isNotEmpty) {
      // Real time lets the shell's platform streams start with no plugin
      // behind them, which says nothing about the foot.
      final reported = FlutterError.onError;
      FlutterError.onError = (_) {};
      addTearDown(() => FlutterError.onError = reported);
      await tester.runAsync(() async {
        RenderObject root = tester.renderObject(progress);
        while (root.parent != null) {
          root = root.parent!;
        }
        final builder = ui.SceneBuilder();
        (root as RenderView).debugLayer!.addToScene(builder);
        final scene = builder.build();
        final size = tester.view.physicalSize / tester.view.devicePixelRatio;
        final image = await scene.toImage(
          size.width.toInt(),
          size.height.toInt(),
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(_capture).create(recursive: true);
        await File(
          '$_capture/topic-foot-${defaultTargetPlatform.name}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
        scene.dispose();
      });
    }
  }, variant: platforms);

  testWidgets('the foot rises with the bar as it lifts to say something', (
    tester,
  ) async {
    await pumpMobileTopicFixture(tester);
    final progress = find.byKey(const ValueKey('topic-progress-button'));
    final dock = find.byType(DMobileDock);
    final rest = tester.getRect(progress);
    final peek = DMobileDockPeek.maybeOf(tester.element(dock))!;
    final lift = DMobileDockGeometry.of(tester.element(dock)).peek;
    expect(peek.say(const DMobileDockSaying(text: 'Bookmarked')), isTrue);
    await tester.pump();
    // On its own curve, 420 ms, to as far as the bar lifts.
    await tester.pump(const Duration(milliseconds: 420));
    expect(tester.getRect(progress).top, closeTo(rest.top - lift, .01));
    await tester.pump(const Duration(milliseconds: 1980));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getRect(progress), rest);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('the timeline says the count as its button does', (tester) async {
    await pumpMobileTopicFixture(tester);
    await tester.tap(find.byKey(const ValueKey('topic-progress-button')));
    await tester.pumpAndSettle();
    final selection = find.byKey(const ValueKey('topic-progress-selection'));
    expect(tester.widget(selection), isA<TopicPostCount>());
    expect(
      tester.widget<TopicPostCount>(selection),
      isA<TopicPostCount>()
          .having((count) => count.position, 'position', 1)
          .having((count) => count.total, 'total', 4),
    );
    expect(tester.takeException(), isNull);
  }, variant: platforms);
}
