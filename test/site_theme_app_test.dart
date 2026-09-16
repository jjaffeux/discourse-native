import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/app_settings_page.dart';
import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/color_contrast.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'support/media_pipeline.dart';
import 'support/site_appearance_fixtures.dart';

void main() {
  const siteA = 'https://a.example';
  const siteB = 'https://b.example';

  testWidgets('Escape closes Settings after changing appearance', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      store: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      appSettingsStore: AppSettingsStore(
        persistence: MemoryAppSettingsPersistence(),
      ),
    );
    final controller = _controller(tester);
    await tester.tap(find.byKey(const ValueKey('settings-rail-button')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('appearance-theme-select')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape, character: '\x1b');
    await tester.pumpAndSettle();
    expect(find.byType(DPopoverContent), findsNothing);
    expect(find.byType(AppSettingsModal), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('appearance-theme-select')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(controller.appSettings.themeMode, AppThemeMode.dark);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape, character: '\x1b');
    await tester.pumpAndSettle();

    expect(find.byType(AppSettingsModal), findsNothing);
    expect(controller.appSettingsModalOpen, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('hydrates an injected app-wide settings store on startup', (
    tester,
  ) async {
    final appSettingsStore = AppSettingsStore(
      persistence: MemoryAppSettingsPersistence(
        contentAlignment: 'right',
        textScale: AppTextScale.percent125.name,
        themeMode: AppThemeMode.dark.name,
      ),
    );

    await _pumpApp(
      tester,
      store: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      appSettingsStore: appSettingsStore,
    );

    expect(
      _controller(tester).appSettings.contentAlignment,
      ContentAlignment.right,
    );
    expect(_controller(tester).appSettings.textScale, AppTextScale.percent125);
    expect(_materialApp(tester).themeMode, ThemeMode.dark);
    expect(_activeTheme(tester).brightness, Brightness.dark);
    expect(
      MediaQuery.textScalerOf(
        tester.element(find.byType(AdaptiveShell)),
      ).scale(DiscourseTypography.base),
      moreOrLessEquals(DiscourseTypography.base * 1.25),
    );
  });

  for (final size in [const Size(390, 700), const Size(1200, 800)]) {
    testWidgets('maximum text size lays out the ${size.width}px shell', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final appSettingsStore = AppSettingsStore(
        persistence: MemoryAppSettingsPersistence(
          textScale: AppTextScale.percent200.name,
        ),
      );

      await _pumpApp(
        tester,
        store: FakeInstanceStore([
          const DiscourseInstance(url: siteA, title: 'A very long forum name'),
        ]),
        api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
        appSettingsStore: appSettingsStore,
      );

      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('settings-rail-button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('200%'), findsOneWidget);
    });
  }

  group('appearance loading and persistence', () {
    testWidgets('renders persisted palettes before refreshing them once', (
      tester,
    ) async {
      final stored = siteAppearance(
        accent: const Color(0xFF112233),
        alternateAccent: const Color(0xFF334455),
      );
      final fresh = siteAppearance(
        accent: const Color(0xFF556677),
        alternateAccent: const Color(0xFF778899),
      );
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final store = FakeInstanceStore([
        const DiscourseInstance(
          url: siteA,
          title: 'A',
        ).copyWith(appearance: stored),
      ]);
      final api = FakeDiscourseApi(
        siteAppearances: {siteA: fresh},
        appearanceGate: gate,
      );

      await _pumpApp(tester, store: store, api: api, settle: false);
      await tester.pump();

      var app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.theme?.colorScheme.primary, stored.base?.tertiary);
      expect(app.darkTheme?.colorScheme.primary, stored.alternate?.tertiary);
      expect(app.themeMode, ThemeMode.system);

      gate.complete();
      await tester.pumpAndSettle();

      app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.theme?.colorScheme.primary, fresh.base?.tertiary);
      expect(app.darkTheme?.colorScheme.primary, fresh.alternate?.tertiary);
      expect(api.appearancesRequested, [siteA]);
      expect((await store.load()).single.appearance, fresh);
      expect(store.saveCount, 1);
    });

    testWidgets('swaps site palettes without an intermediate animated theme', (
      tester,
    ) async {
      final first = siteAppearance(accent: const Color(0xFFAA2200));
      final second = siteAppearance(accent: const Color(0xFF0066BB));
      final store = FakeInstanceStore([
        const DiscourseInstance(
          url: siteA,
          title: 'A',
        ).copyWith(appearance: first),
        const DiscourseInstance(
          url: siteB,
          title: 'B',
        ).copyWith(appearance: second),
      ]);

      await _pumpApp(tester, store: store, api: FakeDiscourseApi());
      final controller = _controller(tester);
      expect(
        _materialApp(tester).themeAnimationStyle,
        AnimationStyle.noAnimation,
      );
      expect(_activeTheme(tester).colorScheme.primary, first.base?.tertiary);

      controller.selectInstance(1);
      await tester.pump();
      expect(_activeTheme(tester).colorScheme.primary, second.base?.tertiary);

      controller.selectInstance(0);
      await tester.pump();
      expect(_activeTheme(tester).colorScheme.primary, first.base?.tertiary);
    });

    testWidgets('clears account-derived data on disconnect', (tester) async {
      final appearance = siteAppearance(accent: const Color(0xFF6B21A8));
      final store = FakeInstanceStore([
        const DiscourseInstance(
          url: siteA,
          title: 'A',
          user: DiscourseUser(username: 'sam'),
        ).copyWith(appearance: appearance),
      ]);
      final authenticator = FakeAuthenticator()..keys[siteA] = 'secret';
      await _pumpApp(
        tester,
        store: store,
        api: FakeDiscourseApi(),
        authenticator: authenticator,
      );

      await _controller(tester).disconnectCurrentInstance();
      await tester.pumpAndSettle();

      expect(_controller(tester).currentSiteAppearance, isNull);
      expect((await store.load()).single.appearance, isNull);
      expect(
        _materialApp(tester).theme?.colorScheme.primary,
        AppTheme.light.colorScheme.primary,
      );
    });
  });

  group('active theme selection', () {
    testWidgets('appearance changes the app and open Settings immediately', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final appearance = siteAppearance(
        alternateAccent: const Color(0xFF80CED7),
        mode: SiteAppearanceMode.alternate,
      );
      await _pumpApp(
        tester,
        store: FakeInstanceStore([
          const DiscourseInstance(
            url: siteA,
            title: 'A',
          ).copyWith(appearance: appearance),
        ]),
        api: FakeDiscourseApi(),
      );
      expect(_activeTheme(tester).brightness, Brightness.light);
      await tester.tap(find.byKey(const ValueKey('settings-rail-button')));
      await tester.pumpAndSettle();

      for (final (label, brightness) in [
        ('Dark', Brightness.dark),
        ('Light', Brightness.light),
        ('System', Brightness.light),
      ]) {
        await tester.tap(find.byKey(const ValueKey('appearance-theme-select')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(_activeTheme(tester).brightness, brightness);
        expect(
          _railAvatarBackground(tester, host: 'a.example'),
          appearance.paletteForBrightness(brightness)!.tertiary,
        );
        expect(
          Theme.of(tester.element(find.text('Appearance'))).brightness,
          brightness,
        );
      }

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(
        _activeTheme(tester).colorScheme.primary,
        appearance.alternate!.tertiary,
      );
      expect(
        Theme.of(tester.element(find.text('Appearance'))).brightness,
        Brightness.dark,
      );
      await tester.tap(find.byKey(const ValueKey('appearance-theme-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Light').last);
      await tester.pumpAndSettle();
      expect(_activeTheme(tester).brightness, Brightness.light);
      await tester.tap(find.byKey(const ValueKey('app-settings-close')));
      await tester.pumpAndSettle();
      _controller(tester).selectAggregate();
      await tester.pump();
      expect(_activeTheme(tester).brightness, Brightness.light);
      expect(_materialApp(tester).themeMode, ThemeMode.light);
    });

    testWidgets('matches palette brightness and supplies missing variants', (
      tester,
    ) async {
      final darkPalette = sitePalette(
        brightness: Brightness.dark,
        background: const Color(0xFF181A1F),
        foreground: const Color(0xFFE8E9EB),
      );
      await _pumpApp(
        tester,
        store: FakeInstanceStore([
          const DiscourseInstance(
            url: siteA,
            title: 'Dark only',
          ).copyWith(appearance: SiteAppearance(base: darkPalette)),
          const DiscourseInstance(
            url: siteB,
            title: 'Light only',
          ).copyWith(appearance: SiteAppearance(alternate: sitePalette())),
        ]),
        api: FakeDiscourseApi(),
      );
      final controller = _controller(tester);
      await controller.appSettings.setThemeMode(AppThemeMode.light);
      await tester.pump();
      expect(_activeTheme(tester).colorScheme, AppTheme.light.colorScheme);
      await controller.appSettings.setThemeMode(AppThemeMode.dark);
      await tester.pump();
      expect(
        _activeTheme(tester).colorScheme,
        AppTheme.fromPalette(darkPalette).colorScheme,
      );
      controller.selectInstance(1);
      await tester.pump();
      expect(_activeTheme(tester).colorScheme, AppTheme.dark.colorScheme);
      await controller.appSettings.setThemeMode(AppThemeMode.light);
      await tester.pump();
      expect(
        _activeTheme(tester).colorScheme,
        AppTheme.fromPalette(sitePalette()).colorScheme,
      );
    });

    testWidgets('uses the neutral app palette inside Settings', (tester) async {
      final forumAppearance = siteAppearance(
        accent: const Color(0xFFAA2200),
        alternateAccent: const Color(0xFF00AACC),
        mode: SiteAppearanceMode.alternate,
      );
      final store = FakeInstanceStore([
        const DiscourseInstance(
          url: siteA,
          title: 'A',
        ).copyWith(appearance: forumAppearance),
      ]);

      await _pumpApp(tester, store: store, api: FakeDiscourseApi());
      final controller = _controller(tester);

      await tester.tap(find.byKey(const ValueKey('settings-rail-button')));
      await tester.pumpAndSettle();

      expect(controller.rootMode, ShellRootMode.forum);
      expect(_materialApp(tester).themeMode, ThemeMode.system);
      expect(
        Theme.of(
          tester.element(find.byKey(const ValueKey('app-settings-form'))),
        ).colorScheme.primary,
        AppTheme.light.colorScheme.primary,
      );

      await tester.tap(find.byKey(const ValueKey('app-settings-close')));
      await tester.pumpAndSettle();

      expect(_materialApp(tester).themeMode, ThemeMode.system);
      expect(
        _materialApp(tester).theme?.colorScheme.primary,
        forumAppearance.base?.tertiary,
      );
    });

    testWidgets('restores app palettes for the aggregate feed', (tester) async {
      final forumAppearance = siteAppearance(
        accent: const Color(0xFFAA2200),
        alternateAccent: const Color(0xFF00AACC),
        mode: SiteAppearanceMode.alternate,
      );
      final store = FakeInstanceStore([
        const DiscourseInstance(
          url: siteA,
          title: 'A',
        ).copyWith(appearance: forumAppearance),
      ]);

      await _pumpApp(tester, store: store, api: FakeDiscourseApi());
      final controller = _controller(tester);
      expect(_materialApp(tester).themeMode, ThemeMode.system);
      expect(
        _materialApp(tester).theme?.colorScheme.primary,
        forumAppearance.base?.tertiary,
      );

      controller.selectAggregate();
      await tester.pump();

      expect(_materialApp(tester).themeMode, ThemeMode.system);
      expect(
        _materialApp(tester).theme?.colorScheme.primary,
        AppTheme.light.colorScheme.primary,
      );
      expect(
        _materialApp(tester).darkTheme?.colorScheme.primary,
        AppTheme.dark.colorScheme.primary,
      );

      controller.selectInstance(0);
      await tester.pump();

      expect(_materialApp(tester).themeMode, ThemeMode.system);
      expect(
        _materialApp(tester).theme?.colorScheme.primary,
        forumAppearance.base?.tertiary,
      );
    });

    testWidgets('uses the app dark preference in navigator overlays', (
      tester,
    ) async {
      final appearance = siteAppearance(
        accent: const Color(0xFF145DA0),
        alternateAccent: const Color(0xFF80CED7),
        mode: SiteAppearanceMode.alternate,
      );
      final store = FakeInstanceStore([
        const DiscourseInstance(
          url: siteA,
          title: 'A',
        ).copyWith(appearance: appearance),
      ]);

      await _pumpApp(tester, store: store, api: FakeDiscourseApi());

      expect(_materialApp(tester).themeMode, ThemeMode.system);
      await _controller(tester).appSettings.setThemeMode(AppThemeMode.dark);
      await tester.pump();
      expect(_activeTheme(tester).brightness, Brightness.dark);
      Color? overlayPrimary;
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(AdaptiveShell)),
          builder: (context) {
            overlayPrimary = Theme.of(context).colorScheme.primary;
            return const AlertDialog(content: Text('Themed overlay'));
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(overlayPrimary, appearance.alternate?.tertiary);
    });

    testWidgets('preserves ThemeData identity during ordinary navigation', (
      tester,
    ) async {
      final appearance = siteAppearance();
      final store = FakeInstanceStore([
        const DiscourseInstance(
          url: siteA,
          title: 'A',
        ).copyWith(appearance: appearance),
      ]);
      await _pumpApp(tester, store: store, api: FakeDiscourseApi());
      final controller = _controller(tester);
      final before = _materialApp(tester).theme;

      controller.pushContent(
        ContentRoute.topic(topicId: 7, slug: 'theme-test', title: 'Theme test'),
      );
      await tester.pump();

      expect(_materialApp(tester).theme, same(before));
    });

    testWidgets('follows platform brightness in the app and rail', (
      tester,
    ) async {
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      final appearance = siteAppearance(
        accent: const Color(0xFF13579B),
        alternateAccent: const Color(0xFFBDF135),
        mode: SiteAppearanceMode.followSystem,
      );
      final store = FakeInstanceStore([
        const DiscourseInstance(
          url: siteA,
          title: 'A',
        ).copyWith(appearance: appearance),
      ]);

      await _pumpApp(tester, store: store, api: FakeDiscourseApi());

      expect(
        _activeTheme(tester).colorScheme.primary,
        appearance.base?.tertiary,
      );
      expect(
        _railAvatarBackground(tester, host: 'a.example'),
        appearance.base?.tertiary,
      );

      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      await tester.pumpAndSettle();

      expect(
        _activeTheme(tester).colorScheme.primary,
        appearance.alternate?.tertiary,
      );
      expect(
        _railAvatarBackground(tester, host: 'a.example'),
        appearance.alternate?.tertiary,
      );
    });
  });

  group('instance rail presentation', () {
    testWidgets('all rail badges follow the current window theme', (
      tester,
    ) async {
      final first = _appearanceWithSuccess(const Color(0xFF004400));
      final second = _appearanceWithSuccess(
        const Color(0xFF002255),
        background: const Color(0xFFFFF3E0),
      );
      const user = DiscourseUser(id: 7, username: 'sam');
      final store = FakeInstanceStore([
        const DiscourseInstance(
          url: siteA,
          title: 'A',
          user: user,
        ).copyWith(appearance: first),
        const DiscourseInstance(
          url: siteB,
          title: 'B',
          user: user,
        ).copyWith(appearance: second),
      ]);
      final authenticator = FakeAuthenticator()
        ..keys[siteA] = 'a-key'
        ..keys[siteB] = 'b-key';

      await _pumpApp(
        tester,
        store: store,
        api: FakeDiscourseApi(
          totals: const NotificationTotals(unreadNotifications: 3),
        ),
        authenticator: authenticator,
      );
      final controller = _controller(tester);
      final seenColors = <Color>{};
      for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
        await controller.appSettings.setThemeMode(mode);
        for (final index in [1, 0]) {
          controller.selectInstance(index);
          await tester.pumpAndSettle();

          final theme = _activeTheme(tester);
          final railSurface = Color.alphaBlend(
            theme.shell.rail,
            opaqueColorOnCanvas(
              theme.scaffoldBackgroundColor,
              theme.brightness,
            ),
          );
          final background = Color.lerp(
            theme.discourse.success,
            railSurface,
            0.2,
          )!;
          final foreground = contrastSafeForeground(
            background: background,
            backdrop: railSurface,
            preferred: [
              theme.discourse.notificationForeground,
              theme.colorScheme.surface,
            ],
          );
          seenColors.add(background);
          for (final host in ['a.example', 'b.example']) {
            final badge = _railBadge(tester, host: host);
            expect(badge.backgroundColor, background);
            expect(badge.foregroundColor, foreground);
            expect(badge.ringColor, railSurface);
          }
        }
      }
      expect(seenColors.length, greaterThan(1));
    });

    testWidgets('updates a non-current item when its appearance arrives late', (
      tester,
    ) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final secondAppearance = siteAppearance(
        accent: const Color(0xFF24A148),
        mode: SiteAppearanceMode.base,
      );
      final store = FakeInstanceStore([
        const DiscourseInstance(url: siteA, title: 'A'),
        const DiscourseInstance(url: siteB, title: 'B'),
      ]);
      final api = FakeDiscourseApi(
        siteAppearances: {siteB: secondAppearance},
        appearanceGate: gate,
      );

      await _pumpApp(tester, store: store, api: api, settle: false);
      await tester.pump();
      final controller = _controller(tester);

      controller.selectInstance(1);
      await tester.pump();
      controller.selectInstance(0);
      await tester.pump();
      final before = _railAvatarBackground(tester, host: 'b.example');
      final currentThemeBefore = _materialApp(tester).theme;

      gate.complete();
      await tester.pumpAndSettle();

      expect(controller.currentInstance?.url, siteA);
      expect(_materialApp(tester).theme, same(currentThemeBefore));
      expect(api.appearancesRequested, [siteA, siteB]);
      expect(
        _railAvatarBackground(tester, host: 'b.example'),
        secondAppearance.base?.tertiary.withValues(alpha: 0.16),
      );
      expect(_railAvatarBackground(tester, host: 'b.example'), isNot(before));
    });

    testWidgets('keeps monograms readable on transparent site accents', (
      tester,
    ) async {
      final paletteJson =
          sitePalette(
              accent: const Color(0x00FFFFFF),
              background: Colors.black,
              foreground: Colors.black,
            ).toJson()
            ..['headerBackground'] = Colors.black.toARGB32()
            ..['headerPrimary'] = Colors.black.toARGB32();
      final appearance = SiteAppearance(
        base: ResolvedSitePalette.fromJson(paletteJson),
        mode: SiteAppearanceMode.base,
      );
      final store = FakeInstanceStore([
        const DiscourseInstance(
          url: siteA,
          title: 'A',
        ).copyWith(appearance: appearance),
        const DiscourseInstance(
          url: siteB,
          title: 'B',
        ).copyWith(appearance: appearance),
      ]);

      await _pumpApp(tester, store: store, api: FakeDiscourseApi());

      _expectReadableRailMonogram(tester, title: 'A', host: 'a.example');
      _expectReadableRailMonogram(tester, title: 'B', host: 'b.example');
    });

    testWidgets('presents site logos with only a small corner radius', (
      tester,
    ) async {
      installTestMediaPipeline(
        client: MockClient(
          (_) async => http.Response(
            '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="40">'
            '<path d="M0 0h24v40H0z"/></svg>',
            200,
            headers: {'content-type': 'image/svg+xml'},
          ),
        ),
      );
      final store = FakeInstanceStore([
        const DiscourseInstance(
          url: siteA,
          title: 'A',
          iconUrl: '$siteA/logo.svg',
        ),
      ]);

      await _pumpApp(tester, store: store, api: FakeDiscourseApi());

      final item = _railItem(host: 'a.example');
      final logo = find.descendant(
        of: item,
        matching: find.byType(AvatarImage),
      );
      expect(tester.widget<AvatarImage>(logo).fit, BoxFit.contain);
      final clip = tester.widget<ClipRRect>(
        find.ancestor(of: logo, matching: find.byType(ClipRRect)),
      );
      expect(clip.borderRadius, BorderRadius.circular(8));
      expect(
        find.ancestor(of: logo, matching: find.byType(AnimatedContainer)),
        findsNothing,
      );
    });
  });
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required FakeInstanceStore store,
  required FakeDiscourseApi api,
  FakeAuthenticator? authenticator,
  AppSettingsStore? appSettingsStore,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    DiscourseApp(
      store: store,
      api: api,
      authenticator: authenticator ?? FakeAuthenticator(),
      appSettingsStore: appSettingsStore,
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
      initialRootMode: ShellRootMode.forum,
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

MaterialApp _materialApp(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp));

ShellController _controller(WidgetTester tester) =>
    tester.widget<ShellScope>(find.byType(ShellScope)).notifier!;

ThemeData _activeTheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(AdaptiveShell)));

