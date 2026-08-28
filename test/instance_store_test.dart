import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bundled_plugins.dart';
import 'support/site_appearance_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = InstanceStore();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('load', () {
    test('answers an empty rail when nothing was stored', () async {
      expect(await store.load(), isEmpty);
    });

    test('answers an empty rail when the stored blob is blank', () async {
      SharedPreferences.setMockInitialValues({
        'discourse_native.instances': '',
      });
      expect(await store.load(), isEmpty);
    });

    test('answers an empty rail when the stored blob cannot be read', () async {
      SharedPreferences.setMockInitialValues({
        'discourse_native.instances': 'not json',
      });
      expect(await store.load(), isEmpty);

      SharedPreferences.setMockInitialValues({
        'discourse_native.instances': '[1, 2, 3]',
      });
      expect(await store.load(), isEmpty);
    });

    test('keeps valid sites when another stored entry is malformed', () async {
      SharedPreferences.setMockInitialValues({
        'discourse_native.instances': '''[
          {"url":"https://one.example","title":"One"},
          {"url":7,"title":"Broken"},
          null,
          {"url":"https://two.example","title":"Two"},
          {"url":"https://one.example","title":"Duplicate"}
        ]''',
      });

      final loaded = await store.load();

      expect(loaded.map((instance) => instance.url), [
        'https://one.example',
        'https://two.example',
      ]);
      expect(loaded.map((instance) => instance.title), ['One', 'Two']);
    });

    test('keeps HTTPS and loopback HTTP origins in canonical form', () async {
      SharedPreferences.setMockInitialValues({
        'discourse_native.instances': jsonEncode([
          {'url': 'https://secure.example/', 'title': 'Secure'},
          {'url': 'https://secure-port.example:8443', 'title': 'Secure port'},
          {'url': 'http://localhost:3000/', 'title': 'Localhost'},
          {'url': 'http://dev.localhost:4200', 'title': 'Localhost subdomain'},
          {'url': 'http://127.42.0.1:8080', 'title': 'IPv4 loopback'},
          {'url': 'http://[::1]:3000', 'title': 'IPv6 loopback'},
        ]),
      });

      final loaded = await store.load();

      expect(loaded.map((instance) => instance.url), [
        'https://secure.example',
        'https://secure-port.example:8443',
        'http://localhost:3000',
        'http://dev.localhost:4200',
        'http://127.42.0.1:8080',
        'http://[::1]:3000',
      ]);
      expect(loaded.map((instance) => instance.host), [
        'secure.example',
        'secure-port.example:8443',
        'localhost:3000',
        'dev.localhost:4200',
        '127.42.0.1:8080',
        '::1:3000',
      ]);
    });

    test('drops unsafe, malformed, and non-origin stored URLs', () async {
      SharedPreferences.setMockInitialValues({
        'discourse_native.instances': jsonEncode([
          {'url': 'https://kept.example', 'title': 'Kept'},
          {'url': 'http://remote.example', 'title': 'Plaintext remote'},
          {'url': 'ftp://remote.example', 'title': 'Wrong scheme'},
          {'url': '//relative.example', 'title': 'Scheme relative'},
          {'url': 'relative.example', 'title': 'Relative'},
          {
            'url': 'https://reader:password@remote.example',
            'title': 'Credentials',
          },
          {'url': 'https://remote.example/forum', 'title': 'Path'},
          {'url': 'https://remote.example?api_key=secret', 'title': 'Query'},
          {'url': 'https://remote.example#secret', 'title': 'Fragment'},
          {'url': 'https://remote.example:invalid', 'title': 'Invalid port'},
          {'url': 'https://[broken', 'title': 'Malformed'},
        ]),
      });

      final loaded = await store.load();

      expect(loaded, hasLength(1));
      expect(loaded.single.url, 'https://kept.example');
      expect(loaded.single.host, 'kept.example');
    });

    test(
      'ignores malformed optional appearance without dropping its site',
      () async {
        SharedPreferences.setMockInitialValues({
          'discourse_native.instances': '''[
          {
            "url":"https://one.example",
            "title":"One",
            "appearance":{"base":{"primary":7}}
          }
        ]''',
        });

        final loaded = await store.load();

        expect(loaded, hasLength(1));
        expect(loaded.single.url, 'https://one.example');
        expect(loaded.single.appearance, isNull);
      },
    );
  });

  group('round trip', () {
    test('brings back everything save() was given', () async {
      final pluginStore = InstanceStore(models: installedPlugins.models);
      final instance = DiscourseInstance(
        url: 'https://meta.discourse.org',
        title: 'Meta',
        description: 'About Discourse',
        iconUrl: 'https://meta.discourse.org/uploads/default/icon.png',
        apiVersion: 20250101,
        loginRequired: true,
        user: const DiscourseUser(
          username: 'sam',
          id: 3,
          name: 'Sam Saffron',
          avatarUrl: 'https://meta.discourse.org/avatar.png',
          draftCount: 3,
        ),
        config: SiteConfig(
          emojiSet: 'apple_classic',
          externalEmojiUrl: 'https://cdn.example.com/emoji',
          plugins: PluginData.none.withValue(
            reactionsSettingsDataKey,
            const ReactionsSettings(
              mainReaction: 'heart',
              offeredReactions: ['heart', '+1'],
              allowAnyEmoji: true,
              desaturatedPanel: true,
            ),
          ),
        ),
      );

      await pluginStore.save([instance]);
      final loaded = await pluginStore.load();

      expect(loaded, hasLength(1));
      final back = loaded.single;
      expect(back.url, instance.url);
      expect(back.title, instance.title);
      expect(back.description, instance.description);
      expect(back.iconUrl, instance.iconUrl);
      expect(back.apiVersion, instance.apiVersion);
      expect(back.loginRequired, instance.loginRequired);
      expect(back.user, instance.user);
      expect(back.config, instance.config);
    });

    test(
      'preserves uninstalled plugin namespaces through load and save',
      () async {
        const siteNamespaces = {
          'future-plugin/site-settings': {
            'enabled': true,
            'nested': [1, 'two', null],
          },
        };
        const userNamespaces = {
          'future-plugin/current-user': {'permission': 'maybe'},
        };
        SharedPreferences.setMockInitialValues({
          SharedPreferencesInstancePersistence.storageKey: jsonEncode([
            {
              'url': 'https://future.example',
              'title': 'Future',
              'config': {'plugins': siteNamespaces},
              'user': {'username': 'sam', 'plugins': userNamespaces},
            },
          ]),
        });
        final coreStore = InstanceStore();

        final loaded = await coreStore.load();
        await coreStore.save(loaded);

        final raw = SharedPreferences.getInstance().then(
          (preferences) => preferences.getString(
            SharedPreferencesInstancePersistence.storageKey,
          ),
        );
        final saved = jsonDecode((await raw)!) as List<dynamic>;
        final entry = saved.single as Map<String, dynamic>;
        expect(
          (entry['config'] as Map<String, dynamic>)['plugins'],
          siteNamespaces,
        );
        expect(
          (entry['user'] as Map<String, dynamic>)['plugins'],
          userNamespaces,
        );
      },
    );

    test('migrates flat plugin fields into installed namespaces', () async {
      SharedPreferences.setMockInitialValues({
        SharedPreferencesInstancePersistence.storageKey: jsonEncode([
          {
            'url': 'https://legacy.example',
            'title': 'Legacy',
            'config': {
              'mainReaction': 'clap',
              'offeredReactions': ['clap', '+1'],
              'allowAnyEmoji': true,
              'desaturatedReactionPanel': true,
              'pollMaximumOptions': 1,
              'pollDefaultPublic': false,
              'localDatesEnabled': true,
              'localDateFormats': ['LLL'],
              'localDateTimezones': ['Etc/UTC'],
              'gifsEnabled': true,
              'gifFileDetail': 'gif',
              'gifResultLimitEnabled': true,
              'gifMaxResults': 48,
              'assignStatusesEnabled': true,
              'assignStatuses': ['New', 'Done'],
              'chatUploadsEnabled': false,
              'chatSearchEnabled': true,
              'chatChannelRetentionDays': 30,
              'chatDmRetentionDays': 7,
              'resenha': {'enabled': true},
            },
            'user': {
              'username': 'sam',
              'canCreatePoll': true,
              'canAssign': false,
              'canAssignGlobally': true,
              'hasChatEnabled': true,
              'chatHeaderIndicatorPreference': 'only_mentions',
              'lastChatChannelId': 42,
            },
          },
        ]),
      });
      final pluginStore = InstanceStore(models: installedPlugins.models);

      final loaded = await pluginStore.load();
      await pluginStore.save(loaded);

      final preferences = await SharedPreferences.getInstance();
      final saved =
          jsonDecode(
                preferences.getString(
                  SharedPreferencesInstancePersistence.storageKey,
                )!,
              )
              as List<dynamic>;
      final entry = saved.single as Map<String, dynamic>;
      final config = entry['config'] as Map<String, dynamic>;
      final user = entry['user'] as Map<String, dynamic>;
      expect((config['plugins'] as Map<String, dynamic>).keys, {
        'discourse-reactions/site-settings',
        'poll/site-settings',
        'discourse-local-dates/site-settings',
        'gifs/site-settings',
        'discourse-assign/site-settings',
        'chat/site-settings',
      });
      expect((user['plugins'] as Map<String, dynamic>).keys, {
        'poll/current-user',
        'discourse-assign/current-user',
        'chat/current-user',
      });
      expect(config, isNot(contains('mainReaction')));
      expect(config, isNot(contains('pollMaximumOptions')));
      expect(config, isNot(contains('resenha')));
      expect(user, isNot(contains('canCreatePoll')));
      expect(user, isNot(contains('hasChatEnabled')));
      expect(
        ((config['plugins'] as Map<String, dynamic>)['poll/site-settings']
            as Map<String, dynamic>)['maximumOptions'],
        1,
      );
    });

    test(
      'core-only load and save preserves plugin notification counters',
      () async {
        final pluginStore = InstanceStore(models: installedPlugins.models);
        final coreStore = InstanceStore();
        final connected = DiscourseInstance(
          url: 'https://counter.example.com',
          title: 'Counter',
          user: const DiscourseUser(id: 7, username: 'sam'),
          notificationTotals: chatNotificationTotals(
            unreadNotifications: 2,
            chatNotifications: 7,
          ),
        );

        await pluginStore.save([connected]);
        final coreLoaded = await coreStore.load();
        expect(coreLoaded.single.notificationTotals?.unreadNotifications, 2);
        await coreStore.save(coreLoaded);

        final restored = (await pluginStore.load()).single.notificationTotals!;
        expect(restored.hasChatEnabled, isTrue);
        expect(restored.chatNotifications, 7);
      },
    );

    test('keeps the rail in order, and keeps a signed-out site', () async {
      const first = DiscourseInstance(
        url: 'https://one.example.com',
        title: 'One',
      );
      const second = DiscourseInstance(
        url: 'https://two.example.com',
        title: 'Two',
      );

      await store.save([first, second]);
      final loaded = await store.load();

      expect(loaded.map((i) => i.url), [first.url, second.url]);
      expect(loaded.every((i) => !i.isConnected), isTrue);
    });

    test('persists a resolved site appearance', () async {
      final appearance = siteAppearance(
        accent: const Color(0xFF123456),
        alternateAccent: const Color(0xFFABCDEF),
      );
      final instance = DiscourseInstance(
        url: 'https://theme.example.com',
        title: 'Theme',
        appearance: appearance,
      );

      await store.save([instance]);
      final loaded = await store.load();

      expect(loaded.single.appearance, appearance);
    });

    test('saving an empty rail wipes the stored one', () async {
      await store.save([
        const DiscourseInstance(url: 'https://one.example.com', title: 'One'),
      ]);
      await store.save(const []);

      expect(await store.load(), isEmpty);
    });

    test('overlapping saves persist the newest snapshot', () async {
      const first = DiscourseInstance(
        url: 'https://one.example.com',
        title: 'One',
      );
      const second = DiscourseInstance(
        url: 'https://two.example.com',
        title: 'Two',
      );
      const third = DiscourseInstance(
        url: 'https://three.example.com',
        title: 'Three',
      );
      final gate = Completer<void>();
      final persistence = ControlledInstancePersistence(firstWriteGate: gate);
      final controlledStore = InstanceStore(persistence: persistence);

      final firstSave = controlledStore.save([first]);
      await persistence.firstWriteStarted.future;
      final secondSave = controlledStore.save([second]);
      final thirdSave = controlledStore.save([third]);

      await Future<void>.delayed(Duration.zero);
      expect(persistence.writeCount, 1);
      expect(thirdSave, same(secondSave));

      gate.complete();
      await Future.wait([firstSave, secondSave, thirdSave]);

      expect(persistence.writeCount, 2);
      expect((await controlledStore.load()).single, third);
    });

    test('a failed write does not strand a newer snapshot', () async {
      const first = DiscourseInstance(
        url: 'https://one.example.com',
        title: 'One',
      );
      const second = DiscourseInstance(
        url: 'https://two.example.com',
        title: 'Two',
      );
      final gate = Completer<void>();
      final failure = StateError('disk unavailable');
      final persistence = ControlledInstancePersistence(
        firstWriteGate: gate,
        firstWriteError: failure,
      );
      final controlledStore = InstanceStore(persistence: persistence);

      final firstSave = controlledStore.save([first]);
      final firstFailure = expectLater(firstSave, throwsA(same(failure)));
      await persistence.firstWriteStarted.future;
      final secondSave = controlledStore.save([second]);

      gate.complete();
      await firstFailure;
      await secondSave;

      expect(persistence.writeCount, 2);
      expect((await controlledStore.load()).single, second);
    });

    test('replacement stores preserve request order', () async {
      const old = DiscourseInstance(
        url: 'https://old.example.com',
        title: 'Old',
      );
      const latest = DiscourseInstance(
        url: 'https://latest.example.com',
        title: 'Latest',
      );
      final gate = Completer<void>();
      final persistence = ControlledInstancePersistence(firstWriteGate: gate);
      final oldStore = InstanceStore(persistence: persistence);
      final replacementStore = InstanceStore(persistence: persistence);

      final oldSave = oldStore.save([old]);
      await persistence.firstWriteStarted.future;
      final replacementSave = replacementStore.save([latest]);

      await Future<void>.delayed(Duration.zero);
      expect(persistence.writeCount, 1);

      gate.complete();
      await Future.wait([oldSave, replacementSave]);

      expect(persistence.writeCount, 2);
      expect((await replacementStore.load()).single, latest);
    });

    test(
      "replacement save wins over an older store's pending snapshot",
      () async {
        const inFlight = DiscourseInstance(
          url: 'https://in-flight.example.com',
          title: 'In flight',
        );
        const stalePending = DiscourseInstance(
          url: 'https://stale-pending.example.com',
          title: 'Stale pending',
        );
        const latest = DiscourseInstance(
          url: 'https://latest.example.com',
          title: 'Latest',
        );
        final gate = Completer<void>();
        final persistence = ControlledInstancePersistence(firstWriteGate: gate);
        final oldStore = InstanceStore(persistence: persistence);
        final replacementStore = InstanceStore(persistence: persistence);

        final inFlightSave = oldStore.save([inFlight]);
        await persistence.firstWriteStarted.future;
        final staleSave = oldStore.save([stalePending]);
        final latestSave = replacementStore.save([latest]);

        await Future<void>.delayed(Duration.zero);
        expect(persistence.writeCount, 1);

        gate.complete();
        await Future.wait([inFlightSave, staleSave, latestSave]);

        expect(persistence.writeCount, 2);
        expect((await replacementStore.load()).single, latest);
      },
    );

    test(
      'replacement load waits for an in-flight and locally pending save',
      () async {
        const inFlight = DiscourseInstance(
          url: 'https://in-flight.example.com',
          title: 'In flight',
        );
        const latest = DiscourseInstance(
          url: 'https://latest.example.com',
          title: 'Latest',
        );
        final gate = Completer<void>();
        final persistence = ControlledInstancePersistence(firstWriteGate: gate);
        final oldStore = InstanceStore(persistence: persistence);
        final replacementStore = InstanceStore(persistence: persistence);

        final inFlightSave = oldStore.save([inFlight]);
        await persistence.firstWriteStarted.future;
        final latestSave = oldStore.save([latest]);
        final loading = replacementStore.load();

        await Future<void>.delayed(Duration.zero);
        expect(persistence.readCount, 0);

        gate.complete();
        await Future.wait([inFlightSave, latestSave]);

        expect((await loading).single, latest);
        expect(persistence.readCount, 1);
        expect(persistence.writeCount, 2);
      },
    );
  });
}

final class ControlledInstancePersistence implements InstancePersistence {
  ControlledInstancePersistence({this.firstWriteGate, this.firstWriteError});

  final Completer<void>? firstWriteGate;
  final Object? firstWriteError;
  final Completer<void> firstWriteStarted = Completer<void>();

  String? stored;
  int readCount = 0;
  int writeCount = 0;

  @override
  Future<String?> read() async {
    readCount++;
    return stored;
  }

  @override
  Future<void> write(String value) async {
    writeCount++;
    if (writeCount == 1) {
      firstWriteStarted.complete();
      await firstWriteGate?.future;
      if (firstWriteError case final error?) throw error;
    }
    stored = value;
  }
}
