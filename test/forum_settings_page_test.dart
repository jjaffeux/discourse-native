import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/data/scalar_preference_repository.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/shared_appearance.dart';
import 'package:discourse_native/src/shell/forum_settings_page.dart';
import 'package:discourse_native/src/shell/forum_theme_editor.dart';
import 'package:discourse_native/src/shell/mobile_shell.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';
import 'support/theme_settings.dart';

void main() {
  setUpAll(() async {
    if (Platform.environment['OFFLINE_FONTS_RENDER_DIR'] == null) return;
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face in entry['fonts'] as List<dynamic>) {
        loader.addFont(
          rootBundle.load((face as Map<String, dynamic>)['asset'] as String),
        );
      }
      await loader.load();
    }
  });

  mobileSettingsPanelClipTests();

  testWidgets('the Settings title carries the gear mark', (tester) async {
    final shell = controller();
    addTearDown(shell.dispose);
    await pumpSettings(tester, shell);
    final heading = find.ancestor(
      of: find.text('Settings'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(
        of: heading.first,
        matching: find.byWidgetPredicate(
          (widget) => widget is DIcon && widget.icon == DIcons.gear,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'offline font roles and the accessibility switch share persisted choices',
    (tester) async {
      final store = ForumSettingsStore.memory();
      final shell = controller(forumSettingsStore: store);
      addTearDown(shell.dispose);
      await pumpSettings(tester, shell);
      await _openSection(tester, 'Display');
      for (final (font, role) in [
        ('lora', 'interface'),
        ('openDyslexic', 'reading'),
      ]) {
        final choice = find.byKey(ValueKey('display-font-$font-$role'));
        await tester.ensureVisible(choice);
        await tester.pumpAndSettle();
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(tester.widget<DToggle>(choice).pressed, isTrue);
      }
      expect(shell.forumSettings.shared.interfaceFont, ForumFont.lora);
      expect(shell.forumSettings.shared.readingFont, ForumFont.openDyslexic);
      final theme = Theme.of(tester.element(find.byType(ForumSettingsPage)));
      expect(theme.textTheme.bodyMedium!.fontFamily, 'Lora');
      expect(theme.textTheme.bodyLarge!.fontFamily, 'OpenDyslexic');

      final restored = controller(forumSettingsStore: store);
      addTearDown(restored.dispose);
      await restored.forumSettings.loadShared(['https://a.example']);
      expect(restored.forumSettings.shared, shell.forumSettings.shared);
      await _openSection(tester, 'Accessibility');
      final toggle = find.byKey(
        const ValueKey('dyslexia-friendly-font-switch'),
      );
      expect(tester.widget<DSwitchTile>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(shell.forumSettings.shared.usesOpenDyslexicForBoth, isTrue);
      expect((await store.loadAppearance()).usesOpenDyslexicForBoth, isTrue);
      expect(
        Theme.of(tester.element(toggle)).textTheme.bodyMedium!.fontFamily,
        'OpenDyslexic',
      );
      expect(
        Theme.of(tester.element(toggle)).textTheme.bodyLarge!.fontFamily,
        'OpenDyslexic',
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(shell.forumSettings.shared.interfaceFont, ForumFont.system);
      expect(shell.forumSettings.shared.readingFont, ForumFont.system);
      expect((await store.loadAppearance()).usesOpenDyslexicForBoth, isFalse);

      for (final role in ['interface', 'reading']) {
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('dyslexia-friendly-font-display')),
        );
        await tester.pumpAndSettle();
        final lora = find.byKey(ValueKey('display-font-lora-$role'));
        await tester.ensureVisible(lora);
        await tester.pumpAndSettle();
        await tester.tap(lora);
        await tester.pumpAndSettle();
        await _openSection(tester, 'Accessibility');
        expect(tester.widget<DSwitchTile>(toggle).value, isFalse);
        expect(
          shell.forumSettings.shared.interfaceFont,
          role == 'interface' ? ForumFont.lora : ForumFont.openDyslexic,
        );
        expect(
          shell.forumSettings.shared.readingFont,
          role == 'reading' ? ForumFont.lora : ForumFont.openDyslexic,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dyslexia-friendly font has one switch target and keyboard activation',
    (tester) async {
      final shell = controller();
      addTearDown(shell.dispose);
      final semantics = tester.ensureSemantics();
      try {
        await pumpSettings(tester, shell, disableAnimations: true);
        await _openSection(tester, 'Accessibility');
        final toggle = find.byKey(
          const ValueKey('dyslexia-friendly-font-switch'),
        );
        final display = find.byKey(
          const ValueKey('dyslexia-friendly-font-display'),
        );
        final node = tester.getSemantics(toggle);
        expect(node.label, contains('Dyslexia-friendly font'));
        expect(
          node.getSemanticsData().flagsCollection.isToggled,
          ui.Tristate.isFalse,
        );
        expect(
          node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isTrue,
        );
        expect(
          find.descendant(of: toggle, matching: find.byType(DButton)),
          findsNothing,
        );
        expect(
          tester
              .getSemantics(display)
              .getSemanticsData()
              .flagsCollection
              .isButton,
          isTrue,
        );
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(
          tester
              .getSemantics(toggle)
              .getSemanticsData()
              .flagsCollection
              .isToggled,
          ui.Tristate.isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(shell.forumSettings.shared.usesOpenDyslexicForBoth, isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(shell.forumSettings.shared.usesOpenDyslexicForBoth, isTrue);
        for (final animated in tester.widgetList<AnimatedContainer>(
          find.descendant(of: toggle, matching: find.byType(AnimatedContainer)),
        )) {
          expect(animated.duration, Duration.zero);
        }
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'failed dyslexia-friendly font writes restore the switch and show a toast',
    (tester) async {
      final persistence = _FontPersistence();
      final shell = controller(
        forumSettingsStore: ForumSettingsStore(persistence: persistence),
      );
      addTearDown(shell.dispose);
      await shell.forumSettings.loadShared(['https://a.example']);
      await pumpSettings(tester, shell);
      await _openSection(tester, 'Accessibility');
      persistence.failWrites = true;
      final toggle = find.byKey(
        const ValueKey('dyslexia-friendly-font-switch'),
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<DSwitchTile>(toggle).value, isFalse);
      expect(shell.forumSettings.shared, SharedAppearance.defaults);
      expect(find.text('Could not save the font.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (name, width, panelWidth, scale, direction) in [
    ('desktop', 1200.0, 620.0, 1.0, TextDirection.ltr),
    ('mobile', 390.0, 390.0, 1.0, TextDirection.ltr),
    ('mobile-large-rtl', 360.0, 360.0, 2.0, TextDirection.rtl),
  ]) {
    testWidgets('offline font controls remain usable at $name', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
      final shell = controller();
      addTearDown(shell.dispose);
      await pumpSettings(
        tester,
        shell,
        width: width,
        panelWidth: panelWidth,
        scale: scale,
        direction: direction,
        disableAnimations: true,
      );
      await _openSection(tester, 'Accessibility');
      final toggle = find.byKey(
        const ValueKey('dyslexia-friendly-font-switch'),
      );
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(shell.forumSettings.shared.usesOpenDyslexicForBoth, isTrue);
      expect(toggle.hitTestable(), findsOneWidget);
      await _captureFonts(tester, '$name-accessibility');
      final display = find.byKey(
        const ValueKey('dyslexia-friendly-font-display'),
      );
      await tester.ensureVisible(display);
      await tester.pumpAndSettle();
      await tester.tap(display);
      await tester.pumpAndSettle();
      for (final font in ['lora', 'openDyslexic']) {
        final choice = find.byKey(ValueKey('display-font-$font-interface'));
        await tester.ensureVisible(choice);
        await tester.pumpAndSettle();
        expect(choice.hitTestable(), findsOneWidget);
        final preview = find.descendant(
          of: find.byKey(ValueKey('display-font-$font')),
          matching: find.text('The quick brown fox jumps over the lazy dog.'),
        );
        expect(
          tester.widget<Text>(preview).style!.fontFamily,
          font == 'lora' ? 'Lora' : 'OpenDyslexic',
        );
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(tester.widget<DToggle>(choice).pressed, isTrue);
        await Scrollable.ensureVisible(
          tester.element(find.byKey(ValueKey('display-font-$font'))),
          alignment: .2,
        );
        await tester.pumpAndSettle();
        await _captureFonts(tester, '$name-$font-choice');
      }
      expect(tester.takeException(), isNull);
    });
  }
  for (final (bottom, scale) in [(0.0, 1.0), (34.0, 1.0), (34.0, 2.0)]) {
    testWidgets(
      'mobile settings clear the dock at the scroll end ($bottom, $scale)',
      (tester) async {
        tester.view.padding = FakeViewPadding(top: 44, bottom: bottom);
        tester.view.viewPadding = FakeViewPadding(top: 44, bottom: bottom);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        // A second forum gives the Themes tab its last control, the one that
        // copies a theme to every other forum.
        await pumpShell(
          tester,
          phone,
          instances: [instance('a.example'), instance('b.example')],
        );
        final shell = ShellScope.read(
          tester.element(find.byType(MobileForumRoot)),
        );
        shell.openCurrentSettings();
        await tester.pumpAndSettle();

        final page = find.byType(ForumSettingsPage);
        final dock = find.byKey(const ValueKey('mobile-bottom-bar'));
        Future<void> scrollToEnd(Finder control) async {
          final scrollable = find
              .ancestor(of: control, matching: find.byType(Scrollable))
              .first;
          final position = tester.state<ScrollableState>(scrollable).position;
          position.jumpTo(position.maxScrollExtent);
          DScrollChrome.maybeOf(tester.element(page))!.reveal();
          await tester.pumpAndSettle();
          expect(position.pixels, closeTo(position.maxScrollExtent, .01));
          expect(
            tester.getRect(control).bottom,
            greaterThan(tester.getRect(scrollable).top),
          );
          expect(
            tester.getRect(control).bottom,
            lessThanOrEqualTo(tester.getRect(dock).top - 16),
          );
          expect(tester.takeException(), isNull);
        }

        final rawMarkdown = find.byKey(
          const ValueKey('raw-markdown-composers-switch'),
        );
        await scrollToEnd(rawMarkdown);
        // At large text sizes the row can be taller than the viewport.
        await tester.tapAt(
          tester.getBottomRight(rawMarkdown) - const Offset(16, 16),
        );
        await tester.pumpAndSettle();
        expect(shell.appSettings.rawMarkdownComposers, isTrue);

        await tester.ensureVisible(find.text('Themes'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Themes'));
        await tester.pumpAndSettle();
        await scrollToEnd(find.byKey(const ValueKey('theme-use-everywhere')));

        await tester.ensureVisible(find.text('Accessibility'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Accessibility'));
        await tester.pumpAndSettle();
        final dyslexiaFont = find.byKey(
          const ValueKey('dyslexia-friendly-font-switch'),
        );
        await tester.ensureVisible(dyslexiaFont);
        await tester.pumpAndSettle();
        final fontViewport = find
            .ancestor(of: dyslexiaFont, matching: find.byType(Scrollable))
            .first;
        final visibleFontRow = tester
            .getRect(dyslexiaFont)
            .intersect(tester.getRect(fontViewport));
        expect(visibleFontRow.height, greaterThan(0));
        await tester.tapAt(visibleFontRow.center);
        await tester.pumpAndSettle();
        expect(shell.forumSettings.shared.usesOpenDyslexicForBoth, isTrue);
        final disableGifs = find.byKey(
          const ValueKey('disable-gif-animations-switch'),
        );
        await scrollToEnd(disableGifs);
        await tester.tapAt(
          tester.getBottomRight(disableGifs) - const Offset(16, 16),
        );
        await tester.pumpAndSettle();
        expect(shell.appSettings.disableGifAnimations, isTrue);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }

  testWidgets('Display exposes raw Markdown on narrow screens', (tester) async {
    final shell = controller();
    addTearDown(shell.dispose);
    await pumpSettings(
      tester,
      shell,
      width: 360,
      panelWidth: 360,
      scale: 2,
      direction: TextDirection.rtl,
    );
    await tester.tap(find.text('Display'));
    await tester.pumpAndSettle();
    final rawMarkdown = find.byKey(
      const ValueKey('raw-markdown-composers-switch'),
    );
    await tester.ensureVisible(rawMarkdown);
    await tester.pumpAndSettle();
    expect(rawMarkdown.hitTestable(), findsOneWidget);
    await tester.tap(rawMarkdown);
    await tester.pumpAndSettle();
    expect(shell.appSettings.rawMarkdownComposers, isTrue);
    expect(tester.widget<DSwitchTile>(rawMarkdown).value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Display changes the shared font, icons, and text scale', (
    tester,
  ) async {
    final shell = controller();
    addTearDown(shell.dispose);
    await pumpSettings(tester, shell);
    await tester.tap(find.text('Display'));
    await tester.pumpAndSettle();

    final systemFont = find.byKey(
      const ValueKey('display-font-system-reading'),
    );
    expect(tester.widget<DToggle>(systemFont).pressed, isTrue);
    expect(
      tester.getSize(find.byKey(const ValueKey('text-size-decrease'))).height,
      28,
    );
    await tester.tap(find.byKey(const ValueKey('display-font-lato-reading')));
    await tester.pumpAndSettle();
    expect(shell.forumSettings.shared.readingFont, ForumFont.lato);
    expect(shell.forumSettings.shared.interfaceFont, ForumFont.system);
    expect(tester.widget<DToggle>(systemFont).pressed, isFalse);
    await tester.tap(
      find.byKey(const ValueKey('display-font-openSans-interface')),
    );
    await tester.pumpAndSettle();
    expect(shell.forumSettings.shared.interfaceFont, ForumFont.openSans);
    expect(shell.forumSettings.shared.readingFont, ForumFont.lato);
    expect(
      find.byKey(const ValueKey('settings-content-width')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('display-icon-set-lucide')),
    );
    final defaultIcons = find.byKey(
      const ValueKey('display-icon-set-defaultSet'),
    );
    expect(tester.widget<DItem>(defaultIcons).selected, isTrue);
    expect(
      tester.widget<DItem>(defaultIcons).selectionStyle,
      DItemSelectionStyle.tinted,
    );
    final previewIcons = find.descendant(
      of: defaultIcons,
      matching: find.byType(DIcon),
    );
    expect(previewIcons, findsNWidgets(8));
    final centers = [
      for (var index = 0; index < 8; index++)
        tester.getCenter(previewIcons.at(index)),
    ];
    for (var index = 0; index < 4; index++) {
      expect(centers[index].dx, closeTo(centers[index + 4].dx, 0.001));
      expect(centers[index].dy, closeTo(centers[0].dy, 0.001));
      expect(centers[index + 4].dy, closeTo(centers[4].dy, 0.001));
    }
    await tester.tap(find.byKey(const ValueKey('display-icon-set-lucide')));
    await tester.pumpAndSettle();
    expect(shell.forumSettings.shared.iconSet, DIconSet.lucide);
    expect(tester.widget<DItem>(defaultIcons).selected, isFalse);

    await tester.ensureVisible(
      find.byKey(const ValueKey('text-size-increase')),
    );
    await tester.tap(find.byKey(const ValueKey('text-size-increase')));
    await tester.pumpAndSettle();
    expect(shell.appSettings.textScale, AppTextScale.percent105);
    await tester.tap(find.byKey(const ValueKey('text-size-reset')));
    await tester.pumpAndSettle();
    expect(shell.appSettings.textScale, AppTextScale.percent100);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Display remains usable at narrow width with large RTL text', (
    tester,
  ) async {
    final shell = controller();
    addTearDown(shell.dispose);
    await pumpSettings(
      tester,
      shell,
      width: 360,
      panelWidth: 360,
      scale: 2,
      direction: TextDirection.rtl,
    );
    await tester.tap(find.text('Display'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('display-font-system')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-content-width')), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('display-icon-set-tabler')),
    );
    await tester.tap(find.byKey(const ValueKey('display-icon-set-tabler')));
    await tester.pumpAndSettle();
    expect(shell.forumSettings.shared.iconSet, DIconSet.tabler);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the forum default has no editing controls or duplicate mode switch',
    (tester) async {
      final shell = controller();
      addTearDown(shell.dispose);
      await pumpSettings(tester, shell);
      expect(
        tester
            .widget<DToggleGroup<AppThemeMode>>(
              find.byKey(const ValueKey('appearance-mode')),
            )
            .values,
        [AppThemeMode.system],
      );
      // The font is an app setting, chosen in Settings.
      expect(find.text('Font'), findsNothing);
      expect(find.byKey(const ValueKey('theme-source')), findsNothing);
      expect(
        tester
            .widget<DItem>(
              find.byKey(const ValueKey(('theme-choice', 'forum'))),
            )
            .selected,
        isTrue,
      );
      final editButton = tester.widget<DButton>(
        find.byKey(const ValueKey(('edit-theme', 'forum'))),
      );
      expect(editButton.variant, DButtonVariant.outline);
      expect(
        find.byKey(const ValueKey(('theme-actions', 'forum'))),
        findsNothing,
      );
      for (final control in ['appearance-theme-select', 'theme-sidebar']) {
        expect(find.byKey(ValueKey(control)), findsNothing, reason: control);
      }
      // Effects apply to every forum, so they live in the app's Settings.
      for (final control in [
        'theme-tint',
        'theme-opacity',
        'theme-texture',
        'theme-intensity',
      ]) {
        expect(find.byKey(ValueKey(control)), findsNothing, reason: control);
      }
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('appearance-mode'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('theme-picker'))).dy,
        ),
      );
      expect(find.byKey(const ValueKey('theme-shown-mode')), findsNothing);
      expect(
        shell.forumSettings.themeModeFor('https://a.example'),
        AppThemeMode.system,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('theme pencils appear on hover or for the selected row', (
    tester,
  ) async {
    final shell = controller();
    addTearDown(shell.dispose);
    await pumpSettings(tester, shell);

    for (final id in [
      'forum',
      for (final preset in forumThemePresets) preset.id,
    ]) {
      final pencil = find.byKey(ValueKey(('edit-theme', id)));
      expect(pencil, findsOneWidget);
      expect(tester.widget<DButton>(pencil).variant, DButtonVariant.outline);
      expect(
        tester
            .widget<Opacity>(
              find.byKey(ValueKey(('edit-theme-visibility', id))),
            )
            .opacity,
        id == 'forum' ? 1 : 0,
      );
      expect(find.byKey(ValueKey(('theme-actions', id))), findsNothing);
    }
    expect(find.text('Customize'), findsNothing);

    final presetRow = find.byKey(const ValueKey(('theme-choice', 'wcag')));
    final presetVisibility = find.byKey(
      const ValueKey(('edit-theme-visibility', 'wcag')),
    );
    await tester.ensureVisible(presetRow);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(presetRow));
    await tester.pump();
    expect(tester.widget<Opacity>(presetVisibility).opacity, 1);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(tester.widget<Opacity>(presetVisibility).opacity, 0);

    await tester.tap(presetRow);
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(presetVisibility).opacity, 1);
    await tester.tap(find.byKey(const ValueKey(('edit-theme', 'wcag'))));
    await tester.pumpAndSettle();
    expect(find.byType(ForumThemeEditor), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
      testWidgets(
        'full settings supports narrow RTL large text in $brightness $platform',
        (tester) async {
          final shell = controller();
          addTearDown(shell.dispose);
          await shell.forumSettings.setThemeMode(
            'https://a.example',
            brightness == Brightness.light
                ? AppThemeMode.light
                : AppThemeMode.dark,
          );
          final semantics = tester.ensureSemantics();

          await pumpSettings(
            tester,
            shell,
            width: 360,
            scale: 2,
            platform: platform,
            direction: TextDirection.rtl,
          );
          expect(find.byType(DDialogContent), findsNothing);
          expect(find.byType(DSheetContent), findsNothing);
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }
}

void mobileSettingsPanelClipTests() {
  for (final translucent in [false, true]) {
    testWidgets(
      'mobile settings keep font cards inside the rounded body, translucent $translucent',
      (tester) async {
        const notificationChannel = MethodChannel(
          'org.discourse.native/notification_opens',
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          notificationChannel,
          (_) async => null,
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            notificationChannel,
            null,
          );
        });
        tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
        await tester.binding.setSurfaceSize(const Size(430, 932));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpShell(
          tester,
          const Size(430, 932),
          instances: [instance('a.example')],
        );
        final shell = ShellScope.read(
          tester.element(find.byType(MobileForumRoot)),
        );
        shell.openCurrentSettings();
        await shell.forumSettings.setThemeMode(
          'https://a.example',
          AppThemeMode.dark,
        );
        await shell.forumSettings.setThemes(
          'https://a.example',
          ForumThemePreferences.preset('dracula'),
        );
        if (translucent) {
          await shell.forumSettings.setShared(
            shell.forumSettings.shared.copyWith(
              effects: const ForumBackground.appearance(transparency: .3),
            ),
          );
        }
        await tester.pumpAndSettle();

        final panel = find.byKey(const ValueKey('mobile-content-panel'));
        final font = find.byKey(const ValueKey('display-font-system'));
        final viewport = find
            .ancestor(of: font, matching: find.byType(Scrollable))
            .first;
        final position = tester.state<ScrollableState>(viewport).position;
        List<int>? outsideBefore;
        List<int>? interiorBefore;
        for (final offset in [0.0, 100.0]) {
          position.jumpTo(offset);
          DScrollChrome.maybeOf(
            tester.element(find.byType(ForumSettingsPage)),
          )!.reveal();
          await tester.pumpAndSettle();
          await _captureFonts(
            tester,
            'mobile-settings-body-$translucent-${offset.round()}',
          );
          final rect = tester.getRect(panel);
          await tester.runAsync(() async {
            final builder = ui.SceneBuilder();
            tester.binding.renderViews.first.debugLayer!.addToScene(builder);
            final scene = builder.build();
            final image = await scene.toImage(430, 932);
            try {
              final bytes = (await image.toByteData())!.buffer.asUint8List();
              if (offset == 0) {
                for (final key in [
                  'text-size-decrease',
                  'display-font-system-interface',
                ]) {
                  final bounds = tester.getRect(find.byKey(ValueKey(key)));
                  final backdrop = bounds.topLeft + const Offset(8, -8);
                  final backdropPixel =
                      (backdrop.dy.floor() * image.width +
                          backdrop.dx.floor()) *
                      4;
                  var rimContrast = 0;
                  for (var dy = 0; dy < 8; dy++) {
                    for (var dx = 0; dx < 8; dx++) {
                      for (final point in [
                        Offset(bounds.left + dx, bounds.top + dy),
                        Offset(bounds.right - dx - 1, bounds.top + dy),
                        Offset(bounds.left + dx, bounds.bottom - dy - 1),
                        Offset(bounds.right - dx - 1, bounds.bottom - dy - 1),
                      ]) {
                        final pixel =
                            (point.dy.floor() * image.width +
                                point.dx.floor()) *
                            4;
                        for (var channel = 0; channel < 3; channel++) {
                          final contrast =
                              (bytes[pixel + channel] -
                                      bytes[backdropPixel + channel])
                                  .abs();
                          if (contrast > rimContrast) rimContrast = contrast;
                        }
                      }
                    }
                  }
                  expect(
                    rimContrast,
                    greaterThan(8),
                    reason: '$key keeps its visible surface inside the panel.',
                  );
                }
              }
              // The body ends at the screen edge, so each bottom corner is
              // read just inside it, well outside the rounded clip.
              final outside = <int>[];
              for (final x in [rect.left + 2, rect.right - 3]) {
                final corner =
                    ((rect.bottom.floor() - 3) * image.width + x.floor()) * 4;
                outside.addAll(bytes.sublist(corner, corner + 3));
              }
              final interior = <int>[];
              for (var y = 450; y < 800; y += 4) {
                for (var x = 24; x < 406; x += 4) {
                  final pixel = (y * image.width + x) * 4;
                  interior.addAll(bytes.sublist(pixel, pixel + 3));
                }
              }
              if (outsideBefore == null) {
                outsideBefore = outside;
                interiorBefore = interior;
              } else {
                expect(
                  outside,
                  outsideBefore,
                  reason:
                      'Moving font cards cannot change either outside corner.',
                );
                var changed = 0;
                for (var i = 0; i < interior.length; i++) {
                  if (interior[i] != interiorBefore![i]) changed++;
                }
                expect(
                  changed,
                  greaterThan(1000),
                  reason:
                      'The rendered content must actually move behind the fixed corners.',
                );
              }
            } finally {
              image.dispose();
              scene.dispose();
            }
          });
        }
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({TargetPlatform.iOS}),
    );
  }
}

Future<void> _openSection(WidgetTester tester, String label) async {
  final section = find.text(label).first;
  await tester.ensureVisible(section);
  await tester.pumpAndSettle();
  await tester.tap(section);
  await tester.pumpAndSettle();
}

Future<void> _captureFonts(WidgetTester tester, String name) async {
  final path = Platform.environment['OFFLINE_FONTS_RENDER_DIR'];
  if (path == null) return;
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final builder = ui.SceneBuilder();
    view.debugLayer!.addToScene(builder);
    final scene = builder.build();
    final image = await scene.toImage(
      view.size.width.round(),
      view.size.height.round(),
    );
    scene.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(path).create(recursive: true);
    await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class _FontPersistence implements ScalarPreferencePersistence<String> {
  final _values = <String, String>{};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<bool> write(String key, String value) async {
    if (failWrites) return false;
    _values[key] = value;
    return true;
  }
}
