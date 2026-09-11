import 'package:discourse_native/src/styleguide/examples/control_comparison_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    // Repository fonts make this regression independent of installed OS fonts.
    await (FontLoader('ControlGolden')
          ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final palette in [
    StyleguideTheme.light,
    StyleguideTheme.dark,
    StyleguideTheme.forest,
    StyleguideTheme.plum,
  ]) {
    testWidgets('control family ${palette.name} rest, hover and open', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(720, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final base = palette.resolve(AppTheme.light);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('controls'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: base.copyWith(
              platform: TargetPlatform.macOS,
              textTheme: base.textTheme.apply(fontFamily: 'ControlGolden'),
            ),
            home: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(24),
                child: ControlComparisonExample(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const ValueKey('controls')),
        matchesGoldenFile('goldens/controls-${palette.name}-rest.png'),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: tester.getCenter(find.text('Button').first),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const ValueKey('controls')),
        matchesGoldenFile('goldens/controls-${palette.name}-hover.png'),
      );
      await mouse.moveTo(tester.getCenter(find.bySemanticsLabel('Category')));
      await mouse.down(tester.getCenter(find.bySemanticsLabel('Category')));
      await mouse.up();
      await mouse.removePointer();
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const ValueKey('controls')),
        matchesGoldenFile('goldens/controls-${palette.name}-open.png'),
      );
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }
}
