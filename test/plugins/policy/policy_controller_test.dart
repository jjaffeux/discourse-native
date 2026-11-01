import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/policy/policies_api.dart';
import 'package:discourse_native/src/plugins/policy/policy_controller.dart';
import 'package:discourse_native/src/plugins/policy/policy_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const site = 'https://forum.example';
const otherSite = 'https://other.example';
const openPolicy = PolicyPostData(
  canAccept: true,
  canRevoke: false,
  accepted: false,
  revoked: false,
  statistics: PolicyStatisticsHidden(),
);
const acceptedPolicy = PolicyPostData(
  canAccept: false,
  canRevoke: true,
  accepted: true,
  revoked: false,
  statistics: PolicyStatisticsHidden(),
);
Post post(PolicyPostData policy) => Post(
  id: 7,
  postNumber: 1,
  username: 'author',
  cooked: '<div class="policy">Read this</div>',
  plugins: PluginData.none.withValue(policyPostKey, policy),
);
Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late _Api api;
  late _Requests requests;
  late _Posts posts;
  late PolicyController controller;
  late SiteConfig config;
  setUp(() {
    api = _Api();
    requests = _Requests();
    posts = _Posts();
    posts.records[site] = post(openPolicy);
    config = const SiteConfig();
    controller = PolicyController(
      api: api,
      requests: requests,
      posts: posts,
      siteState: PluginSiteStateHost(
        currentUserFor: (_) => null,
        siteConfigFor: (_) => config,
      ),
      freshAccount: _Fresh(),
      accounts: _Accounts(),
    );
  });
  tearDown(() => controller.dispose());

  test(
    'acceptance waits for server refresh and shares the host write lane',
    () async {
      api.gate = Completer<void>();
      posts.refreshGate = Completer<void>();
      final lease = controller.captureSiteSession(site);
      final write = controller.act(
        siteUrl: site,
        topicId: 3,
        postId: 7,
        action: PolicyAction.accept,
        lease: lease,
      );
      await flush();
      expect(api.writes, 1);
      expect(posts.records[site]!.plugins.policy!.accepted, isFalse);
      expect(controller.interaction(site, 7).phase, PolicyWritePhase.sending);
      expect(
        await controller.act(
          siteUrl: site,
          topicId: 3,
          postId: 7,
          action: PolicyAction.accept,
          lease: lease,
        ),
        PolicyMutationKind.busy,
      );
      api.gate!.complete();
      await flush();
      expect(
        controller.interaction(site, 7).phase,
        PolicyWritePhase.refreshing,
      );
      expect(posts.records[site]!.plugins.policy!.accepted, isFalse);
      posts.afterRefresh = post(acceptedPolicy);
      posts.refreshGate!.complete();
      expect(await write, PolicyMutationKind.confirmed);
      expect(posts.records[site]!.plugins.policy!.accepted, isTrue);
      expect(posts.busy, isEmpty);
    },
  );

  test(
    'ambiguous response cannot be retried until the host confirms a refresh',
    () async {
      api.failure = const WriteException(WriteFailure.unreachable);
      posts.fresh = false;
      final original = posts.records[site];
      expect(
        await controller.act(
          siteUrl: site,
          topicId: 3,
          postId: 7,
          action: PolicyAction.accept,
          lease: controller.captureSiteSession(site),
        ),
        PolicyMutationKind.uncertain,
      );
      expect(controller.interaction(site, 7).phase, PolicyWritePhase.uncertain);
      expect(
        await controller.act(
          siteUrl: site,
          topicId: 3,
          postId: 7,
          action: PolicyAction.accept,
          lease: controller.captureSiteSession(site),
        ),
        PolicyMutationKind.busy,
      );
      expect(api.writes, 1);
      await controller.checkStatus(
        siteUrl: site,
        topicId: 3,
        postId: 7,
        lease: controller.captureSiteSession(site),
      );
      expect(controller.interaction(site, 7).phase, PolicyWritePhase.uncertain);
      posts.fresh = true;
      await controller.checkStatus(
        siteUrl: site,
        topicId: 3,
        postId: 7,
        lease: controller.captureSiteSession(site),
      );
      expect(controller.interaction(site, 7).phase, PolicyWritePhase.idle);
      expect(posts.records[site], same(original));
      expect(posts.records[site]!.plugins.policy!.canAccept, isTrue);
      expect(api.writes, 1);
    },
  );

  test(
    'explicit disabled settings stop actions but stale config does not override post authority',
    () async {
      config = SiteConfig(
        plugins: PluginData.none.withValue(
          policySettingsKey,
          const PolicySettings(enabled: false),
        ),
      );
      expect(
        await controller.act(
          siteUrl: site,
          topicId: 3,
          postId: 7,
          action: PolicyAction.accept,
          lease: controller.captureSiteSession(site),
        ),
        PolicyMutationKind.inactive,
      );
      expect(api.writes, 0);
      config = SiteConfig(cookingSettingsStale: true, plugins: config.plugins);
      expect(controller.enabled(site), isTrue);
    },
  );

  test(
    'account retirement during synchronous lane admission dispatches no write',
    () async {
      posts.onBegin = () {
        requests.rotate();
        controller.forget(site);
        posts.busy.clear();
      };
      expect(
        await controller.act(
          siteUrl: site,
          topicId: 3,
          postId: 7,
          action: PolicyAction.accept,
          lease: controller.captureSiteSession(site),
        ),
        PolicyMutationKind.inactive,
      );
      expect(api.writes, 0);
      expect(controller.interaction(site, 7).phase, PolicyWritePhase.idle);
    },
  );

  test(
    'explicit refusal remains confirmed old state and does not call refresh',
    () async {
      api.failure = const WriteException(
        WriteFailure.validation,
        errors: ['User does not exist in group'],
      );
      expect(
        await controller.act(
          siteUrl: site,
          topicId: 3,
          postId: 7,
          action: PolicyAction.accept,
          lease: controller.captureSiteSession(site),
        ),
        PolicyMutationKind.refused,
      );
      expect(posts.refreshes, 0);
      expect(controller.interaction(site, 7).error, same(api.failure));
      expect(posts.records[site]!.plugins.policy!.accepted, isFalse);
    },
  );

  test(
    'retired write cannot refresh or release the replacement account lane',
    () async {
      api.gate = Completer<void>();
      final old = controller.act(
        siteUrl: site,
        topicId: 3,
        postId: 7,
        action: PolicyAction.accept,
        lease: controller.captureSiteSession(site),
      );
      await flush();
      requests.rotate();
      controller.forget(site);
      posts.busy.clear();
      posts.beginWrite(site, 7);
      api.gate!.complete();
      expect(await old, PolicyMutationKind.inactive);
      expect(posts.refreshes, 0);
      expect(posts.writeInFlight(site, 7), isTrue);
    },
  );

  test('post IDs on different sites have independent state', () async {
    posts.records[otherSite] = post(openPolicy);
    api.gate = Completer<void>();
    final first = controller.act(
      siteUrl: site,
      topicId: 3,
      postId: 7,
      action: PolicyAction.accept,
      lease: controller.captureSiteSession(site),
    );
    await flush();
    expect(controller.interaction(otherSite, 7).pending, isFalse);
    final second = controller.act(
      siteUrl: otherSite,
      topicId: 3,
      postId: 7,
      action: PolicyAction.accept,
      lease: controller.captureSiteSession(otherSite),
    );
    await flush();
    expect(api.writes, 2);
    api.gate!.complete();
    await Future.wait([first, second]);
  });

  test(
    'hidden statistics and retired pages never request or publish identities',
    () async {
      expect(
        await controller.participants(
          siteUrl: site,
          postId: 7,
          list: PolicyParticipantList.accepted,
          offset: 0,
          lease: controller.captureSiteSession(site),
        ),
        isNull,
      );
      expect(api.pages, 0);
      posts.records[site] = post(
        PolicyPostData(
          canAccept: true,
          canRevoke: false,
          accepted: false,
          revoked: false,
          statistics: PolicyStatisticsVisible(
            acceptedCount: 1,
            outstandingCount: 0,
            acceptedPreview: const [],
            outstandingPreview: const [],
          ),
        ),
      );
      api.pageGate = Completer<PolicyUsersPage>();
      final page = controller.participants(
        siteUrl: site,
        postId: 7,
        list: PolicyParticipantList.accepted,
        offset: 0,
        lease: controller.captureSiteSession(site),
      );
      await flush();
      expect(api.pages, 1);
      requests.rotate();
      controller.forget(site);
      api.pageGate!.complete(PolicyUsersPage(users: [], receivedCount: 0));
      expect(await page, isNull);
    },
  );

  test('foreground refreshes only retained policies', () async {
    final release = controller.retain(siteUrl: site, topicId: 3, postId: 7);
    posts.afterRefresh = post(openPolicy);
    controller.setForeground(true);
    await flush();
    expect(posts.refreshes, 1);
    release();
    controller.setForeground(true);
    await flush();
    expect(posts.refreshes, 1);
  });

  test(
    'disposal releases its lane but a late completion cannot change state',
    () async {
      api.gate = Completer<void>();
      final write = controller.act(
        siteUrl: site,
        topicId: 3,
        postId: 7,
        action: PolicyAction.accept,
        lease: controller.captureSiteSession(site),
      );
      await flush();
      controller.dispose();
      expect(posts.busy, isEmpty);
      posts.beginWrite(site, 7);
      api.gate!.complete();
      expect(await write, PolicyMutationKind.inactive);
      expect(posts.writeInFlight(site, 7), isTrue);
      // tearDown receives an already disposed ChangeNotifier only in this case.
      controller = PolicyController(
        api: api,
        requests: requests,
        posts: posts,
        siteState: PluginSiteStateHost(
          currentUserFor: (_) => null,
          siteConfigFor: (_) => config,
        ),
        freshAccount: _Fresh(),
        accounts: _Accounts(),
      );
    },
  );
}

