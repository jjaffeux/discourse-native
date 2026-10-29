import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// A pill [full] wide that drops to [tight] while its row asks it to.
class _Pill extends StatelessWidget {
  const _Pill(this.name, {required this.full, this.tight});

  final String name;
  final double full;
  final double? tight;

  @override
  Widget build(BuildContext context) {
    final short = tight != null && DFitRow.tightOf(context);
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
}
