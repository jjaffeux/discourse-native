import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/shell/forum_settings_dialog.dart';
import 'package:discourse_native/src/shell/forum_theme_preview.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final brightness in Brightness.values) {
    testWidgets('narrow $brightness forum settings supports large RTL text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();

      final controller = ShellController(
        instanceStore: FakeInstanceStore(),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(controller.dispose);
      try {
        await tester.pumpWidget(
          ShellScope(
            controller: controller,
            child: MaterialApp(
              theme: brightness == Brightness.dark
                  ? AppTheme.dark
                  : AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: child!,
                ),
              ),
              home: Builder(
                builder: (context) => Center(
                  child: DButton(
                    label: const Text('Open'),
                    onPressed: () => showForumSettingsDialog(
                      context,
                      siteUrl: 'https://a.example',
                      name: 'A forum with a long name',
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Close settings'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const ValueKey('appearance-theme-select')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .descendant(
                of: find.byKey(const ValueKey('appearance-theme-select')),
                matching: find.text('Dark'),
              )
              .last,
        );
        await tester.pumpAndSettle();
        expect(
          controller.forumSettings.themeModeFor('https://a.example'),
          AppThemeMode.dark,
        );
        expect(tester.takeException(), isNull);
        final fontPicker = find.byKey(const ValueKey('appearance-font-select'));
        await tester.ensureVisible(fontPicker);
        await tester.pumpAndSettle();
        await tester.tap(fontPicker);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Lato').last);
        await tester.pumpAndSettle();
        expect(
          controller.forumSettings.themesFor('https://a.example').font,
          ForumFont.lato,
        );
        final preview = tester.widget<ForumThemePreview>(
          find.byType(ForumThemePreview),
        );
        expect(preview.theme.textTheme.bodyMedium?.fontFamily, 'Lato');
        expect(tester.takeException(), isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(ForumSettingsDialog), findsNothing);
      } finally {
        semantics.dispose();
      }
    });
  }
}
