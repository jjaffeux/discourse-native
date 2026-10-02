import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _reader = DiscourseUser(
  id: 7,
  username: 'reader',
  unifiedNewEnabled: true,
);
const _replacement = DiscourseUser(
  id: 8,
  username: 'replacement',
  unifiedNewEnabled: true,
);
const _category = TopicCategory(
  id: 21,
  name: 'Support',
  slug: 'support',
  color: '0088cc',
);
const _tag = TopicTag(id: 4, name: 'Support');
const _rows = [
  Topic(
    id: 1,
    title: 'A support topic',
    slug: 'support-topic',
    categoryId: 21,
    tags: [_tag],
  ),
  Topic(id: 2, title: 'An unrelated topic', slug: 'unrelated-topic'),
];

enum _Scope { tag, category }

enum _Change { unchanged, global, failedReconnect, failedDisconnect, reconnect }

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          null,
        ),
  );
  for (final scope in _Scope.values) {
    for (final change in _Change.values) {
      testWidgets(
        'Native Dismiss New ${scope.name} ${change.name} owns its '
        'rendered scope before repaint',
        (tester) async {
          final fixture = await _open(tester, scope);
          final shell = fixture.shell;
          final button = find.byKey(const ValueKey('dismiss-new-topics'));
          expect(tester.widget(button), isA<DButton>());
          final element = tester.element(button);
          final source = shell.topicListContent!;
          final lease = shell.lifecycle.capture(_site);
          expect(shell.currentFeed!.topicIds, [1]);
          if (change == _Change.global) {
            shell.clearTopicListFilters();
            await tester.runAsync(() => pumpEventQueue());
            expect(shell.topicListContent, isNot(source));
            expect(shell.topicListContent!.tagNames, isEmpty);
            expect(shell.topicListContent!.categoryId, isNull);
            expect(shell.currentFeed!.topicIds, [1, 2]);
          } else if (change != _Change.unchanged) {
            fixture.store.failSignedOut = change != _Change.reconnect;
            if (change == _Change.failedDisconnect) {
              expect(
                await tester.runAsync(() => shell.disconnectInstance(_site)),
                isFalse,
              );
            } else {
              await tester.runAsync(shell.connectCurrentInstance);
            }
            expect(lease.isCurrent, isFalse);
            expect(
              shell.currentInstance?.user?.id,
              change == _Change.reconnect ? 8 : 7,
            );
            if (change == _Change.reconnect) {
              await shell.selectTopicListMode(TopicListMode.newActivity);
            }
            await shell.loadFeed(shell.currentFeedId!);
            await tester.runAsync(() => pumpEventQueue());
            expect(shell.canDismissNewTopics, isTrue);
          }
          expect(tester.element(button), same(element));
          await tester.tap(button);
          await _pump(tester);
          if (change == _Change.unchanged) {
            expect(fixture.api.writes, hasLength(1));
            _expectScope(fixture.api.writes.single, scope, 'old-key');
          } else {
            expect(fixture.api.writes, isEmpty);
            expect(shell.currentFeed!.topicIds, isNotEmpty);
            // Repainted controls express the current feed/account's intent.
            expect(button, findsOneWidget);
            await tester.tap(button);
            await _pump(tester);
            expect(fixture.api.writes, hasLength(1));
            _expectScope(
              fixture.api.writes.single,
              change == _Change.global || change == _Change.reconnect
                  ? null
                  : scope,
              change == _Change.reconnect ? 'replacement-key' : 'old-key',
            );
          }
          expect(tester.takeException(), isNull);
        },
        variant: const TargetPlatformVariant({
          TargetPlatform.iOS,
          TargetPlatform.android,
          TargetPlatform.macOS,
        }),
      );
    }
  }

  testWidgets(
    'an accepted Native tag dismissal keeps its scope while navigating',
    (tester) async {
      final fixture = await _open(tester, _Scope.tag);
      final gate = Completer<void>();
      fixture.api.writeGate = gate;
      await tester.tap(find.byKey(const ValueKey('dismiss-new-topics')));
      await tester.pump();
      expect(fixture.api.writes, hasLength(1));
      _expectScope(fixture.api.writes.single, _Scope.tag, 'old-key');
      fixture.shell.clearTopicListFilters();
      await _pump(tester);
      expect(fixture.shell.currentFeed!.topicIds, [1, 2]);
      gate.complete();
      await _pump(tester);
      expect(fixture.api.writes, hasLength(1));
      expect(fixture.shell.topicListContent!.tagNames, isEmpty);
      expect(fixture.shell.currentFeed!.topicIds, [1, 2]);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
      TargetPlatform.macOS,
    }),
  );
}

