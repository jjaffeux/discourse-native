import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/separator_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('boundary controls update actual geometry and semantics live', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final theme = ValueNotifier(AppTheme.light);

    addTearDown(theme.dispose);
    try {
      await _pump(tester, separatorExamples.examples[0], theme: theme);
      final separator = find.byKey(const ValueKey('separator-configurable'));
      expect(tester.widget<DSeparator>(separator).decorative, isTrue);
      await tester.tap(find.text('Meaningful boundary'));
      await tester.tap(find.text('Asymmetric insets'));
      await tester.tap(find.text('Emphasize boundary'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('End of introduction'), findsOneWidget);
      final configured = tester.widget<DSeparator>(separator);
      expect(configured.indent, DSpacing.xl);
      expect(configured.endIndent, DSpacing.sm);
      expect(configured.thickness, 3);
      theme.value = AppTheme.dark;
      await tester.pumpAndSettle();
      expect(tester.widget<DSeparator>(separator).decorative, isFalse);
      expect(tester.widget<DSeparator>(separator).thickness, 3);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('vertical navigation retains native Tab and Enter actions', (
    tester,
  ) async {
    await _pump(tester, separatorExamples.examples[1]);
    await tester.tap(find.widgetWithText(DButton, 'Blog'));
    await tester.pump();
    expect(find.text('Destination: Blog'), findsOneWidget);
    Focus.of(tester.element(find.text('Blog'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('Destination: Docs'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('Destination: Source'), findsOneWidget);
  });

  testWidgets(
    'responsive menu preserves every destination and local selection',
    (tester) async {
      for (final width in [320.0, 760.0]) {
        await _pump(
          tester,
          separatorExamples.examples[2],
          width: width,
          textScale: 2,
        );
        expect(
          tester
              .widgetList<DSeparator>(find.byType(DSeparator))
              .map((line) => line.orientation),
          everyElement(width < 520 ? Axis.horizontal : Axis.vertical),
        );
        for (final title in ['Settings', 'Account', 'Help']) {
          await tester.tap(find.widgetWithText(DButton, title));
          await tester.pump();
          expect(find.text('Selected: $title'), findsOneWidget);
        }
        for (final description in [
          'Manage preferences',
          'Profile and security',
          'Support and docs',
        ]) {
          expect(
            tester
                .renderObject<RenderParagraph>(find.text(description))
                .didExceedMaxLines,
            isFalse,
            reason: '$description at $width and 200% text must remain readable',
          );
        }
      }
    },
  );

  testWidgets('local list scrolls, selects, clears and adds a first item', (
    tester,
  ) async {
    await _pump(tester, separatorExamples.examples[3]);
    final list = find.byKey(const ValueKey('separator-example-list'));
    final scroll = find.descendant(of: list, matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(
      find.text('Item 12'),
      200,
      scrollable: scroll,
    );
    await tester.tap(find.text('Item 12'));
    await tester.pump();
    expect(find.text('Selected: Item 12'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    final clear = find.widgetWithText(DButton, 'Clear list');
    await tester.tap(clear);
    await tester.pump();
    expect(find.text('No items. Add one to start again.'), findsOneWidget);
    expect(find.byType(DSeparator), findsNothing);
    expect(tester.widget<DButton>(clear).onPressed, isNull);
    await tester.tap(find.widgetWithText(DButton, 'Add item'));
    await tester.pump();
    expect(find.text('Item 1'), findsOneWidget);
    expect(find.text('1 item'), findsOneWidget);
    expect(find.byType(DSeparator), findsNothing);
    expect(tester.widget<DButton>(clear).onPressed, isNotNull);
    await tester.tap(find.widgetWithText(DButton, 'Add item'));
    await tester.pump();
    expect(find.byType(DSeparator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final example in separatorExamples.examples) {
    testWidgets('${example.title} fits scaled RTL layouts in every palette', (
      tester,
    ) async {
      for (final palette in [
        StyleguideTheme.light,
        StyleguideTheme.dark,
        StyleguideTheme.forest,
        StyleguideTheme.plum,
      ]) {
        final theme = ValueNotifier(palette.resolve(AppTheme.light));
        addTearDown(theme.dispose);
        for (final width in [320.0, 760.0]) {
          await _pump(
            tester,
            example,
            theme: theme,
            width: width,
            textScale: 2,
            direction: TextDirection.rtl,
          );
          expect(find.byType(DSeparator), findsWidgets);
          expect(
            tester.takeException(),
            isNull,
            reason: '${palette.name} / $width',
          );
        }
      }
    });
  }

  testWidgets('catalogue search opens the real Separator examples', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const ComponentStyleguidePage()),
    );
    await tester.enterText(
      find.byKey(const ValueKey('styleguide-search')),
      'separator',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('styleguide-component-separator')),
    );
    await tester.pump();
    expect(find.text('Horizontal and meaningful boundaries'), findsWidgets);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('styleguide-preview')),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('styleguide-detail-separator')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.byKey(const ValueKey('separator-configurable')),
      findsOneWidget,
    );
    await tester.tap(find.text('Meaningful boundary'));
    await tester.pump();
    expect(
      tester
          .widget<DSeparator>(
            find.byKey(const ValueKey('separator-configurable')),
          )
          .decorative,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  StyleguideExample example, {
  ValueNotifier<ThemeData>? theme,
  double width = 760,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final previewTheme = theme ?? ValueNotifier(AppTheme.light);
  if (theme == null) addTearDown(previewTheme.dispose);
  await tester.pumpWidget(
    ValueListenableBuilder(
      valueListenable: previewTheme,
      builder: (context, value, _) => MaterialApp(
        theme: value,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 900),
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
            ),
            child: DDirection(
              textDirection: direction,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: SingleChildScrollView(
                    child: Builder(builder: example.builder),
                  ),
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