final class _Api implements PoliciesApi {
  int writes = 0, pages = 0;
  Completer<void>? gate;
  Completer<PolicyUsersPage>? pageGate;
  Object? failure;
  @override
  Future<void> mutate({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required int postId,
    required PolicyAction action,
  }) async {
    writes++;
    await gate?.future;
    if (failure case final error?) throw error;
  }

  @override
  Future<PolicyUsersPage> participants({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required int postId,
    required PolicyParticipantList list,
    required int offset,
  }) {
    pages++;
    return pageGate?.future ??
        Future.value(PolicyUsersPage(users: [], receivedCount: 0));
  }
}

final class _Lease implements PluginSiteLease {
  _Lease(this.host, this.generation);
  final _Requests host;
  final int generation;
  @override
  bool get isCurrent => generation == host.generation;
  @override
  bool commit(VoidCallback action) {
    if (!isCurrent) return false;
    action();
    return true;
  }
}

final class _Requests implements PluginRequestHost {
  int generation = 0;
  void rotate() => generation++;
  @override
  PluginSiteLease capture(String siteUrl) => _Lease(this, generation);
  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async =>
      const PluginRequestCredentials(apiKey: 'key', clientId: 'client');
  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) async =>
      (credentials: await credentialsFor(siteUrl), failure: null);
}

