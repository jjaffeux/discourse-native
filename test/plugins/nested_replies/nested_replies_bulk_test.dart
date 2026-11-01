import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_api.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_bulk.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://forum.example';
const _credentials = PluginRequestCredentials(
  apiKey: 'key',
  clientId: 'client',
);
const _first = Topic(id: 7, title: 'Sailing', slug: 'sailing');
const _second = Topic(id: 8, title: 'Harbour', slug: 'harbour');

void main() {
  test(
    'only enabled optional-mode sites and staff can select public topics',
    () {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.settings(null);
      fixture.controller.start(_site);
      expect(fixture.controller.selecting(_site), isFalse);
      fixture.settings(const NestedRepliesSettings(enabled: false));
      expect(fixture.controller.available(_site), isFalse);
      fixture.settings(
        const NestedRepliesSettings(enabled: true, defaultEnabled: true),
      );
      expect(fixture.controller.available(_site), isFalse);
      fixture.settings(const NestedRepliesSettings(enabled: true));
      fixture.user = const DiscourseUser(username: 'member');
      expect(fixture.controller.available(_site), isFalse);
      fixture.user = const DiscourseUser(username: 'staff', staff: true);
      fixture.controller.start(_site);
      fixture.controller.toggle(
        _site,
        const Topic(id: 9, title: 'Message', slug: 'pm', privateMessage: true),
      );
      fixture.controller.toggle(_site, _first);
      expect(fixture.controller.selectedTopicIds(_site), {7});
      expect(fixture.transport.writes, isEmpty);
    },
  );

  test(
    'partial bulk response refreshes changed topics and retains refused selection',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.select([_first, _second]);
      fixture.transport.response = {
        'topic_ids': [7],
        'errors': ['Not permitted'],
      };
      expect(await fixture.controller.submit(_site, enabled: true), isFalse);
      expect(fixture.transport.writes.single.path, '/topics/bulk.json');
      expect(fixture.transport.writes.single.method, 'PUT');
      expect(fixture.transport.writes.single.body, <String, Object?>{
        'topic_ids': [7, 8],
        'operation': {'type': 'enable_nested_view'},
      });
      expect(fixture.refreshes, [
        [7],
      ]);
      expect(fixture.controller.selectedTopicIds(_site), {8});
      expect(
        fixture.controller.problem(_site),
        NestedRepliesBulkProblem.partial,
      );
      expect(fixture.controller.selecting(_site), isTrue);
      fixture.transport.response = {
        'topic_ids': [8],
      };
      expect(await fixture.controller.submit(_site, enabled: false), isTrue);
      expect(fixture.transport.writes.last.body['operation'], {
        'type': 'disable_nested_view',
      });
      expect(fixture.controller.selecting(_site), isFalse);
      expect(fixture.controller.selectedTopicIds(_site), isEmpty);
    },
  );

  test('retirement during credential acquisition prevents the write', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.select([_first]);
    final credential = Completer<PluginWriteCredential>();
    fixture.requests.pending = credential.future;
    final operation = fixture.controller.submit(_site, enabled: true);
    fixture.requests.lease.current = false;
    credential.complete((credentials: _credentials, failure: null));
    expect(await operation, isFalse);
    expect(fixture.transport.writes, isEmpty);
    expect(fixture.refreshes, isEmpty);
  });

  test(
    'retired response cannot refresh or clear a successor selection',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.select([_first]);
      final pending = Completer<Map<String, dynamic>>();
      fixture.transport.pending = pending.future;
      final operation = fixture.controller.submit(_site, enabled: true);
      await Future<void>.delayed(Duration.zero);
      expect(fixture.transport.writes, hasLength(1));
      fixture.requests.lease.current = false;
      fixture.requests.lease = _Lease();
      fixture.controller.start(_site);
      fixture.controller.toggle(_site, _second);
      pending.complete({
        'topic_ids': [7],
      });
      expect(await operation, isFalse);
      expect(fixture.refreshes, isEmpty);
      expect(fixture.controller.selectedTopicIds(_site), {8});
      expect(fixture.controller.busy(_site), isFalse);
    },
  );

  test(
    'uncertain writes require a successful state refresh before another write',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.select([_first]);
      fixture.transport.failure = const WriteException(
        WriteFailure.unreachable,
      );
      expect(await fixture.controller.submit(_site, enabled: false), isFalse);
      expect(fixture.controller.needsRecheck(_site), isTrue);
      expect(
        fixture.controller.problem(_site),
        NestedRepliesBulkProblem.uncertain,
      );
      expect(await fixture.controller.submit(_site, enabled: false), isFalse);
      expect(fixture.transport.writes, hasLength(1));
      fixture.refreshFailure = StateError('Offline');
      await fixture.controller.recheck(_site);
      expect(fixture.controller.needsRecheck(_site), isTrue);
      fixture.refreshFailure = null;
      await fixture.controller.recheck(_site);
      expect(fixture.refreshes, [
        [7],
        [7],
      ]);
      expect(fixture.controller.needsRecheck(_site), isFalse);
      expect(fixture.transport.writes, hasLength(1));
      fixture.transport.failure = null;
      fixture.transport.response = {
        'topic_ids': [7],
      };
      expect(await fixture.controller.submit(_site, enabled: false), isTrue);
      expect(fixture.transport.writes, hasLength(2));
    },
  );

  test(
    'cancel does not bypass uncertainty and recheck retains original targets',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.select([_first]);
      fixture.transport.failure = const WriteException(
        WriteFailure.unreachable,
      );
      await fixture.controller.submit(_site, enabled: true);
      fixture.controller.cancel(_site);
      fixture.controller.start(_site);
      fixture.controller.toggle(_site, _second);
      expect(fixture.controller.selectedTopicIds(_site), isEmpty);
      expect(await fixture.controller.submit(_site, enabled: false), isFalse);
      expect(fixture.transport.writes, hasLength(1));
      await fixture.controller.recheck(_site);
      expect(fixture.refreshes, [
        [7],
      ]);
      expect(fixture.controller.needsRecheck(_site), isFalse);
      fixture.controller.toggle(_site, _second);
      expect(fixture.controller.selectedTopicIds(_site), {8});
    },
  );

  test(
    'a definite refusal does not require uncertain-outcome recovery',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.select([_first]);
      fixture.transport.failure = const WriteException(WriteFailure.forbidden);
      expect(await fixture.controller.submit(_site, enabled: true), isFalse);
      expect(fixture.controller.needsRecheck(_site), isFalse);
      expect(
        fixture.controller.problem(_site),
        NestedRepliesBulkProblem.failed,
      );
      expect(fixture.controller.selectedTopicIds(_site), {7});
    },
  );

  test(
    'an unrelated changed id is not accepted as successful local state',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.select([_first]);
      fixture.transport.response = {
        'topic_ids': [99],
      };
      expect(await fixture.controller.submit(_site, enabled: true), isFalse);
      expect(fixture.refreshes, isEmpty);
      expect(fixture.controller.needsRecheck(_site), isTrue);
      expect(fixture.controller.selectedTopicIds(_site), {7});
    },
  );

  test(
    'capability revocation clears selection and prevents pending writes',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.select([_first]);
      final credential = Completer<PluginWriteCredential>();
      fixture.requests.pending = credential.future;
      final operation = fixture.controller.submit(_site, enabled: true);
      fixture.settings(const NestedRepliesSettings(enabled: false));
      credential.complete((credentials: _credentials, failure: null));
      expect(await operation, isFalse);
      expect(fixture.controller.selecting(_site), isFalse);
      expect(fixture.controller.selectedTopicIds(_site), isEmpty);
      expect(fixture.transport.writes, isEmpty);
    },
  );

  testWidgets('bulk controls select a topic and submit the chosen operation', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.transport.response = {
      'topic_ids': [7],
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: Column(
              children: [
                NestedRepliesBulkActions(
                  controller: fixture.controller,
                  siteUrl: _site,
                ),
                NestedRepliesBulkTitle(
                  controller: fixture.controller,
                  siteUrl: _site,
                  topic: _first,
                  title: const Text('Sailing'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('nested-bulk-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DCheckbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${appL10n.nestedRepliesSettings} (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(appL10n.nestedRepliesBulkEnable));
    await tester.pumpAndSettle();
    expect(fixture.transport.writes, hasLength(1));
    expect(fixture.transport.writes.single.body['operation'], {
      'type': 'enable_nested_view',
    });
    expect(fixture.refreshes, [
      [7],
    ]);
    expect(find.byType(DCheckbox), findsNothing);
    expect(find.text('Sailing'), findsOneWidget);
  });

  testWidgets(
    'selection decorates the title once and checkbox does not activate it',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      var opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: NestedRepliesBulkTitle(
                controller: fixture.controller,
                siteUrl: _site,
                topic: _first,
                title: DButton(
                  label: const Text('Sailing'),
                  onPressed: () => opens++,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Sailing'), findsOneWidget);
      expect(find.byType(DCheckbox), findsNothing);
      fixture.controller.start(_site);
      await tester.pump();
      expect(find.text('Sailing'), findsOneWidget);
      await tester.tap(find.byType(DCheckbox));
      await tester.pump();
      expect(fixture.controller.selectedTopicIds(_site), {7});
      expect(opens, 0);
      await tester.tap(find.text('Sailing'));
      expect(opens, 1);
      fixture.controller.cancel(_site);
      await tester.pump();
      expect(find.byType(DCheckbox), findsNothing);
      expect(find.text('Sailing'), findsOneWidget);
    },
  );
}

final class _Fixture {
  _Fixture() {
    settings(const NestedRepliesSettings(enabled: true));
    controller = NestedRepliesBulkController(
      api: NestedRepliesApi(transport, const DiscourseModelCodec.core()),
      requests: requests,
      siteState: PluginSiteStateHost(
        currentUserFor: (_) => user,
        siteConfigFor: (_) => config.value,
        siteConfigListenableFor: (_) => config,
      ),
      onChanged: (_, ids) async {
        refreshes.add(List.of(ids));
        if (refreshFailure != null) throw refreshFailure!;
      },
    );
  }

  final transport = _Transport();
  final requests = _Requests();
  final config = ValueNotifier(const SiteConfig.unknown());
  DiscourseUser? user = const DiscourseUser(username: 'staff', staff: true);
  late final NestedRepliesBulkController controller;
  final List<List<int>> refreshes = [];
  Object? refreshFailure;

  void settings(NestedRepliesSettings? settings) {
    config.value = SiteConfig(
      plugins: settings == null
          ? PluginData.none
          : PluginData.none.withValue(nestedRepliesSettingsKey, settings),
    );
  }

  void select(List<Topic> topics) {
    controller.start(_site);
    for (final topic in topics) {
      controller.toggle(_site, topic);
    }
  }

  void dispose() {
    controller.dispose();
    config.dispose();
  }
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
  _Lease lease = _Lease();
  Future<PluginWriteCredential>? pending;
  @override
  PluginSiteLease capture(String siteUrl) => lease;
  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async =>
      _credentials;
  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) =>
      pending ?? Future.value((credentials: _credentials, failure: null));
}

final class _Transport implements PluginApiTransport {
  final writes = <({String path, String method, Map<String, Object?> body})>[];
  Map<String, dynamic> response = {'topic_ids': <int>[]};
  Object? failure;
  Future<Map<String, dynamic>>? pending;

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) => throw StateError('Bulk selection must not read topic trees.');

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    writes.add((path: path, method: method, body: body));
    if (failure != null) throw failure!;
    return pending ?? response;
  }
}
