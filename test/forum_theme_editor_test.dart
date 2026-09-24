import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/shell/forum_settings_page.dart';
import 'package:discourse_native/src/shell/forum_theme_editor.dart';
import 'package:discourse_native/src/shell/settings_section.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/theme_settings.dart';

const _site = 'https://a.example';

ForumThemePreferences _preferences(ShellController shell) =>
    shell.forumSettings.themesFor(_site);

Finder _choice(String id) => find.byKey(ValueKey(('theme-choice', id)));

Finder _checkmark(String id) => find.descendant(
  of: _choice(id),
  matching: find.byWidgetPredicate(
    (widget) => widget is DIcon && widget.icon == DIcons.check,
  ),
);

Finder _input(String role) => find.descendant(
  of: find.byKey(ValueKey('theme-color-$role')),
  matching: find.byType(EditableText),
);

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _source(WidgetTester tester, ForumThemeSource source) =>
    _tap(tester, find.byKey(ValueKey(('theme-source', source))));

Future<void> _appearance(WidgetTester tester, String mode) => _tap(
  tester,
  find.descendant(
    of: find.byKey(const ValueKey('appearance-mode')),
    matching: find.text(mode),
  ),
);

/// The app around the page, which is the preview of every choice.
ThemeData _appTheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(ForumSettingsPage)));

ForumTheme _saved(String id, String name, String preset) =>
    ForumTheme.fromJson({
      ...forumThemePresets.firstWhere((theme) => theme.id == preset).toJson(),
      'name': name,
    }, id: id);

