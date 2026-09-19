import 'dart:convert';

import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SiteConfig roundTrip(SiteConfig config) => SiteConfig.fromJson(
    jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>,
  );

  test('cold and old stored configurations retain default provenance', () {
    const cold = SiteConfig.unknown();
    expect(SiteConfig.fromJson(const {}), cold);
    expect(roundTrip(cold), cold);
    expect(cold.cookingKnownSettings, isEmpty);
    expect(cold.cookingSettingsStale, isFalse);
    expect(cold.cookingSettings['default_code_lang'], 'auto');
    expect(cold.cookingSettings['enable_emoji_shortcuts'], isTrue);
    expect(cold.cookingSettings['enable_inline_emoji_translation'], isFalse);
    expect(
      cold.cookingSettings['markdown_typographer_quotation_marks'],
      '“|”|‘|’',
    );
  });

  test(
    'wire values and per-field knowledge survive persistence and copies',
    () {
      final config = SiteConfig.fromSettings(const {
        'enable_emoji_shortcuts': false,
        'enable_inline_emoji_translation': true,
        'unicode_usernames': true,
        'traditional_markdown_linebreaks': true,
        'enable_markdown_typographer': false,
        'markdown_typographer_quotation_marks': '« | »|‹ | ›',
        'default_code_lang': 'ruby',
        'secure_uploads': true,
        'enable_mentions': false,
        'markdown_linkify_tlds': 'dev|example',
        'spoiler_enabled': true,
        'unknown_plugin_setting': {'credential': 'not projected'},
      });
      expect(config.emojiShortcutsEnabled, isFalse);
      expect(config.inlineEmojiTranslationEnabled, isTrue);
      expect(config.unicodeUsernames, isTrue);
      expect(config.traditionalMarkdownLinebreaks, isTrue);
      expect(config.markdownTypographerEnabled, isFalse);
      expect(config.secureUploads, isTrue);
      expect(config.cookingSettings['default_code_lang'], 'ruby');
      expect(config.cookingSettings['markdown_linkify_tlds'], 'dev|example');
      expect(config.cookingKnownSettings, hasLength(10));
      expect(config.cookingKnownSettings, isNot(contains('spoiler_enabled')));
      expect(config.cookingSettings, isNot(contains('unknown_plugin_setting')));
      expect(roundTrip(config), config);
      expect(roundTrip(config).hashCode, config.hashCode);
      expect(config.withPlugins(PluginData.none), config);
    },
  );

  test('stale knowledge is distinct from both fresh values and defaults', () {
    final fresh = SiteConfig.fromSettings(const {
      'enable_emoji_shortcuts': true,
    });
    final stale = fresh.withCookingSettingsStale(true);
    expect(stale.cookingSettings, fresh.cookingSettings);
    expect(stale.cookingKnownSettings, fresh.cookingKnownSettings);
    expect(stale, isNot(fresh));
    expect(roundTrip(stale), stale);
    expect(stale.withPlugins(PluginData.none).cookingSettingsStale, isTrue);
    expect(stale.withCookingSettingsStale(false), fresh);
    expect(fresh, isNot(const SiteConfig.unknown()));
  });

  test('malformed and unknown settings do not claim server knowledge', () {
    final config = SiteConfig.fromSettings(const {
      'enable_emoji_shortcuts': 'false',
      'unicode_usernames': 1,
      'default_code_lang': null,
      'markdown_linkify_tlds': [7],
      'plugin_secret': 'opaque',
    });
    expect(config.cookingKnownSettings, isEmpty);
    expect(config.emojiShortcutsEnabled, isTrue);
    expect(config.unicodeUsernames, isFalse);
    expect(config.defaultCodeLang, 'auto');
    expect(config.cookingSettings, isNot(contains('plugin_secret')));
  });

  test('decoding captures immutable values independently of source maps', () {
    final tlds = ['dev'];
    final input = <String, dynamic>{'markdown_linkify_tlds': tlds};
    final config = SiteConfig.fromSettings(input);
    final projected = config.cookingSettings;
    tlds.add('mutated');
    input['enable_emoji_shortcuts'] = false;
    expect(projected['markdown_linkify_tlds'], 'dev');
    expect(config.cookingKnownSettings, {'markdown_linkify_tlds'});
    expect(() => projected['enable_emoji'] = false, throwsUnsupportedError);
    expect(
      () => config.cookingKnownSettings.add('secret'),
      throwsUnsupportedError,
    );
  });

  test(
    'provenance serializes deterministically and filters unknown stored keys',
    () {
      final a = SiteConfig.fromSettings(const {
        'enable_emoji': true,
        'secure_uploads': false,
      });
      final b = SiteConfig.fromSettings(const {
        'secure_uploads': false,
        'enable_emoji': true,
      });
      expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
      final stored = a.toJson();
      (stored['cookingKnownSettings'] as List).add('plugin_secret');
      expect(SiteConfig.fromJson(stored), a);
    },
  );

  test(
    'ordinary instance persistence carries cooking settings and provenance',
    () {
      final config = SiteConfig.fromSettings(const {
        'default_code_lang': 'ruby',
      }).withCookingSettingsStale(true);
      final instance = DiscourseInstance(
        url: 'https://example.com',
        title: 'Example',
        config: config,
      );
      final restored = DiscourseInstance.fromJson(
        jsonDecode(jsonEncode(instance.toJson())) as Map<String, dynamic>,
      );
      expect(restored.config, config);
      expect(restored.copyWith(title: 'Renamed').config, config);
      expect(
        restored.copyWith(clearConfig: true).config.cookingKnownSettings,
        isEmpty,
      );
    },
  );
}
