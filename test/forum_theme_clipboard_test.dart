import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/forum_theme_share.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/theme_settings.dart';

const _site = 'https://a.example';

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

  testWidgets('editor copies both live palettes and disables an unnamed copy', (
    tester,
  ) async {
    final shell = controller();
    addTearDown(shell.dispose);
    await shell.forumSettings.setThemes(
      _site,
      ForumThemePreferences().save(custom),
    );
    await pumpSettings(tester, shell);
    final accent = find.descendant(
      of: find.byKey(const ValueKey('theme-color-accent')),
      matching: find.byType(EditableText),
    );
    await tester.ensureVisible(accent);
    await tester.enterText(accent, '#112233');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save and share'));
    await tester.tap(find.text('Save and share'));
    await tester.pumpAndSettle();
    final name = find.descendant(
      of: find.byKey(const ValueKey('theme-name')),
      matching: find.byType(EditableText),
    );
    await tester.ensureVisible(name);
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
      expect(
        decoded.resolve(mode),
        shell.forumSettings.themesFor(_site).themeFor(mode)!.resolve(mode),
      );
    }
    await tester.ensureVisible(name);
    await tester.enterText(name, '');
    await tester.pumpAndSettle();
    expect(tester.widget<DButton>(copy).onPressed, isNull);
  });

  testWidgets('saved themes can be copied without applying them', (
    tester,
  ) async {
    final shell = controller();
    addTearDown(shell.dispose);
    final before = ForumThemePreferences(customThemes: [custom]);
    await shell.forumSettings.setThemes(_site, before);
    await pumpSettings(tester, shell, width: 360, scale: 2);
    await tester.ensureVisible(find.text('Save and share'));
    await tester.tap(find.text('Save and share'));
    await tester.pumpAndSettle();
    final copy = find.byKey(ValueKey(('copy-saved-theme', custom.id)));
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    final decoded = ForumThemeShare.decode(copied!.split('\n')[1])!;
    expect(ForumThemeShare.matches(decoded, custom), isTrue);
    expect(shell.forumSettings.themesFor(_site), before);
    expect(tester.takeException(), isNull);
  });
}
