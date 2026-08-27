import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/user_summary.dart';
import 'package:discourse_native/src/shell/user_summary_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://one.example';
const _otherSite = 'https://two.example';
const _instance = DiscourseInstance(
  url: _site,
  title: 'One',
  user: DiscourseUser(username: 'reader'),
);

final class _ReadyKeys implements SiteApiKeyReader {
  @override
  Future<String?> apiKeyFor(String siteUrl) async => 'api-key';
}

final class _GatedKeys implements SiteApiKeyReader {
  final List<Completer<String?>> results = [];

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    final result = Completer<String?>();
    results.add(result);
    return result.future;
  }
}

final class _GatedSummaries implements UserSummariesApi {
  final List<Completer<UserSummary>> results = [];
  final List<({String siteUrl, String username})> requests = [];

  @override
  Future<UserSummary> userSummary({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) {
    requests.add((siteUrl: siteUrl, username: username));
    final result = Completer<UserSummary>();
    results.add(result);
    return result.future;
  }
}

void main() {
  test(
    'coalesces reads and isolates cached state by site and account',
    () async {
      final api = _GatedSummaries();
      final controller = UserSummaryController(
        api: api,
        credentials: _ReadyKeys(),
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);

      final first = controller.load(_instance);
      final duplicate = controller.load(_instance);
      await pumpEventQueue();
      expect(api.requests, [(siteUrl: _site, username: 'reader')]);
      api.results.single.complete(const UserSummary(likesGiven: 7));
      await Future.wait([first, duplicate]);

      const other = DiscourseInstance(
        url: _otherSite,
        title: 'Two',
        user: DiscourseUser(username: 'reader'),
      );
      final otherLoad = controller.load(other);
      await pumpEventQueue();
      api.results[1].complete(const UserSummary(likesGiven: 22));
      await otherLoad;

      expect(controller.stateFor(_site, 'READER').summary?.likesGiven, 7);
      expect(controller.stateFor(_otherSite, 'reader').summary?.likesGiven, 22);
      expect(controller.stateFor(_site, 'someone-else').loaded, isFalse);
    },
  );

  test('refresh retains content and publishes a recoverable error', () async {
    final api = _GatedSummaries();
    final controller = UserSummaryController(
      api: api,
      credentials: _ReadyKeys(),
      lifecycle: SiteLifecycle(),
    );
    addTearDown(controller.dispose);

    final seed = controller.load(_instance);
    await pumpEventQueue();
    const summary = UserSummary(likesReceived: 14);
    api.results.single.complete(summary);
    await seed;

    final refresh = controller.load(_instance, refresh: true);
    await pumpEventQueue();
    expect(controller.stateFor(_site, 'reader').loading, isTrue);
    expect(controller.stateFor(_site, 'reader').summary, same(summary));
    api.results[1].completeError(StateError('offline'), StackTrace.current);
    await refresh;

    final failed = controller.stateFor(_site, 'reader');
    expect(failed.loading, isFalse);
    expect(failed.summary, same(summary));
    expect(failed.error, contains("Couldn't load"));
  });

  test(
    'forget while credentials are pending sends no private request',
    () async {
      final api = _GatedSummaries();
      final keys = _GatedKeys();
      final controller = UserSummaryController(
        api: api,
        credentials: keys,
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);

      final load = controller.load(_instance);
      await pumpEventQueue();
      controller.forget(_site);
      keys.results.single.complete('stale-api-key');
      await load;

      expect(api.requests, isEmpty);
      expect(controller.stateFor(_site, 'reader').loaded, isFalse);
    },
  );

  test(
    'session rotation prevents an older response replacing new state',
    () async {
      final api = _GatedSummaries();
      final lifecycle = SiteLifecycle();
      final controller = UserSummaryController(
        api: api,
        credentials: _ReadyKeys(),
        lifecycle: lifecycle,
      );
      addTearDown(controller.dispose);

      final oldLoad = controller.load(_instance);
      await pumpEventQueue();
      lifecycle.invalidate(_site);
      controller.forget(_site);

      final replacementLoad = controller.load(_instance);
      await pumpEventQueue();
      expect(api.results, hasLength(2));
      api.results[1].complete(const UserSummary(postCount: 20));
      await replacementLoad;

      api.results[0].complete(const UserSummary(postCount: 10));
      await oldLoad;

      final state = controller.stateFor(_site, 'reader');
      expect(state.summary?.postCount, 20);
      expect(state.error, isNull);
    },
  );

  test('lifecycle invalidation during credentials stops dispatch', () async {
    final api = _GatedSummaries();
    final keys = _GatedKeys();
    final lifecycle = SiteLifecycle();
    final controller = UserSummaryController(
      api: api,
      credentials: keys,
      lifecycle: lifecycle,
    );
    addTearDown(controller.dispose);

    final load = controller.load(_instance);
    await pumpEventQueue();
    lifecycle.invalidate(_site);
    keys.results.single.complete('old-session-key');
    await load;

    expect(api.requests, isEmpty);
  });
}
