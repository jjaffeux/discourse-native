import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_api.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_data.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://forum.example';
const _credentials = PluginRequestCredentials(
  apiKey: 'key',
  clientId: 'client',
);

void main() {
  test('pin writes serialize and publish the returned pin state', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.transport.pending = Completer();
    final first = h.service.togglePin(_UnmountedContext(), _site, 7, 103);
    await pumpEventQueue();
    expect(h.service.pinBusy(_site, 7), isTrue);
    await h.service.togglePin(_UnmountedContext(), _site, 7, 103);
    expect(h.transport.writes, hasLength(1));
    h.transport.pending!.complete({
      'pinned_post_ids': [103],
    });
    await first;
    expect(h.topic.plugins.get(nestedRepliesTopicKey)?.pinnedPostIds, [103]);
    expect(h.service.pinBusy(_site, 7), isFalse);
    expect(h.closedReaders, 1);
  });

  test(
    'an uncertain pin rechecks state before another toggle is allowed',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.transport.failure = const WriteException(WriteFailure.unreachable);
      await h.service.togglePin(_UnmountedContext(), _site, 7, 103);
      expect(h.transport.writes, hasLength(1));
      h.transport.failure = null;
      h.transport.response = {
        'topic': {'id': 7, 'is_nested_view': true},
        'roots': <Object?>[],
        'page': 0,
        'has_more_roots': false,
        'pinned_post_ids': [103],
      };
      await h.service.togglePin(_UnmountedContext(), _site, 7, 103);
      expect(h.transport.writes, hasLength(1));
      expect(h.transport.gets.single, contains('/n/tree/7.json'));
      expect(h.transport.gets.single, isNot(contains('track_visit')));
      expect(h.topic.plugins.get(nestedRepliesTopicKey)?.pinnedPostIds, [103]);
      h.transport.response = {'pinned_post_ids': <int>[]};
      await h.service.togglePin(_UnmountedContext(), _site, 7, 103);
      expect(h.transport.writes, hasLength(2));
      expect(
        h.topic.plugins.get(nestedRepliesTopicKey)?.pinnedPostIds,
        isEmpty,
      );
    },
  );

  for (final withdrawal in ['mode', 'staff', 'account']) {
    test(
      '$withdrawal withdrawal during credentials prevents pin dispatch',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        h.requests.pending = Completer();
        final write = h.service.togglePin(_UnmountedContext(), _site, 7, 103);
        await pumpEventQueue();
        switch (withdrawal) {
          case 'mode':
            h.topic = h.topic.withPlugins(
              PluginData.none.withValue(
                nestedRepliesTopicKey,
                const NestedTopicData(enabled: false),
              ),
            );
          case 'staff':
            h.staff = false;
          case 'account':
            h.requests.lease.current = false;
        }
        h.requests.pending!.complete(_credentials);
        await write;
        expect(h.transport.writes, isEmpty);
        expect(h.service.pinBusy(_site, 7), isFalse);
        expect(h.closedReaders, 1);
      },
    );
  }
}

final class _Harness implements PluginTopicReaderHost {
  final transport = _Transport();
  final requests = _Requests();
  final records = _Records();
  bool staff = true;
  int closedReaders = 0;
  TopicDetail topic =
      const TopicDetail(
        id: 7,
        title: 'Tree',
        stream: [],
        canEdit: true,
      ).withPlugins(
        PluginData.none.withValue(
          nestedRepliesTopicKey,
          const NestedTopicData(enabled: true),
        ),
      );
  late final service = NestedRepliesServices(
    api: NestedRepliesApi(transport, const DiscourseModelCodec.core()),
    requests: requests,
    siteState: PluginSiteStateHost(
      currentUserFor: (_) => null,
      siteConfigFor: (_) => SiteConfig(
        plugins: PluginData.none.withValue(
          nestedRepliesSettingsKey,
          const NestedRepliesSettings(enabled: true),
        ),
      ),
    ),
    readers: this,
    records: records,
    topics: PluginTopicRefreshHost(reloadTopic: (_, _) async {}),
    targets: _UnusedTarget(),
    navigation: _UnusedNavigation(),
    accounts: _UnusedAccount(),
  );
  @override
  PluginTopicReader forVisibleTopic(String siteUrl, int topicId) =>
      _Reader(this);
  void dispose() {
    service.dispose();
    records.notifier.dispose();
  }
}

final class _Reader extends ChangeNotifier implements PluginTopicReader {
  _Reader(this.h);
  final _Harness h;
  bool closed = false;
  @override
  bool get isCurrent => !closed && h.requests.lease.isCurrent;
  @override
  bool get foreground => isCurrent;
  @override
  String get siteUrl => _site;
  @override
  TopicDetail get topic => h.topic;
  @override
  bool get currentUserStaff => h.staff;
  @override
  ContentRoute get route =>
      ContentRoute.topic(topicId: 7, slug: 'tree', title: 'Tree');
  @override
  Future<AcceptedTopicContent<T>?> ingest<T>(
    Future<TopicContentResult<T>> Function(PluginRequestCredentials) read,
  ) async {
    final result = await read(_credentials);
    if (!isCurrent) return null;
    if (result.metadata case final metadata?) h.topic = metadata;
    return AcceptedTopicContent(
      value: result.value,
      postIds: const [],
      revision: 1,
    );
  }

  @override
  void close() {
    if (!closed) h.closedReaders++;
    closed = true;
    dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Lease implements PluginSiteLease {
  bool _current = true;
  final _retirementObservers = <void Function()>{};
  bool get current => _current;
  set current(bool value) {
    _current = value;
    if (!value) {
      final observers = _retirementObservers.toList();
      _retirementObservers.clear();
      for (final observer in observers) {
        observer();
      }
    }
  }

  @override
  bool get isCurrent => current;
  @override
  bool commit(VoidCallback mutation) {
    if (!current) return false;
    mutation();
    return true;
  }

  @override
  void Function() onRetire(void Function() observer) {
    if (!isCurrent) {
      observer();
      return () {};
    }
    _retirementObservers.add(observer);
    return () => _retirementObservers.remove(observer);
  }
}

final class _Requests implements PluginRequestHost {
  final lease = _Lease();
  Completer<PluginRequestCredentials>? pending;
  @override
  PluginSiteLease capture(String siteUrl) => lease;
  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async =>
      pending?.future ?? _credentials;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Records implements PluginTopicRecordsHost {
  final notifier = ChangeNotifier();
  @override
  Listenable get changes => notifier;
  @override
  void invalidate(String siteUrl, PluginSiteLease originalLease) {}
}

final class _UnusedNavigation implements PluginNavigationHost {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnusedTarget implements PluginTargetHost {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnusedAccount implements PluginFreshAccountHost {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnmountedContext implements BuildContext {
  @override
  bool get mounted => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Transport implements PluginApiTransport {
  final writes = <String>[];
  final gets = <String>[];
  Completer<Map<String, dynamic>>? pending;
  Object? failure;
  Map<String, dynamic> response = {};
  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    gets.add(path);
    if (failure case final failure?) throw failure;
    return response;
  }

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    writes.add(path);
    if (failure case final failure?) throw failure;
    return pending?.future ?? response;
  }
}
