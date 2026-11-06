import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpSheet(
  WidgetTester tester, {
  required int sheer,
  bool writing = false,
}) async {
  final base = ThemeData(platform: TargetPlatform.iOS);
  await tester.pumpWidget(
    MaterialApp(
      theme: base.copyWith(extensions: [if (sheer > 0) DFrost(sheer: sheer)]),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: DSheetContent(
            side: DSheetSide.bottom,
            variant: DSheetVariant.menu,
            showCloseButton: false,
            fillAvailableHeight: writing,
            extendBehindKeyboard: writing,
            children: const [SizedBox(key: ValueKey('body'), height: 120)],
          ),
        ),
      ),
    ),
  );
}

Finder get _frost => find.descendant(
  of: find.byType(DSheetContent),
  matching: find.byType(BackdropFilter),
);

Color _fill(WidgetTester tester) => tester
    .widget<Material>(
      find
          .descendant(
            of: find.byType(DSheetContent),
            matching: find.byType(Material),
          )
          .first,
    )
    .color!;

void main() {
  group('a phone menu sheet', () {
    testWidgets('is solid and unfrosted while the palette is opaque', (
      tester,
    ) async {
      await _pumpSheet(tester, sheer: 0);
      expect(_frost, findsNothing);
      expect(_fill(tester).a, 1);
    });

    testWidgets('frosts what is behind it once the palette is see-through', (
      tester,
    ) async {
      await _pumpSheet(tester, sheer: 30);
      expect(_frost, findsOneWidget);
      expect(tester.getRect(_frost).width, 800);
      expect(_fill(tester).a, closeTo(.9, .005));
    });

    testWidgets(
      'to write on stays solid even when the palette is see-through',
      (tester) async {
        await _pumpSheet(tester, sheer: 30, writing: true);
        expect(_frost, findsNothing);
        expect(_fill(tester).a, 1);
      },
    );
  });

  group('the forum background', () {
    ForumBackground at(double transparency) =>
        ForumBackground.appearance(strength: .1, transparency: transparency);

    test('is sheer in proportion to its transparency, and only above zero', () {
      expect(at(0).sheer, 0);
      expect(at(ForumBackground.maxTransparency).sheer, 30);
      expect(at(ForumBackground.defaultTransparency).sheer, 10);
    });

    test('puts its sheerness on the theme for the kit', () {
      final sheer = AppTheme.forBrightness(
        Brightness.dark,
        background: at(.1),
      ).extension<DFrost>();
      expect(sheer?.sheer, 10);
      final opaque = AppTheme.forBrightness(
        Brightness.dark,
        background: at(0),
      ).extension<DFrost>();
      expect((opaque ?? DFrost.none).isSheer, isFalse);
    });
  });
}