void _expectScope(http.Request request, _Scope? scope, String key) {
  expect(request.method, 'PUT');
  expect(request.url, Uri.parse('$_site/topics/reset-new'));
  expect(request.headers['User-Api-Key'], key);
  expect(jsonDecode(request.body), {
    'tracked': false,
    'dismiss_topics': true,
    'dismiss_posts': true,
    if (scope == _Scope.tag) 'tag_name': 'Support',
    if (scope == _Scope.category) ...{
      'category_id': 21,
      'include_subcategories': true,
    },
  });
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<({ShellController shell, _Api api, _Store store})> _open(
  WidgetTester tester,
  _Scope scope,
) async {
  final site = instance('meta.discourse.org').copyWith(user: _reader);
  final store = _Store([site]);
  final api = _Api();
  addTearDown(api.transport.close);
  await pumpShell(
    tester,
    defaultTargetPlatform == TargetPlatform.macOS ? desktop : phone,
    instances: [site],
    store: store,
    api: api,
    authenticator: _Authenticator()..keys[_site] = 'old-key',
  );
  final shell = ShellScope.read(tester.element(primaryMainContent));
  await shell.selectTopicListMode(TopicListMode.newActivity);
  if (scope == _Scope.tag) {
    shell.selectTopicListTag('Support');
  } else {
    shell.selectTopicListCategory(_category);
  }
  await tester.runAsync(() => pumpEventQueue());
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('dismiss-new-topics')), findsOneWidget);
  return (shell: shell, api: api, store: store);
}

class _Api extends FakeDiscourseApi {
  _Api() : super(user: _reader) {
    accounts['replacement-key'] = _replacement;
    transport = DiscourseApi(
      client: MockClient((request) async {
        writes.add(request);
        await writeGate?.future;
        return http.Response('{"topic_ids":[1]}', 200);
      }),
    );
  }
  late final DiscourseApi transport;
  final writes = <http.Request>[];
  Completer<void>? writeGate;

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    feedPaths.add(path);
    final global = path == '/latest.json' || path == '/new.json';
    return TopicList(
      topics: global ? _rows : [_rows.first],
      categories: const [_category],
    );
  }

  @override
  Future<List<int>> dismissNewTopics({
    required String siteUrl,
    required String apiKey,
    required bool dismissTopics,
    required bool dismissPosts,
    int? categoryId,
    String? tagName,
    List<int>? topicIds,
    String? clientId,
  }) => transport.dismissNewTopics(
    siteUrl: siteUrl,
    apiKey: apiKey,
    dismissTopics: dismissTopics,
    dismissPosts: dismissPosts,
    categoryId: categoryId,
    tagName: tagName,
    topicIds: topicIds,
    clientId: clientId,
  );
}

class _Authenticator extends FakeAuthenticator {
  _Authenticator()
    : super(
        credentials: const UserApiCredentials(
          key: 'replacement-key',
          apiVersion: 4,
          push: false,
        ),
      );
}

class _Store extends FakeInstanceStore {
  _Store(super.instances);
  bool failSignedOut = false;
  @override
  Future<void> save(List<DiscourseInstance> instances) {
    if (failSignedOut && instances.any((site) => site.user == null)) {
      return Future.error(StateError('Account snapshot unavailable'));
    }
    return super.save(instances);
  }
}
