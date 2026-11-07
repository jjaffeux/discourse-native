import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_admin.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_api.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _credential = PluginRequestCredentials(apiKey: 'key', clientId: 'client');

void main() {
  testWidgets(
    'category conversion asks for its scope after the default is saved',
    (tester) async {
      final transport = _Transport()..response = _category();
      final controller = _admin(_Reader(), transport, _Requests());
      addTearDown(controller.dispose);
      await controller.loadCategory();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: NestedRepliesSettingsPanel(controller: controller),
              ),
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('nested-convert-category')),
        findsNothing,
      );
      transport.response = _category(enabled: true);
      await tester.tap(find.byKey(const ValueKey('nested-category-default')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('nested-convert-category')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('nested-convert-category')));
      await tester.pumpAndSettle();
      expect(find.byType(DAlertDialogContent), findsOneWidget);
      expect(
        find.text(appL10n.nestedRepliesConvertConfirm('Sailing')),
        findsOneWidget,
      );
      expect(transport.writes, hasLength(1));
      await tester.tap(find.text(appL10n.cancel));
      await tester.pumpAndSettle();
      expect(transport.writes, hasLength(1));
    },
  );

  test(
    'staff still need current topic/category permission before changing them',
    () async {
      final transport = _Transport()..response = _category(canEdit: false);
      final reader = _Reader();
      final requests = _Requests();
      final controller = _admin(reader, transport, requests);
      addTearDown(controller.dispose);
      expect(controller.canChangeTopic, isTrue);
      await controller.loadCategory();
      expect(controller.canChangeCategory, isFalse);
      expect(await controller.setCategoryDefault(true), isFalse);
      expect(transport.writes, isEmpty);
      reader.staff = false;
      expect(await controller.setTopicEnabled(false), isFalse);
      expect(transport.writes, isEmpty);
    },
  );

  test(
    'category conversion follows a saved default and records its returned result',
    () async {
      final transport = _Transport()..response = _category();
      final reader = _Reader();
      final controller = _admin(reader, transport, _Requests());
      addTearDown(controller.dispose);
      await controller.loadCategory();
      expect(controller.canConvert, isFalse);
      transport.response = _category(enabled: true);
      expect(await controller.setCategoryDefault(true), isTrue);
      expect(controller.canConvert, isTrue);
      expect(transport.writes.single.body['category_setting_attributes'], {
        'nested_replies_default': true,
      });
      transport.response = {
        'success': 'OK',
        'converted_topic_count': 12,
        'nested_replies_conversion_completed': true,
      };
      expect(await controller.convertExistingTopics(), isTrue);
      expect(controller.convertedCount, 12);
      expect(controller.categoryConverted, isTrue);
      expect(controller.canConvert, isFalse);
      expect(
        transport.writes.last.path,
        '/categories/3/convert_nested_replies.json',
      );
    },
  );

  test(
    'uncertain mode writes cannot toggle again before an authoritative recheck',
    () async {
      final transport = _Transport()
        ..failure = const WriteException(WriteFailure.unreachable);
      final reader = _Reader();
      final controller = _admin(reader, transport, _Requests());
      addTearDown(controller.dispose);
      expect(await controller.setTopicEnabled(false), isFalse);
      expect(controller.problem, NestedRepliesAdminProblem.uncertain);
      expect(controller.needsRecheck, isTrue);
      expect(await controller.setTopicEnabled(false), isFalse);
      expect(transport.writes, hasLength(1));
      transport.failure = null;
      transport.response = _category();
      await controller.recheck();
      expect(controller.needsRecheck, isFalse);
      expect(reader.refreshes, 1);
      transport.response = {'is_nested_view': false};
      expect(await controller.setTopicEnabled(false), isTrue);
      expect(transport.writes, hasLength(2));
      expect(reader.refreshes, 2);
    },
  );

  test(
    'account retirement during credential access prevents a mutation',
    () async {
      final pending = Completer<PluginWriteCredential>();
      final requests = _Requests()..pendingWrite = pending;
      final reader = _Reader();
      final transport = _Transport();
      final controller = _admin(reader, transport, requests);
      addTearDown(controller.dispose);
      final operation = controller.setTopicEnabled(false);
      requests.lease.current = false;
      pending.complete((credentials: _credential, failure: null));
      expect(await operation, isFalse);
      expect(transport.writes, isEmpty);
    },
  );

  test(
    'live capability denial prevents mutations without retiring the account',
    () async {
      var enabled = true;
      final transport = _Transport();
      final controller = NestedRepliesAdminController(
        reader: _Reader(),
        api: NestedRepliesApi(transport, const DiscourseModelCodec.core()),
        categories: PluginCategorySettingsApi(transport),
        requests: _Requests(),
        settings: const NestedRepliesSettings(enabled: true),
        available: () => enabled,
      );
      addTearDown(controller.dispose);
      enabled = false;
      expect(controller.canOpen, isFalse);
      expect(await controller.setTopicEnabled(false), isFalse);
      expect(transport.writes, isEmpty);
    },
  );

  testWidgets(
    'activity revocation removes loaded content and error from the sheet',
    (tester) async {
      var available = true;
      final reader = _Reader();
      final transport = _Transport()..response = _activity();
      final controller = NestedRepliesActivityController(
        reader: reader,
        api: NestedRepliesApi(transport, const DiscourseModelCodec.core()),
        available: () => available,
      );
      addTearDown(controller.dispose);
      await controller.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: NestedRepliesActivityPanel(controller: controller),
          ),
        ),
      );
      expect(find.text(appL10n.topicCreatedBy('alice')), findsOneWidget);
      transport.failure = const WriteException(WriteFailure.unreachable);
      await controller.load(refresh: true);
      await tester.pump();
      expect(find.text(appL10n.nestedRepliesCouldNotLoad), findsOneWidget);

      available = false;
      reader.changed();
      await tester.pump();
      expect(controller.entries, isEmpty);
      expect(controller.error, isNull);
      expect(controller.loading, isFalse);
      expect(find.text(appL10n.topicCreatedBy('alice')), findsNothing);
      expect(find.text(appL10n.nestedRepliesCouldNotLoad), findsNothing);
      expect(find.text(appL10n.nestedRepliesModeUnavailable), findsOneWidget);
      expect(find.byType(DButton), findsNothing);
      await controller.load();
      expect(transport.gets, hasLength(2));
    },
  );

  test(
    'activity completed after revocation cannot ingest or replace new activity',
    () async {
      final reader = _Reader();
      final pending = Completer<Map<String, dynamic>>();
      final transport = _Transport()..pendingGet = pending;
      final controller = NestedRepliesActivityController(
        reader: reader,
        api: NestedRepliesApi(transport, const DiscourseModelCodec.core()),
      );
      addTearDown(controller.dispose);
      final retiredLoad = controller.load();
      expect(controller.loading, isTrue);
      reader.activityLog = false;
      reader.changed();
      expect(controller.loading, isFalse);
      expect(controller.entries, isEmpty);
      expect(controller.error, isNull);

      reader.activityLog = true;
      reader.changed();
      transport.pendingGet = null;
      transport.response = _activity(username: 'bob');
      await controller.load();
      pending.complete({
        'small_actions': [
          {
            'id': 102,
            'post_number': 2,
            'topic_id': 7,
            'username': 'alice',
            'cooked': '<p>Closed</p>',
            'action_code': 'closed.enabled',
          },
        ],
        'has_more': true,
      });
      await retiredLoad;
      expect(controller.entries.single.username, 'bob');
      expect(reader.canonical, isEmpty);
      expect(controller.error, isNull);
      expect(controller.loading, isFalse);
    },
  );

  test(
    'activity requires enabled topic mode and activity permission',
    () async {
      final reader = _Reader()..nestedEnabled = false;
      final transport = _Transport()..response = _activity();
      final controller = NestedRepliesActivityController(
        reader: reader,
        api: NestedRepliesApi(transport, const DiscourseModelCodec.core()),
      );
      addTearDown(controller.dispose);
      expect(controller.isAvailable, isFalse);
      await controller.load();
      expect(transport.gets, isEmpty);
      reader.nestedEnabled = true;
      reader.activityLog = false;
      reader.changed();
      expect(controller.isAvailable, isFalse);
      await controller.load();
      expect(transport.gets, isEmpty);
      reader.activityLog = true;
      reader.changed();
      await controller.load();
      expect(controller.entries, hasLength(1));
      reader.nestedEnabled = false;
      reader.changed();
      expect(controller.entries, isEmpty);
      expect(controller.isAvailable, isFalse);
    },
  );

  test(
    'activity keeps synthetic entries separate and retries the same failed page',
    () async {
      final reader = _Reader();
      final transport = _Transport()
        ..response = {
          'small_actions': [
            {
              'synthetic': true,
              'action_code': 'topic_created',
              'username': 'alice',
            },
            {
              'id': 102,
              'post_number': 2,
              'topic_id': 7,
              'username': 'alice',
              'cooked': '<p>Closed</p>',
              'action_code': 'closed.enabled',
            },
          ],
          'has_more': true,
        };
      final controller = NestedRepliesActivityController(
        reader: reader,
        api: NestedRepliesApi(transport, const DiscourseModelCodec.core()),
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.entries.map((entry) => entry.synthetic), [true, false]);
      expect(reader.canonical.keys, [102]);
      transport.failure = const WriteException(WriteFailure.unreachable);
      await controller.load();
      expect(controller.entries, hasLength(2));
      expect(controller.error, isNotNull);
      transport.failure = null;
      transport.response = {'small_actions': <Object?>[], 'has_more': false};
      await controller.load();
      expect(
        transport.gets.map((path) => Uri.parse(path).queryParameters['page']),
        ['0', '1', '1'],
      );
      expect(controller.hasMore, isFalse);
      transport.failure = const WriteException(WriteFailure.unreachable);
      await controller.load(refresh: true);
      transport.failure = null;
      await controller.load();
      expect(
        transport.gets
            .skip(3)
            .map((path) => Uri.parse(path).queryParameters['page']),
        ['0', '0'],
      );
      expect(controller.entries, isEmpty);
    },
  );
}

