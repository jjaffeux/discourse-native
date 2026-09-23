import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/forum_theme_share.dart';
import 'package:discourse_native/src/shell/forum_appearance_settings.dart';
import 'package:discourse_native/src/shell/forum_theme_editor.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  final custom = ForumTheme.fromJson({
    ...forumThemePresets.first.toJson(),
    'name': 'Moss',
  }, id: 'custom-moss');
  String? copied;
  setUp(() {
    copied = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  testWidgets(
    'editor copies both variants, including unsaved changes, and disables invalid copies',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: SingleChildScrollView(
            child: DCard(
              child: ForumThemeEditor(
                initialTheme: custom,
                customThemes: [custom],
                onChanged: (_) {},
                onSave: (_) async {},
              ),
            ),
          ),
        ),
      );
      final name = find.descendant(
        of: find.byKey(const ValueKey('custom-theme-name')),
        matching: find.byType(EditableText),
      );
      await tester.enterText(name, 'My new Moss');
      await tester.pumpAndSettle();
      final copy = find.byKey(const ValueKey('copy-custom-theme'));
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(copied, startsWith('```discourse-theme\n'));
      final decoded = ForumThemeShare.decode(copied!.split('\n')[1])!;
      expect(decoded.name, 'My new Moss');
      expect(decoded.alternate, isNotNull);
      for (final mode in Brightness.values) {
        expect(decoded.resolve(mode), custom.resolve(mode));
      }
      await tester.ensureVisible(name);
      await tester.enterText(name, '');
      await tester.pumpAndSettle();
      expect(tester.widget<DButton>(copy).onPressed, isNull);
    },
  );

  testWidgets('saved custom themes can be copied directly from the library', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(controller.dispose);
    const site = 'https://example.com';
    final before = ForumThemePreferences(
      customThemes: [custom],
      selectedId: custom.id,
    );
    await controller.forumSettings.setThemes(site, before);
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: const DCard(
            child: Expanded(child: ForumAppearanceSettings(siteUrl: site)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final copy = find.byKey(const ValueKey('copy-saved-theme'));
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    final decoded = ForumThemeShare.decode(copied!.split('\n')[1])!;
    expect(ForumThemeShare.matches(decoded, custom), isTrue);
    expect(controller.forumSettings.themesFor(site), before);
    expect(tester.takeException(), isNull);
  });
}
