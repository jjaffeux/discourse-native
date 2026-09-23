import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/data/scalar_preference_repository.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/forum_theme_share.dart';
import 'package:discourse_native/src/shell/code_block.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/forum_settings_controller.dart';
import 'package:discourse_native/src/shell/forum_theme_thumbnail.dart';
import 'package:discourse_native/src/shell/oneboxes/forum_theme.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _site = 'https://example.com/forum';
final _theme = ForumThemeShare.decode(
  jsonEncode({
    ...forumThemePresets.first.toJson(),
    'name': 'Moss',
    'colors': {
      ...forumThemePresets.first.toJson()['colors'] as Map,
      'tertiary': '#5D7954',
    },
  }),
)!;

Widget _host(
  Widget child, {
  double width = 410,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Directionality(
      textDirection: direction,
      child: SingleChildScrollView(
        child: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'preview toggle changes only the preview; apply saves both modes and undo restores selection',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final store = ForumSettingsStore.memory();
      final settings = ForumSettingsController(store: store);
      addTearDown(settings.dispose);
      await settings.setThemes(
        _site,
        ForumThemePreferences(selectedId: 'dracula')
            .withPalette(
              forumThemePresets.first
                  .forBrightness(Brightness.light)
                  .copyWith(tertiary: const Color(0xff112233)),
            )
            .withPalette(forumThemePresets.last.forBrightness(Brightness.dark))
            .withBackground(
              const ForumBackground.appearance(strength: .6, transparency: .2),
            ),
      );
      await settings.setThemeMode(_site, AppThemeMode.light);
      final before = settings.themesFor(_site);
      await tester.pumpWidget(
        _host(
          ForumThemeOnebox(theme: _theme, siteUrl: _site, settings: settings),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Light'), findsNothing);
      expect(find.text('Dark'), findsNothing);
      expect(find.bySemanticsLabel('Preview light theme'), findsOneWidget);
      expect(find.bySemanticsLabel('Preview dark theme'), findsOneWidget);
      ThemeData preview() =>
          tester.widget<ThemeThumbnail>(find.byType(ThemeThumbnail)).theme;
      expect(preview().brightness, Brightness.light);
      final light = preview().colorScheme.surface;
      await tester.tap(find.bySemanticsLabel('Preview dark theme'));
      await tester.pumpAndSettle();
      expect(preview().brightness, Brightness.dark);
      expect(preview().colorScheme.surface, isNot(light));
      expect(settings.themesFor(_site), before);
      expect(settings.themeModeFor(_site), AppThemeMode.light);
      await tester.tap(find.text('Use theme'));
      await tester.pumpAndSettle();
      expect(find.text('Using theme'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(settings.themesFor(_site).selectedTheme, _theme);
      expect(settings.themesFor(_site).selectedTheme!.alternate, isNotNull);
      expect(settings.themeModeFor(_site), AppThemeMode.light);
      expect((await store.loadThemes(_site)).selectedTheme, _theme);
      await tester.tap(find.bySemanticsLabel('Preview light theme'));
      await tester.pumpAndSettle();
      expect(preview().brightness, Brightness.light);
      expect(settings.themesFor(_site).selectedTheme, _theme);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(settings.themesFor(_site).selectedId, 'dracula');
      expect(settings.themesFor(_site).palettes, before.palettes);
      expect(settings.themesFor(_site).background, before.background);
      expect(settings.themesFor(_site).customThemes, [_theme]);
      expect(find.text('Use theme'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('live palette edits supersede an applied shared theme', (
    tester,
  ) async {
    final settings = ForumSettingsController(
      store: ForumSettingsStore.memory(),
    );
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      _host(
        ForumThemeOnebox(theme: _theme, siteUrl: _site, settings: settings),
      ),
    );
    await tester.tap(find.text('Use theme'));
    await tester.pumpAndSettle();
    expect(find.text('Using theme'), findsOneWidget);
    await settings.setThemes(
      _site,
      settings
          .themesFor(_site)
          .withPalette(
            _theme
                .forBrightness(Brightness.light)
                .copyWith(tertiary: const Color(0xff112233)),
          ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Use theme'), findsOneWidget);
    expect(find.text('Using theme'), findsNothing);
    expect(find.text('Undo'), findsNothing);
    expect(
      settings.themesFor(_site).themeFor(Brightness.light)!.tertiary,
      const Color(0xff112233),
    );
  });

  for (final chat in [false, true]) {
    testWidgets(
      'cooked ${chat ? 'chat' : 'post'} uses the shared card and the destination forum settings',
      (tester) async {
        final controller = ShellController(
          instanceStore: FakeInstanceStore(),
          api: FakeDiscourseApi(),
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          updateStore: FakeUpdateStore(),
        );
        addTearDown(controller.dispose);
        final escaped = const HtmlEscape().convert(jsonEncode(_theme.toJson()));
        await tester.pumpWidget(
          ShellScope(
            controller: controller,
            child: _host(
              CookedHtml(
                html:
                    '<p>My theme:</p><pre data-code-wrap="discourse-theme"><code class="lang-discourse-theme">$escaped</code></pre><p>Enjoy!</p>',
                siteUrl: _site,
                compactParagraphs: chat,
                contentSized: chat,
                buildAsync: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ForumThemeOnebox), findsOneWidget);
        expect(find.byType(CodeBlock), findsNothing);
        expect(find.text('Moss'), findsOneWidget);
        await tester.tap(find.text('Use theme'));
        await tester.pumpAndSettle();
        expect(controller.forumSettings.themesFor(_site).selectedTheme, _theme);
        expect(
          controller.forumSettings
              .themesFor('https://other.example')
              .selectedTheme,
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'invalid shares have an error and ordinary code remains ordinary code',
    (tester) async {
      await tester.pumpWidget(
        _host(
          const CookedHtml(
            html:
                '<pre><code class="lang-discourse-theme">{"version":99}</code></pre><pre><code class="lang-json">{"value":42}</code></pre>',
            siteUrl: _site,
            buildAsync: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ForumThemeOnebox), findsNothing);
      expect(find.byType(DAlert), findsOneWidget);
      expect(find.byType(CodeBlock), findsOneWidget);
      expect(find.text('Use theme'), findsNothing);
    },
  );

  testWidgets('failed saves retain the current theme and allow a retry', (
    tester,
  ) async {
    final persistence = _FailingPersistence();
    final settings = ForumSettingsController(
      store: ForumSettingsStore(persistence: persistence),
    );
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      _host(
        ForumThemeOnebox(theme: _theme, siteUrl: _site, settings: settings),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use theme'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save theme. Try again.'), findsOneWidget);
    expect(settings.themesFor(_site).selectedTheme, isNull);
    expect(find.text('Using theme'), findsNothing);
    persistence.fail = false;
    await tester.tap(find.text('Use theme'));
    await tester.pumpAndSettle();
    expect(settings.themesFor(_site).selectedTheme, _theme);
    expect(find.text('Could not save theme. Try again.'), findsNothing);
  });

  testWidgets(
    'compact cards retain controls at narrow widths, large text and RTL',
    (tester) async {
      final settings = ForumSettingsController(
        store: ForumSettingsStore.memory(),
      );
      addTearDown(settings.dispose);
      final longName = ForumTheme.fromJson({
        ..._theme.toJson(),
        'name': 'A calm green theme for comfortable daily reading',
      }, id: _theme.id);
      for (final width in [410.0, 320.0, 240.0]) {
        for (final scale in [1.0, 2.0]) {
          for (final direction in TextDirection.values) {
            await tester.pumpWidget(
              _host(
                ForumThemeOnebox(
                  theme: longName,
                  siteUrl: _site,
                  settings: settings,
                ),
                width: width,
                scale: scale,
                direction: direction,
              ),
            );
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.byIcon(Icons.dark_mode_outlined));
            await tester.tap(find.byIcon(Icons.dark_mode_outlined));
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<ThemeThumbnail>(find.byType(ThemeThumbnail))
                  .theme
                  .brightness,
              Brightness.dark,
            );
            expect(find.text('Use theme'), findsOneWidget);
            expect(
              tester.takeException(),
              isNull,
              reason: '$width / $scale / $direction',
            );
            expect(
              tester.getSize(find.byType(DCard)).width,
              lessThanOrEqualTo(width),
            );
          }
        }
      }
    },
  );
}

class _FailingPersistence implements ScalarPreferencePersistence<String> {
  bool fail = true;
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<bool> write(String key, String value) async {
    if (fail) return false;
    values[key] = value;
    return true;
  }
}
