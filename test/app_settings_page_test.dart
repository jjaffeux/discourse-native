import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/data/scalar_preference_repository.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/shell/app_settings_page.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/finders.dart';

/// The Text size readout, which the effects' percentages must not be
/// mistaken for.
Finder _textSize(String value) => find.descendant(
  of: find.byKey(const ValueKey('text-size-value')),
  matching: find.text(value),
);

void main() {
  testWidgets('settings switch row responds to mouse hover in the modal', (
    tester,
  ) async {
    final strategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pumpPage(tester, controller);

    final tile = find.byKey(const ValueKey('limit-content-size-switch'));
    final row = find
        .descendant(of: tile, matching: find.byType(AnimatedContainer))
        .first;
    Color? fill() =>
        (tester.widget<AnimatedContainer>(row).decoration! as BoxDecoration)
            .color;
    expect(fill(), isNull);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Limit content size')));
    await tester.pumpAndSettle();
    expect(fill(), isNotNull);
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(fill(), isNull);
    await mouse.removePointer();
  });

  testWidgets('the app settings form is centered and updates immediately', (
    tester,
  ) async {
    final persistence = MemoryAppSettingsPersistence();
    final controller = _controller(appSettingsPersistence: persistence);
    addTearDown(controller.dispose);
    await controller.appSettings.load();

    await _pumpPage(tester, controller, size: const Size(1100, 700));

    expect(find.byType(DDialogContent), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(DFieldGroup), findsOneWidget);
    expect(find.byType(DButtonGroup), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('app-settings-form'))).width,
      568,
    );
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Appearance'), findsNothing);
    expect(find.text('System'), findsNothing);
    expect(find.text('Limit content size'), findsOneWidget);
    expect(find.text('Text size'), findsOneWidget);
    expect(find.text('Choose a comfortable reading size.'), findsNothing);
    expect(find.text('Topic list'), findsNothing);
    expect(_textSize('100%'), findsOneWidget);
    expect(find.text('Disable GIF animations'), findsOneWidget);
    expect(
      find.textContaining('reading lane is limited to 825 px'),
      findsNothing,
    );
    expect(find.textContaining('Save'), findsNothing);

    var segmented = tester.widget<DSwitchTile>(
      find.byKey(const ValueKey('limit-content-size-switch')),
    );
    expect(segmented.value, false);

    expect(find.byKey(const ValueKey('topic-list-mode-toggle')), findsNothing);

    await tester.tap(find.text('Limit content size'));
    await tester.pump();

    expect(controller.appSettings.limitContentSize, true);
    expect(persistence.limitContentSize, true);
    segmented = tester.widget<DSwitchTile>(
      find.byKey(const ValueKey('limit-content-size-switch')),
    );
    expect(segmented.value, true);

    await tester.tap(find.byKey(const ValueKey('text-size-increase')));
    await tester.pump();

    expect(controller.appSettings.textScale, AppTextScale.percent110);
    expect(persistence.textScale, AppTextScale.percent110.name);
    expect(_textSize('110%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('text-size-reset')));
    await tester.pump();

    expect(controller.appSettings.textScale, AppTextScale.percent100);
    expect(persistence.textScale, AppTextScale.percent100.name);
    expect(_textSize('100%'), findsOneWidget);

    await tester.ensureVisible(find.text('Disable GIF animations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disable GIF animations'));
    await tester.pump();

    expect(controller.appSettings.disableGifAnimations, isTrue);
    expect(persistence.disableGifAnimations, isTrue);
  });

  testWidgets(
    'opacity and texture are in Settings and apply to every forum, and the '
    'tint is left to themes',
    (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await _pumpPage(tester, controller, size: const Size(1100, 900));
      final settings = controller.forumSettings;
      DSlider slider(String name) =>
          tester.widget(find.byKey(ValueKey('theme-$name')));
      expect(slider('intensity').onChanged, isNull);
      expect(find.byKey(const ValueKey('theme-tint')), findsNothing);
      final opacity = find.byKey(const ValueKey('theme-opacity'));
      await tester.ensureVisible(opacity);
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getTopLeft(opacity) + const Offset(1, 13));
      await tester.pumpAndSettle();
      expect(find.text('70%'), findsOneWidget);
      await tester.tap(find.text('Paper'));
      await tester.pumpAndSettle();
      expect(slider('intensity').onChanged, isNotNull);

      final effects = settings.shared.effects;
      expect(effects.transparency, .3);
      expect(effects.effect, ForumBackgroundEffect.paper);
      expect((await settings.store.loadAppearance()).effects, effects);
      // A forum on its own colours draws the same effects.
      final forum = SiteAppearance(
        base: forumThemePresets.first.resolve(Brightness.light),
      );
      for (final site in ['https://a.example', 'https://b.example']) {
        expect(
          settings.appearanceFor(site, forum)!.base!.background,
          effects,
          reason: site,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('two effects chosen before Settings redraws both stay', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pumpPage(tester, controller, size: const Size(1100, 1400));
    final opacity = find.byKey(const ValueKey('theme-opacity'));
    await tester.tapAt(tester.getTopLeft(opacity) + const Offset(1, 13));
    await tester.tap(find.text('Paper'));
    await tester.pumpAndSettle();
    final effects = controller.forumSettings.shared.effects;
    expect(effects.transparency, .3);
    expect(effects.effect, ForumBackgroundEffect.paper);
    expect(
      (await controller.forumSettings.store.loadAppearance()).effects,
      effects,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an effect that cannot be saved is put back and said so', (
    tester,
  ) async {
    final controller = _controller(
      forumSettingsStore: ForumSettingsStore(
        persistence: _FailingPersistence(),
      ),
    );
    addTearDown(controller.dispose);
    await _pumpPage(tester, controller, size: const Size(1100, 1400));
    await tester.tap(find.text('Paper'));
    await tester.pumpAndSettle();
    expect(
      controller.forumSettings.shared.effects.effect,
      ForumBackgroundEffect.normal,
    );
    expect(find.text('Could not save the effects.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings heading grows to fit 200% text without clipping', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pumpPage(tester, controller, scale: 2, size: const Size(800, 800));
    final title = tester.getRect(find.text('Settings'));
    final header = tester.getRect(
      find.byKey(const ValueKey('app-settings-header')),
    );
    expect(header.height, greaterThanOrEqualTo(title.height));
    expect(tester.getSize(_textSize('100%')).height, closeTo(40, 0.001));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('app-settings-close')));
    await tester.pumpAndSettle();
    expect(find.byType(AppSettingsModal), findsNothing);
  });

  testWidgets('the form and Close control expose useful semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = _controller();
    addTearDown(controller.dispose);
    try {
      await controller.appSettings.load();
      await _pumpPage(tester, controller);

      expect(find.bySemanticsLabel('Close settings'), findsOneWidget);
      for (final (label, level) in [
        ('Settings', 1),
        ('Text size', 2),
        ('Font', 2),
      ]) {
        expect(
          tester.getSemantics(find.text(label)).getSemanticsData().headingLevel,
          level,
        );
      }
      expect(
        find.bySemanticsLabel(RegExp('Limit content size')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Decrease text size'), findsOneWidget);
      expect(find.bySemanticsLabel('Increase text size'), findsOneWidget);
      expect(find.bySemanticsLabel('Current text size'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Disable GIF animations')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('app-settings-close')));
      await tester.pumpAndSettle();

      expect(find.byType(AppSettingsModal), findsNothing);
      expect(controller.appSettingsModalOpen, isFalse);
      expect(controller.rootMode, ShellRootMode.forum);
    } finally {
      semantics.dispose();
    }
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets('the font is chosen here for every forum on $platform', (
      tester,
    ) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await _pumpPage(
        tester,
        controller,
        size: const Size(360, 800),
        scale: 2,
        theme: AppTheme.light.copyWith(platform: platform),
        rtl: true,
      );
      expect(tester.takeException(), isNull);

      for (final option in ForumFont.values) {
        final row = find.byKey(ValueKey('appearance-font-${option.name}'));
        expect(tester.widget<DItem>(row).selected, option == ForumFont.system);
        final sample = tester.widget<Text>(
          find.descendant(
            of: row,
            matching: find.text('The quick brown fox jumps over the lazy dog.'),
          ),
        );
        expect(
          sample.style!.fontFamily,
          option.family ??
              ThemeData(platform: platform).textTheme.bodyLarge!.fontFamily,
        );
        expect(
          sample.style!.fontFamilyFallback,
          forumFontFamilyFallback(option.family) ?? const [],
        );
      }

      final lato = find.byKey(const ValueKey('appearance-font-lato'));
      await tester.ensureVisible(lato);
      await tester.tap(lato);
      await tester.pumpAndSettle();
      expect(controller.forumSettings.shared.font, ForumFont.lato);
      expect(
        (await controller.forumSettings.store.loadAppearance()).font,
        ForumFont.lato,
      );
      expect(tester.widget<DItem>(lato).selected, isTrue);
      expect(
        tester
            .widget<DItem>(find.byKey(const ValueKey('appearance-font-system')))
            .selected,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a font that cannot be saved is put back and says so', (
    tester,
  ) async {
    final controller = _controller(
      forumSettingsStore: ForumSettingsStore(
        persistence: _FailingPersistence(),
      ),
    );
    addTearDown(controller.dispose);
    await _pumpPage(tester, controller, size: const Size(800, 1200));

    await tester.tap(find.byKey(const ValueKey('appearance-font-lato')));
    await tester.pumpAndSettle();

    expect(controller.forumSettings.shared.font, ForumFont.system);
    expect(
      tester
          .widget<DItem>(find.byKey(const ValueKey('appearance-font-system')))
          .selected,
      isTrue,
    );
    expect(find.text('Could not save the font.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Diagnostics is the bottom-most rail destination when present', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = _controller();
    addTearDown(controller.dispose);
    await controller.load();
    final diagnostics = await DiagnosticsController.create(
      persistence: MemoryDiagnosticsPersistence(),
    );

    try {
      await _pumpRail(tester, controller, diagnostics: diagnostics);

      final settings = find.byKey(const ValueKey('settings-rail-button'));
      final diagnosticsButton = find.byKey(
        const ValueKey('diagnostics-rail-button'),
      );
      expect(settings, findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
      expect(
        find.descendant(of: settings, matching: find.dIcon(DIcons.gear)),
        findsOneWidget,
      );
      for (final key in [
        'styleguide-rail-button',
        'settings-rail-button',
        'diagnostics-rail-button',
      ]) {
        final control = find.byKey(ValueKey(key));
        final button = tester.widget<DButton>(control);
        expect(button.variant, DButtonVariant.ghost);
        expect(button.size, DButtonSize.large);
        expect(tester.getSize(control), const Size.square(48));
      }
      expect(
        tester.getRect(diagnosticsButton).top,
        greaterThan(tester.getRect(settings).bottom),
      );
      expect(
        tester.getRect(find.byType(InstanceRail)).bottom -
            tester.getRect(diagnosticsButton).bottom,
        6,
      );

      final data = tester.getSemantics(settings).getSemanticsData();
      expect(data.label, 'Settings');
      expect(data.flagsCollection.isButton, isTrue);

      await tester.tap(settings);
      await tester.pumpAndSettle();

      expect(controller.rootMode, ShellRootMode.aggregate);
      expect(controller.aggregateSettingsOpen, isTrue);
      expect(controller.appSettingsModalOpen, isFalse);
    } finally {
      await diagnostics.close();
      semantics.dispose();
    }
  });

  testWidgets('the gear remains available before sites have loaded', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await _pumpRail(tester, controller);

    expect(controller.loadStatus, InstanceLoadStatus.loading);
    expect(find.byKey(const ValueKey('settings-rail-button')), findsOneWidget);
  });

  testWidgets('Settings uses Home colors and responds to system appearance', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final siteTheme = StyleguideTheme.plum.resolve(AppTheme.light);
    await _pumpPage(tester, controller, theme: siteTheme);
    void expectHome(ThemeData expected) {
      for (final finder in [
        find.byType(DDialogContent),
        find.byKey(const ValueKey('limit-content-size-switch')),
        find.byKey(const ValueKey('disable-gif-animations-switch')),
        find.byKey(const ValueKey('text-size-increase')),
      ]) {
        final context = tester.element(finder);
        expect(Theme.of(context).colorScheme, expected.colorScheme);
        expect(
          DTokens.of(context).surface,
          expected.extension<DTokens>()!.surface,
        );
      }
      expect(
        Theme.of(tester.element(find.text('Open settings'))).colorScheme,
        siteTheme.colorScheme,
      );
      expect(controller.rootMode, ShellRootMode.forum);
    }

    expectHome(AppTheme.light);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expectHome(AppTheme.dark);
  });

  testWidgets(
    'narrow Settings supports large RTL text and reachable controls',
    (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await _pumpPage(
        tester,
        controller,
        size: const Size(360, 640),
        scale: 2,
        rtl: true,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Limit content size'));
      await tester.tap(find.text('Limit content size'));
      await tester.pumpAndSettle();
      expect(controller.appSettings.limitContentSize, true);
      await tester.ensureVisible(
        find.byKey(const ValueKey('text-size-increase')),
      );
      await tester.tap(find.byKey(const ValueKey('text-size-increase')));
      await tester.pumpAndSettle();
      expect(controller.appSettings.textScale, AppTextScale.percent110);
      await tester.ensureVisible(find.text('Disable GIF animations'));
      await tester.tap(find.text('Disable GIF animations'));
      await tester.pumpAndSettle();
      expect(controller.appSettings.disableGifAnimations, isTrue);
      await tester.ensureVisible(
        find.byKey(const ValueKey('app-settings-close')),
      );
      await tester.tap(find.byKey(const ValueKey('app-settings-close')));
      await tester.pumpAndSettle();
      expect(find.byType(AppSettingsModal), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

ShellController _controller({
  AppSettingsPersistence? appSettingsPersistence,
  ForumSettingsStore? forumSettingsStore,
}) => ShellController(
  instanceStore: FakeInstanceStore(),
  api: FakeDiscourseApi(),
  authenticator: FakeAuthenticator(),
  drafts: FakeDraftStore(),
  forumTabs: FakeForumTabStore(),
  trackers: FakeSiteTracker.reset(),
  updateStore: FakeUpdateStore(),
  initialRootMode: ShellRootMode.forum,
  appSettingsStore: AppSettingsStore(
    persistence: appSettingsPersistence ?? MemoryAppSettingsPersistence(),
  ),
  forumSettingsStore: forumSettingsStore,
);

class _FailingPersistence implements ScalarPreferencePersistence<String> {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<bool> write(String key, String value) async => false;
}

Future<void> _pumpPage(
  WidgetTester tester,
  ShellController controller, {
  Size size = const Size(800, 600),
  double scale = 1,
  ThemeData? theme,
  bool rtl = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        // The app hosts toasts above every page.
        builder: (context, child) => DToaster(
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: child!,
            ),
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey('open-app-settings'),
              onPressed: () => showAppSettingsModal(context),
              child: const Text('Open settings'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-app-settings')));
  await tester.pumpAndSettle();
}

Future<void> _pumpRail(
  WidgetTester tester,
  ShellController controller, {
  DiagnosticsController? diagnostics,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  Widget rail = const SizedBox(width: 72, child: InstanceRail());
  if (diagnostics != null) {
    rail = DiagnosticsScope(controller: diagnostics, child: rail);
  }
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Align(alignment: Alignment.centerLeft, child: rail),
        ),
      ),
    ),
  );
  await tester.pump();
}
