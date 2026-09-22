import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final (size, height, font, icon) in [
      (DControlSize.small, 40.0, 12.5, 12.0),
      (DControlSize.regular, 44.0, 13.0, 14.0),
      (DControlSize.large, 48.0, 14.0, 16.0),
    ]) {
      testWidgets(
        '$platform ${size.name} keeps shared type with touch geometry and accepts edge taps',
        (tester) async {
          var presses = 0;
          var toggles = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light.copyWith(platform: platform),
              home: Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DButton.iconOnly(
                        size: size,
                        icon: const Icon(Icons.add),
                        tooltip: 'Add',
                        onPressed: () => presses++,
                      ),
                      DToggle(
                        size: size,
                        onPressedChanged: (_) => toggles++,
                        child: const Text('Toggle'),
                      ),
                      DSelect<String>(
                        size: size,
                        width: 180,
                        value: 'a',
                        entries: const [
                          DSelectOption(
                            value: 'a',
                            label: 'Alpha',
                            child: Text('Alpha'),
                          ),
                        ],
                        onChanged: (_) {},
                      ),
                      SizedBox(width: 180, child: DInput(size: size)),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final button = find.byType(FilledButton);
          final material = find.descendant(
            of: button,
            matching: find.byType(Material),
          );
          expect(tester.getSize(material), Size.square(height));
          expect(tester.getSize(find.byIcon(Icons.add)), Size.square(icon));
          expect(
            tester
                .widget<FilledButton>(button)
                .style!
                .textStyle!
                .resolve({})!
                .fontSize,
            font,
          );
          final rect = tester.getRect(button);
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.height, greaterThanOrEqualTo(48));
          await tester.tapAt(rect.topLeft + const Offset(1, 1));
          expect(presses, 1);
          final toggle = tester.getRect(find.byType(DToggle));
          expect(toggle.height, greaterThanOrEqualTo(48));
          await tester.tapAt(toggle.centerLeft + const Offset(1, 0));
          await tester.pump();
          expect(toggles, 1);
          expect(
            tester
                .getSize(find.byKey(const Key('d-select-trigger-visual')))
                .height,
            height,
          );
          expect(tester.getSize(find.byType(DInput)).height, 48);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('mobile action row fits 320px and grows for accessible text', (
    tester,
  ) async {
    for (final scale in [1.0, 2.0, 3.0]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: Wrap(
                  spacing: DSpacing.controlGap,
                  runSpacing: DSpacing.controlGap,
                  children: [
                    DButton(
                      label: const Text('Reply'),
                      icon: const Icon(Icons.reply),
                      onPressed: () {},
                    ),
                    DButtonGroup(
                      children: [
                        DButton.iconOnly(
                          icon: const Icon(Icons.bookmark_outline),
                          tooltip: 'Bookmark',
                          onPressed: () {},
                        ),
                        DButton.iconOnly(
                          icon: const Icon(Icons.more_horiz),
                          tooltip: 'More',
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final button in find.byType(FilledButton).evaluate()) {
        final rect = tester.getRect(find.byWidget(button.widget));
        expect(rect.height, greaterThanOrEqualTo(48));
      }
      await tester.tap(find.byTooltip('Bookmark'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}
