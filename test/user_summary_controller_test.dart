import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/user_summary.dart';
import 'package:discourse_native/src/shell/user_summary_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _oneUrl = 'https://one.example';
const _twoUrl = 'https://two.example';
const _one = DiscourseInstance(
  url: _oneUrl,
  title: 'One',
  user: DiscourseUser(username: 'reader-one'),
);
const _two = DiscourseInstance(
  url: _twoUrl,
  title: 'Two',
  user: DiscourseUser(username: 'reader-two'),
);

final class _SummaryRequest {
  _SummaryRequest(this.siteUrl, this.username);

  final String siteUrl;
  final String username;
  final Completer<UserSummary> result = Completer<UserSummary>();
}

final class _GatedSummaryApi implements UserSummariesApi {
  final List<_SummaryRequest> requests = [];

  @override
  Future<UserSummary> userSummary({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) {
    final request = _SummaryRequest(siteUrl, username);
    requests.add(request);
    return request.result.future;
  }
}

final class _ReadyKeys implements SiteApiKeyReader {
  @override
  Future<String?> apiKeyFor(String siteUrl) async => 'key-$siteUrl';
}

final class _GatedKeys implements SiteApiKeyReader {
  final List<Completer<String?>> results = [];
  final List<String> sites = [];

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    sites.add(siteUrl);
    final result = Completer<String?>();
    results.add(result);
    return result.future;
  }
}

void main() {
  test(
    'loads and refreshes one account without dropping held content',
    () async {
      final api = _GatedSummaryApi();
      final controller = UserSummaryController(
        api: api,
        credentials: _ReadyKeys(),
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);

      final first = controller.load(_one);
      await pumpEventQueue();
      expect(controller.stateFor(_oneUrl).loading, isTrue);
      expect(api.requests.single.username, 'reader-one');
      api.requests.single.result.complete(const UserSummary(daysVisited: 4));
      await first;

      expect(controller.stateFor(_oneUrl).summary?.daysVisited, 4);
      final refresh = controller.load(_one, refresh: true);
      await pumpEventQueue();
      expect(controller.stateFor(_oneUrl).summary?.daysVisited, 4);
      expect(controller.stateFor(_oneUrl).loading, isTrue);
      api.requests.last.result.complete(const UserSummary(daysVisited: 9));
      await refresh;

      expect(controller.stateFor(_oneUrl).summary?.daysVisited, 9);
      expect(controller.stateFor(_oneUrl).loading, isFalse);
    },
  );

  test('forum summaries remain isolated', () async {
    final api = _GatedSummaryApi();
    final controller = UserSummaryController(
      api: api,
      credentials: _ReadyKeys(),
      lifecycle: SiteLifecycle(),
    );
    addTearDown(controller.dispose);

    final one = controller.load(_one);
    await pumpEventQueue();
    final two = controller.load(_two);
    await pumpEventQueue();
    api.requests[0].result.complete(const UserSummary(daysVisited: 1));
    api.requests[1].result.complete(const UserSummary(daysVisited: 2));
    await Future.wait([one, two]);

    expect(controller.stateFor(_oneUrl).summary?.daysVisited, 1);
    expect(controller.stateFor(_twoUrl).summary?.daysVisited, 2);
    expect(api.requests.map((request) => request.username), [
      'reader-one',
      'reader-two',
    ]);
  });

  test(
    'session rotation rejects a stale response from the former account',
    () async {
      final api = _GatedSummaryApi();
      final lifecycle = SiteLifecycle();
      final controller = UserSummaryController(
        api: api,
        credentials: _ReadyKeys(),
        lifecycle: lifecycle,
      );
      addTearDown(controller.dispose);

      final former = controller.load(_one);
      await pumpEventQueue();
      lifecycle.invalidate(_oneUrl);
      controller.forget(_oneUrl);

      const replacement = DiscourseInstance(
        url: _oneUrl,
        title: 'One',
        user: DiscourseUser(username: 'replacement'),
      );
      final current = controller.load(replacement);
      await pumpEventQueue();
      api.requests.last.result.complete(const UserSummary(daysVisited: 20));
      await current;

      api.requests.first.result.complete(const UserSummary(daysVisited: 99));
      await former;

      expect(controller.stateFor(_oneUrl).summary?.daysVisited, 20);
      expect(api.requests.map((request) => request.username), [
        'reader-one',
        'replacement',
      ]);
    },
  );

  test(
    'rotation while credentials are pending sends no stale request',
    () async {
      final api = _GatedSummaryApi();
      final credentials = _GatedKeys();
      final lifecycle = SiteLifecycle();
      final controller = UserSummaryController(
        api: api,
        credentials: credentials,
        lifecycle: lifecycle,
      );
      addTearDown(controller.dispose);

      final load = controller.load(_one);
      await pumpEventQueue();
      lifecycle.invalidate(_oneUrl);
      controller.forget(_oneUrl);
      credentials.results.single.complete('former-key');
      await load;

      expect(api.requests, isEmpty);
      expect(controller.stateFor(_oneUrl).summary, isNull);
    },
  );

  test('dispose while credentials are pending sends no request', () async {
    final api = _GatedSummaryApi();
    final credentials = _GatedKeys();
    final controller = UserSummaryController(
      api: api,
      credentials: credentials,
      lifecycle: SiteLifecycle(),
    );

    final load = controller.load(_one);
    await pumpEventQueue();
    controller.dispose();
    credentials.results.single.complete('stale-key');
    await load;

    expect(api.requests, isEmpty);
  });
}
