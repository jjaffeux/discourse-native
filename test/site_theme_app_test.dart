import 'dart:async';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/diagnostics/surface_opening_trace.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/forum_settings_dialog.dart';
import 'package:discourse_native/src/shell/forum_theme_surfaces.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/color_contrast.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('custom background retains framed panels on one desktop canvas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const topic = Topic(
      id: 1,
      title: 'Continuous background',
      slug: 'background',
    );
    await _pumpApp(
      tester,
      capture: true,
      store: FakeInstanceStore([
        const DiscourseInstance(url: siteA, title: 'A'),
      ]),
      api: FakeDiscourseApi(
        feeds: const {
          '/latest.json': [topic],
        },
        topics: const {
          1: (
            detail: TopicDetail(
              id: 1,
              title: 'Continuous background',
              stream: [11],
              postsCount: 1,
            ),
            posts: [
              Post(
                id: 11,
                postNumber: 1,
                username: 'reviewer',
                cooked: '<p>A topic on the shared canvas.</p>',
              ),
            ],
          ),
        },
      ),
      appSettingsStore: AppSettingsStore(
        persistence: MemoryAppSettingsPersistence(),
      ),
    );
    final controller = _controller(tester);
    controller.openTopicFromList(topic);
    await tester.pumpAndSettle();
    final original = _activeTheme(tester).shell.content;
    final source = forumThemePresets.firstWhere((t) => t.id == 'dracula');
    Color paintedBox(Finder parent) => tester
        .widget<ColoredBox>(
          find.descendant(of: parent, matching: find.byType(ColoredBox)).first,
        )
        .color;

    final flatPixels = <(AppThemeMode, bool), ByteData>{};
    for (final mode in [AppThemeMode.dark, AppThemeMode.light]) {
      await controller.forumSettings.setThemeMode(siteA, mode);
      for (final effect in ForumBackgroundEffect.values) {
        for (final darkerSidebars in [false, true]) {
          final custom = ForumTheme.fromJson({
            ...source.toJson(),
            'darkerSidebars': darkerSidebars,
            'background': ForumBackground(
              color: const Color(0xffdc63ae),
              strength: .8,
              effect: effect,
            ).toJson(),
          }, id: 'custom-pink');
          await controller.forumSettings.setThemes(
            siteA,
            ForumThemePreferences().save(custom),
          );
          // Lava keeps ticking; allow the inherited theme to finish changing.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          final theme = _activeTheme(tester);
          final expected = Color(
            Color.lerp(
              source.forBrightness(theme.brightness).secondary,
              const Color(0xffdc63ae),
              .8 * .45,
            )!.toARGB32(),
          );
          expect(theme.shell.content, expected);
          expect(paintedBox(find.byType(ShellTitleBar)), Colors.transparent);
          expect(paintedBox(find.byType(InstanceRail)), Colors.transparent);
          final panels = [
            find
                .ancestor(
                  of: find.byType(DSidebar),
                  matching: find.byType(DCard),
                )
                .first,
            find
                .descendant(
                  of: find.byKey(const ValueKey('inbox-topic-list-pane')),
                  matching: find.byType(DCard),
                )
                .first,
            find
                .descendant(
                  of: find.byKey(const ValueKey('inbox-topic-reader-pane')),
                  matching: find.byType(DCard),
                )
                .first,
          ];
          final panelColors = <Color>[];
          for (final panel in panels) {
            final surface = tester.widget<Material>(
              find.descendant(of: panel, matching: find.byType(Material)).first,
            );
            expect(surface.color!.a, greaterThan(0));
            expect(surface.color!.a, lessThan(1));
            panelColors.add(surface.color!);
            final frame = tester.widget<DecoratedBox>(
              find
                  .descendant(of: panel, matching: find.byType(DecoratedBox))
                  .first,
            );
            final border =
                (frame.decoration as BoxDecoration).border! as Border;
            expect(border.top.color.a, greaterThan(0));
            expect(border.top.width, greaterThan(0));
            expect(frame.position, DecorationPosition.foreground);
          }
          expect(panelColors.toSet(), hasLength(1));
          for (final key in ['topic-list-bottom-bar', 'topic-bottom-bar']) {
            final footer = find.byKey(ValueKey(key));
            expect(paintedBox(footer).a, greaterThan(panelColors.first.a));
            expect(paintedBox(footer).a, lessThan(1));
            expect(tester.widget<DCardFooter>(footer).border, isTrue);
            expect(tester.widget<DCardFooter>(footer).rounded, isTrue);
          }
          expect(
            find.byKey(const ValueKey('forum-window-canvas')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('forum-window-effect')),
            effect == ForumBackgroundEffect.normal
                ? findsNothing
                : findsOneWidget,
          );
          final canvas = tester.widget<DecoratedBox>(
            find
                .descendant(
                  of: find.byType(ForumWindowBackground),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          );
          expect(
            (canvas.decoration as BoxDecoration).color,
            expected,
            reason: 'Only the root canvas paints the base color.',
          );
          {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('app-paint-boundary')),
            );
            final pixels = (await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              final width = image.width;
              image.dispose();
              return (bytes: bytes, width: width);
            }))!;
            final bytes = pixels.bytes;
            if (effect == ForumBackgroundEffect.normal) {
              flatPixels[(mode, darkerSidebars)] = bytes;
            }
            final sidebar = tester.getRect(find.byType(DSidebar));
            final list = tester.getRect(
              find.byKey(const ValueKey('inbox-topic-list-pane')),
            );
            final reader = tester.getRect(
              find.byKey(const ValueKey('inbox-topic-reader-pane')),
            );
            var totalChangedPixels = 0;
            for (final (point, surface) in [
              (const Offset(16, 400), expected),
              (const Offset(80, 44), expected),
              (
                sidebar.bottomRight - const Offset(24, 90),
                Color.alphaBlend(panelColors[0], expected),
              ),
              (
                list.bottomCenter - const Offset(0, 90),
                Color.alphaBlend(panelColors[1], expected),
              ),
              (
                reader.bottomCenter - const Offset(0, 90),
                Color.alphaBlend(panelColors[2], expected),
              ),
            ]) {
              final index =
                  (point.dy.floor() * pixels.width + point.dx.floor()) * 4;
              final painted = Color.fromARGB(
                bytes.getUint8(index + 3),
                bytes.getUint8(index),
                bytes.getUint8(index + 1),
                bytes.getUint8(index + 2),
              );
              if (effect == ForumBackgroundEffect.normal) {
                for (final (actual, desired) in [
                  (painted.r, surface.r),
                  (painted.g, surface.g),
                  (painted.b, surface.b),
                ]) {
                  expect(
                    actual,
                    closeTo(desired, 1 / 255),
                    reason:
                        'The shared canvas and retained panel fill at $point in $mode',
                  );
                }
              } else {
                final flat = flatPixels[(mode, darkerSidebars)]!;
                var changedPixels = 0;
                for (var dy = -32; dy <= 32; dy++) {
                  for (var dx = -12; dx <= 12; dx++) {
                    final pixel =
                        ((point.dy.floor() + dy) * pixels.width +
                            point.dx.floor() +
                            dx) *
                        4;
                    if ([0, 1, 2].any(
                      (channel) =>
                          (bytes.getUint8(pixel + channel) -
                                  flat.getUint8(pixel + channel))
                              .abs() >
                          1,
                    )) {
                      changedPixels++;
                    }
                  }
                }
                totalChangedPixels += changedPixels;
                if (effect == ForumBackgroundEffect.noise) {
                  expect(
                    changedPixels,
                    greaterThan(0),
                    reason:
                        'Noise remains visible through the surface at $point in $mode',
                  );
                }
              }
            }
            if (effect == ForumBackgroundEffect.lava) {
              expect(
                totalChangedPixels,
                greaterThan(0),
                reason: 'Lava remains visible behind the framed workspace',
              );
            }
          }
          expect(tester.takeException(), isNull);
        }
      }
    }
    await controller.forumSettings.setThemes(
      siteA,
      ForumThemePreferences.defaults,
    );
    await controller.forumSettings.setThemeMode(siteA, AppThemeMode.system);
    await tester.pumpAndSettle();
    expect(_activeTheme(tester).shell.content, original);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('mobile pages share one custom background painter', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final forums = ForumSettingsStore.memory();
    final custom = ForumTheme.fromJson({
      ...forumThemePresets.first.toJson(),
      'background': const ForumBackground(
        color: Colors.purple,
        effect: ForumBackgroundEffect.noise,
      ).toJson(),
    }, id: 'custom-mobile');
    await forums.writeThemes(siteA, ForumThemePreferences().save(custom));
    tester.view.physicalSize = const Size(390, 844);
    await _pumpApp(
      tester,
      store: FakeInstanceStore([
        const DiscourseInstance(url: siteA, title: 'A'),
      ]),
      api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
      forumSettingsStore: forums,
      appSettingsStore: AppSettingsStore(
        persistence: MemoryAppSettingsPersistence(),
      ),
    );
    for (final width in [390.0, 1200.0]) {
      tester.view.physicalSize = Size(width, 844);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('forum-window-canvas')), findsOneWidget);
      expect(find.byKey(const ValueKey('forum-window-effect')), findsOneWidget);
      expect(
        tester
            .widget<DPageSurface>(
              find.byKey(const ValueKey('mobile-content-panel')),
            )
            .framed,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    }
    await _controller(
      tester,
    ).forumSettings.setThemes(siteA, ForumThemePreferences.defaults);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DPageSurface>(
            find.byKey(const ValueKey('mobile-content-panel')),
          )
          .framed,
      isTrue,
    );
    expect(find.byKey(const ValueKey('forum-window-effect')), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Escape closes forum Settings after changing appearance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpApp(
      tester,
      store: FakeInstanceStore([
        const DiscourseInstance(url: siteA, title: 'A'),
      ]),
      api: FakeDiscourseApi(),
      appSettingsStore: AppSettingsStore(
        persistence: MemoryAppSettingsPersistence(),
      ),
    );
    final controller = _controller(tester);
    await _openForumSettings(tester);

    await tester.tap(
      find
          .descendant(
            of: find.byKey(const ValueKey('appearance-theme-select')),
            matching: find.text('Dark'),
          )
          .last,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(controller.forumSettings.themeModeFor(siteA), AppThemeMode.dark);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape, character: '\x1b');
    await tester.pumpAndSettle();

    expect(find.byType(ForumSettingsDialog), findsNothing);
    expect(controller.appSettingsModalOpen, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'a personal palette updates the app and restores forum defaults',
    (tester) async {
      final forums = ForumSettingsStore.memory();
      final source = siteAppearance();
      final instances = FakeInstanceStore([
        const DiscourseInstance(
          url: siteA,
          title: 'A',
        ).copyWith(appearance: source),
        const DiscourseInstance(url: siteB, title: 'B'),
      ]);
      await _pumpApp(
        tester,
        store: instances,
        api: FakeDiscourseApi(),
        forumSettingsStore: forums,
      );
      var controller = _controller(tester);
      await controller.forumSettings.setThemes(
        siteA,
        ForumThemePreferences(selectedId: 'dracula'),
      );
      await tester.pumpAndSettle();
      expect(
        _activeTheme(tester).colorScheme.primary,
        forumThemePresets.firstWhere((theme) => theme.id == 'dracula').tertiary,
      );
      controller.selectInstance(1);
      await tester.pumpAndSettle();
      expect(
        _activeTheme(tester).colorScheme.primary,
        isNot(
          forumThemePresets
              .firstWhere((theme) => theme.id == 'dracula')
              .tertiary,
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await _pumpApp(
        tester,
        store: instances,
        api: FakeDiscourseApi(),
        forumSettingsStore: forums,
      );
      controller = _controller(tester);
      expect(
        _activeTheme(tester).colorScheme.primary,
        forumThemePresets.firstWhere((theme) => theme.id == 'dracula').tertiary,
      );
      await controller.forumSettings.setThemes(
        siteA,
        ForumThemePreferences.defaults,
      );
      await tester.pumpAndSettle();
      expect(_activeTheme(tester).colorScheme.primary, source.base!.tertiary);
    },
  );

  testWidgets('hydrates an injected app-wide settings store on startup', (
    tester,
  ) async {
    final appSettingsStore = AppSettingsStore(
      persistence: MemoryAppSettingsPersistence(
        limitContentSize: true,
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

    expect(_controller(tester).appSettings.limitContentSize, true);
    expect(_controller(tester).appSettings.textScale, AppTextScale.percent125);
    expect(_materialApp(tester).themeMode, ThemeMode.system);
    expect(
      MediaQuery.textScalerOf(
        tester.element(find.byType(AdaptiveShell)),
      ).scale(DiscourseTypography.base),
      moreOrLessEquals(
        DiscourseTypography.base * 1.25 * DiscourseTypography.mobileScale,
      ),
    );
  });

  testWidgets('forum choices survive switching and an app restart', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final forums = ForumSettingsStore.memory();
    final instances = FakeInstanceStore([
      const DiscourseInstance(url: siteA, title: 'A'),
      const DiscourseInstance(url: siteB, title: 'B'),
    ]);
    await _pumpApp(
      tester,
      store: instances,
      api: FakeDiscourseApi(),
      forumSettingsStore: forums,
    );
    var controller = _controller(tester);
    await _openForumSettings(tester);
    expect(
      find.descendant(
        of: find.byType(ForumSettingsDialog),
        matching: find.text('A'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find
          .descendant(
            of: find.byKey(const ValueKey('appearance-theme-select')),
            matching: find.text('Dark'),
          )
          .last,
    );
    await tester.pumpAndSettle();
    expect(_activeTheme(tester).brightness, Brightness.dark);
    await tester.tap(find.byKey(const ValueKey('forum-settings-close')));
    await tester.pumpAndSettle();
    controller.selectInstance(1);
    await tester.pumpAndSettle();
    await _openForumSettings(tester);
    expect(
      find.descendant(
        of: find.byType(ForumSettingsDialog),
        matching: find.text('B'),
      ),
      findsOneWidget,
    );
    expect(find.text('System'), findsOneWidget);
    await tester.tap(
      find
          .descendant(
            of: find.byKey(const ValueKey('appearance-theme-select')),
            matching: find.text('Light'),
          )
          .last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('forum-settings-close')));
    await tester.pumpAndSettle();
    controller.selectInstance(0);
    await tester.pumpAndSettle();
    expect(_materialApp(tester).themeMode, ThemeMode.dark);
    controller.selectInstance(1);
    await tester.pumpAndSettle();
    expect(_materialApp(tester).themeMode, ThemeMode.light);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await _pumpApp(
      tester,
      store: instances,
      api: FakeDiscourseApi(),
      forumSettingsStore: forums,
    );
    controller = _controller(tester);
    expect(_materialApp(tester).themeMode, ThemeMode.dark);
    controller.selectInstance(1);
    await tester.pumpAndSettle();
    expect(_materialApp(tester).themeMode, ThemeMode.light);
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
      final firstLight = _materialApp(tester).theme;
      final firstDark = _materialApp(tester).darkTheme;

      controller.selectInstance(1);
      await tester.pump();
      expect(_activeTheme(tester).colorScheme.primary, second.base?.tertiary);

      controller.selectInstance(0);
      await tester.pump();
      expect(_activeTheme(tester).colorScheme.primary, first.base?.tertiary);
      expect(_materialApp(tester).theme, same(firstLight));
      expect(_materialApp(tester).darkTheme, same(firstDark));
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
    testWidgets('equal palettes reuse themes and rapid switches trace once', (
      tester,
    ) async {
      final first = siteAppearance(alternateAccent: const Color(0xFF80CED7));
      final second = SiteAppearance.fromJson(first.toJson());
      expect(second, first);
      expect(identical(second, first), isFalse);
      await _pumpApp(
        tester,
        store: FakeInstanceStore([
          instance('a.example').copyWith(appearance: first),
          instance('b.example').copyWith(appearance: second),
        ]),
        api: FakeDiscourseApi(),
      );
      final light = _materialApp(tester).theme;
      final dark = _materialApp(tester).darkTheme;
      final controller = _controller(tester);
      controller.selectInstance(1);
      await tester.pump();
      expect(_materialApp(tester).theme, same(light));
      expect(_materialApp(tester).darkTheme, same(dark));

      final events = <String>[];
      SurfaceOpeningTrace.observer = (name, _) => events.add(name);
      addTearDown(() => SurfaceOpeningTrace.observer = null);
      controller.selectInstance(0);
      controller.selectInstance(1);
      controller.selectInstance(0);
      expect(events.where((event) => event == 'forum.frame'), isEmpty);
      await tester.pump();
      expect(events.where((event) => event == 'forum.frame'), hasLength(1));
      expect(controller.currentInstance?.url, siteA);

      events.clear();
      controller.selectInstance(1);
      controller.selectAggregate();
      await tester.pump();
      expect(events.where((event) => event == 'forum.frame'), isEmpty);
    });

    testWidgets('appearance changes the forum and open dialog immediately', (
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
      await _openForumSettings(tester);

      for (final (label, brightness) in [
        ('Dark', Brightness.dark),
        ('Light', Brightness.light),
        ('System', Brightness.light),
      ]) {
        await tester.tap(
          find
              .descendant(
                of: find.byKey(const ValueKey('appearance-theme-select')),
                matching: find.text(label),
              )
              .last,
        );
        await tester.pumpAndSettle();
        expect(_activeTheme(tester).brightness, brightness);
        expect(
          _railAvatarBackground(tester, host: 'a.example'),
          appearance.paletteForBrightness(brightness)!.tertiary,
        );
        expect(
          Theme.of(tester.element(find.byType(ForumSettingsDialog))).brightness,
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
        Theme.of(tester.element(find.byType(ForumSettingsDialog))).brightness,
        Brightness.dark,
      );
      await tester.tap(
        find
            .descendant(
              of: find.byKey(const ValueKey('appearance-theme-select')),
              matching: find.text('Light'),
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(_activeTheme(tester).brightness, Brightness.light);
      await tester.tap(find.byKey(const ValueKey('forum-settings-close')));
      await tester.pumpAndSettle();
      _controller(tester).selectAggregate();
      await tester.pump();
      expect(_activeTheme(tester).brightness, Brightness.dark);
      expect(_materialApp(tester).themeMode, ThemeMode.system);
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
      await controller.forumSettings.setThemeMode(
        controller.currentInstance!.url,
        AppThemeMode.light,
      );
      await tester.pump();
      expect(_activeTheme(tester).colorScheme, AppTheme.light.colorScheme);
      await controller.forumSettings.setThemeMode(
        controller.currentInstance!.url,
        AppThemeMode.dark,
      );
      await tester.pump();
      expect(
        _activeTheme(tester).colorScheme,
        AppTheme.fromPalette(darkPalette).colorScheme,
      );
      controller.selectInstance(1);
      await controller.forumSettings.setThemeMode(siteB, AppThemeMode.dark);
      await tester.pump();
      expect(_activeTheme(tester).colorScheme, AppTheme.dark.colorScheme);
      await controller.forumSettings.setThemeMode(
        controller.currentInstance!.url,
        AppThemeMode.light,
      );
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

    testWidgets('uses the forum dark preference in navigator overlays', (
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
      await _controller(
        tester,
      ).forumSettings.setThemeMode(siteA, AppThemeMode.dark);
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
        await controller.forumSettings.setThemeMode(siteA, mode);
        await controller.forumSettings.setThemeMode(siteB, mode);
        for (final index in [1, 0]) {
          controller.selectInstance(index);
          await tester.pumpAndSettle();

          final theme = _activeTheme(tester);
          final railSurface = Color.alphaBlend(
            theme.shell.content,
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
        find.ancestor(of: logo, matching: find.byType(ClipRRect)).first,
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
  ForumSettingsStore? forumSettingsStore,
  bool settle = true,
  bool capture = false,
}) async {
  final app = DiscourseApp(
    store: store,
    api: api,
    authenticator: authenticator ?? FakeAuthenticator(),
    appSettingsStore: appSettingsStore,
    forumSettingsStore: forumSettingsStore ?? ForumSettingsStore.memory(),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    initialRootMode: ShellRootMode.forum,
    notificationOpenUrls: capture ? const Stream<String>.empty() : null,
  );
  await tester.pumpWidget(
    capture
        ? RepaintBoundary(key: const ValueKey('app-paint-boundary'), child: app)
        : app,
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

Future<void> _openForumSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('forum-identity-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('forum-identity-settings')));
  await tester.pumpAndSettle();
}