Finder _railItem({required String host}) => find.descendant(
  of: find.byKey(ValueKey<String>('https://$host')),
  matching: find.byType(DTooltip),
);

SiteAppearance _appearanceWithSuccess(
  Color success, {
  Color background = Colors.white,
}) {
  final json = sitePalette(background: background).toJson()
    ..['success'] = success.toARGB32();
  return SiteAppearance(
    base: ResolvedSitePalette.fromJson(json),
    mode: SiteAppearanceMode.base,
  );
}

DBadge _railBadge(WidgetTester tester, {required String host}) {
  final badge = find.byKey(
    ValueKey<String>('instance-rail-badge-https://$host'),
  );
  expect(badge, findsOneWidget);
  return tester.widget<DBadge>(badge);
}

Color _railAvatarBackground(WidgetTester tester, {required String host}) {
  final container = find.descendant(
    of: _railItem(host: host),
    matching: find.byType(AnimatedContainer),
  );
  expect(container, findsOneWidget);
  final decoration = tester.widget<AnimatedContainer>(container).decoration;
  expect(decoration, isA<BoxDecoration>());
  return (decoration! as BoxDecoration).color!;
}

void _expectReadableRailMonogram(
  WidgetTester tester, {
  required String title,
  required String host,
}) {
  final item = _railItem(host: host);
  final monogram = find.descendant(of: item, matching: find.text(title));
  expect(monogram, findsOneWidget);
  final foreground = tester.widget<Text>(monogram).style!.color!;
  final theme = Theme.of(tester.element(find.byType(InstanceRail)));
  final canvas = theme.brightness == Brightness.dark
      ? Colors.black
      : Colors.white;
  final scaffold = Color.alphaBlend(theme.scaffoldBackgroundColor, canvas);
  final rail = Color.alphaBlend(theme.shell.rail, scaffold);
  final background = Color.alphaBlend(
    _railAvatarBackground(tester, host: host),
    rail,
  );
  final paintedForeground = Color.alphaBlend(foreground, background);

  expect(_contrast(paintedForeground, background), greaterThanOrEqualTo(4.5));
}

double _contrast(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
