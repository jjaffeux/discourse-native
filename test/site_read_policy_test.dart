import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_about.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/shell/site_read_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _noForwarding = (username: null, apiKey: null, clientId: null);

void main() {
  group('the five public reads', () {
    test('drop an orphaned key on a signed-out site', () async {
      final h = _Harness(user: null);

      await h.readAll(apiKey: 'orphaned', clientId: 'orphaned-client');

      expect(h.api.reads, {
        'appearance': _noForwarding,
        'config': _noForwarding,
        'customEmojis': _noForwarding,
        'emojiCatalog': _noForwarding,
        'emojiSearchAliases': _noForwarding,
      });
    });

    test('drop an orphaned key for a site no longer stored', () async {
      final h = _Harness(user: null)..current = null;

      await h.readAll(apiKey: 'orphaned', clientId: 'orphaned-client');

      expect(h.api.reads.values, everyElement(_noForwarding));
      expect(h.api.reads, hasLength(5));
    });

    test('forward the account of a connected site', () async {
      final h = _Harness(user: const DiscourseUser(id: 7, username: 'reader'));

      await h.readAll(apiKey: 'key', clientId: 'client');

      const forwarded = (username: null, apiKey: 'key', clientId: 'client');
      expect(h.api.reads, {
        'appearance': (username: 'reader', apiKey: 'key', clientId: 'client'),
        'config': forwarded,
        'customEmojis': forwarded,
        'emojiCatalog': forwarded,
        'emojiSearchAliases': forwarded,
      });
    });

    test('stay anonymous on a connected site with no key', () async {
      final h = _Harness(user: const DiscourseUser(id: 7, username: 'reader'));

      await h.readAll(apiKey: null, clientId: 'client');

      expect(h.api.reads.values, everyElement(_noForwarding));
    });
  });

  group('loadForumAbout', () {
    test('reads a public site anonymously, ignoring a stored key', () async {
      final h = _Harness(user: null);
      h.credentials.keys[_site] = 'orphaned';

      await h.policy.loadForumAbout(_site);

      expect(h.api.aboutKeys, [null]);
    });

    test('a connected site without a key is unreachable', () async {
      final h = _Harness(user: const DiscourseUser(id: 7, username: 'reader'));

      await expectLater(
        h.policy.loadForumAbout(_site),
        throwsA(isA<SiteLookupException>()),
      );
      expect(h.api.aboutKeys, isEmpty);
    });

    test('a result outliving its account lease is withheld', () async {
      final h = _Harness(user: const DiscourseUser(id: 7, username: 'reader'));
      h.credentials.keys[_site] = 'key';
      final gate = Completer<void>();
      h.api.aboutGate = gate.future;

      final reading = h.policy.loadForumAbout(_site);
      await pumpEventQueue();
      expect(h.api.aboutKeys, ['key']);
      h.lifecycle.invalidate(_site);
      gate.complete();

      await expectLater(reading, throwsA(isA<SiteLookupException>()));
    });

    test('a result outliving the shell is withheld', () async {
      final h = _Harness(user: const DiscourseUser(id: 7, username: 'reader'));
      h.credentials.keys[_site] = 'key';
      final gate = Completer<void>();
      h.api.aboutGate = gate.future;

      final reading = h.policy.loadForumAbout(_site);
      await pumpEventQueue();
      h.disposed = true;
      gate.complete();

      await expectLater(reading, throwsA(isA<SiteLookupException>()));
    });
  });
}

typedef _Forwarded = ({String? username, String? apiKey, String? clientId});

final class _Harness {
  _Harness({required DiscourseUser? user})
    : current = instance('meta.discourse.org', user: user) {
    policy = SiteReadPolicy(
      siteAppearance: api.siteAppearance,
      siteConfig: api.siteConfig,
      customEmojis: api.customEmojis,
      emojiCatalog: api.emojiCatalog,
      emojiSearchAliases: api.emojiSearchAliases,
      forumAbout: api.forumAbout,
      credentials: credentials,
      lifecycle: lifecycle,
      instanceFor: (_) => current,
      isDisposed: () => disposed,
    );
  }

  final api = _RecordingApi();
  final credentials = FakeApiCredentialReader();
  final lifecycle = SiteLifecycle();
  DiscourseInstance? current;
  bool disposed = false;
  late final SiteReadPolicy policy;

  Future<void> readAll({
    required String? apiKey,
    required String? clientId,
  }) async {
    await policy.loadAppearance(
      siteUrl: _site,
      apiKey: apiKey,
      clientId: clientId,
    );
    await policy.loadConfig(siteUrl: _site, apiKey: apiKey, clientId: clientId);
    await policy.loadCustomEmojis(
      siteUrl: _site,
      apiKey: apiKey,
      clientId: clientId,
    );
    await policy.loadEmojiCatalog(
      siteUrl: _site,
      apiKey: apiKey,
      clientId: clientId,
    );
    await policy.loadEmojiSearchAliases(
      siteUrl: _site,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}

final class _RecordingApi extends FakeDiscourseApi {
  final reads = <String, _Forwarded>{};
  final aboutKeys = <String?>[];
  Future<void>? aboutGate;

  @override
  Future<SiteAppearance?> siteAppearance({
    required String siteUrl,
    String? username,
    String? apiKey,
    String? clientId,
  }) async {
    reads['appearance'] = (
      username: username,
      apiKey: apiKey,
      clientId: clientId,
    );
    return null;
  }

  @override
  Future<SiteConfig> siteConfig({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    reads['config'] = (username: null, apiKey: apiKey, clientId: clientId);
    return const SiteConfig();
  }

  @override
  Future<Map<String, String>> customEmojis({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    reads['customEmojis'] = (
      username: null,
      apiKey: apiKey,
      clientId: clientId,
    );
    return const {};
  }

  @override
  Future<SiteEmojiCatalog> emojiCatalog({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    reads['emojiCatalog'] = (
      username: null,
      apiKey: apiKey,
      clientId: clientId,
    );
    return SiteEmojiCatalog.empty;
  }

  @override
  Future<Map<String, List<String>>> emojiSearchAliases({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    reads['emojiSearchAliases'] = (
      username: null,
      apiKey: apiKey,
      clientId: clientId,
    );
    return const {};
  }

  @override
  Future<ForumAbout> forumAbout({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    aboutKeys.add(apiKey);
    await aboutGate;
    return const ForumAbout(title: 'About');
  }
}
