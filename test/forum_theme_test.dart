import 'dart:async';
import 'dart:ui';

import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/data/scalar_preference_repository.dart';
import 'package:discourse_native/src/models/forum_background.dart';
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

  test('the forum default keeps the chosen presets, saved theme and font', () {
    final chosen = ForumThemePreferences()
        .withPreset(Brightness.dark, 'dracula')
        .save(custom)
        .withFont(ForumFont.lato);
    final forum = ForumThemePreferences.fromJson(
      chosen.withSource(ForumThemeSource.forum).toJson(),
    );
    expect(forum.source, ForumThemeSource.forum);
    for (final mode in Brightness.values) {
      expect(forum.themeFor(mode), isNull, reason: '$mode');
    }
    expect(forum.font, ForumFont.lato);
    expect(forum.withSource(ForumThemeSource.custom), chosen);
    expect(
      forum
          .withSource(ForumThemeSource.preset)
          .themeFor(Brightness.dark)!
          .tertiary,
      dracula.tertiary,
    );
  });

  test(
    'presets are chosen per mode and a mode without one keeps the forum colours',
    () {
      final solarized = forumThemePresets.firstWhere(
        (t) => t.id == 'solarized',
      );
      final light = ForumThemePreferences().withPreset(
        Brightness.light,
        'solarized',
      );
      expect(light.source, ForumThemeSource.preset);
      expect(
        light.themeFor(Brightness.light)!.tertiary,
        solarized.forBrightness(Brightness.light).tertiary,
      );
      expect(light.themeFor(Brightness.dark), isNull);
      final both = light.withPreset(Brightness.dark, 'dracula');
      final restored = ForumThemePreferences.fromJson(both.toJson());
      expect(restored, both);
      expect(restored.presets, {
        Brightness.light: 'solarized',
        Brightness.dark: 'dracula',
      });
      expect(restored.themeFor(Brightness.dark)!.tertiary, dracula.tertiary);
      for (final mode in Brightness.values) {
        expect(
          restored.themeFor(mode)!.background,
          const ForumBackground.appearance(),
        );
      }
      expect(
        ForumThemePreferences.fromJson({
          ...both.toJson(),
          'presets': const {'light': 'dracula', 'dark': 'unknown'},
        }).presets,
        isEmpty,
        reason: 'a preset only applies to a mode it has a palette for',
      );
      expect(ForumThemePreferences.preset('dracula').presets, {
        Brightness.dark: 'dracula',
      });
      expect(ForumThemePreferences.preset('solarized').presets, {
        Brightness.light: 'solarized',
        Brightness.dark: 'solarized',
      });
    },
  );

  test(
    'a mode without a preset keeps the forum palette for that mode',
    () async {
      final settings = ForumSettingsController(
        store: ForumSettingsStore.memory(),
      );
      addTearDown(settings.dispose);
      final forum = SiteAppearance(
        base: forumThemePresets
            .firstWhere((t) => t.id == 'solarized')
            .resolve(Brightness.light),
        alternate: forumThemePresets.first.resolve(Brightness.dark),
      );
      await settings.setThemes(
        site,
        ForumThemePreferences().withPreset(Brightness.dark, 'dracula'),
      );
      final appearance = settings.appearanceFor(site, forum)!;
      expect(appearance.base, same(forum.base));
      expect(appearance.alternate!.tertiary, dracula.tertiary);
    },
  );

  test(
    'reference tint mixes the accent into background and text separately',
    () {
      for (final mode in Brightness.values) {
        final source = dracula.forBrightness(mode);
        final resolved = source
            .copyWith(background: const ForumBackground.appearance(strength: 1))
            .resolve(mode);
        expect(
          resolved.secondary.toARGB32(),
          Color.lerp(source.secondary, source.tertiary, .22)!.toARGB32(),
        );
        expect(
          resolved.primary.toARGB32(),
          Color.lerp(source.primary, source.tertiary, .11)!.toARGB32(),
        );
      }
    },
  );

  test('live palettes are visible before persistence completes', () async {
    final persistence = _Persistence()..gate = Completer<void>();
    final settings = ForumSettingsController(
      store: ForumSettingsStore(persistence: persistence),
    );
    addTearDown(settings.dispose);
    final loading = settings.load(site);
    await persistence.readStarted.future;
    final next = ForumThemePreferences().withPreset(Brightness.dark, 'dracula');
    final saving = settings.setThemes(site, next);
    expect(settings.themesFor(site), next);
    expect(
      settings.appearanceFor(site, null)!.alternate!.tertiary,
      dracula.tertiary,
    );
    persistence.gate!.complete();
    await Future.wait([loading, saving]);
    expect(await settings.store.loadThemes(site), next);
  });

  test('paired appearances resolve and persist their own surface settings', () {
    final source = forumThemePresets.first;
    const lightBackground = ForumBackground(
      color: Color(0xff558844),
      strength: .3,
    );
    const darkBackground = ForumBackground(
      color: Color(0xffaa88dd),
      strength: .7,
      effect: ForumBackgroundEffect.noise,
    );
    final paired = ForumTheme.fromJson({
      ...source.toJson(),
      'background': lightBackground.toJson(),
      'alternate': {
        ...source.alternate!.toJson(),
        'background': darkBackground.toJson(),
        'windowGradient': true,
        'darkerSidebars': true,
      },
    }, id: 'custom-pair');
    final restored = ForumThemePreferences.fromJson(
      ForumThemePreferences().save(paired).toJson(),
    ).customTheme!;
    expect(restored, paired);
    for (final mode in Brightness.values) {
      final authored = mode == Brightness.light ? paired : paired.alternate!;
      final standalone = restored.forBrightness(mode);
      final resolved = restored.resolve(mode);
      expect(standalone.background, authored.background);
      expect(standalone.windowGradient, authored.windowGradient);
      expect(standalone.darkerSidebars, authored.darkerSidebars);
      expect(resolved.background, authored.background);
      expect(resolved.windowGradient, authored.windowGradient);
      expect(resolved.darkerSidebars, authored.darkerSidebars);
      expect(resolved, standalone.resolve(mode));
    }
  });

  test('surface effects remain independent for every preset and mode', () {
    for (final source in forumThemePresets) {
      for (final mode in Brightness.values) {
        final original = AppTheme.fromPalette(source.resolve(mode));
        for (final gradient in [false, true]) {
          for (final darker in [false, true]) {
            final custom = ForumTheme.fromJson({
              ...source.forBrightness(mode).toJson(),
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
        ).customTheme,
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
      final edited = chosen.save(custom).withSource(ForumThemeSource.forum);
      expect(edited.font, ForumFont.lato);
      expect(edited.remove(custom.id).font, ForumFont.lato);
      expect(ForumThemePreferences.fromJson(edited.toJson()), edited);
      expect(
        ForumThemePreferences.fromJson(const {'version': 1}).font,
        ForumFont.system,
      );
      expect(
        ForumThemePreferences.fromJson(const {
          'version': 2,
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
        expect(preferences.source, ForumThemeSource.preset, reason: old);
        expect(preferences.presets, {
          Brightness.light: current,
          Brightness.dark: current,
        }, reason: old);
        expect(preferences.toJson()['presets'], {
          'light': current,
          'dark': current,
        });
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
    expect(restored.source, ForumThemeSource.forum);
    expect(restored.customTheme, isNull);
    final updated = restored.save(custom);
    expect(updated.customTheme, custom);
    expect(updated.customThemes, hasLength(1));
    final removed = updated.remove(custom.id);
    expect(removed.customTheme, isNull);
    expect(removed.source, ForumThemeSource.forum);
    expect(
      ForumThemePreferences.fromJson({
        'version': 2,
        'source': 'custom',
        'custom': 'custom-gone',
        'customThemes': [
          {'id': custom.id, ...custom.toJson()},
        ],
      }).source,
      ForumThemeSource.forum,
      reason: 'a missing saved theme leaves the forum colours',
    );
    expect(
      () => ForumThemePreferences.fromJson(const {'version': 3}),
      throwsFormatException,
    );
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
    expect(restored.themesFor(site).customTheme, custom);
    expect(restored.themesFor('https://example.com').customTheme, isNull);
    const source = SiteAppearance.unknown();
    expect(
      restored.appearanceFor(site, source)?.base?.tertiary,
      custom.tertiary,
    );
    await restored.setThemes(
      site,
      restored.themesFor(site).withSource(ForumThemeSource.forum),
    );
    expect(restored.appearanceFor(site, source), same(source));
    expect(restored.themesFor(site).customThemes, [custom]);
  });

  test('a failed save retains the previously applied theme', () async {
    final persistence = _Persistence();
    final settings = ForumSettingsController(
      store: ForumSettingsStore(persistence: persistence),
    );
    addTearDown(settings.dispose);
    final initial = ForumThemePreferences.preset('dracula');
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
      ForumThemePreferences.preset('dracula'),
    );
    final last = settings.setThemes(
      site,
      ForumThemePreferences.defaults.save(custom),
    );
    persistence.gate!.complete();
    await Future.wait([load, first, last]);
    expect(settings.themesFor(site).customTheme, custom);
    final restored = await settings.store.loadThemes(site);
    expect(restored.customTheme, custom);
  });

  group('version 1 documents', () {
    Map<String, dynamic> legacy({
      Map<Brightness, ForumTheme> palettes = const {},
      ForumBackground? background,
      List<ForumTheme> customThemes = const [],
      String font = 'system',
    }) => {
      'version': 1,
      'useCustomTheme': true,
      'font': font,
      'selectedId': null,
      if (background != null) 'background': background.toJson(),
      'palettes': {
        for (final entry in palettes.entries)
          entry.key.name: {'id': entry.value.id, ...entry.value.toJson()},
      },
      'customThemes': [
        for (final theme in customThemes) {'id': theme.id, ...theme.toJson()},
      ],
    };
    ForumTheme forumCopy(Brightness mode) => forumThemePresets.first
        .forBrightness(mode)
        .copyWith(id: 'forum', name: 'Forum default');

    test('a font chosen over the forum colours keeps the forum default', () {
      final preferences = ForumThemePreferences.fromJson(
        legacy(
          palettes: {
            for (final mode in Brightness.values) mode: forumCopy(mode),
          },
          background: const ForumBackground.appearance(),
          font: 'lato',
        ),
      );
      expect(preferences.source, ForumThemeSource.forum);
      expect(preferences.font, ForumFont.lato);
      expect(preferences.customThemes, isEmpty);
    });

    test(
      'a preset chosen for one mode keeps the forum colours in the other',
      () {
        final preferences = ForumThemePreferences.fromJson(
          legacy(
            palettes: {
              Brightness.light: forumCopy(Brightness.light),
              Brightness.dark: dracula.forBrightness(Brightness.dark),
            },
            background: const ForumBackground.appearance(),
          ),
        );
        expect(preferences.source, ForumThemeSource.preset);
        expect(preferences.presets, {Brightness.dark: 'dracula'});
        expect(preferences.themeFor(Brightness.light), isNull);
      },
    );

    test('an applied saved theme stays applied', () {
      final preferences = ForumThemePreferences.fromJson(
        legacy(
          palettes: {
            for (final mode in Brightness.values)
              mode: custom.forBrightness(mode),
          },
          background: const ForumBackground.appearance(),
          customThemes: [custom],
        ),
      );
      expect(preferences.source, ForumThemeSource.custom);
      expect(preferences.customThemes, [custom]);
      expect(preferences.customTheme, custom);
    });

    test(
      'edited colours and effects become a saved theme that looks the same',
      () {
        final solarized = forumThemePresets.firstWhere(
          (t) => t.id == 'solarized',
        );
        final palettes = {
          Brightness.light: solarized
              .forBrightness(Brightness.light)
              .copyWith(tertiary: const Color(0xff112233)),
          Brightness.dark: dracula
              .forBrightness(Brightness.dark)
              .copyWith(darkerSidebars: true),
        };
        const background = ForumBackground.appearance(
          strength: .5,
          effect: ForumBackgroundEffect.noise,
        );
        final existing = custom.copyWith(id: 'custom-mine', name: 'My theme');
        final preferences = ForumThemePreferences.fromJson(
          legacy(
            palettes: palettes,
            background: background,
            customThemes: [existing],
          ),
        );
        expect(preferences.source, ForumThemeSource.custom);
        expect(preferences.customThemes.first, existing);
        final migrated = preferences.customTheme!;
        expect(preferences.customThemes.last, migrated);
        expect(migrated.name, 'My theme 2');
        for (final mode in Brightness.values) {
          expect(
            preferences.themeFor(mode)!.resolve(mode),
            palettes[mode]!.copyWith(background: background).resolve(mode),
            reason: '$mode',
          );
        }
        expect(
          ForumThemePreferences.fromJson(preferences.toJson()),
          preferences,
        );
      },
    );

    test('the forum default keeps the library and font', () {
      final preferences = ForumThemePreferences.fromJson({
        ...legacy(customThemes: [custom], font: 'lato'),
        'useCustomTheme': false,
      });
      expect(preferences.source, ForumThemeSource.forum);
      expect(preferences.customThemes, [custom]);
      expect(preferences.font, ForumFont.lato);
    });
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
