import 'dart:async';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/topic_filter_lookups.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

void main() {
  test('a lookup whose account stays current answers its result', () async {
    final h = _Harness();

    final found = h.lookups.searchUsers(siteUrl: _site, term: 's');
    await pumpEventQueue();
    h.api.lookupGate.complete();

    expect((await found).single.name, 'sam');
  });

  test('a result arriving after its account retired is withheld', () async {
    final h = _Harness();

    final found = h.lookups.searchUsers(siteUrl: _site, term: 's');
    await pumpEventQueue();
    expect(h.api.searches, ['s']);
    h.lifecycle.invalidate(_site);
    h.api.lookupGate.complete();

    expect(await found, isEmpty);
  });

  test('a result arriving after disposal is withheld', () async {
    final h = _Harness();

    final found = h.lookups.searchUsers(siteUrl: _site, term: 's');
    await pumpEventQueue();
    h.disposed = true;
    h.api.lookupGate.complete();

    expect(await found, isEmpty);
  });

  test('an account retired during the key read starts no lookup', () async {
    final credentials = _GatedCredentials();
    final h = _Harness(credentials: credentials);

    final found = h.lookups.searchUsers(siteUrl: _site, term: 's');
    await pumpEventQueue();
    h.lifecycle.invalidate(_site);
    credentials.pending.complete('key');

    expect(await found, isEmpty);
    expect(h.api.searches, isEmpty);
  });

  test('a failed lookup answers empty', () async {
    final h = _Harness();

    final found = h.lookups.run<String>(
      _site,
      (_, _) => Future.error(StateError('offline')),
    );

    expect(await found, isEmpty);
  });

  test('group search stays local without an account', () async {
    final h = _Harness(credentials: FakeApiCredentialReader());

    expect(await h.lookups.searchGroups(siteUrl: _site, term: 'x'), isEmpty);
    expect(h.api.groupSearches, 0);
  });
}

final class _Harness {
  _Harness({FakeApiCredentialReader? credentials})
    : credentials =
          credentials ?? (FakeApiCredentialReader()..keys[_site] = 'key') {
    lookups = TopicFilterLookups(
      topicFeeds: api,
      lookups: api,
      credentials: this.credentials,
      lifecycle: lifecycle,
      isDisposed: () => disposed,
    );
  }

  final api = _Api();
  final FakeApiCredentialReader credentials;
  final lifecycle = SiteLifecycle();
  bool disposed = false;
  late final TopicFilterLookups lookups;
}

final class _Api extends FakeDiscourseApi {
  final lookupGate = Completer<void>();
  final searches = <String>[];
  int groupSearches = 0;

  @override
  Future<List<FoundUser>> searchUsers({
    required String siteUrl,
    required String term,
    int? topicId,
    int limit = 10,
    String? apiKey,
    String? clientId,
  }) async {
    searches.add(term);
    await lookupGate.future;
    return const [FoundUser(username: 'sam', name: 'sam')];
  }

  @override
  Future<List<TopicFilterLookupValue>> searchFilterGroups({
    required String siteUrl,
    required String term,
    int limit = 10,
    String? apiKey,
    String? clientId,
  }) async {
    groupSearches++;
    return const [];
  }
}

final class _GatedCredentials extends FakeApiCredentialReader {
  final pending = Completer<String?>();

  @override
  Future<String?> apiKeyFor(String siteUrl) => pending.future;
}