void main() {
  testWidgets(
    'choosing a preset applies it to one mode and leaves the other with the '
    'forum colours',
    (tester) async {
      final shell = controller();
      addTearDown(shell.dispose);
      await pumpSettings(tester, shell);
      expect(_preferences(shell).source, ForumThemeSource.forum);
      expect(_preferences(shell).presets, isEmpty);
      expect(
        find.byKey(const ValueKey(('theme-source', ForumThemeSource.forum))),
        findsNothing,
      );
      expect(
        tester
            .widget<DRadioGroup<ForumThemeSource>>(
              find.byKey(const ValueKey('theme-source')),
            )
            .groupValue,
        ForumThemeSource.preset,
      );
      expect(_choice('forum'), findsOneWidget);
      expect(tester.widget<DItem>(_choice('forum')).selected, isTrue);
      expect(
        tester.getTopLeft(_choice('forum')).dy,
        lessThan(tester.getTopLeft(_choice('neutral')).dy),
      );
      expect(_choice('summer'), findsOneWidget);
      expect(_choice('dracula'), findsNothing, reason: 'Dracula is dark only');
      expect(find.byKey(const ValueKey('theme-shown-mode')), findsNothing);

      await _tap(tester, _choice('solarized'));
      expect(_preferences(shell).source, ForumThemeSource.preset);
      expect(_preferences(shell).presets, {Brightness.light: 'solarized'});
      expect(tester.widget<DItem>(_choice('forum')).selected, isFalse);
      expect(_appTheme(tester).colorScheme.primary, const Color(0xff0088cc));
      expect(find.text('Built-in presets'), findsNothing);
      expect(find.text('Solarized · light and dark'), findsNothing);
      expect(find.text('Make my own from this'), findsNothing);
      expect(_checkmark('solarized'), findsNothing);

      await _appearance(tester, 'Dark');
      expect(_appTheme(tester).brightness, Brightness.dark);
      expect(_choice('summer'), findsNothing, reason: 'Summer is light only');
      await _tap(tester, _choice('dracula'));
      expect(_preferences(shell).presets, {
        Brightness.light: 'solarized',
        Brightness.dark: 'dracula',
      });
      expect(_appTheme(tester).colorScheme.primary, const Color(0xffbd93f9));
      expect(find.text('Dracula · dark only'), findsNothing);
      expect(tester.widget<DItem>(_choice('dracula')).selected, isTrue);
      expect(_checkmark('dracula'), findsNothing);
      expect(tester.widget<DItem>(_choice('neutral')).selected, isFalse);
      expect(shell.forumSettings.themeModeFor(_site), AppThemeMode.dark);
      await _tap(tester, _choice('forum'));
      expect(_preferences(shell).source, ForumThemeSource.forum);
      expect(_preferences(shell).presets, {
        Brightness.light: 'solarized',
        Brightness.dark: 'dracula',
      });
      expect(tester.widget<DItem>(_choice('forum')).selected, isTrue);
      expect(tester.widget<DItem>(_choice('dracula')).selected, isFalse);
      await _source(tester, ForumThemeSource.preset);
      expect(_preferences(shell).source, ForumThemeSource.forum);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Presets restores a previously chosen palette from Your own', (
    tester,
  ) async {
    final shell = controller();
    addTearDown(shell.dispose);
    final saved = _saved('custom-moss', 'Moss', 'neutral');
    await shell.forumSettings.setThemes(
      _site,
      ForumThemePreferences(
        source: ForumThemeSource.custom,
        customId: saved.id,
        customThemes: [saved],
        presets: const {Brightness.light: 'wcag'},
      ),
    );
    await pumpSettings(tester, shell);

    await _source(tester, ForumThemeSource.preset);
    expect(_preferences(shell).source, ForumThemeSource.preset);
    expect(tester.widget<DItem>(_choice('wcag')).selected, isTrue);
    expect(tester.widget<DItem>(_choice('forum')).selected, isFalse);
    await _tap(tester, _choice('forum'));
    expect(_preferences(shell).source, ForumThemeSource.forum);
    expect(_preferences(shell).presets, {Brightness.light: 'wcag'});
    expect(tester.widget<DItem>(_choice('forum')).selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each preset reveals its own Customize action on hover', (
    tester,
  ) async {
    final shell = controller();
    addTearDown(shell.dispose);
    await pumpSettings(tester, shell);

    final neutralAction = find.byKey(
      const ValueKey(('customize-theme', 'neutral')),
    );
    final solarizedAction = find.byKey(
      const ValueKey(('customize-theme', 'solarized')),
    );
    double opacity(Finder action) => tester
        .widget<Opacity>(
          find.ancestor(of: action, matching: find.byType(Opacity)).first,
        )
        .opacity;
    expect(opacity(neutralAction), 0);
    expect(opacity(solarizedAction), 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(0, 0));
    await tester.ensureVisible(_choice('neutral'));
    await tester.pumpAndSettle();
    await mouse.moveTo(tester.getCenter(_choice('neutral')));
    await tester.pump();
    expect(opacity(neutralAction), 1);
    expect(opacity(solarizedAction), 0);

    await tester.tap(neutralAction);
    await tester.pumpAndSettle();
    expect(_preferences(shell).presets, isEmpty);
    expect(find.byType(DDialogContent), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('new-theme-name')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      'Neutral copy',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Customize on Forum default starts from the forum palette', (
    tester,
  ) async {
    final shell = controller();
    addTearDown(shell.dispose);
    await pumpSettings(tester, shell);

    await _tap(
      tester,
      find.byKey(const ValueKey(('customize-theme', 'forum'))),
    );
    expect(find.byType(DDialogContent), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('new-theme-name')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      'Forum default copy',
    );
    expect(
      tester
          .widget<DItem>(
            find.byKey(const ValueKey(('new-theme-base', 'forum'))),
          )
          .selected,
      isTrue,
    );
    expect(find.byKey(const ValueKey('new-theme-note')), findsNothing);
    expect(_preferences(shell).source, ForumThemeSource.forum);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new theme choices share one grid without section copy', (
    tester,
  ) async {
    final shell = controller();
    addTearDown(shell.dispose);
    final saved = _saved('custom-moss', 'Moss', 'neutral');
    await shell.forumSettings.setThemes(
      _site,
      ForumThemePreferences().save(saved),
    );
    await pumpSettings(tester, shell);
    await _tap(tester, find.byKey(const ValueKey('new-theme')));

    final dialog = find.byType(DDialogContent);
    expect(dialog, findsOneWidget);
    for (final text in [
      'Start blank or from a theme you like. You can change every colour afterwards.',
      'Presets',
      'Your themes',
    ]) {
      expect(
        find.descendant(of: dialog, matching: find.text(text)),
        findsNothing,
      );
    }
    expect(find.byKey(const ValueKey('new-theme-note')), findsNothing);
    Finder gridFor(String id) => find
        .ancestor(
          of: find.byKey(ValueKey(('new-theme-base', id))),
          matching: find.byType(Wrap),
        )
        .first;
    final grid = tester.element(gridFor('blank'));
    for (final id in ['forum', 'neutral', saved.id]) {
      expect(tester.element(gridFor(id)), grid);
    }
    final neutral = find.byKey(const ValueKey(('new-theme-base', 'neutral')));
    expect(
      tester.widget<DItem>(neutral).borderColor,
      DTokens.of(tester.element(neutral)).foreground.withValues(alpha: .24),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor mode preview resets when Cancel returns to the picker', (
    tester,
  ) async {
    final shell = controller();
    addTearDown(shell.dispose);
    await shell.forumSettings.setThemes(
      _site,
      ForumThemePreferences.preset('wcag'),
    );
    await pumpSettings(tester, shell);
    await _tap(tester, find.byKey(const ValueKey(('customize-theme', 'wcag'))));
    await _tap(tester, find.byKey(const ValueKey('new-theme-continue')));
    await _tap(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('appearance-theme-select')),
        matching: find.text('Dark'),
      ),
    );
    expect(_appTheme(tester).brightness, Brightness.dark);
    expect(_appTheme(tester).colorScheme.primary, const Color(0xff759aff));
    expect(shell.forumSettings.themeModeFor(_site), AppThemeMode.system);
    expect(
      await shell.forumSettings.store.loadThemeMode(_site),
      AppThemeMode.system,
    );

    await _tap(tester, find.byKey(const ValueKey('theme-cancel')));
    expect(shell.forumSettings.previewBrightnessFor(_site), isNull);
    expect(_appTheme(tester).brightness, Brightness.light);
    expect(_appTheme(tester).colorScheme.primary, const Color(0xff0033cc));
    expect(find.byKey(const ValueKey('theme-shown-mode')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a preset is never edited in place: making your own starts a new theme '
    'that is only saved from the editor',
    (tester) async {
      final shell = controller();
      addTearDown(shell.dispose);
      await pumpSettings(tester, shell);
      await _tap(tester, _choice('solarized'));
      final applied = _preferences(shell);

      await _tap(
        tester,
        find.byKey(const ValueKey(('customize-theme', 'solarized'))),
      );
      expect(find.byType(DDialogContent), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('new-theme-name')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'Solarized copy',
      );
      expect(
        tester
            .widget<DItem>(
              find.byKey(const ValueKey(('new-theme-base', 'solarized'))),
            )
            .selected,
        isTrue,
      );
      expect(find.byKey(const ValueKey('new-theme-note')), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('new-theme-continue')));

      expect(find.byType(DDialogContent), findsNothing);
      expect(find.byKey(const ValueKey('theme-picker')), findsNothing);
      expect(
        tester.widget<EditableText>(_input('accent')).controller.text,
        '#0088CC',
      );
      expect(_preferences(shell), applied);

      await _tap(tester, find.byKey(const ValueKey('theme-cancel')));
      expect(find.byKey(const ValueKey('theme-picker')), findsOneWidget);
      expect(_preferences(shell), applied);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'your first theme is started from the Your own choice and saved with both '
    'modes',
    (tester) async {
      final shell = controller();
      addTearDown(shell.dispose);
      await pumpSettings(tester, shell);
      await _source(tester, ForumThemeSource.custom);
      expect(find.byType(DDialogContent), findsOneWidget);
      await _tap(tester, find.widgetWithText(DButton, 'Cancel'));
      expect(_preferences(shell).source, ForumThemeSource.forum);

      await _source(tester, ForumThemeSource.custom);
      await _tap(
        tester,
        find.byKey(const ValueKey(('new-theme-base', 'wcag'))),
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('new-theme-name')),
          matching: find.byType(EditableText),
        ),
        '  Evening  ',
      );
      await tester.pump();
      await _tap(tester, find.byKey(const ValueKey('new-theme-continue')));

      await tester.ensureVisible(_input('accent'));
      await tester.enterText(_input('accent'), '#39845B');
      await tester.pumpAndSettle();
      expect(_preferences(shell).customThemes, isEmpty);
      final tabs = find.byKey(const ValueKey('appearance-theme-select'));
      await _tap(
        tester,
        find.descendant(of: tabs, matching: find.text('Dark')),
      );
      expect(
        tester.widget<EditableText>(_input('accent')).controller.text,
        '#759AFF',
      );
      expect(_appTheme(tester).brightness, Brightness.dark);

      await _tap(tester, find.byKey(const ValueKey('theme-save')));
      final preferences = _preferences(shell);
      final saved = preferences.customThemes.single;
      expect(saved.name, 'Evening');
      expect(saved.alternate!.name, 'Evening');
      expect(preferences.source, ForumThemeSource.custom);
      expect(preferences.customId, saved.id);
      expect(
        preferences.themeFor(Brightness.light)!.tertiary,
        const Color(0xff39845b),
      );
      expect(
        preferences.themeFor(Brightness.dark)!.tertiary,
        const Color(0xff759aff),
      );
      expect(await shell.forumSettings.store.loadThemes(_site), preferences);
      expect(find.byKey(const ValueKey('theme-picker')), findsOneWidget);
      expect(tester.widget<DItem>(_choice(saved.id)).selected, isTrue);
      expect(_checkmark(saved.id), findsNothing);
      expect(find.byKey(const ValueKey('theme-shown-mode')), findsNothing);
      expect(_appTheme(tester).brightness, Brightness.light);
      expect(_appTheme(tester).colorScheme.primary, const Color(0xff39845b));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the app shows an edited theme as it changes, and only Save stores it in '
    'place',
    (tester) async {
      final shell = controller();
      addTearDown(shell.dispose);
      final first = _saved('custom-first', 'First theme', 'neutral');
      final second = _saved('custom-second', 'Second theme', 'dracula');
      final initial = ForumThemePreferences(
        source: ForumThemeSource.custom,
        customId: second.id,
        customThemes: [first, second],
      );
      await shell.forumSettings.setThemes(_site, initial);
      await pumpSettings(tester, shell);
      await _tap(tester, find.byKey(ValueKey(('edit-theme', second.id))));

      final sidebar = find.byKey(const ValueKey('theme-sidebar'));
      // The sidebar tone is part of each mode's colours.
      expect(
        find.descendant(
          of: find.byWidgetPredicate(
            (widget) => widget is SettingsSection && widget.title == 'Colours',
          ),
          matching: sidebar,
        ),
        findsOneWidget,
      );
      for (final control in ['theme-tint', 'theme-texture']) {
        expect(
          find.descendant(
            of: find.byType(ForumThemeEditor),
            matching: find.byKey(ValueKey(control)),
          ),
          findsNothing,
          reason: control,
        );
      }
      expect(tester.widget<DToggleGroup<bool>>(sidebar).values, [false]);
      Object? sidebarTheme() =>
          _appTheme(tester).extension<ForumThemeEffects>()?.sidebarTheme;
      await _tap(tester, find.text('Darker sidebar'));
      expect(tester.widget<DToggleGroup<bool>>(sidebar).values, [true]);
      expect(sidebarTheme(), isNotNull);
      await _tap(tester, find.text('Neutral sidebar'));
      expect(sidebarTheme(), isNull);
      await _tap(tester, find.text('Darker sidebar'));
      expect(sidebarTheme(), isNotNull);
      expect(_preferences(shell), initial);

      await _tap(tester, find.byKey(const ValueKey('theme-save')));
      final preferences = _preferences(shell);
      expect(preferences.customThemes.map((theme) => theme.id), [
        first.id,
        second.id,
      ]);
      expect(preferences.customId, second.id);
      final edited = preferences.customTheme!;
      expect(edited.forBrightness(Brightness.light).darkerSidebars, isTrue);
      expect(edited.forBrightness(Brightness.dark).darkerSidebars, isFalse);
      for (final mode in Brightness.values) {
        expect(edited.forBrightness(mode).background, isNull);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tint, opacity and texture are found without a theme of your own and '
    'apply to every forum at once',
    (tester) async {
      final shell = controller();
      addTearDown(shell.dispose);
      await pumpSettings(tester, shell);
      await _tap(tester, _choice('wcag'));
      final applied = _preferences(shell);
      DSlider slider(String name) =>
          tester.widget(find.byKey(ValueKey('theme-$name')));
      expect(slider('intensity').onChanged, isNull);
      final tint = find.byKey(const ValueKey('theme-tint'));
      await tester.ensureVisible(tint);
      await tester.tapAt(tester.getTopRight(tint) + const Offset(-2, 13));
      await tester.pumpAndSettle();
      expect(find.text('22%'), findsOneWidget);
      final opacity = find.byKey(const ValueKey('theme-opacity'));
      await tester.tapAt(tester.getTopLeft(opacity) + const Offset(1, 13));
      await tester.pumpAndSettle();
      expect(find.text('70%'), findsOneWidget);
      await _tap(tester, find.text('Noise'));
      expect(slider('intensity').onChanged, isNotNull);

      final effects = shell.forumSettings.shared.effects;
      expect(effects.strength, 1);
      expect(effects.transparency, .3);
      expect(effects.effect, ForumBackgroundEffect.noise);
      expect(
        _appTheme(tester).extension<ForumThemeEffects>()!.background,
        effects,
      );
      expect(_preferences(shell), applied);
      expect(
        (await shell.forumSettings.store.loadAppearance()).effects,
        effects,
      );
      // Another forum, still on its own colours, draws the same effects.
      final other = SiteAppearance(
        base: forumThemePresets.first.resolve(Brightness.light),
      );
      expect(
        shell.forumSettings
            .appearanceFor('https://b.example', other)!
            .base!
            .background,
        effects,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Use on all forums copies these colours to every other forum', (
    tester,
  ) async {
    final shell = controller(
      instances: const [
        DiscourseInstance(url: _site, title: 'A'),
        DiscourseInstance(url: 'https://b.example', title: 'B'),
      ],
    );
    addTearDown(shell.dispose);
    await shell.load();
    await pumpSettings(tester, shell);
    final use = find.byKey(const ValueKey('theme-use-everywhere'));
    expect(use, findsNothing, reason: 'both show their forum colours');
    expect(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is SettingsSection && widget.title == 'Theme',
        ),
        matching: find.text('Used on all forums'),
      ),
      findsOneWidget,
    );

    await _tap(tester, _choice('wcag'));
    expect(
      shell.forumSettings.themesFor('https://b.example').source,
      ForumThemeSource.forum,
    );
    await _tap(tester, use);
    expect(shell.forumSettings.themesFor('https://b.example').presets, {
      Brightness.light: 'wcag',
    });
    expect(
      await shell.forumSettings.store.loadThemes('https://b.example'),
      shell.forumSettings.themesFor('https://b.example'),
    );
    expect(find.text('Every forum now uses these colours.'), findsOneWidget);
    expect(use, findsNothing);
    expect(find.text('Used on all forums'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('with one forum there is nothing to copy colours to', (
    tester,
  ) async {
    final shell = controller(
      instances: const [DiscourseInstance(url: _site, title: 'A')],
    );
    addTearDown(shell.dispose);
    await shell.load();
    await pumpSettings(tester, shell);
    await _tap(tester, _choice('wcag'));
    expect(find.byKey(const ValueKey('theme-use-everywhere')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'colour grid and hex field stay synchronized with keyboard and pointer edits',
    (tester) async {
      final shell = controller();
      addTearDown(shell.dispose);
      await pumpSettings(tester, shell);
      await _source(tester, ForumThemeSource.custom);
      await _tap(tester, find.byKey(const ValueKey('new-theme-continue')));
      final palette = find.byWidgetPredicate(
        (w) => w is DColorPicker && w.semanticLabel == 'Accent colour palette',
      );
      await _tap(tester, palette);
      final chosen = tester.widget<DColorPicker>(palette).value;
      expect(
        tester.widget<EditableText>(_input('accent')).controller.text,
        ForumTheme.hex(chosen),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      final lighter = tester.widget<DColorPicker>(palette).value;
      expect(
        lighter.computeLuminance(),
        greaterThan(chosen.computeLuminance()),
      );
      expect(
        tester.widget<EditableText>(_input('accent')).controller.text,
        ForumTheme.hex(lighter),
      );
      expect(tester.getSize(palette).height, 58);
      expect(tester.takeException(), isNull);
    },
  );

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets(
      'deleting the theme in use asks first and returns to the forum colours '
      'on $platform',
      (tester) async {
        final shell = controller();
        addTearDown(shell.dispose);
        final moss = _saved('custom-moss', 'Moss', 'clover-dark');
        final kept = _saved('custom-kept', 'Keep me', 'latte');
        final initial = ForumThemePreferences(
          source: ForumThemeSource.custom,
          customId: moss.id,
          customThemes: [moss, kept],
        );
        await shell.forumSettings.setThemes(_site, initial);
        await shell.forumSettings.setThemes('https://b.example', initial);
        await pumpSettings(
          tester,
          shell,
          width: platform == TargetPlatform.iOS ? 360 : 960,
          scale: platform == TargetPlatform.iOS ? 2 : 1,
          platform: platform,
          direction: TextDirection.rtl,
        );
        Future<void> openDelete() async {
          await _tap(tester, find.byKey(ValueKey(('theme-actions', moss.id))));
          await _tap(tester, find.byKey(ValueKey(('delete-theme', moss.id))));
        }

        await openDelete();
        expect(find.text('Delete “Moss”?'), findsOneWidget);
        await _tap(tester, find.widgetWithText(DButton, 'Cancel'));
        expect(_preferences(shell), initial);
        await openDelete();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(DAlertDialogContent), findsNothing);
        expect(_preferences(shell), initial);

        await openDelete();
        await _tap(tester, find.widgetWithText(DButton, 'Delete'));
        final after = _preferences(shell);
        expect(after.customThemes, [kept]);
        expect(after.source, ForumThemeSource.forum);
        expect(await shell.forumSettings.store.loadThemes(_site), after);
        expect(shell.forumSettings.themesFor('https://b.example'), initial);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Cancel, or leaving the page, puts the saved theme back in the app',
    (tester) async {
      final shell = controller();
      addTearDown(shell.dispose);
      final moss = _saved('custom-moss', 'Moss', 'wcag');
      final initial = ForumThemePreferences().save(moss);
      await shell.forumSettings.setThemes(_site, initial);
      await pumpSettings(tester, shell);
      final saved = shell.forumSettings.appearanceFor(_site, null);
      expect(_appTheme(tester).colorScheme.primary, const Color(0xff0033cc));

      Future<void> edit() async {
        await _tap(tester, find.byKey(ValueKey(('edit-theme', moss.id))));
        await tester.ensureVisible(_input('accent'));
        await tester.enterText(_input('accent'), '#39845B');
        await tester.pumpAndSettle();
        expect(_appTheme(tester).colorScheme.primary, const Color(0xff39845b));
        expect(_preferences(shell), initial);
      }

      await edit();
      await _tap(tester, find.byKey(const ValueKey('theme-cancel')));
      expect(_appTheme(tester).colorScheme.primary, const Color(0xff0033cc));
      expect(shell.forumSettings.appearanceFor(_site, null), saved);

      await edit();
      await tester.pumpWidget(const SizedBox());
      expect(shell.forumSettings.appearanceFor(_site, null), saved);
      expect(_preferences(shell), initial);
      expect(await shell.forumSettings.store.loadThemes(_site), initial);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'duplicate adds a copy without applying it and copy puts the theme on '
    'the clipboard',
    (tester) async {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final shell = controller();
      addTearDown(shell.dispose);
      final moss = _saved('custom-moss', 'Moss', 'clover-dark');
      await shell.forumSettings.setThemes(
        _site,
        ForumThemePreferences().save(moss),
      );
      await pumpSettings(tester, shell);
      await _tap(tester, find.byKey(ValueKey(('theme-actions', moss.id))));
      await _tap(tester, find.byKey(ValueKey(('duplicate-theme', moss.id))));
      final preferences = _preferences(shell);
      expect(preferences.customThemes.map((theme) => theme.name), [
        'Moss',
        'Moss copy',
      ]);
      expect(preferences.customId, moss.id);

      await _tap(tester, find.byKey(ValueKey(('theme-actions', moss.id))));
      await _tap(tester, find.byKey(ValueKey(('copy-theme', moss.id))));
      expect(copied, startsWith('```discourse-theme\n'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the font is every forum\'s, applies with every source and '
      'never changes it', (tester) async {
    final shell = controller();
    addTearDown(shell.dispose);
    await pumpSettings(tester, shell);
    expect(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is SettingsSection && widget.title == 'Font',
        ),
        matching: find.text('All forums'),
      ),
      findsOneWidget,
    );
    await _tap(tester, find.byKey(const ValueKey('appearance-font-lato')));
    expect(shell.forumSettings.shared.font, ForumFont.lato);
    expect(_preferences(shell).source, ForumThemeSource.forum);
    String? family() => Theme.of(
      tester.element(find.byType(ForumSettingsPage)),
    ).textTheme.bodyMedium!.fontFamily;
    expect(family(), 'Lato');
    await _tap(tester, _choice('wcag'));
    expect(shell.forumSettings.shared.font, ForumFont.lato);
    expect(family(), 'Lato');
    await _tap(tester, _choice('forum'));
    expect(shell.forumSettings.shared.font, ForumFont.lato);
    expect(_preferences(shell).presets, {Brightness.light: 'wcag'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('a font and a preset chosen before the page redraws both stay', (
    tester,
  ) async {
    final shell = controller();
    addTearDown(shell.dispose);
    await pumpSettings(tester, shell);
    tester.view.physicalSize = const Size(960, 2400);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('appearance-font-lato')));
    await tester.tap(_choice('wcag'));
    await tester.pumpAndSettle();
    expect(shell.forumSettings.shared.font, ForumFont.lato);
    expect(_preferences(shell).presets, {Brightness.light: 'wcag'});
    expect(
      await shell.forumSettings.store.loadThemes(_site),
      _preferences(shell),
    );
    expect(
      (await shell.forumSettings.store.loadAppearance()).font,
      ForumFont.lato,
    );
    expect(tester.takeException(), isNull);
  });
}
