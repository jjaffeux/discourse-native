import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/shell/forum_appearance_settings.dart';
import 'package:discourse_native/src/shell/forum_settings_dialog.dart';
import 'package:discourse_native/src/shell/forum_theme_editor.dart';
import 'package:discourse_native/src/shell/forum_theme_preview.dart';
import 'package:discourse_native/src/shell/forum_theme_surfaces.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_create_button.dart';
import 'package:discourse_native/src/shell/topic_list_bottom_bar.dart';
import 'package:discourse_native/src/shell/topic_list_filter_bar.dart';
import 'package:discourse_native/src/shell/topic_list_navigation.dart';
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
  testWidgets('saved theme thumbnails follow the resolved preview colors', (
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
    const siteUrl = 'https://a.example';
    final source = forumThemePresets.firstWhere((t) => t.id == 'dracula');
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: const DCard(
            child: Expanded(child: ForumAppearanceSettings(siteUrl: siteUrl)),
          ),
        ),
      ),
    );
    for (final darkerSidebars in [false, true]) {
      final custom = ForumTheme.fromJson({
        ...source.toJson(),
        'name': 'Dracula custom',
        'background': const ForumBackground(
          color: Color(0xff39a876),
          strength: .8,
        ).toJson(),
        'darkerSidebars': darkerSidebars,
        'alternate': {
          ...source.forBrightness(Brightness.light).toJson(),
          'background': const ForumBackground(
            color: Color(0xffe891bd),
            strength: .6,
          ).toJson(),
          'darkerSidebars': darkerSidebars,
        },
      }, id: 'custom-thumbnail');
      await controller.forumSettings.setThemes(
        siteUrl,
        ForumThemePreferences(customThemes: [custom], selectedId: custom.id),
      );
      for (final mode in [AppThemeMode.dark, AppThemeMode.light]) {
        await controller.forumSettings.setThemeMode(siteUrl, mode);
        await tester.pumpAndSettle();
        final thumbnail = find.descendant(
          of: find.byKey(const ValueKey('forum-theme-custom-thumbnail')),
          matching: find.byType(ThemeThumbnail),
        );
        final colors = tester
            .widgetList<ColoredBox>(
              find.descendant(of: thumbnail, matching: find.byType(ColoredBox)),
            )
            .map((box) => box.color)
            .toList();
        final preview = tester.widget<ForumThemePreview>(
          find.byType(ForumThemePreview),
        );
        final sidebar = Theme.of(
          tester.element(find.byKey(const ValueKey('theme-preview-sidebar'))),
        );
        expect(colors.first, preview.theme.shell.content);
        expect(colors[1], sidebar.shell.sidebar);
        expect(colors[2], preview.theme.colorScheme.primary);
        expect(
          colors.skip(3),
          everyElement(
            preview.theme.colorScheme.onSurface.withValues(alpha: .24),
          ),
        );
        expect(tester.getSize(thumbnail), const Size(44, 36));
        expect(tester.takeException(), isNull);
      }
    }
  });

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
    final noise = find.byKey(const ValueKey('custom-theme-noise-intensity'));
    final transparency = find.byKey(
      const ValueKey('custom-theme-transparency'),
    );
    expect(tester.widget<DSlider>(noise).value, 20);
    expect(tester.widget<DSlider>(transparency).value, 10);
    await tester.ensureVisible(noise);
    await tester.tap(noise);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(draft!.background!.noiseIntensity, 0);
    expect(draft!.background!.transparency, .1);
    await tester.ensureVisible(transparency);
    await tester.tap(transparency);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(draft!.background!.transparency, .2);
    expect(draft!.background!.noiseIntensity, 0);
    expect(draft!.background!.strength, closeTo(.51, .01));
    expect(find.text('Palette mode'), findsNothing);
    expect(draft!.darkerSidebars, isTrue);
    final save = find.byKey(const ValueKey('save-custom-theme'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    expect(saved, draft);
    await tester.pumpWidget(editor(saved!));
    expect(tester.widget<DSlider>(noise).value, 0);
    expect(tester.widget<DSlider>(transparency).value, 20);
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
            ...source.forBrightness(mode).toJson(),
            'darkerSidebars': darkerSidebars,
            'background': ForumBackground(
              color: Colors.purple,
              effect: effect,
            ).toJson(),
          }, id: 'custom-background');
          final theme = AppTheme.fromPalette(
            custom.resolve(mode),
          ).copyWith(platform: TargetPlatform.macOS);
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
            darkerSidebars ? DTokens.of(context).muted : Colors.transparent,
          );
          if (darkerSidebars) {
            expect(
              navigation.shell.sidebar.computeLuminance(),
              lessThan(theme.shell.sidebar.computeLuminance()),
            );
          }
          expect(
            Theme.of(tester.element(find.byType(TopicFeedMenu))).colorScheme,
            theme.colorScheme,
          );
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets(
    'appearance tabs retain independent drafts through saving and reopening',
    (tester) async {
      final initial = forumThemePresets.first;
      ForumTheme? saved;
      ForumTheme? draft;
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
      Future<void> select(Brightness mode) async {
        final tab = find.byKey(ValueKey('custom-theme-${mode.name}-tab'));
        await tester.ensureVisible(tab);
        await tester.tap(tab);
        await tester.pumpAndSettle();
      }

      String accent() => tester
          .widget<EditableText>(input('custom-theme-tertiary'))
          .controller
          .text;
      await tester.pumpWidget(editor(initial));
      expect(accent(), ForumTheme.hex(initial.tertiary));
      await tester.enterText(input('custom-theme-tertiary'), '#39845B');
      await tester.ensureVisible(find.bySemanticsLabel('Noise background'));
      await tester.tap(find.bySemanticsLabel('Noise background'));
      await tester.pumpAndSettle();
      final noise = find.byKey(const ValueKey('custom-theme-noise-intensity'));
      final transparency = find.byKey(
        const ValueKey('custom-theme-transparency'),
      );
      await tester.ensureVisible(noise);
      await tester.tap(noise);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      await tester.ensureVisible(transparency);
      await tester.tap(transparency);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      final light = draft!.forBrightness(Brightness.light);
      await select(Brightness.dark);
      expect(accent(), ForumTheme.hex(initial.alternate!.tertiary));
      expect(
        tester
            .widget<DToggle>(
              find.byKey(const ValueKey('custom-theme-darker-sidebars')),
            )
            .pressed,
        isFalse,
      );
      await tester.enterText(input('custom-theme-tertiary'), '#AA88DD');
      final darker = find.byKey(const ValueKey('custom-theme-darker-sidebars'));
      await tester.ensureVisible(darker);
      await tester.tap(darker);
      await tester.pumpAndSettle();
      expect(draft!.background, isNull);
      expect(draft!.darkerSidebars, isTrue);
      expect(draft!.forBrightness(Brightness.light), light);
      await select(Brightness.light);
      expect(accent(), '#39845B');
      expect(tester.widget<DSlider>(noise).value, 0);
      expect(tester.widget<DSlider>(transparency).value, 20);
      expect(
        tester
            .widget<DToggleGroup<ForumBackgroundEffect>>(
              find.byKey(const ValueKey('custom-theme-background-effect')),
            )
            .values,
        [ForumBackgroundEffect.noise],
      );
      await tester.enterText(input('custom-theme-name'), 'Day and night');
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('save-custom-theme')),
      );
      await tester.tap(find.byKey(const ValueKey('save-custom-theme')));
      final restored = ForumTheme.fromJson(saved!.toJson(), id: saved!.id);
      await tester.pumpWidget(editor(restored));
      expect(accent(), '#39845B');
      expect(tester.widget<DSlider>(noise).value, 0);
      expect(tester.widget<DSlider>(transparency).value, 20);
      await select(Brightness.dark);
      expect(tester.widget<DSlider>(transparency).value, 10);
      expect(accent(), '#AA88DD');
      expect(draft!.name, 'Day and night');
      expect(draft!.alternate!.name, 'Day and night');
      expect(draft!.darkerSidebars, isTrue);
      expect(draft!.background, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('preset changes affect only the selected appearance', (
    tester,
  ) async {
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
    await tester.enterText(input('custom-theme-tertiary'), '#39845B');
    final light = draft!.forBrightness(Brightness.light);
    final dark = find.byKey(const ValueKey('custom-theme-dark-tab'));
    await tester.ensureVisible(dark);
    await tester.tap(dark);
    await tester.pumpAndSettle();
    final presets = find.byType(DSelect<String>);
    await tester.ensureVisible(presets);
    await tester.tap(presets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Solarized'));
    await tester.tap(find.text('Solarized'));
    await tester.pumpAndSettle();
    expect(draft!.tertiary, const Color(0xff1a97d5));
    expect(draft!.forBrightness(Brightness.light), light);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'invalid inactive appearance prevents saving and retains its text',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SingleChildScrollView(
            child: DCard(
              child: ForumThemeEditor(
                initialTheme: forumThemePresets.first,
                customThemes: const [],
                onChanged: (_) {},
                onSave: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.enterText(input('custom-theme-tertiary'), '#12');
      final dark = find.byKey(const ValueKey('custom-theme-dark-tab'));
      await tester.ensureVisible(dark);
      await tester.tap(dark);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DButton>(find.byKey(const ValueKey('save-custom-theme')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<DButton>(find.widgetWithText(DButton, 'Export'))
            .onPressed,
        isNull,
      );
      expect(
        find.text('Enter a name and valid colors in both appearance tabs.'),
        findsOneWidget,
      );
      // Arrow-key activation returns to the draft without losing invalid input.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(input('custom-theme-tertiary'))
            .controller
            .text,
        '#12',
      );
      await tester.enterText(input('custom-theme-tertiary'), '#123456');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DButton>(find.byKey(const ValueKey('save-custom-theme')))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('preview scopes dark navigation and paints the window gradient', (
    tester,
  ) async {
    for (final mode in Brightness.values) {
      final source = forumThemePresets.first;
      final themed = ForumTheme.fromJson({
        ...source.forBrightness(mode).toJson(),
        'windowGradient': true,
        'darkerSidebars': true,
      }, id: 'custom-effects');
      final theme = AppTheme.fromPalette(
        themed.resolve(mode),
      ).copyWith(platform: TargetPlatform.macOS);
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
      final contentContext = tester.element(find.byType(TopicFeedMenu));
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
              theme: AppTheme.fromPalette(
                source.resolve(mode),
              ).copyWith(platform: TargetPlatform.macOS),
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
      final otherAppearance = draft!.alternate;
      await tester.ensureVisible(find.text('Surprise me'));
      await tester.tap(find.text('Surprise me'));
      await tester.pumpAndSettle();
      expect(draft!.name, 'My garden');
      expect(draft!.id, id);
      expect(draft!.tertiary, isNot(before));
      expect(draft!.alternate, otherAppearance);
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
      'alternate': forumThemePresets.first.toJson()..remove('alternate'),
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
    expect(draft!.alternate!.tertiary, forumThemePresets.first.tertiary);
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
    expect(exported.alternate!.background, isNull);
    expect(exported.alternate!.darkerSidebars, isFalse);
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
    expect(find.byType(ForumIdentityHeader), findsOneWidget);
    expect(find.byType(TopicFeedMenu), findsOneWidget);
    expect(find.byType(TopicListFilterBar), findsOneWidget);
    expect(find.byType(TopicCreateAction), findsOneWidget);
    expect(find.text('Normal'), findsNothing);
    expect(find.byKey(const ValueKey('theme-preview-sidebar')), findsOneWidget);
    expect(find.byType(ForumThemePreview), findsOneWidget);
    expect(find.byType(TopicListRow), findsNWidgets(2));
    expect(find.byType(ThemeThumbnail), findsNWidgets(10));
    final palette = find.byType(ThemePaletteStrip);
    expect(
      find.descendant(of: palette, matching: find.byType(Semantics)),
      findsNWidgets(7),
    );
    expect(
      tester.getSize(find.byType(TopicListRow).first).width,
      greaterThan(600),
    );
    final footer = find.descendant(
      of: find.byType(TopicListFooter),
      matching: find.byType(DCardFooter),
    );
    expect(tester.widget<DCardFooter>(footer).rounded, isTrue);
    expect(tester.getSize(footer).height, 50);
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
    final savedMode = controller.forumSettings.themeModeFor(
      'https://a.example',
    );
    final darkTab = find.byKey(const ValueKey('custom-theme-dark-tab'));
    await tester.ensureVisible(darkTab);
    await tester.tap(darkTab);
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(preview)).brightness, Brightness.dark);
    expect(
      Theme.of(tester.element(preview)).colorScheme.primary,
      const Color(0xffbd93f9),
    );
    await tester.enterText(input('custom-theme-tertiary'), '#AA88DD');
    final lightTab = find.byKey(const ValueKey('custom-theme-light-tab'));
    await tester.ensureVisible(lightTab);
    await tester.tap(lightTab);
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(preview)).brightness, Brightness.light);
    expect(
      controller.forumSettings.themeModeFor('https://a.example'),
      savedMode,
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
    await tester.ensureVisible(find.text('Edit theme'));
    await tester.tap(find.text('Edit theme'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(darkTab);
    await tester.tap(darkTab);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(input('custom-theme-tertiary'))
          .controller
          .text,
      '#AA88DD',
    );
    expect(
      Theme.of(tester.element(preview)).colorScheme.primary,
      const Color(0xffaa88dd),
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
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
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
