import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/shell/forum_appearance_settings.dart';
import 'package:discourse_native/src/shell/forum_settings_dialog.dart';
import 'package:discourse_native/src/shell/forum_theme_editor.dart';
import 'package:discourse_native/src/shell/forum_theme_preview.dart';
import 'package:discourse_native/src/shell/forum_theme_surfaces.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Finder input(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(EditableText),
);

void main() {
  testWidgets('surface toggles update the draft, save and reopen', (
    tester,
  ) async {
    ForumTheme? saved;
    ForumTheme? draft;
    final initial = forumThemePresets.first;
    Widget editor(ForumTheme theme) => MaterialApp(
      theme: AppTheme.light,
      home: SingleChildScrollView(
        child: DCard(
          child: ForumThemeEditor(
            key: ValueKey(theme),
            initialTheme: theme,
            customThemes: const [],
            onChanged: (value) => draft = value,
            onSave: (value) async => saved = value,
          ),
        ),
      ),
    );
    await tester.pumpWidget(editor(initial));
    final toggle = find.byKey(const ValueKey('custom-theme-darker-sidebars'));
    expect(tester.widget<DToggle>(toggle).pressed, isFalse);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final strength = find.byKey(const ValueKey('custom-theme-strength'));
    await tester.ensureVisible(strength);
    await tester.tap(strength);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Noise background'));
    await tester.pump();
    final plane = find.byKey(const ValueKey('color-picker-inline-plane'));
    await tester.tapAt(tester.getCenter(plane));
    await tester.pump();
    expect(draft!.background!.effect, ForumBackgroundEffect.noise);
    expect(draft!.background!.color, isNot(initial.tertiary));
    expect(draft!.background!.strength, closeTo(.51, .01));
    expect(find.text('Palette mode'), findsNothing);
    expect(draft!.darkerSidebars, isTrue);
    final save = find.byKey(const ValueKey('save-custom-theme'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    expect(saved, draft);
    await tester.pumpWidget(editor(saved!));
    expect(
      tester.widget<DSlider>(strength).value,
      saved!.background!.strength * 100,
    );
    expect(
      tester
          .widget<DToggleGroup<ForumBackgroundEffect>>(
            find.byKey(const ValueKey('custom-theme-background-effect')),
          )
          .values,
      [ForumBackgroundEffect.noise],
    );
    expect(tester.widget<DToggle>(toggle).pressed, isTrue);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    expect(draft!.darkerSidebars, isFalse);
    expect(draft!.background, saved!.background);
    await tester.ensureVisible(save);
    await tester.tap(save);
    expect(saved, draft);
    await tester.pumpWidget(editor(saved!));
    expect(tester.widget<DToggle>(toggle).pressed, isFalse);
  });

  testWidgets('custom background previews honor the darker sidebars toggle', (
    tester,
  ) async {
    final source = forumThemePresets.first;
    for (final mode in Brightness.values) {
      for (final effect in ForumBackgroundEffect.values) {
        for (final darkerSidebars in [false, true, false]) {
          final custom = ForumTheme.fromJson({
            ...source.toJson(),
            'darkerSidebars': darkerSidebars,
            'background': ForumBackground(
              color: Colors.purple,
              effect: effect,
            ).toJson(),
          }, id: 'custom-background');
          final theme = AppTheme.fromPalette(custom.resolve(mode));
          await tester.pumpWidget(
            MaterialApp(
              home: SingleChildScrollView(
                child: ForumThemePreview(
                  theme: theme,
                  siteUrl: 'https://example.com',
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          final sidebar = find.byKey(const ValueKey('theme-preview-sidebar'));
          final context = tester.element(sidebar);
          final navigation = Theme.of(context);
          expect(
            navigation.brightness,
            darkerSidebars ? Brightness.dark : mode,
          );
          expect(ForumWindowBackground.isContinuous(context), !darkerSidebars);
          expect(
            tester.widget<DSidebar>(sidebar).backgroundColor,
            darkerSidebars ? isNull : Colors.transparent,
          );
          if (darkerSidebars) {
            expect(
              navigation.shell.sidebar.computeLuminance(),
              lessThan(theme.shell.sidebar.computeLuminance()),
            );
          }
          expect(
            Theme.of(tester.element(find.text('Latest topics'))).colorScheme,
            theme.colorScheme,
          );
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('preview scopes dark navigation and paints the window gradient', (
    tester,
  ) async {
    for (final mode in Brightness.values) {
      final source = forumThemePresets.first;
      final themed = ForumTheme.fromJson({
        ...source.toJson(),
        'windowGradient': true,
        'darkerSidebars': true,
      }, id: 'custom-effects');
      final theme = AppTheme.fromPalette(themed.resolve(mode));
      await tester.pumpWidget(
        MaterialApp(
          home: SingleChildScrollView(
            child: ForumThemePreview(
              theme: theme,
              siteUrl: 'https://example.com',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final sidebarContext = tester.element(
        find.byKey(const ValueKey('theme-preview-sidebar')),
      );
      final contentContext = tester.element(find.text('Latest topics'));
      final navigation = Theme.of(sidebarContext);
      expect(navigation.brightness, Brightness.dark);
      expect(Theme.of(contentContext).colorScheme, theme.colorScheme);
      expect(
        navigation.shell.sidebar.computeLuminance(),
        lessThan(theme.shell.sidebar.computeLuminance()),
      );
      final tokens = DTokens.of(sidebarContext);
      double contrast(Color foreground, Color background) {
        final a = foreground.computeLuminance();
        final b = background.computeLuminance();
        return ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05);
      }

      expect(
        contrast(tokens.foreground, tokens.muted),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(tokens.selectedForeground, tokens.selected),
        greaterThanOrEqualTo(4.5),
      );
      final canvas = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(ForumWindowBackground),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((canvas.decoration as BoxDecoration).gradient, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: SingleChildScrollView(
            child: ForumThemePreview(
              theme: AppTheme.fromPalette(source.resolve(mode)),
              siteUrl: 'https://example.com',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(
          tester.element(find.byKey(const ValueKey('theme-preview-sidebar'))),
        ).brightness,
        mode,
      );
      final plain = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(ForumWindowBackground),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((plain.decoration as BoxDecoration).gradient, isNull);
    }
  });

  testWidgets(
    'invalid colors disable saving and valid edits emit a portable theme',
    (tester) async {
      ForumTheme? draft;
      ForumTheme? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SingleChildScrollView(
            child: DCard(
              child: ForumThemeEditor(
                initialTheme: forumThemePresets.firstWhere(
                  (theme) => theme.id == 'dracula',
                ),
                customThemes: const [],
                onChanged: (value) => draft = value,
                onSave: (value) async => saved = value,
              ),
            ),
          ),
        ),
      );
      await tester.enterText(input('custom-theme-tertiary'), '#broken');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DButton>(find.byKey(const ValueKey('save-custom-theme')))
            .onPressed,
        isNull,
      );
      expect(draft, isNull);
      await tester.enterText(input('custom-theme-tertiary'), '#39845B');
      await tester.enterText(input('custom-theme-name'), 'Forest');
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('save-custom-theme')),
      );
      await tester.tap(find.byKey(const ValueKey('save-custom-theme')));
      expect(saved?.name, 'Forest');
      expect(saved?.tertiary, const Color(0xff39845b));
      expect(saved?.id, startsWith('custom-'));
      expect(ForumTheme.fromJson(saved!.toJson(), id: saved!.id), saved);
    },
  );

  testWidgets(
    'Surprise me updates the draft and preserves its name until saved',
    (tester) async {
      ForumTheme? draft;
      ForumTheme? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SingleChildScrollView(
            child: DCard(
              child: ForumThemeEditor(
                initialTheme: forumThemePresets.firstWhere(
                  (theme) => theme.id == 'dracula',
                ),
                customThemes: const [],
                onChanged: (value) => draft = value,
                onSave: (value) async => saved = value,
              ),
            ),
          ),
        ),
      );
      await tester.enterText(input('custom-theme-name'), 'My garden');
      await tester.pumpAndSettle();
      final id = draft!.id;
      final before = draft!.tertiary;
      await tester.ensureVisible(find.text('Surprise me'));
      await tester.tap(find.text('Surprise me'));
      await tester.pumpAndSettle();
      expect(draft!.name, 'My garden');
      expect(draft!.id, id);
      expect(draft!.tertiary, isNot(before));
      expect(saved, isNull);
      final firstAccent = draft!.tertiary;
      await tester.tap(find.text('Surprise me'));
      await tester.pumpAndSettle();
      expect(draft!.tertiary, isNot(firstAccent));
      await tester.tap(find.byKey(const ValueKey('save-custom-theme')));
      expect(saved, draft);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('imports validated JSON into the editor without applying it', (
    tester,
  ) async {
    final previous = FileSelectorPlatform.instance;
    final files = _ThemeFiles();
    FileSelectorPlatform.instance = files;
    addTearDown(() => FileSelectorPlatform.instance = previous);
    ForumTheme? draft;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SingleChildScrollView(
          child: DCard(
            child: ForumThemeEditor(
              initialTheme: forumThemePresets.first,
              customThemes: const [],
              onChanged: (value) => draft = value,
              onSave: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Import'));
    files.contents = '{invalid';
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a valid theme JSON file.'), findsOneWidget);
    expect(draft, isNull);
    files.contents = jsonEncode({
      ...forumThemePresets
          .firstWhere((theme) => theme.id == 'dracula')
          .toJson(),
      'name': 'Imported night',
      'windowGradient': true,
      'darkerSidebars': true,
    });
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(draft?.name, 'Imported night');
    expect(draft?.windowGradient, isTrue);
    expect(draft?.darkerSidebars, isTrue);
    expect(
      draft?.tertiary,
      forumThemePresets.firstWhere((theme) => theme.id == 'dracula').tertiary,
    );
    expect(draft?.id, startsWith('custom-'));
    final imported = draft;
    files.contents = null;
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(draft, imported);
    expect(files.types!.single.extensions, ['json']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exports a JSON file and cancelling export writes nothing', (
    tester,
  ) async {
    final previous = FileSelectorPlatform.instance;
    final files = _ThemeFiles();
    FileSelectorPlatform.instance = files;
    addTearDown(() => FileSelectorPlatform.instance = previous);
    final directory = Directory.systemTemp.createTempSync('theme-export-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SingleChildScrollView(
          child: DCard(
            child: ForumThemeEditor(
              initialTheme: forumThemePresets.firstWhere(
                (theme) => theme.id == 'dracula',
              ),
              customThemes: const [],
              onChanged: (_) {},
              onSave: (_) async {},
            ),
          ),
        ),
      ),
    );
    for (final key in ['darker-sidebars']) {
      final toggle = find.byKey(ValueKey('custom-theme-$key'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.bySemanticsLabel('Noise background'));
    await tester.tap(find.bySemanticsLabel('Noise background'));
    await tester.pump();
    await tester.ensureVisible(find.text('Export'));
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(directory.listSync(), isEmpty);
    files.destination = '${directory.path}/palette.json';
    await tester.runAsync(() async {
      await tester.tap(find.text('Export'));
      // Let the real XFile filesystem write complete outside the fake clock.
      for (
        var attempt = 0;
        attempt < 100 && find.text('Theme exported.').evaluate().isEmpty;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    final json =
        jsonDecode(File(files.destination!).readAsStringSync())
            as Map<String, dynamic>;
    final exported = ForumTheme.fromJson(json, id: 'exported');
    expect(exported.name, 'Dracula custom');
    expect(exported.background!.effect, ForumBackgroundEffect.noise);
    expect(exported.darkerSidebars, isTrue);
    expect(
      exported.tertiary,
      forumThemePresets.firstWhere((theme) => theme.id == 'dracula').tertiary,
    );
    expect(files.suggestedName, 'Dracula-custom.json');
    expect(find.text('Theme exported.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('sidebar, presets, and custom preview use real components', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 950);
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
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => DButton(
              label: const Text('Open'),
              onPressed: () => showForumSettingsDialog(
                context,
                siteUrl: 'https://a.example',
                name: 'A forum',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(DSidebar), findsNWidgets(2));
    expect(find.byKey(const ValueKey('theme-preview-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('theme-preview-sidebar')), findsOneWidget);
    expect(find.byType(ForumThemePreview), findsOneWidget);
    expect(find.byType(TopicListRow), findsNWidgets(2));
    expect(find.byType(ThemeThumbnail), findsNWidgets(10));
    final palette = find.byType(ThemePaletteStrip);
    expect(
      find.descendant(of: palette, matching: find.byType(Semantics)),
      findsNWidgets(7),
    );
    final previewBounds = tester.getRect(
      find.byKey(const ValueKey('forum-theme-preview')),
    );
    final newTopicBounds = tester.getRect(
      find.widgetWithText(DButton, 'New topic'),
    );
    expect(
      newTopicBounds.left - previewBounds.left,
      greaterThanOrEqualTo(DSpacing.lg),
    );
    expect(
      previewBounds.bottom - newTopicBounds.bottom,
      greaterThanOrEqualTo(DSpacing.lg),
    );
    final lato = find.byKey(const ValueKey('appearance-font-lato'));
    await tester.ensureVisible(lato);
    await tester.tap(lato);
    await tester.pumpAndSettle();
    final dracula = find.byKey(const ValueKey('forum-theme-dracula'));
    await tester.ensureVisible(dracula);
    await tester.tap(dracula);
    await tester.pumpAndSettle();
    expect(
      controller.forumSettings.themesFor('https://a.example').selectedId,
      'dracula',
    );
    final preview = find.byKey(const ValueKey('forum-theme-preview'));
    expect(
      Theme.of(tester.element(preview)).textTheme.bodyMedium?.fontFamily,
      'Lato',
    );
    expect(
      Theme.of(tester.element(preview)).colorScheme.primary,
      const Color(0xffbd93f9),
    );
    await tester.ensureVisible(find.text('Custom'));
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(input('custom-theme-tertiary'));
    await tester.enterText(input('custom-theme-tertiary'), '#39845B');
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(preview)).colorScheme.primary,
      const Color(0xff39845b),
    );
    expect(
      controller.forumSettings
          .themesFor('https://a.example')
          .selectedTheme
          ?.tertiary,
      const Color(0xffbd93f9),
    );
    await tester.enterText(input('custom-theme-tertiary'), '#39');
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(input('custom-theme-tertiary'))
          .controller
          .text,
      '#39',
    );
    expect(
      Theme.of(tester.element(preview)).colorScheme.primary,
      const Color(0xff39845b),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.bySemanticsLabel('Choose accent color'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Choose accent color'));
    await tester.pumpAndSettle();
    final plane = find.byKey(const ValueKey('color-picker-plane'));
    await tester.tapAt(tester.getCenter(plane));
    await tester.pumpAndSettle();
    final chosen = tester
        .widget<EditableText>(input('custom-theme-tertiary'))
        .controller
        .text;
    expect(chosen, isNot('#BD93F9'));
    expect(
      ForumTheme.hex(Theme.of(tester.element(preview)).colorScheme.primary),
      chosen,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ForumSettingsDialog), findsOneWidget);
    await tester.enterText(input('custom-theme-tertiary'), '#39845B');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('save-custom-theme')));
    await tester.tap(find.byKey(const ValueKey('save-custom-theme')));
    await tester.pumpAndSettle();
    expect(
      controller.forumSettings.themesFor('https://a.example').selectedId,
      startsWith('custom-'),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('forum-default-theme')),
    );
    await tester.tap(find.byKey(const ValueKey('forum-default-theme')));
    await tester.pumpAndSettle();
    expect(
      controller.forumSettings.themesFor('https://a.example').selectedId,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}

final class _ThemeFiles extends FileSelectorPlatform {
  String? contents;
  String? destination;
  String? suggestedName;
  List<XTypeGroup>? types;
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    types = acceptedTypeGroups;
    return contents == null
        ? null
        : XFile.fromData(
            Uint8List.fromList(utf8.encode(contents!)),
            name: 'theme.json',
          );
  }

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    types = acceptedTypeGroups;
    suggestedName = options.suggestedName;
    return destination == null ? null : FileSaveLocation(destination!);
  }
}
