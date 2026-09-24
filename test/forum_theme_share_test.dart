import 'dart:convert';
import 'dart:ui';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/forum_theme_share.dart';
import 'package:discourse_native/src/shell/forum_settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

void main() {
  final source = ForumTheme.fromJson({
    ...forumThemePresets.first.toJson(),
    'name': 'Moss 🌿',
    'background': const ForumBackground(
      color: Color(0xff65906a),
      effect: ForumBackgroundEffect.noise,
      noiseIntensity: .4,
      transparency: .15,
    ).toJson(),
    'darkerSidebars': true,
    'alternate': {
      ...forumThemePresets.first.alternate!.toJson(),
      'name': 'Moss 🌿',
      'windowGradient': true,
      'background': const ForumBackground(
        color: Color(0xff17291f),
        effect: ForumBackgroundEffect.lava,
      ).toJson(),
    },
  }, id: 'custom-original');

  test(
    'portable share retains both appearances and effects without a sender ID',
    () {
      final markdown = ForumThemeShare.encode(source);
      expect(markdown, isNot(contains(source.id)));
      final decoded = ForumThemeShare.decode(markdown.split('\n')[1])!;
      expect(decoded.id, startsWith('custom-shared-'));
      expect(decoded.name, source.name);
      for (final brightness in Brightness.values) {
        expect(decoded.resolve(brightness), source.resolve(brightness));
      }
    },
  );

  test(
    'sharing from either appearance and differently ordered JSON deduplicates',
    () {
      final darkFirst = ForumTheme.fromJson({
        ...source.forBrightness(Brightness.dark).toJson(),
        'alternate': source.forBrightness(Brightness.light).toJson(),
      }, id: 'custom-another-id');
      final lightShare = ForumThemeShare.decode(jsonEncode(source.toJson()))!;
      final darkShare = ForumThemeShare.decode(jsonEncode(darkFirst.toJson()))!;
      expect(darkShare, lightShare);
      expect(ForumThemeShare.encode(darkFirst), ForumThemeShare.encode(source));
      final shuffled = Map<String, dynamic>.fromEntries(
        source.toJson().entries.toList().reversed,
      );
      shuffled['id'] = 'custom-original';
      expect(ForumThemeShare.decode(jsonEncode(shuffled)), lightShare);
    },
  );

  test(
    'invalid, oversized, unsupported and recursively paired shares are rejected',
    () {
      for (final raw in [
        '',
        '{',
        '[]',
        'null',
        ' ' * (ForumThemeShare.maxLength + 1),
        jsonEncode({...source.toJson(), 'version': 2}),
        jsonEncode({...source.toJson(), 'name': ''}),
        jsonEncode({
          ...source.toJson(),
          'colors': {'primary': 'red'},
        }),
        jsonEncode({...source.toJson(), 'alternate': source.toJson()}),
        jsonEncode({
          ...source.toJson(),
          'alternate': source.forBrightness(Brightness.light).toJson(),
        }),
        jsonEncode({
          ...source.toJson(),
          'background': {'effect': 'url(https://example.com)'},
        }),
      ]) {
        expect(ForumThemeShare.decode(raw), isNull);
      }
    },
  );

  test(
    'imports preserve an existing library, font and other forums before loading',
    () async {
      const site = 'https://example.com/forum';
      const otherSite = 'https://other.example';
      final store = ForumSettingsStore.memory();
      final existing = ForumTheme.fromJson({
        ...source.toJson(),
        'name': 'My theme',
      }, id: 'custom-existing');
      final original = ForumThemePreferences(
        source: ForumThemeSource.custom,
        customId: existing.id,
        customThemes: [existing],
        font: ForumFont.values.last,
      );
      await store.writeThemes(site, original);
      await store.writeThemes(otherSite, original);
      final settings = ForumSettingsController(store: store);
      addTearDown(settings.dispose);
      final incoming = ForumThemeShare.decode(jsonEncode(source.toJson()))!;
      expect(await settings.importTheme(site, incoming), original);
      final saved = await store.loadThemes(site);
      expect(saved.customThemes, [existing, incoming]);
      expect(saved.customTheme, incoming);
      expect(saved.font, original.font);
      expect(await store.loadThemes(otherSite), original);
      await settings.importTheme(site, incoming);
      expect(settings.themesFor(site).customThemes, [existing, incoming]);
      final second = ForumThemeShare.decode(
        jsonEncode({...source.toJson(), 'name': 'Second share'}),
      )!;
      final third = ForumThemeShare.decode(
        jsonEncode({...source.toJson(), 'name': 'Third share'}),
      )!;
      await Future.wait([
        settings.importTheme(site, second),
        settings.importTheme(site, third),
      ]);
      expect(settings.themesFor(site).customThemes, [
        existing,
        incoming,
        second,
        third,
      ]);
    },
  );

  test('using your own shared theme selects its existing local identity', () {
    final incoming = ForumThemeShare.decode(jsonEncode(source.toJson()))!;
    final saved = ForumThemePreferences(
      customThemes: [source],
    ).importTheme(incoming);
    expect(saved.customThemes, [source]);
    expect(saved.customId, source.id);
  });

  for (final profile in [CookingProfile.post, CookingProfile.chat]) {
    test(
      '${profile.name} cooking preserves the copy/paste payload and surrounding text',
      () async {
        final service = OfflineCookingService();
        addTearDown(service.dispose);
        final tricky = ForumTheme.fromJson({
          ...source.toJson(),
          'name': 'Moss <b> & "quotes"\n```',
        }, id: source.id);
        final result = await service.cook(
          CookingRequest(
            raw: 'My theme:\n\n${ForumThemeShare.encode(tricky)}\n\nEnjoy!',
            profile: profile,
            snapshot: CookingSnapshot(
              siteId: 'test-site',
              accountId: 'test-account',
            ),
          ),
        );
        expect(result.failure, isNull);
        final document = html.parseFragment(result.html);
        final code = document.querySelector(
          'pre > code.lang-${ForumThemeShare.language}',
        );
        expect(code, isNotNull);
        expect(ForumThemeShare.decode(code!.text)!.name, tricky.name);
        expect(document.text, allOf(contains('My theme:'), contains('Enjoy!')));
        expect(document.querySelector('b'), isNull);
      },
    );
  }
}
