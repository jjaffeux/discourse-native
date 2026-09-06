import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

const _registry = PluginRegistry([ReactionsPlugin()]);

void main() {
  test('Reactions plugin decodes its site-settings wire keys', () {
    final config = SiteConfig.fromSettings(const {
      'discourse_reactions_enabled': true,
      'discourse_reactions_reaction_for_like': 'heart',
      'discourse_reactions_like_icon': 'star',
      'discourse_reactions_enabled_reactions': '+1|clap',
      'discourse_reactions_allow_any_emoji': true,
      'discourse_reactions_desaturated_reaction_panel': true,
    }, extensions: _registry);

    expect(
      config.reactionsSettings,
      const ReactionsSettings(
        mainReaction: 'heart',
        likeIcon: 'star',
        offeredReactions: ['heart', '+1', 'clap'],
        allowAnyEmoji: true,
        desaturatedPanel: true,
      ),
    );
    expect(config.mainReaction, 'heart');
    expect(config.offeredReactions, ['heart', '+1', 'clap']);
    expect(config.allowAnyEmoji, isTrue);
    expect(config.desaturatedReactionPanel, isTrue);
  });

  test('Reactions settings round-trip without flat feature keys', () {
    final config = SiteConfig.fromJson({
      'plugins': {
        reactionsSettingsDataKey.id: const {
          'mainReaction': 'clap',
          'likeIcon': 'star',
          'offeredReactions': ['clap', 'heart'],
          'allowAnyEmoji': false,
          'desaturatedPanel': true,
        },
      },
    }, extensions: _registry);

    final stored = config.toJson(extensions: _registry);
    expect(stored, isNot(contains('mainReaction')));
    expect(stored['plugins'], {
      reactionsSettingsDataKey.id: {
        'mainReaction': 'clap',
        'likeIcon': 'star',
        'offeredReactions': ['clap', 'heart'],
        'allowAnyEmoji': false,
        'desaturatedPanel': true,
      },
    });
    final restored = SiteConfig.fromJson(stored, extensions: _registry);
    expect(restored, config);
    expect(restored.hashCode, config.hashCode);
  });

  test('legacy flat Reactions settings migrate into the plugin namespace', () {
    final config = SiteConfig.fromJson(const {
      'mainReaction': '+1',
      'offeredReactions': ['+1', 'laughing'],
      'allowAnyEmoji': true,
      'desaturatedReactionPanel': true,
    }, extensions: _registry);

    expect(
      config.reactionsSettings,
      const ReactionsSettings(
        mainReaction: '+1',
        offeredReactions: ['+1', 'laughing'],
        allowAnyEmoji: true,
        desaturatedPanel: true,
      ),
    );
    expect(config.toJson(extensions: _registry)['plugins'], {
      reactionsSettingsDataKey.id: {
        'mainReaction': '+1',
        'likeIcon': 'heart',
        'offeredReactions': ['+1', 'laughing'],
        'allowAnyEmoji': true,
        'desaturatedPanel': true,
      },
    });
  });

  test(
    'the like icon defaults to heart for older settings and stored data',
    () {
      expect(
        ReactionsSettings.fromSiteSettings(const {
          'discourse_reactions_enabled': true,
        }).likeIcon,
        'heart',
      );
      expect(ReactionsSettings.fromStored(const {})?.likeIcon, 'heart');
      expect(
        const ReactionsSettings(likeIcon: 'star'),
        isNot(const ReactionsSettings()),
      );
    },
  );
}