NestedRepliesAdminController _admin(
  _Reader reader,
  _Transport transport,
  _Requests requests,
) => NestedRepliesAdminController(
  reader: reader,
  api: NestedRepliesApi(transport, const DiscourseModelCodec.core()),
  categories: PluginCategorySettingsApi(transport),
  settings: const NestedRepliesSettings(enabled: true),
  requests: requests,
);

Map<String, dynamic> _activity({String username = 'alice'}) => {
  'small_actions': [
    {'synthetic': true, 'action_code': 'topic_created', 'username': username},
  ],
  'has_more': false,
};

Map<String, dynamic> _category({bool canEdit = true, bool enabled = false}) => {
  'category': {
    'id': 3,
    'name': 'Sailing',
    if (canEdit) 'can_edit': true,
    'category_setting': {
      'nested_replies_default': enabled,
      'other_setting': 'keep',
    },
    'custom_fields': {'other_plugin': true},
  },
};

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
  Completer<PluginWriteCredential>? pendingWrite;
  @override
  PluginSiteLease capture(String siteUrl) => lease;
  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async =>
      _credential;
  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) =>
      pendingWrite?.future ??
      Future.value((credentials: _credential, failure: null));
}

final class _Reader extends ChangeNotifier implements PluginTopicReader {
  bool current = true;
  bool staff = true;
  bool nestedEnabled = true;
  bool activityLog = true;
  void changed() => notifyListeners();
  int refreshes = 0;
  final canonical = <int, Post>{};
  final _events = StreamController<Object?>.broadcast();
  @override
  String get siteUrl => 'https://forum.example';
  @override
  String get tabId => 'tab';
  @override
  int get topicId => 7;
  @override
  ContentRoute get route =>
      ContentRoute.topic(topicId: 7, slug: 'tree', title: 'Tree');
  @override
  bool get isCurrent => current;
  @override
  bool get foreground => current;
  @override
  bool get isConnected => true;
  @override
  int? get currentUserId => 1;
  @override
  bool get currentUserStaff => staff;
  @override
  DiscourseModelCodec get models => const DiscourseModelCodec.core();
  @override
  TopicDetail? get topic => models
      .topic({
        'id': 7,
        'title': 'Tree',
        'category_id': 3,
        'details': {'can_edit': true},
      }, siteUrl)
      .detail
      .withPlugins(
        PluginData.none.withValue(
          nestedRepliesTopicKey,
          NestedTopicData(enabled: nestedEnabled, hasActivityLog: activityLog),
        ),
      );
  @override
  Post? post(int postId) => canonical[postId];
  @override
  Future<AcceptedTopicContent<T>?> ingest<T>(
    Future<TopicContentResult<T>> Function(PluginRequestCredentials request)
    read,
  ) async {
    final result = await read(_credential);
    if (!current) return null;
    for (final item in result.posts) {
      canonical[item.post.id] = item.post;
    }
    return AcceptedTopicContent(
      value: result.value,
      postIds: result.posts.map((item) => item.post.id),
      revision: 1,
    );
  }

  @override
  void reply({int? parentPostNumber, String? username}) {}
  @override
  void edit(int postId) {}
  @override
  void navigate({int? postNumber, String? query, bool replace = false}) {}
  @override
  bool updateQuery(String? query) => false;
  @override
  Future<void> observeVisible(Iterable<int> postNumbers) async {}
  @override
  Future<void> reconcileVisit() async {}
  @override
  Future<void> refreshMetadata() async {
    refreshes++;
  }

  @override
  void setVisiblePostIds(Iterable<int> postIds) {}
  @override
  Stream<Object?> get topicEvents => _events.stream;
  @override
  void close() {
    current = false;
    unawaited(_events.close());
  }
}

final class _Transport implements PluginApiTransport {
  Map<String, dynamic> response = {};
  Object? failure;
  Completer<Map<String, dynamic>>? pendingGet;
  final gets = <String>[];
  final writes = <({String path, Map<String, Object?> body})>[];
  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    gets.add(path);
    if (failure != null) throw failure!;
    return pendingGet?.future ?? response;
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
    writes.add((path: path, body: body));
    if (failure != null) throw failure!;
    return response;
  }
}
