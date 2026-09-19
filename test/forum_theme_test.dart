import 'dart:async';
import 'dart:ui';

import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/data/scalar_preference_repository.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/shell/forum_settings_controller.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const site = 'https://example.com/forum';
  final dracula = forumThemePresets.firstWhere((t) => t.id == 'dracula');
  final custom = ForumTheme.fromJson({
    ...dracula.toJson(),
    'name': 'My night',
  }, id: 'custom-night');

  test('surface effects remain independent for every preset and mode', () {
    for (final source in forumThemePresets) {
      for (final mode in Brightness.values) {
        final original = AppTheme.fromPalette(source.resolve(mode));
        for (final gradient in [false, true]) {
          for (final darker in [false, true]) {
            final custom = ForumTheme.fromJson({
              ...source.toJson(),
              'windowGradient': gradient,
              'darkerSidebars': darker,
            }, id: 'custom-effects');
            final theme = AppTheme.fromPalette(custom.resolve(mode));
            final effects = theme.extension<ForumThemeEffects>();
            expect(effects?.windowGradient != null, gradient);
            expect(effects?.sidebarTheme != null, darker);
            expect(theme.shell.content, original.shell.content);
            expect(theme.shell.panel, original.shell.panel);
            if (effects?.sidebarTheme case final sidebar?) {
              expect(
                sidebar.shell.sidebar.computeLuminance(),
                lessThanOrEqualTo(original.shell.sidebar.computeLuminance()),
              );
              final a = sidebar.shell.selected.computeLuminance();
              final b = sidebar.shell.selectedForeground.computeLuminance();
              expect(
                ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05),
                greaterThanOrEqualTo(4.5),
                reason: '${source.id} $mode selected text',
              );
            }
          }
        }
      }
    }
  });

  test(
    'surface options round trip and survive mode conversion and resolution',
    () {
      final themed = ForumTheme.fromJson({
        ...dracula.toJson(),
        'windowGradient': true,
        'darkerSidebars': true,
      }, id: 'custom-effects');
      expect(ForumTheme.fromJson(themed.toJson(), id: themed.id), themed);
      expect(
        ForumThemePreferences.fromJson(
          ForumThemePreferences().save(themed).toJson(),
        ).selectedTheme,
        themed,
      );
      for (final mode in Brightness.values) {
        expect(themed.forBrightness(mode).windowGradient, isTrue);
        expect(themed.forBrightness(mode).darkerSidebars, isTrue);
        final palette = themed.resolve(mode);
        expect(palette.windowGradient, isTrue);
        expect(palette.darkerSidebars, isTrue);
        expect(ResolvedSitePalette.fromJson(palette.toJson()), palette);
        expect(palette, isNot(dracula.resolve(mode)));
      }
      final legacy = Map<String, dynamic>.of(dracula.toJson())
        ..remove('windowGradient')
        ..remove('darkerSidebars');
      expect(ForumTheme.fromJson(legacy, id: dracula.id), dracula);
      for (final key in ['windowGradient', 'darkerSidebars']) {
        expect(
          () => ForumTheme.fromJson({...legacy, key: 'yes'}, id: 'bad'),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'font survives theme edits and older or unknown preferences default safely',
    () {
      final chosen = ForumThemePreferences().withFont(ForumFont.lato);
      final edited = chosen.save(custom).select(null);
      expect(edited.font, ForumFont.lato);
      expect(edited.remove(custom.id).font, ForumFont.lato);
      expect(ForumThemePreferences.fromJson(edited.toJson()), edited);
      expect(
        ForumThemePreferences.fromJson(const {'version': 1}).font,
        ForumFont.system,
      );
      expect(
        ForumThemePreferences.fromJson(const {
          'version': 1,
          'font': 'unknown',
        }).font,
        ForumFont.system,
      );
    },
  );

  test(
    'fonts persist independently per forum and failed writes retain the choice',
    () async {
      final persistence = _Persistence();
      final store = ForumSettingsStore(persistence: persistence);
      final settings = ForumSettingsController(store: store);
      addTearDown(settings.dispose);
      await settings.setThemes(
        site,
        ForumThemePreferences().withFont(ForumFont.openSans),
      );
      await settings.setThemes(
        'https://other.example',
        ForumThemePreferences().withFont(ForumFont.lato),
      );
      final restored = ForumSettingsController(
        store: ForumSettingsStore(persistence: persistence),
      );
      addTearDown(restored.dispose);
      await restored.load(site);
      await restored.load('https://other.example');
      expect(restored.themesFor(site).font, ForumFont.openSans);
      expect(restored.themesFor('https://other.example').font, ForumFont.lato);
      persistence.failWrites = true;
      await expectLater(
        settings.setThemes(
          site,
          settings.themesFor(site).withFont(ForumFont.system),
        ),
        throwsStateError,
      );
      expect(settings.themesFor(site).font, ForumFont.openSans);
    },
  );

  test('contains all reference schemes with their original colors', () {
    expect(forumThemePresets.map((t) => t.id), [
      'neutral',
      'grey-amber',
      'shades-of-blue',
      'latte',
      'summer',
      'dark-rose',
      'wcag',
      'dracula',
      'solarized',
      'clover-dark',
    ]);
    expect(dracula.secondary, const Color(0xff2d303e));
    expect(dracula.tertiary, const Color(0xffbd93f9));
    for (final theme in forumThemePresets) {
      expect(ForumTheme.fromJson(theme.toJson(), id: theme.id), theme);
    }
  });

  test(
    'paired themes resolve authored palettes and migrate old selections',
    () {
      final wcag = forumThemePresets.firstWhere((t) => t.id == 'wcag');
      expect(wcag.resolve(Brightness.light).tertiary, const Color(0xff0033cc));
      expect(wcag.resolve(Brightness.dark).tertiary, const Color(0xff759aff));
      expect(wcag.resolve(Brightness.dark).secondary, const Color(0xff0c0c0c));
      final solarized = forumThemePresets.firstWhere(
        (t) => t.id == 'solarized',
      );
      expect(
        solarized.resolve(Brightness.light).tertiary,
        const Color(0xff0088cc),
      );
      expect(
        solarized.resolve(Brightness.dark).tertiary,
        const Color(0xff1a97d5),
      );
      for (final (old, current) in [
        ('dark', 'neutral'),
        ('wcag-dark', 'wcag'),
        ('solarized-light', 'solarized'),
        ('solarized-dark', 'solarized'),
      ]) {
        final preferences = ForumThemePreferences.fromJson({
          'version': 1,
          'selectedId': old,
        });
        expect(preferences.selectedId, current);
        expect(preferences.selectedTheme, isNotNull);
        expect(preferences.toJson()['selectedId'], current);
      }
      for (final theme in forumThemePresets) {
        for (final brightness in Brightness.values) {
          final thumbnail = theme.forBrightness(brightness);
          final resolved = theme.resolve(brightness);
          expect(thumbnail.secondary, resolved.secondary);
          expect(thumbnail.tertiary, resolved.tertiary);
          expect(thumbnail.brightness, brightness);
        }
      }
    },
  );

  test('resolves both modes and retains the forum geometry', () {
    final geometry = ResolvedSitePalette.fromJson(const {
      'primary': 0xff222222,
      'secondary': 0xffffffff,
      'tertiary': 0xff0088cc,
      'borderRadius': 9,
      'avatarBorderRadius': {'value': 12, 'unit': 'pixels'},
    });
    final dark = dracula.resolve(Brightness.dark, forumPalette: geometry);
    final light = dracula.resolve(Brightness.light, forumPalette: geometry);
    expect(dark.primary, dracula.primary);
    expect(dark.secondary, dracula.secondary);
    expect(light.primary, dracula.secondary);
    expect(light.secondary, dracula.primary);
    expect(light.tertiary, dark.tertiary);
    expect(light.borderRadius, 9);
    expect(dark.avatarBorderRadius, const AvatarBorderRadius.pixels(12));
    expect(dark.primaryVeryLow, isNot(dark.secondary));
    expect(dark.contentBorderColor, isNot(dark.secondary));
  });

  test('portable imports reject invalid names, modes, and colors', () {
    for (final bad in [
      {...custom.toJson(), 'name': ''},
      {...custom.toJson(), 'mode': 'system'},
      {...custom.toJson(), 'version': 2},
      {
        ...custom.toJson(),
        'colors': {'primary': '#abc'},
      },
      {
        ...custom.toJson(),
        'colors': {...custom.toJson()['colors'] as Map, 'love': '#11223344'},
      },
    ]) {
      expect(
        () => ForumTheme.fromJson(bad, id: 'custom-test'),
        throwsFormatException,
      );
    }
  });

  test('damaged custom entries do not hide valid themes', () {
    final restored = ForumThemePreferences.fromJson({
      'version': 1,
      'selectedId': 'missing',
      'customThemes': [
        {'id': custom.id, ...custom.toJson()},
        const {'id': 'custom-bad', 'name': 'Broken'},
        {'id': 'dracula', ...custom.toJson()},
      ],
    });
    expect(restored.customThemes, [custom]);
    expect(restored.selectedTheme, isNull);
    final updated = restored.save(custom);
    expect(updated.selectedTheme, custom);
    expect(updated.customThemes, hasLength(1));
    expect(updated.remove(custom.id).selectedTheme, isNull);
  });

  test('custom themes and selections persist per canonical forum', () async {
    final store = ForumSettingsStore.memory();
    final first = ForumSettingsController(store: store);
    final restored = ForumSettingsController(store: store);
    addTearDown(first.dispose);
    addTearDown(restored.dispose);
    await first.setThemes(site, ForumThemePreferences.defaults.save(custom));
    await restored.load('$site/');
    await restored.load('https://example.com');
    expect(restored.themesFor(site).selectedTheme, custom);
    expect(restored.themesFor('https://example.com').selectedTheme, isNull);
    const source = SiteAppearance.unknown();
    expect(
      restored.appearanceFor(site, source)?.base?.tertiary,
      custom.tertiary,
    );
    await restored.setThemes(site, restored.themesFor(site).select(null));
    expect(restored.appearanceFor(site, source), same(source));
    expect(restored.themesFor(site).customThemes, [custom]);
  });

  test('a failed save retains the previously applied theme', () async {
    final persistence = _Persistence();
    final settings = ForumSettingsController(
      store: ForumSettingsStore(persistence: persistence),
    );
    addTearDown(settings.dispose);
    final initial = ForumThemePreferences(selectedId: 'dracula');
    await settings.setThemes(site, initial);
    persistence.failWrites = true;
    await expectLater(
      settings.setThemes(site, initial.save(custom)),
      throwsStateError,
    );
    expect(settings.themesFor(site), initial);
  });

  test('hydration and rapid saves retain the last chosen theme', () async {
    final persistence = _Persistence()..gate = Completer<void>();
    final settings = ForumSettingsController(
      store: ForumSettingsStore(persistence: persistence),
    );
    addTearDown(settings.dispose);
    final load = settings.load(site);
    await persistence.readStarted.future;
    final first = settings.setThemes(
      site,
      ForumThemePreferences(selectedId: 'dracula'),
    );
    final last = settings.setThemes(
      site,
      ForumThemePreferences.defaults.save(custom),
    );
    persistence.gate!.complete();
    await Future.wait([load, first, last]);
    expect(settings.themesFor(site).selectedTheme, custom);
    final restored = await settings.store.loadThemes(site);
    expect(restored.selectedTheme, custom);
  });
}

class _Persistence implements ScalarPreferencePersistence<String> {
  final values = <String, String>{};
  final readStarted = Completer<void>();
  Completer<void>? gate;
  bool failWrites = false;

  @override
  Future<String?> read(String key) async {
    if (!readStarted.isCompleted) readStarted.complete();
    await gate?.future;
    return values[key];
  }

  @override
  Future<bool> write(String key, String value) async {
    if (failWrites) return false;
    values[key] = value;
    return true;
  }
}
