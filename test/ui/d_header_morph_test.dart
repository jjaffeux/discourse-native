import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Reference: discourse-native-mockups 13db54c, `useMorph` in App.tsx.

final _title = find.byKey(const ValueKey('title'));
final _tools = find.byKey(const ValueKey('tools'));

Widget _header(
  bool compact, {
  TextDirection direction = TextDirection.ltr,
  bool reduced = false,
  VoidCallback? onTools,
}) => Directionality(
  textDirection: direction,
  child: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 400,
        height: 300,
        child: DHeaderMorph(
          compact: compact,
          builder: (context, compact, part) => Stack(
            children: [
              PositionedDirectional(
                top: compact ? 8 : 40,
                start: compact ? 16 : 32,
                child: part(
                  'title',
                  SizedBox(
                    key: const ValueKey('title'),
                    width: compact ? 140 : 220,
                    height: compact ? 14 : 22,
                  ),
                  fontSize: compact ? 14 : 22,
                ),
              ),
              PositionedDirectional(
                top: compact ? 8 : 120,
                start: compact ? 200 : 16,
                child: part(
                  'tools',
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onTools,
                    child: SizedBox(
                      key: const ValueKey('tools'),
                      width: compact ? 60 : 90,
                      height: 30,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'a sized part starts over its old place, with no frame at its new one',
    (tester) async {
      await tester.pumpWidget(_header(false));
      expect(tester.getRect(_title), const Rect.fromLTWH(32, 40, 220, 22));

      await tester.pumpWidget(_header(true));
      expect(tester.getRect(_title), const Rect.fromLTWH(32, 40, 220, 22));

      await tester.pump(const Duration(milliseconds: 60));
      final moving = tester.getRect(_title);
      expect(moving.width, inExclusiveRange(140, 220));
      expect(moving.height / 14, closeTo(moving.width / 140, .001));

      await tester.pumpAndSettle();
      expect(tester.getRect(_title), const Rect.fromLTWH(16, 8, 140, 14));
    },
  );

  testWidgets('a sized part grows back from its compact place', (tester) async {
    await tester.pumpWidget(_header(true));
    await tester.pumpWidget(_header(false));
    expect(tester.getRect(_title), const Rect.fromLTWH(16, 8, 140, 14));

    await tester.pumpAndSettle();
    expect(tester.getRect(_title), const Rect.fromLTWH(32, 40, 220, 22));
  });

  testWidgets('a part without a font size only moves', (tester) async {
    await tester.pumpWidget(_header(false));
    await tester.pumpWidget(_header(true));
    expect(tester.getRect(_tools), const Rect.fromLTWH(16, 120, 60, 30));

    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getSize(_tools), const Size(60, 30));
    expect(tester.getTopLeft(_tools).dy, inExclusiveRange(8, 120));

    await tester.pumpAndSettle();
    expect(tester.getRect(_tools), const Rect.fromLTWH(200, 8, 60, 30));
  });

  testWidgets('a part scales from its start edge in a right-to-left layout', (
    tester,
  ) async {
    await tester.pumpWidget(_header(false, direction: TextDirection.rtl));
    final before = tester.getRect(_title);

    await tester.pumpWidget(_header(true, direction: TextDirection.rtl));
    expect(tester.getRect(_title).right, closeTo(before.right, .001));
    expect(tester.getRect(_title).width, closeTo(before.width, .001));
  });

  testWidgets('an interrupted change starts from where the part had got to', (
    tester,
  ) async {
    await tester.pumpWidget(_header(false));
    await tester.pumpWidget(_header(true));
    await tester.pump(const Duration(milliseconds: 60));
    final reached = tester.getTopLeft(_tools);

    await tester.pumpWidget(_header(false));
    expect(tester.getTopLeft(_tools).dx, closeTo(reached.dx, .001));
    expect(tester.getTopLeft(_tools).dy, closeTo(reached.dy, .001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('targets travel with the part they belong to', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_header(false, onTools: () => taps++));
    await tester.pumpWidget(_header(true, onTools: () => taps++));

    await tester.tapAt(const Offset(46, 135));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('reduced motion changes layout at once', (tester) async {
    await tester.pumpWidget(_header(false, reduced: true));
    await tester.pumpWidget(_header(true, reduced: true));
    expect(tester.getRect(_title), const Rect.fromLTWH(16, 8, 140, 14));
    expect(tester.getRect(_tools), const Rect.fromLTWH(200, 8, 60, 30));
  });
}
