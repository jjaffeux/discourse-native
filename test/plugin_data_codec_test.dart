import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_manifest.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/poll/poll_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

const _registry = PluginRegistry([PollPlugin()]);
const _models = DiscourseModelCodec(extensions: _registry);
const _futureSiteNamespace = 'future-plugin/site-settings';
const _futureUserNamespace = 'future-plugin/current-user';

void main() {
  test('an installed registry preserves namespaces it does not claim', () {
    final config = SiteConfig.fromJson({
      'plugins': {
        pollSettingsDataKey.id: const {
          'maximumOptions': 37,
          'defaultPublic': false,
        },
        _futureSiteNamespace: const {
          'enabled': true,
          'nested': [1, 'two', null],
        },
      },
    }, extensions: _registry);

    expect(
      config.pollSettings,
      const PollSettings(maximumOptions: 37, defaultPublic: false),
    );
    expect(config.toJson(extensions: _registry)['plugins'], {
      _futureSiteNamespace: {
        'enabled': true,
        'nested': [1, 'two', null],
      },
      pollSettingsDataKey.id: {'maximumOptions': 37, 'defaultPublic': false},
    });
  });

  test(
    'live settings refresh replaces known data and carries unknown data',
    () {
      final held = SiteConfig.fromJson({
        'plugins': {
          pollSettingsDataKey.id: const {
            'maximumOptions': 21,
            'defaultPublic': true,
          },
          _futureSiteNamespace: const {'token': 'opaque'},
        },
      }, extensions: _registry);
      final incoming = _models.siteConfig(const {
        'poll_maximum_options': 48,
        'poll_default_public': false,
      }, 'https://forum.example');

      final merged = _models.preserveUnknownSiteSettings(held, incoming);

      expect(
        merged.pollSettings,
        const PollSettings(maximumOptions: 48, defaultPublic: false),
      );
      expect(merged.toJson(extensions: _registry)['plugins'], {
        _futureSiteNamespace: {'token': 'opaque'},
        pollSettingsDataKey.id: {'maximumOptions': 48, 'defaultPublic': false},
      });
    },
  );

  test(
    'current-user refresh preserves unknown data only for the same account',
    () {
      final held = DiscourseUser.fromJson({
        'username': 'Sam',
        'id': 7,
        'plugins': {
          pollCurrentUserDataKey.id: const {'canCreatePoll': false},
          _futureUserNamespace: const {'permission': 'opaque'},
        },
      }, extensions: _registry);
      final incoming = _models.currentUser(const {
        'id': 7,
        'username': 'renamed-sam',
        'can_create_poll': true,
      }, 'https://forum.example');

      final sameAccount = _models.preserveUnknownCurrentUser(held, incoming);
      final otherAccount = _models.preserveUnknownCurrentUser(
        held,
        const DiscourseUser(id: 8, username: 'Sam'),
      );
      final missingIncomingId = _models.preserveUnknownCurrentUser(
        held,
        const DiscourseUser(username: 'Sam'),
      );

      expect(sameAccount.canCreatePoll, isTrue);
      expect(sameAccount.toJson(extensions: _registry)['plugins'], {
        _futureUserNamespace: {'permission': 'opaque'},
        pollCurrentUserDataKey.id: {'canCreatePoll': true},
      });
      expect(
        otherAccount.toJson(extensions: _registry),
        isNot(contains('plugins')),
      );
      expect(
        missingIncomingId.toJson(extensions: _registry),
        isNot(contains('plugins')),
      );
    },
  );

  test('legacy users without IDs fall back to case-insensitive usernames', () {
    final held = DiscourseUser.fromJson(const {
      'username': 'Sam',
      'plugins': {
        _futureUserNamespace: {'permission': 'opaque'},
      },
    }, extensions: _registry);

    final merged = _models.preserveUnknownCurrentUser(
      held,
      const DiscourseUser(username: 'sam'),
    );

    expect(merged.toJson(extensions: _registry)['plugins'], {
      _futureUserNamespace: {'permission': 'opaque'},
    });
  });

  test('core-only manifest does not decode optional live schemas', () async {
    final installed = PluginInstaller.install(corePluginManifest);
    addTearDown(installed.close);

    final config = installed.models.siteConfig(const {
      'poll_maximum_options': 37,
      'poll_default_public': false,
    }, 'https://forum.example');
    final user = installed.models.currentUser(const {
      'username': 'sam',
      'can_create_poll': true,
    }, 'https://forum.example');

    expect(config.plugins.isEmpty, isTrue);
    expect(user.plugins.isEmpty, isTrue);

    final storedConfig = SiteConfig.fromJson({
      'plugins': {
        pollSettingsDataKey.id: const {
          'maximumOptions': 37,
          'defaultPublic': false,
        },
      },
    }, extensions: installed.registry);
    final storedUser = DiscourseUser.fromJson({
      'username': 'sam',
      'plugins': {
        pollCurrentUserDataKey.id: const {'canCreatePoll': true},
      },
    }, extensions: installed.registry);

    expect(storedConfig.plugins.get(pollSettingsDataKey), isNull);
    expect(storedUser.plugins.get(pollCurrentUserDataKey), isNull);
    expect(storedConfig.toJson(extensions: installed.registry)['plugins'], {
      pollSettingsDataKey.id: {'maximumOptions': 37, 'defaultPublic': false},
    });
    expect(storedUser.toJson(extensions: installed.registry)['plugins'], {
      pollCurrentUserDataKey.id: {'canCreatePoll': true},
    });
  });
}
