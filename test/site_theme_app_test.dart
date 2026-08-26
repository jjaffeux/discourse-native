import 'dart:async';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/avatar_loader.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'support/site_appearance_fixtures.dart';

void main() {
  const siteA = 'https://a.example';
  const siteB = 'https://b.example';

  testWidgets('uses persisted palettes immediately and refreshes once', (
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

  testWidgets('switching sites swaps palettes without cross-site bleed', (
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
      _materialApp(tester).theme?.colorScheme.primary,
      first.base?.tertiary,
    );

    controller.selectInstance(1);
    await tester.pump();
    expect(
      _materialApp(tester).theme?.colorScheme.primary,
      second.base?.tertiary,
    );

    controller.selectInstance(0);
    await tester.pump();
    expect(
      _materialApp(tester).theme?.colorScheme.primary,
      first.base?.tertiary,
    );
  });

  testWidgets('aggregate uses the app theme instead of a forum palette', (
    tester,
  ) async {
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
    expect(_materialApp(tester).themeMode, ThemeMode.dark);
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

    expect(_materialApp(tester).themeMode, ThemeMode.dark);
    expect(
      _materialApp(tester).theme?.colorScheme.primary,
      forumAppearance.base?.tertiary,
    );
  });

  testWidgets('mirrors forced mode and themes navigator overlays', (
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

    expect(_materialApp(tester).themeMode, ThemeMode.dark);
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

  testWidgets('disconnect clears an account-derived persisted appearance', (
    tester,
  ) async {
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

  testWidgets('ordinary navigation preserves ThemeData identity', (
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

  testWidgets('followSystem tracks platform brightness in the app and rail', (
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

    expect(_activeTheme(tester).colorScheme.primary, appearance.base?.tertiary);
    expect(
      _railAvatarBackground(tester, title: 'A', host: 'a.example'),
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
      _railAvatarBackground(tester, title: 'A', host: 'a.example'),
      appearance.alternate?.tertiary,
    );
  });

  testWidgets('a late appearance updates a non-current rail item', (
    tester,
  ) async {
    final gate = Completer<void>();
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
    final before = _railAvatarBackground(tester, title: 'B', host: 'b.example');
    final currentThemeBefore = _materialApp(tester).theme;

    gate.complete();
    await tester.pumpAndSettle();

    expect(controller.currentInstance?.url, siteA);
    expect(_materialApp(tester).theme, same(currentThemeBefore));
    expect(api.appearancesRequested, containsAll([siteA, siteB]));
    expect(
      _railAvatarBackground(tester, title: 'B', host: 'b.example'),
      secondAppearance.base?.tertiary.withValues(alpha: 0.16),
    );
    expect(
      _railAvatarBackground(tester, title: 'B', host: 'b.example'),
      isNot(before),
    );
  });

  testWidgets('rail monograms remain readable on transparent site accents', (
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

  testWidgets('rail presents site logos with only a small corner radius', (
    tester,
  ) async {
    final previousLoader = AvatarLoader.instance;
    AvatarLoader.instance = AvatarLoader(
      client: MockClient(
        (_) async => http.Response(
          '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="40">'
          '<path d="M0 0h24v40H0z"/></svg>',
          200,
          headers: {'content-type': 'image/svg+xml'},
        ),
      ),
    );
    addTearDown(() {
      AvatarLoader.instance.clear();
      AvatarLoader.instance = previousLoader;
    });
    final store = FakeInstanceStore([
      const DiscourseInstance(
        url: siteA,
        title: 'A',
        iconUrl: '$siteA/logo.svg',
      ),
    ]);

    await _pumpApp(tester, store: store, api: FakeDiscourseApi());

    final item = _railItem(host: 'a.example');
    final logo = find.descendant(of: item, matching: find.byType(AvatarImage));
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
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required FakeInstanceStore store,
  required FakeDiscourseApi api,
  FakeAuthenticator? authenticator,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    DiscourseApp(
      store: store,
      api: api,
      authenticator: authenticator ?? FakeAuthenticator(),
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
  matching: find.byType(RawTooltip),
);

Color _railAvatarBackground(
  WidgetTester tester, {
  required String title,
  required String host,
}) {
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
    _railAvatarBackground(tester, title: title, host: host),
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
