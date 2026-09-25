import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/data/scalar_preference_repository.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/shared_appearance.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/shell/forum_settings_controller.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon_sets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const site = 'https://example.com/forum';
  final dracula = forumThemePresets.firstWhere((t) => t.id == 'dracula');
  final custom = ForumTheme.fromJson({
    ...dracula.toJson(),
    'name': 'My night',
  }, id: 'custom-night');

  test('the forum default keeps the chosen presets and saved theme', () {
    final chosen = ForumThemePreferences()
        .withPreset(Brightness.dark, 'dracula')
        .save(custom);
    final forum = ForumThemePreferences.fromJson(
      chosen.withSource(ForumThemeSource.forum).toJson(),
    );
    expect(forum.source, ForumThemeSource.forum);
    for (final mode in Brightness.values) {
      expect(forum.themeFor(mode), isNull, reason: '$mode');
    }
    expect(forum.toJson(), isNot(contains('font')));
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
            .copyWith(tint: 1, background: const ForumBackground.appearance())
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

  test('a preview shows a draft and a mode without storing them, and only its '
      'owner ends it', () async {
    final settings = ForumSettingsController(
      store: ForumSettingsStore.memory(),
    );
    addTearDown(settings.dispose);
    final stored = ForumThemePreferences.preset('wcag');
    await settings.setThemes(site, stored);
    final saved = settings.appearanceFor(site, null);
    var notified = 0;
    settings.addListener(() => notified++);
    final page = Object();
    final other = Object();

    settings.preview(site, page, brightness: Brightness.dark, draft: dracula);
    expect(notified, 1);
    expect(settings.previewBrightnessFor(site), Brightness.dark);
    expect(
      settings.appearanceFor(site, null)!.alternate!.tertiary,
      dracula.tertiary,
    );
    settings.preview(site, page, brightness: Brightness.dark, draft: dracula);
    expect(notified, 1, reason: 'an unchanged preview does not notify');
    settings.preview(site, other);
    expect(settings.previewBrightnessFor(site), Brightness.dark);
    expect(notified, 1);

    settings.preview(site, page, brightness: Brightness.dark);
    expect(settings.appearanceFor(site, null), saved);
    settings.preview(site, page);
    expect(notified, 3);
    expect(settings.previewBrightnessFor(site), isNull);
    expect(settings.themesFor(site), stored);
    expect(await settings.store.loadThemes(site), stored);
  });

  test('a new theme previews its own texture before it is saved', () async {
    final settings = ForumSettingsController(
      store: ForumSettingsStore.memory(),
    );
    addTearDown(settings.dispose);
    const paper = ForumBackground.appearance(
      effect: ForumBackgroundEffect.paper,
      noiseIntensity: 1,
    );
    final draft = ForumTheme.fromJson({
      ...dracula
          .forBrightness(Brightness.light)
          .copyWith(background: paper)
          .toJson(),
      'alternate': dracula
          .forBrightness(Brightness.dark)
          .copyWith(background: paper)
          .toJson(),
    }, id: 'custom-preview');
    final owner = Object();

    settings.preview(site, owner, draft: draft);
    for (final mode in Brightness.values) {
      expect(
        settings
            .appearanceFor(site, null)!
            .paletteForBrightness(mode)!
            .background,
        paper,
      );
    }

    settings.preview(site, owner);
    expect(settings.appearanceFor(site, null), isNull);
    await settings.setThemes(site, ForumThemePreferences().save(draft));
    expect(settings.appearanceFor(site, null)!.base!.background, paper);
  });

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
      effect: ForumBackgroundEffect.paper,
    );
    final paired = ForumTheme.fromJson({
      ...source.toJson(),
      'background': lightBackground.toJson(),
      'tint': .3,
      'alternate': {
        ...source.alternate!.toJson(),
        'background': darkBackground.toJson(),
        'windowGradient': true,
        'darkerSidebars': true,
        'tint': .8,
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
      expect(standalone.tint, authored.tint);
      // The tint is the theme's own; the other effects are the app's.
      expect(restored.colours.forBrightness(mode).tint, authored.tint);
      expect(restored.colours.forBrightness(mode).background, isNull);
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

  test('the shared font and effects round trip and damaged values default '
      'safely', () {
    const shared = SharedAppearance(
      font: ForumFont.lato,
      iconSet: DIconSet.phosphor,
      effects: ForumBackground.appearance(
        effect: ForumBackgroundEffect.paper,
        transparency: .2,
      ),
    );
    expect(SharedAppearance.fromJson(shared.toJson()), shared);
    // A tint stored while it was shared is dropped; themes carry their own.
    expect(
      SharedAppearance.fromJson({
        ...shared.toJson(),
        'effects': shared.effects.copyWith(strength: .4).toJson(),
      }),
      shared,
    );
    expect(
      SharedAppearance.fromJson({...shared.toJson(), 'effects': 'damaged'}),
      const SharedAppearance(font: ForumFont.lato, iconSet: DIconSet.phosphor),
    );
    expect(
      SharedAppearance.fromJson({...shared.toJson(), 'font': 'unknown'}).font,
      ForumFont.system,
    );
    expect(
      SharedAppearance.fromJson({
        ...shared.toJson(),
        'iconSet': 'unknown',
      }).iconSet,
      DIconSet.defaultSet,
    );
    expect(
      SharedAppearance.fromJson(const {'version': 1, 'font': 'lato'}).iconSet,
      DIconSet.defaultSet,
    );
    expect(
      () => SharedAppearance.fromJson(const {'version': 2}),
      throwsFormatException,
    );
    // An older shared theme's own tint colour becomes the accent tint, which
    // is then dropped with any other shared tint.
    const legacy = ForumBackground(
      color: Color(0xff336699),
      strength: .22,
      transparency: .2,
    );
    expect(
      SharedAppearance.fromJson({
        'version': 1,
        'effects': legacy.toJson(),
      }).effects,
      legacy.toAccentTint().copyWith(strength: 0),
    );
    expect(legacy.toAccentTint().useAccentTint, isTrue);
    expect(legacy.toAccentTint().strength, closeTo(.45, 1e-9));
  });

  test('the shared appearance is stored once for every forum, and a failed '
      'write restores the saved choice', () async {
    final persistence = _Persistence();
    final settings = ForumSettingsController(
      store: ForumSettingsStore(persistence: persistence),
    );
    addTearDown(settings.dispose);
    await settings.loadShared(const []);
    final chosen = settings.shared.copyWith(
      font: ForumFont.openSans,
      effects: const ForumBackground.appearance(transparency: .15),
    );
    await settings.setShared(chosen);
    expect(persistence.values.keys, [ForumSettingsStore.appearanceKey]);
    final restored = ForumSettingsController(
      store: ForumSettingsStore(persistence: persistence),
    );
    addTearDown(restored.dispose);
    await restored.loadShared([site]);
    expect(restored.shared, chosen);
    persistence.failWrites = true;
    await expectLater(
      settings.setShared(chosen.copyWith(font: ForumFont.lato)),
      throwsStateError,
    );
    expect(settings.shared, chosen);
  });

  test('a choice made while the shared appearance is read wins', () async {
    final persistence = _Persistence()
      ..values[ForumSettingsStore.appearanceKey] = jsonEncode(
        const SharedAppearance(font: ForumFont.lato).toJson(),
      )
      ..gate = Completer<void>();
    final settings = ForumSettingsController(
      store: ForumSettingsStore(persistence: persistence),
    );
    addTearDown(settings.dispose);
    final loading = settings.loadShared(const []);
    await persistence.readStarted.future;
    final saving = settings.setShared(
      const SharedAppearance(font: ForumFont.jetBrainsMono),
    );
    persistence.gate!.complete();
    await Future.wait([loading, saving]);
    expect(settings.shared.font, ForumFont.jetBrainsMono);
  });

  group('the first shared load', () {
    Future<(SharedAppearance, _Persistence)> adopt(
      Map<String, Map<String, dynamic>> forums, {
      List<String>? order,
    }) async {
      final persistence = _Persistence();
      for (final entry in forums.entries) {
        persistence.values[ForumSettingsStore.themesKey(entry.key)] =
            jsonEncode(entry.value);
      }
      final shared = await ForumSettingsStore(
        persistence: persistence,
      ).loadAppearance(sites: order ?? forums.keys);
      return (shared, persistence);
    }

    const paper = ForumBackground.appearance(
      strength: .5,
      effect: ForumBackgroundEffect.paper,
      transparency: .1,
    );
    final themed = ForumTheme.fromJson({
      ...custom.toJson(),
      'background': paper.toJson(),
    }, id: 'custom-paper');

    test('adopts the first font and the first theme effects in forum order, '
        'and stores them', () async {
      final (shared, persistence) = await adopt(
        {
          'https://a.example': {
            ...ForumThemePreferences().toJson(),
            'font': 'system',
          },
          'https://b.example': {
            ...ForumThemePreferences().save(themed).toJson(),
            'font': 'openSans',
          },
          'https://c.example': {
            ...ForumThemePreferences().toJson(),
            'font': 'lato',
          },
        },
        order: ['https://a.example', 'https://b.example', 'https://c.example'],
      );
      // The theme's tint stays with themes rather than becoming shared.
      expect(
        shared,
        SharedAppearance(
          font: ForumFont.openSans,
          effects: paper.copyWith(strength: 0),
        ),
      );
      expect(
        SharedAppearance.fromJson(
          jsonDecode(persistence.values[ForumSettingsStore.appearanceKey]!)
              as Map<String, dynamic>,
        ),
        shared,
      );
    });

    test('ignores effects of a saved theme that is not shown', () async {
      final (shared, _) = await adopt({
        'https://a.example': ForumThemePreferences()
            .save(themed)
            .withSource(ForumThemeSource.forum)
            .toJson(),
      });
      expect(shared, SharedAppearance.defaults);
    });

    test(
      'never replaces a stored appearance, even an unreadable one',
      () async {
        final persistence = _Persistence()
          ..values[ForumSettingsStore.appearanceKey] = '{not json'
          ..values[ForumSettingsStore.themesKey(site)] = jsonEncode({
            ...ForumThemePreferences().toJson(),
            'font': 'lato',
          });
        final shared = await ForumSettingsStore(
          persistence: persistence,
        ).loadAppearance(sites: [site]);
        expect(shared, SharedAppearance.defaults);
        expect(
          persistence.values[ForumSettingsStore.appearanceKey],
          '{not json',
        );
      },
    );
  });

  group('effects', () {
    final forum = SiteAppearance(
      base: ResolvedSitePalette.fromJson(const {
        'brightness': 'light',
        'primary': 0xff222222,
        'secondary': 0xffffffff,
        'tertiary': 0xff0088cc,
        'headerBackground': 0xff113355,
        'primaryLow': 0xffe9e9e9,
      }),
    );
    const effects = ForumBackground.appearance(
      effect: ForumBackgroundEffect.paper,
      transparency: .2,
    );

    test('without effects the forum palette is shown exactly as published', () {
      final settings = ForumSettingsController(
        store: ForumSettingsStore.memory(),
      );
      addTearDown(settings.dispose);
      expect(settings.appearanceFor(site, forum), same(forum));
    });

    test('are drawn over every source, and only a saved theme tints', () async {
      final settings = ForumSettingsController(
        store: ForumSettingsStore.memory(),
      );
      addTearDown(settings.dispose);
      await settings.setShared(const SharedAppearance(effects: effects));
      final published = forum.base!;
      final shown = settings.appearanceFor(site, forum)!.base!;
      expect(shown.background, effects);
      expect(shown, published.withEffects(effects));
      expect(shown.secondary, published.secondary);
      expect(shown.headerBackground, published.headerBackground);

      await settings.setThemes(
        site,
        ForumThemePreferences().withPreset(Brightness.light, 'solarized'),
      );
      expect(
        settings.appearanceFor(site, forum)!.base,
        forumThemePresetFor('solarized', Brightness.light)!
            .forBrightness(Brightness.light)
            .copyWith(background: effects)
            .resolve(Brightness.light, forumPalette: published),
      );

      final legacy = ForumTheme.fromJson({
        ...custom.toJson(),
        'background': const ForumBackground(
          color: Color(0xff00ff00),
          strength: 1,
        ).toJson(),
      }, id: 'custom-legacy');
      await settings.setThemes(site, ForumThemePreferences().save(legacy));
      expect(
        settings.appearanceFor(site, forum)!.base,
        legacy
            .forBrightness(Brightness.light)
            .resolve(Brightness.light, forumPalette: published),
        reason: 'a saved custom theme keeps its own effects',
      );

      final tinted = custom.copyWith(id: 'custom-tinted', tint: 1);
      await settings.setThemes(site, ForumThemePreferences().save(tinted));
      final shownTinted = settings.appearanceFor(site, forum)!.base!;
      expect(shownTinted.background, effects);
      expect(
        shownTinted.secondary,
        Color(
          Color.lerp(
            custom.forBrightness(Brightness.light).secondary,
            custom.forBrightness(Brightness.light).tertiary,
            ForumBackground.maxTint,
          )!.toARGB32(),
        ),
      );
    });
  });

  group('using one forum\'s colours in the others', () {
    const other = 'https://other.example';
    const third = 'https://third.example';

    test('copies the forum default, presets or saved theme and keeps each '
        'library', () async {
      final settings = ForumSettingsController(
        store: ForumSettingsStore.memory(),
      );
      addTearDown(settings.dispose);
      final theirs = custom.copyWith(id: 'custom-theirs', name: 'Theirs');
      await settings.setThemes(other, ForumThemePreferences().save(theirs));

      await settings.setThemes(
        site,
        ForumThemePreferences().withPreset(Brightness.dark, 'dracula'),
      );
      await settings.useThemesIn(site, [site, other, third]);
      for (final forum in [other, third]) {
        expect(settings.themesFor(forum).source, ForumThemeSource.preset);
        expect(settings.themesFor(forum).presets, {Brightness.dark: 'dracula'});
      }
      expect(settings.themesFor(other).customThemes, [theirs]);

      await settings.setThemes(site, settings.themesFor(site).save(custom));
      await settings.useThemesIn(site, [other, third]);
      for (final forum in [other, third]) {
        expect(settings.themesFor(forum).customTheme, custom);
      }
      expect(settings.themesFor(other).customThemes, [theirs, custom]);

      // Applying again changes nothing and adds no second copy.
      final before = settings.themesFor(other);
      expect(before.showing(settings.themesFor(site)), before);
      await settings.useThemesIn(site, [other]);
      expect(settings.themesFor(other), before);

      await settings.setThemes(
        site,
        settings.themesFor(site).withSource(ForumThemeSource.forum),
      );
      await settings.useThemesIn(site, [other]);
      expect(settings.themesFor(other).source, ForumThemeSource.forum);
      expect(settings.themesFor(other).customThemes, [theirs, custom]);
    });

    test('loads a forum not yet read before changing it', () async {
      final store = ForumSettingsStore.memory();
      final theirs = custom.copyWith(id: 'custom-theirs', name: 'Theirs');
      await store.writeThemes(other, ForumThemePreferences().save(theirs));
      final settings = ForumSettingsController(store: store);
      addTearDown(settings.dispose);
      await settings.setThemes(site, ForumThemePreferences().save(custom));
      await settings.useThemesIn(site, [other]);
      expect(settings.themesFor(other).customThemes, [theirs, custom]);
      expect((await store.loadThemes(other)).customTheme, custom);
    });
  });

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

  test('portable imports reject invalid names, modes, colors, and tints', () {
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
      {...custom.toJson(), 'tint': 'strong'},
      {...custom.toJson(), 'tint': -.1},
      {...custom.toJson(), 'tint': 1.5},
      {...custom.toJson(), 'tint': double.nan},
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

    test('a font chosen over the forum colours keeps the forum default, '
        'and becomes every forum\'s font', () async {
      final document = legacy(
        palettes: {for (final mode in Brightness.values) mode: forumCopy(mode)},
        background: const ForumBackground.appearance(),
        font: 'lato',
      );
      final preferences = ForumThemePreferences.fromJson(document);
      expect(preferences.source, ForumThemeSource.forum);
      expect(preferences.customThemes, isEmpty);
      final persistence = _Persistence()
        ..values[ForumSettingsStore.themesKey(site)] = jsonEncode(document);
      final shared = await ForumSettingsStore(
        persistence: persistence,
      ).loadAppearance(sites: [site]);
      expect(shared.font, ForumFont.lato);
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
          effect: ForumBackgroundEffect.paper,
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

    test('the forum default keeps the library', () {
      final preferences = ForumThemePreferences.fromJson({
        ...legacy(customThemes: [custom], font: 'lato'),
        'useCustomTheme': false,
      });
      expect(preferences.source, ForumThemeSource.forum);
      expect(preferences.customThemes, [custom]);
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
