import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/topic_taxonomy_button.dart';
import 'package:discourse_native/src/styleguide/examples/control_comparison_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/button_surface.dart';

void main() {
  testWidgets(
    'button, field and production filter share dark outline geometry',
    (tester) async {
      for (final palette in [StyleguideTheme.dark, StyleguideTheme.plum]) {
        final theme = palette
            .resolve(AppTheme.dark)
            .copyWith(platform: TargetPlatform.macOS);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Column(
                children: [
                  DButton(
                    label: const Text('Action'),
                    variant: DButtonVariant.outline,
                    onPressed: () {},
                  ),
                  DSelect<String>(
                    width: 128,
                    value: 'Recent',
                    entries: const [
                      DSelectItem(
                        value: 'Recent',
                        textValue: 'Recent',
                        child: Text('Recent'),
                      ),
                    ],
                    onChanged: (_) {},
                  ),
                  TopicTaxonomyButton(
                    label: 'Tags',
                    semanticLabel: 'Tags',
                    onPressed: () {},
                    maximumWidth: 200,
                  ),
                ],
              ),
            ),
          ),
        );
        final action = buttonSurface(
          tester,
          of: find.widgetWithText(DButton, 'Action'),
        );
        final filter = buttonSurface(
          tester,
          of: find.byType(TopicTaxonomyButton),
        );
        final select =
            tester
                    .widget<AnimatedContainer>(
                      find.byKey(const Key('d-select-trigger-visual')),
                    )
                    .decoration!
                as DButtonDecoration;
        for (final surface in [filter, select]) {
          expect(surface.borderRadius, action.borderRadius);
          expect(surface.borderColor, action.borderColor);
          expect(surface.color, action.color);
        }
        expect(
          tester
              .getSize(find.byKey(const Key('d-select-trigger-visual')))
              .height,
          tester.getSize(find.widgetWithText(FilledButton, 'Action')).height,
        );
      }
    },
  );

  testWidgets(
    'standard menu trigger owns one button and restores borrowed focus',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var activated = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: DDropdownMenu(
              content: DDropdownMenuContent(
                children: [
                  DDropdownMenuItem(
                    child: const Text('Run'),
                    onPressed: () => activated = true,
                  ),
                ],
              ),
              child: DDropdownMenuTrigger.button(
                label: const Text('Open'),
                focusNode: focus,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(DButton), findsOneWidget);
      expect(
        tester.widget<DButton>(find.byType(DButton)).variant,
        DButtonVariant.outline,
      );
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Run'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(activated, isTrue);
      expect(focus.hasFocus, isTrue);
      expect(find.text('Run'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('comparison retains selections and notification behavior', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: ControlComparisonExample()),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Feed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trending').last);
    await tester.pumpAndSettle();
    expect(find.text('Trending'), findsNWidgets(2));
    await tester.tap(find.bySemanticsLabel('Category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Support'));
    await tester.pumpAndSettle();
    expect(find.text('Support'), findsNWidgets(2));
    await tester.tap(find.text('Normal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Watching'));
    await tester.pumpAndSettle();
    expect(find.text('Watching'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled standard trigger cannot open', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DDropdownMenu(
            content: const DDropdownMenuContent(
              children: [DDropdownMenuItem(child: Text('Hidden'))],
            ),
            child: DDropdownMenuTrigger.button(
              label: const Text('Disabled'),
              enabled: false,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Disabled'));
    await tester.pumpAndSettle();
    expect(find.text('Hidden'), findsNothing);
  });
}