final class _Posts implements PluginPostHost {
  final records = <String, Post>{};
  final busy = <(String, int)>{};
  int refreshes = 0;
  VoidCallback? onBegin;
  Completer<void>? refreshGate;
  Post? afterRefresh;
  bool fresh = true;
  @override
  bool beginWrite(String siteUrl, int postId) {
    final admitted = busy.add((siteUrl, postId));
    if (admitted) onBegin?.call();
    return admitted;
  }

  @override
  void endWrite(String siteUrl, int postId) => busy.remove((siteUrl, postId));
  @override
  Post? readPost(String siteUrl, int postId) => records[siteUrl];
  @override
  bool topicArchived(String siteUrl, int topicId) => false;
  @override
  bool writeInFlight(String siteUrl, int postId) =>
      busy.contains((siteUrl, postId));
  @override
  void updatePluginRecord<T extends Object>(
    String siteUrl,
    int postId,
    PluginDataKey<T> key,
    T? Function(T?) update,
  ) => throw UnimplementedError();
  @override
  Future<bool> refreshPost({
    required String siteUrl,
    required int topicId,
    required int postId,
    required String? apiKey,
    required PluginSiteLease lease,
  }) async {
    refreshes++;
    await refreshGate?.future;
    if (afterRefresh case final value?) {
      lease.commit(() => records[siteUrl] = value);
    }
    return fresh && lease.isCurrent;
  }
}

final class _Fresh implements PluginFreshAccountHost {
  @override
  PluginFreshAccountProfile? profileFor(String siteUrl) => null;
  @override
  T? recordFor<T extends Object>(String siteUrl, PluginDataKey<T> key) => null;
}

final class _Accounts implements PluginAccountConnectionHost {
  @override
  bool isConnected(String siteUrl) => true;
  @override
  Future<String?> connect(String siteUrl) async => null;
}
