import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/shell/forum_theme_preview.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/topic_create_button.dart';
import 'package:discourse_native/src/shell/topic_list_bottom_bar.dart';
import 'package:discourse_native/src/shell/topic_list_navigation.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets('preview retains $platform layout across settings widths', (
      tester,
    ) async {
      for (final width in [320.0, 480.0]) {
        for (final scale in [1.0, 2.0]) {
          for (final brightness in Brightness.values) {
            final theme = AppTheme.fromPalette(
              forumThemePresets
                  .firstWhere((theme) => theme.id == 'dracula')
                  .resolve(brightness),
            ).copyWith(platform: platform);
            await tester.pumpWidget(
              MaterialApp(
                home: SingleChildScrollView(
                  child: Center(
                    child: SizedBox(
                      width: width,
                      child: MediaQuery(
                        data: MediaQueryData(
                          textScaler: TextScaler.linear(scale),
                        ),
                        child: ForumThemePreview(
                          theme: theme,
                          siteUrl: 'https://preview.invalid',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final desktop = platform == TargetPlatform.macOS;
            final row = find.byType(TopicListRow).first;
            expect(
              tester.getSize(row).width,
              desktop ? greaterThan(600) : lessThan(600),
            );
            expect(
              find.byType(ForumIdentityHeader),
              desktop ? findsOneWidget : findsNothing,
            );
            expect(find.byType(TopicFeedMenu), findsOneWidget);
            expect(find.byType(TopicListFooter), findsOneWidget);
            expect(find.byType(TopicCreateAction), findsOneWidget);
            expect(
              Theme.of(tester.element(row)).colorScheme,
              theme.colorScheme,
            );
            expect(
              MediaQuery.textScalerOf(tester.element(row)).scale(14),
              14 * scale,
            );
          }
        }
      }
    });
  }

  testWidgets('sample controls cannot navigate or receive focus', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    try {
      final outsideFocus = FocusNode();
      addTearDown(outsideFocus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: SingleChildScrollView(
            child: Column(
              children: [
                DButton(
                  focusNode: outsideFocus,
                  label: const Text('Outside'),
                  onPressed: () {},
                ),
                SizedBox(
                  width: 480,
                  child: ForumThemePreview(
                    theme: AppTheme.light.copyWith(
                      platform: TargetPlatform.macOS,
                    ),
                    siteUrl: 'https://preview.invalid',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Forum appearance preview'), findsOneWidget);
      expect(find.bySemanticsLabel('New topic'), findsNothing);
      for (final control in [
        find.byType(ForumIdentityHeader),
        find.byType(TopicFeedMenu),
        find.byType(TopicCreateAction),
      ]) {
        await tester.tap(control, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byType(DDropdownMenuContent), findsNothing);
      }
      outsideFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(outsideFocus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
