import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/shell/forum_settings_page.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/theme_settings.dart';

const _site = 'https://a.example';
Finder input(String role) => find.descendant(
  of: find.byKey(ValueKey('theme-color-$role')),
  matching: find.byType(EditableText),
);

Future<void> preset(WidgetTester tester, String name) async {
  final picker = find.byKey(const ValueKey('theme-preset'));
  await tester.ensureVisible(picker);
  await tester.tap(picker);
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

Future<void> mode(WidgetTester tester, String name) async {
  final tabs = find.byKey(const ValueKey('appearance-theme-select'));
  await tester.ensureVisible(tabs);
  await tester.tap(find.descendant(of: tabs, matching: find.text(name)));
  await tester.pumpAndSettle();
}

Future<void> openLibrary(WidgetTester tester) async {
  final toggle = find.text('Save and share');
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Gradient updates live and survives saving and mode changes', (
    tester,
  ) async {
    final shell = controller();
    addTearDown(shell.dispose);
    await pumpSettings(tester, shell);
    await tester.ensureVisible(find.text('Gradient'));
    await tester.tap(find.text('Gradient'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final background = shell.forumSettings.themesFor(_site).background!;
    expect(background.effect, ForumBackgroundEffect.gradient);
    expect(background.strength, 0);
    expect(background.noiseIntensity, .14);
    expect(
      find.byKey(const ValueKey('forum-gradient-texture')),
      findsOneWidget,
    );
    expect(
      (await shell.forumSettings.store.loadThemes(_site)).background,
      background,
    );

    // Disable motion through the real Intensity field before settling a mode
    // switch. Selecting Gradient must not require changing the Tint field.
    final intensity = find.byKey(const ValueKey('theme-intensity'));
    await tester.tapAt(tester.getTopLeft(intensity) + const Offset(1, 13));
    await tester.pumpAndSettle();
    expect(shell.forumSettings.themesFor(_site).background!.noiseIntensity, 0);
    await mode(tester, 'Dark');
    expect(
      shell.forumSettings.themesFor(_site).background!.effect,
      ForumBackgroundEffect.gradient,
    );
    await openLibrary(tester);
    final save = find.widgetWithText(DButton, 'Save theme');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final saved = shell.forumSettings.themesFor(_site).customThemes.single;
    for (final brightness in Brightness.values) {
      expect(
        saved.forBrightness(brightness).background!.effect,
        ForumBackgroundEffect.gradient,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('live appearance changes retain unsaved form state', (
    tester,
  ) async {
    final shell = controller();
    addTearDown(shell.dispose);
    await pumpSettings(tester, shell);
    await openLibrary(tester);
    final name = find.descendant(
      of: find.byKey(const ValueKey('theme-name')),
      matching: find.byType(EditableText),
    );
    await tester.ensureVisible(name);
    await tester.enterText(name, 'Work in progress');
    await preset(tester, 'Solarized');
    await tester.ensureVisible(find.text('Noise'));
    await tester.tap(find.text('Noise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(name).controller.text,
      'Work in progress',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'preset and colour edits update the page immediately and retain both modes',
    (tester) async {
      final shell = controller();
      addTearDown(shell.dispose);
      await pumpSettings(tester, shell);
      expect(find.byType(DDialogContent), findsNothing);
      expect(find.byType(DSheetContent), findsNothing);
      expect(find.byType(DColorPicker), findsNWidgets(12));
      await preset(tester, 'Solarized');
      expect(
        Theme.of(
          tester.element(find.byType(ForumSettingsPage)),
        ).colorScheme.primary,
        const Color(0xff0088cc),
      );
      await tester.ensureVisible(input('accent'));
      await tester.enterText(input('accent'), '#39845B');
      await tester.pump();
      expect(
        shell.forumSettings
            .themesFor(_site)
            .themeFor(Brightness.light)!
            .tertiary,
        const Color(0xff39845b),
      );
      await tester.pumpAndSettle();
      await tester.enterText(input('accent'), '#ZZ');
      await tester.pumpAndSettle();
      expect(find.text('Use #RRGGBB.'), findsOneWidget);
      expect(
        shell.forumSettings
            .themesFor(_site)
            .themeFor(Brightness.light)!
            .tertiary,
        const Color(0xff39845b),
      );
      await mode(tester, 'Dark');
      await preset(tester, 'Dracula');
      await mode(tester, 'Light');
      expect(
        tester.widget<EditableText>(input('accent')).controller.text,
        '#39845B',
      );
      expect(
        shell.forumSettings
            .themesFor(_site)
            .themeFor(Brightness.dark)!
            .tertiary,
        const Color(0xffbd93f9),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tint opacity and texture intensity are independent and persist across presets',
    (tester) async {
      final shell = controller();
      addTearDown(shell.dispose);
      await pumpSettings(tester, shell);
      await preset(tester, 'Solarized');
      DSlider slider(String name) =>
          tester.widget(find.byKey(ValueKey('theme-$name')));
      expect(slider('intensity').onChanged, isNull);
      final tint = find.byKey(const ValueKey('theme-tint'));
      await tester.tapAt(tester.getTopRight(tint) + const Offset(-2, 13));
      await tester.pumpAndSettle();
      expect(shell.forumSettings.themesFor(_site).background!.strength, 1);
      expect(find.text('22%'), findsOneWidget);
      final opacity = find.byKey(const ValueKey('theme-opacity'));
      await tester.tapAt(tester.getTopLeft(opacity) + const Offset(1, 13));
      await tester.pumpAndSettle();
      expect(shell.forumSettings.themesFor(_site).background!.transparency, .3);
      expect(find.text('70%'), findsOneWidget);
      await tester.tap(find.text('Noise'));
      await tester.pumpAndSettle();
      expect(slider('intensity').onChanged, isNotNull);
      final before = shell.forumSettings.themesFor(_site).background!;
      await mode(tester, 'Dark');
      await preset(tester, 'Dracula');
      expect(shell.forumSettings.themesFor(_site).background, before);
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      expect(slider('intensity').onChanged, isNull);
      expect(
        shell.forumSettings.themesFor(_site).background!.noiseIntensity,
        before.noiseIntensity,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'colour grid and hex field stay synchronized with keyboard and pointer edits',
    (tester) async {
      final shell = controller();
      addTearDown(shell.dispose);
      await pumpSettings(tester, shell);
      final palette = find.byWidgetPredicate(
        (w) => w is DColorPicker && w.semanticLabel == 'Accent colour palette',
      );
      await tester.ensureVisible(palette);
      await tester.tap(palette);
      await tester.pumpAndSettle();
      final chosen = shell.forumSettings
          .themesFor(_site)
          .themeFor(Brightness.light)!
          .tertiary;
      expect(
        tester.widget<EditableText>(input('accent')).controller.text,
        ForumTheme.hex(chosen),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      final lighter = shell.forumSettings
          .themesFor(_site)
          .themeFor(Brightness.light)!
          .tertiary;
      expect(
        lighter.computeLuminance(),
        greaterThan(chosen.computeLuminance()),
      );
      expect(
        tester.widget<EditableText>(input('accent')).controller.text,
        ForumTheme.hex(lighter),
      );
      expect(tester.getSize(palette).height, 58);
    },
  );

  testWidgets('font and reset keep the saved library and per-forum isolation', (
    tester,
  ) async {
    final shell = controller();
    addTearDown(shell.dispose);
    await pumpSettings(tester, shell);
    await preset(tester, 'Solarized');
    final font = find.byKey(const ValueKey('appearance-font-lato'));
    await tester.ensureVisible(font);
    await tester.tap(font);
    await tester.pumpAndSettle();
    expect(shell.forumSettings.themesFor(_site).font, ForumFont.lato);
    await openLibrary(tester);
    final save = find.widgetWithText(DButton, 'Save theme');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(shell.forumSettings.themesFor(_site).customThemes, hasLength(1));
    final reset = find.text('Reset to forum theme');
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    final preferences = shell.forumSettings.themesFor(_site);
    expect(preferences.palettes, isEmpty);
    expect(preferences.background, isNull);
    expect(preferences.font, ForumFont.lato);
    expect(preferences.customThemes, hasLength(1));
    expect(
      shell.forumSettings.themesFor('https://b.example'),
      ForumThemePreferences.defaults,
    );
  });

  testWidgets(
    'import validates before applying and export includes both palettes and effects',
    (tester) async {
      final files = _ThemeFiles();
      final previous = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = files;
      addTearDown(() => FileSelectorPlatform.instance = previous);
      final directory = Directory.systemTemp.createTempSync(
        'live-theme-export-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final shell = controller();
      addTearDown(shell.dispose);
      await pumpSettings(tester, shell);
      await openLibrary(tester);
      final import = find.widgetWithText(DButton, 'Import');
      await tester.ensureVisible(import);
      files.contents = '{broken';
      await tester.tap(import);
      await tester.pumpAndSettle();
      expect(find.text('Choose a valid theme JSON file.'), findsOneWidget);
      expect(shell.forumSettings.themesFor(_site).palettes, isEmpty);
      final solarized = forumThemePresets.firstWhere(
        (theme) => theme.id == 'solarized',
      );
      files.contents = jsonEncode(solarized.toJson());
      await tester.tap(import);
      await tester.pumpAndSettle();
      expect(
        shell.forumSettings
            .themesFor(_site)
            .themeFor(Brightness.light)!
            .tertiary,
        solarized.tertiary,
      );
      files.destination = '${directory.path}/theme.json';
      await tester.tap(find.widgetWithText(DButton, 'Export'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      final decoded =
          jsonDecode(File(files.destination!).readAsStringSync())
              as Map<String, dynamic>;
      final exported = ForumTheme.fromJson(decoded, id: 'exported');
      expect(
        exported.forBrightness(Brightness.dark).tertiary,
        solarized.alternate!.tertiary,
      );
      expect(exported.background!.useAccentTint, isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

final class _ThemeFiles extends FileSelectorPlatform {
  String? contents;
  String? destination;
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => contents == null
      ? null
      : XFile.fromData(
          Uint8List.fromList(utf8.encode(contents!)),
          name: 'theme.json',
        );
  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async => destination == null ? null : FileSaveLocation(destination!);
}
