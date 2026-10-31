import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// A pill [full] wide that drops to [tight] while its row asks it to.
class _Pill extends StatelessWidget {
  const _Pill(
    this.name, {
    required this.full,
    this.tight,
    this.compactOnly = false,
  });

  final String name;
  final double full;
  final double? tight;
  final bool compactOnly;

  @override
  Widget build(BuildContext context) {
    final short =
        tight != null &&
        (compactOnly ? DFitRow.compactOf(context) : DFitRow.tightOf(context));
    return SizedBox(
      key: ValueKey(name),
      width: short ? tight : full,
      height: 30,
      child: Text(short ? '$name-tight' : name),
    );
  }
}

class _Views extends StatelessWidget {
  const _Views();

  @override
  Widget build(BuildContext context) {
    final room = DFitRow.availableWidthOf(context) ?? double.infinity;
    final count = room >= 300
        ? 3
        : room >= 200
        ? 2
        : 1;
    return SizedBox(
      width: count * 100,
      height: 30,
      child: Text('$count views'),
    );
  }
}

void _desktopTest(String description, WidgetTesterCallback callback) =>
    testWidgets(
      description,
      callback,
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

void main() {
  testWidgets('view-switch track eases its width without stretching segments', (
    tester,
  ) async {
    late StateSetter rebuild;
    var compact = false;
    const boundaryKey = ValueKey('track-paint');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return RepaintBoundary(
                key: boundaryKey,
                child: ColoredBox(
                  color: Colors.white,
                  child: SizedBox(
                    width: 400,
                    height: 80,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: DFitRow(
                        compact: compact,
                        children: [
                          Builder(
                            builder: (context) => DButtonGroup.inset(
                              children: [
                                if (DFitRow.compactOf(context))
                                  const DToggle.iconOnly(
                                    size: DToggleSize.segment,
                                    variant: DToggleVariant.segmented,
                                    semanticLabel: 'Latest topics',
                                    icon: DIcon(DIcons.tag, size: 14),
                                  )
                                else
                                  const DToggle(
                                    size: DToggleSize.segment,
                                    variant: DToggleVariant.segmented,
                                    child: Text('Latest topics'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    final track = find.byType(DButtonGroup);
    final before = tester.getSize(track);
    rebuild(() => compact = true);
    await tester.pump();
    final after = tester.getSize(track);
    final x = (after.width + (before.width - after.width) * .125 - 2).floor();
    final y = (after.height / 2).floor();
    expect(x, greaterThan(after.width));
    Future<List<int>> pixel() async => (await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final offset = (y * image.width + x) * 4;
      final result = List.generate(
        4,
        (index) => bytes.getUint8(offset + index),
      );
      image.dispose();
      return result;
    }))!;
    await tester.pump(const Duration(milliseconds: 130));
    expect(await pixel(), isNot([255, 255, 255, 255]));
    await tester.pumpAndSettle();
    expect(await pixel(), [255, 255, 255, 255]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'nested controls move without scaling their artwork or targets',
    (tester) async {
      final semantics = tester.ensureSemantics();
      late StateSetter rebuild;
      var compact = false;
      var reducedMotion = false;
      var activated = 0;
      const glyphKey = ValueKey('moving-glyph');
      const buttonKey = ValueKey('moving-button');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: reducedMotion),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 400,
                      child: DFitRow(
                        compact: compact,
                        children: [
                          DFitRowItem(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DButtonGroup.quiet(
                                children: [
                                  Builder(
                                    builder: (context) =>
                                        DFitRow.compactOf(context)
                                        ? DButton.iconOnly(
                                            icon: const DIcon(
                                              DIcons.tag,
                                              size: 14,
                                            ),
                                            semanticLabel: 'First category',
                                            tooltip: 'First category',
                                            size: DButtonSize.filter,
                                            variant: DButtonVariant.quiet,
                                            onPressed: () {},
                                          )
                                        : DButton(
                                            label: const Text('First category'),
                                            icon: const DIcon(
                                              DIcons.tag,
                                              size: 14,
                                            ),
                                            size: DButtonSize.filter,
                                            variant: DButtonVariant.quiet,
                                            onPressed: () {},
                                          ),
                                  ),
                                  DButton.iconOnly(
                                    key: buttonKey,
                                    icon: const DIcon(
                                      DIcons.tag,
                                      key: glyphKey,
                                      size: 14,
                                    ),
                                    semanticLabel: 'Second category',
                                    tooltip: 'Second category',
                                    size: DButtonSize.filter,
                                    variant: DButtonVariant.quiet,
                                    onPressed: () => activated++,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      Rect painted(Finder finder) {
        final box = tester.renderObject<RenderBox>(finder);
        return Rect.fromPoints(
          box.localToGlobal(Offset.zero),
          box.localToGlobal(box.size.bottomRight(Offset.zero)),
        );
      }

      final glyph = find.byKey(glyphKey);
      final button = find.byKey(buttonKey);
      final element = tester.element(button);
      final initialGlyph = painted(glyph);
      rebuild(() => compact = true);
      await tester.pump();
      expect(painted(glyph).left, closeTo(initialGlyph.left, .01));
      await tester.pump(const Duration(milliseconds: 130));
      final middle = painted(glyph);
      expect(middle.size, initialGlyph.size);
      expect(
        tester.getSemantics(button).getSemanticsData().label,
        'Second category',
      );
      expect(tester.element(button), same(element));
      await tester.tapAt(middle.center);
      expect(activated, 1);
      await tester.pumpAndSettle();
      final end = painted(glyph);
      expect(end.size, initialGlyph.size);
      expect(
        middle.left,
        closeTo(
          initialGlyph.left +
              (end.left - initialGlyph.left) *
                  const Cubic(.2, .8, .2, 1).transform(.5),
          .01,
        ),
      );
      rebuild(() => compact = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      final expanding = painted(glyph);
      expect(expanding.size, initialGlyph.size);
      await tester.tapAt(expanding.center + const Offset(16, 0));
      expect(activated, 2);
      final interrupted = painted(glyph);
      rebuild(() => compact = true);
      await tester.pump();
      expect(painted(glyph).left, closeTo(interrupted.left, .01));
      await tester.pumpAndSettle();
      rebuild(() {
        compact = false;
        reducedMotion = true;
      });
      await tester.pump();
      expect(painted(glyph), initialGlyph);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  // Three pills of 100, 100 and a Filters of 96 that drops to 31, 8 apart:
  // 312 at full length, 247 tight.
  Future<void> pumpRow(WidgetTester tester, double width, {double? last}) =>
      tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: DFitRow(
                children: [
                  const _Pill('sort', full: 100),
                  const _Pill('category', full: 100),
                  _Pill('filters', full: last ?? 96, tight: 31),
                ],
              ),
            ),
          ),
        ),
      );

  Rect pill(WidgetTester tester, String name) =>
      tester.getRect(find.byKey(ValueKey(name)));

  _desktopTest(
    'adaptive leading controls receive measured remaining row width',
    (tester) async {
      for (final (width, count) in [(560.0, 2), (520.0, 1)]) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: const DFitRow(
                  children: [
                    DFitRowItem(leading: true, child: _Views()),
                    _Pill('category', full: 140),
                    _Pill('tag', full: 90),
                    _Pill('filters', full: 90),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(find.text('$count views'), findsOneWidget);
        expect(tester.getSize(find.byType(DFitRow)).height, 30);
        expect(tester.takeException(), isNull);
      }
    },
  );

  _desktopTest('shortens a third run then places the long control last', (
    tester,
  ) async {
    for (final width in [300.0, 230.0]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: const DFitRow(
                children: [
                  DFitRowItem(leading: true, child: _Pill('views', full: 100)),
                  DFitRowItem(
                    last: true,
                    child: _Pill('category', full: 220, tight: 140),
                  ),
                  _Pill('tag', full: 80, tight: 50),
                  _Pill('filters', full: 100, tight: 50),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('category-tight'), findsOneWidget);
      expect(tester.getSize(find.byType(DFitRow)).height, 68);
      expect(pill(tester, 'category').top, 38);
      expect(pill(tester, 'tag').top, width == 300 ? 38 : 0);
      expect(pill(tester, 'filters').top, width == 300 ? 38 : 0);
      expect(tester.takeException(), isNull);
    }
  });

  _desktopTest('keeps its full length while one line holds it', (tester) async {
    await pumpRow(tester, 312);
    expect(pill(tester, 'filters'), const Rect.fromLTWH(216, 0, 96, 30));
    expect(find.text('filters'), findsOneWidget);
  });

  _desktopTest('says less before it takes a second line', (tester) async {
    await pumpRow(tester, 311);
    expect(find.text('filters-tight'), findsOneWidget);
    expect(pill(tester, 'filters'), const Rect.fromLTWH(216, 0, 31, 30));
    await pumpRow(tester, 247);
    expect(pill(tester, 'filters'), const Rect.fromLTWH(216, 0, 31, 30));
    expect(tester.takeException(), isNull);
  });

  _desktopTest('wraps at full length when saying less is not enough', (
    tester,
  ) async {
    await pumpRow(tester, 246);
    expect(find.text('filters'), findsOneWidget);
    expect(pill(tester, 'category').top, 0);
    expect(pill(tester, 'filters'), const Rect.fromLTWH(0, 38, 96, 30));
    expect(tester.getSize(find.byType(DFitRow)), const Size(246, 68));
    expect(tester.takeException(), isNull);
  });

  _desktopTest('steps back once the row is as wide as each step needed', (
    tester,
  ) async {
    await pumpRow(tester, 210);
    expect(find.text('filters'), findsOneWidget);
    expect(pill(tester, 'filters').top, 38);

    final row = tester.renderObject<RenderBox>(find.byType(DFitRow));
    final room = tester.renderObject<RenderConstrainedBox>(
      find.ancestor(of: find.byType(DFitRow), matching: find.byType(SizedBox)),
    );
    void resize(double width) =>
        room.additionalConstraints = BoxConstraints.tightFor(width: width);

    // Resized without a rebuild, the row keeps what each step needed.
    resize(246);
    await tester.pump();
    expect(pill(tester, 'filters').top, 38);
    resize(247);
    await tester.pump();
    expect(find.text('filters-tight'), findsOneWidget);
    expect(pill(tester, 'filters').top, 0);
    resize(311);
    await tester.pump();
    expect(find.text('filters-tight'), findsOneWidget);
    resize(312);
    await tester.pump();
    expect(find.text('filters'), findsOneWidget);
    expect(row.size, const Size(312, 30));
    expect(tester.takeException(), isNull);
  });

  _desktopTest('measures rebuilt children afresh', (tester) async {
    await pumpRow(tester, 290);
    expect(find.text('filters-tight'), findsOneWidget);
    await pumpRow(tester, 290, last: 70);
    expect(find.text('filters'), findsOneWidget);
    expect(pill(tester, 'filters'), const Rect.fromLTWH(216, 0, 70, 30));
  });

  _desktopTest('a child is measured at its own width, not what hangs past it', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 208,
            child: DFitRow(
              children: [
                _Pill('sort', full: 100),
                SizedBox(
                  width: 100,
                  height: 30,
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    maxWidth: 320,
                    child: SizedBox(width: 320, height: 30),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(DFitRow)), const Size(208, 30));
  });
  _desktopTest('compact rows ease their pills without remounting controls', (
    tester,
  ) async {
    late StateSetter rebuild;
    var compact = false;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 340,
                  child: DFitRow(
                    compact: compact,
                    children: const [
                      _Pill('sort', full: 100, tight: 40),
                      _Pill('category', full: 100, tight: 40),
                      _Pill('filters', full: 100, tight: 40),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    final sort = find.byKey(const ValueKey('sort'));
    final element = tester.element(sort);
    Rect painted() {
      final box = tester.renderObject<RenderBox>(sort);
      return Rect.fromPoints(
        box.localToGlobal(Offset.zero),
        box.localToGlobal(box.size.bottomRight(Offset.zero)),
      );
    }

    final before = painted();
    rebuild(() => compact = true);
    await tester.pump();
    final initial = painted();
    expect(initial.width, closeTo(before.width, .01));
    await tester.pump(const Duration(milliseconds: 130));
    expect(tester.element(sort), same(element));
    expect(painted().width, inExclusiveRange(40, before.width));
    await tester.pumpAndSettle();
    expect(painted().width, 40);
    expect(tester.element(sort), same(element));
    expect(tester.takeException(), isNull);
  });

  _desktopTest(
    'a compact row eases its height when its second line goes away',
    (tester) async {
      late StateSetter rebuild;
      var compact = false;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 220,
                    child: DFitRow(
                      compact: compact,
                      children: const [
                        _Pill('one', full: 100, tight: 40, compactOnly: true),
                        _Pill('two', full: 100, tight: 40, compactOnly: true),
                        _Pill('three', full: 100, tight: 40, compactOnly: true),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      final row = find.byType(DFitRow);
      expect(tester.getSize(row).height, 68);
      rebuild(() => compact = true);
      await tester.pump();
      expect(tester.getSize(row).height, 68);
      await tester.pump(const Duration(milliseconds: 130));
      expect(tester.getSize(row).height, inExclusiveRange(30, 68));
      await tester.pumpAndSettle();
      expect(tester.getSize(row).height, 30);
      expect(tester.takeException(), isNull);
    },
  );
}
