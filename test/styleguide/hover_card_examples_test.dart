import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/hover_card_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Hover Card registers the frozen documentation examples', () {
    expect(componentExamples['hover-card'], same(hoverCardExamples));
    expect(hoverCardExamples.status, ComponentStatus.planned);
    expect(hoverCardExamples.examples.map((example) => example.title), [
      'Basic',
      'Composition',
      'Trigger delays',
      'Positioning',
      'Sides',
      'RTL',
      'Controlled and controller',
    ]);
  });

  testWidgets('examples mount at narrow 200 percent RTL in live palettes', (
    tester,
  ) async {
    for (final example in hoverCardExamples.examples) {
      for (final theme in [
        AppTheme.light,
        AppTheme.dark,
        StyleguideTheme.forest.resolve(AppTheme.light),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: SingleChildScrollView(
                    child: SizedBox(
                      width: 216,
                      child: Builder(builder: example.builder),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: example.title);
      }
    }
  });

  testWidgets('Basic uses the real Button and opens the exact preview', (
    tester,
  ) async {
    final basic = hoverCardExamples.examples.first;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(child: Builder(builder: basic.builder)),
        ),
      ),
    );
    expect(find.byType(DButton), findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Hover Here')));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('@nextjs'), findsOneWidget);
    expect(
      find.text('The React Framework – created and maintained by @vercel.'),
      findsOneWidget,
    );
    expect(tester.getSize(find.byType(DHoverCardContent)).width, 256);
  });

  testWidgets('controller example opens only its controller-owned preview', (
    tester,
  ) async {
    final example = hoverCardExamples.examples.last;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(child: Builder(builder: example.builder)),
        ),
      ),
    );
    await tester.tap(find.text('Open preview'));
    await tester.pumpAndSettle();
    expect(find.text('Controller preview'), findsOneWidget);
    expect(find.text('Controlled preview'), findsNothing);
  });
}
