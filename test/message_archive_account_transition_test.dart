import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/message_archive_button.dart';
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
const _original = DiscourseUser(
  id: 1,
  username: 'reader',
  canSendPrivateMessages: true,
);
const _replacement = DiscourseUser(
  id: 2,
  username: 'replacement',
  canSendPrivateMessages: true,
);
const _topic = Topic(
  id: 7,
  title: 'A private message',
  slug: 'private-message',
  privateMessage: true,
);

enum _Operation { unchanged, failedReconnect, failedDisconnect, reconnect }

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
  for (final archived in [false, true]) {
    for (final operation in _Operation.values) {
      testWidgets(
        'Native PM ${archived ? 'Move to inbox' : 'Archive'} '
        '${operation.name} owns its rendered account before repaint',
        (tester) async {
          final site = instance('meta.discourse.org').copyWith(user: _original);
          final store = _Store([site]);
          final api = _Api(archived: archived);
          addTearDown(api.transport.close);
          final auth = _Authenticator()..keys[_site] = 'old-key';
          await pumpShell(
            tester,
            defaultTargetPlatform == TargetPlatform.macOS ? desktop : phone,
            instances: [site],
            store: store,
            api: api,
            authenticator: auth,
          );
          final shell = ShellScope.read(tester.element(primaryMainContent));
          await tester.runAsync(() async {
            shell.openTopic(_topic);
            await pumpEventQueue();
          });
          await tester.pumpAndSettle();
          expect(shell.currentTopic, isNotNull);
          expect(shell.currentTopic!.privateMessage, isTrue);
          final button = find.byKey(const ValueKey('message-archive-button'));
          expect(button, findsOneWidget);
          expect(
            tester.widget<DButton>(button).tooltip,
            archived ? 'Move to your inbox' : 'Archive from your inbox',
          );
          final state = tester.state(find.byType(MessageArchiveButton));
          final lease = shell.lifecycle.capture(_site);
          if (operation != _Operation.unchanged) {
            store.failSignedOut = operation != _Operation.reconnect;
            if (operation == _Operation.failedDisconnect) {
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
              operation == _Operation.reconnect ? 2 : 1,
            );
            // Fetch the same authorized PM through the real reader API for the
            // restored/replacement account before repainting the old control.
            await tester.runAsync(() async {
              await shell.loadTopic(7, _topic.slug, force: true);
              // Restoration may already own an in-flight load; a force read
              // queues behind it, so drain its real HTTP completion as well.
              await pumpEventQueue();
            });
            expect(api.reads.last.headers['User-Api-Key'], auth.keys[_site]);
            expect(
              shell.store.read<TopicDetail>(_site, 7)!.privateMessage,
              isTrue,
            );
            expect(
              shell.store.read<TopicDetail>(_site, 7)!.messageArchived,
              archived,
            );
          }
          expect(tester.state(find.byType(MessageArchiveButton)), same(state));
          await tester.tap(button);
          await _pump(tester);
          if (operation == _Operation.unchanged) {
            expect(api.writes, hasLength(1));
            _expectWrite(api.writes.single, 'old-key', !archived);
            // The normal Undo action retains its existing opening-session guard.
            await tester.tap(find.text('Undo'));
            await _pump(tester);
            expect(api.writes, hasLength(2));
            _expectWrite(api.writes.last, 'old-key', archived);
          } else {
            expect(api.writes, isEmpty);
            expect(find.text('Undo'), findsNothing);
            expect(api.archivedFor(auth.keys[_site]!), archived);
          }
          await tester.runAsync(() async {
            shell.openTopic(_topic);
            await pumpEventQueue();
          });
          await _pump(tester);
          await tester.tap(button);
          await _pump(tester);
          _expectWrite(
            api.writes.last,
            operation == _Operation.reconnect ? 'replacement-key' : 'old-key',
            !archived,
          );
          expect(
            api.writes,
            hasLength(operation == _Operation.unchanged ? 3 : 1),
          );
          expect(shell.currentTopic!.messageArchived, !archived);
          expect(find.text('Undo'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pump(const Duration(seconds: 5));
        },
        variant: const TargetPlatformVariant({
          TargetPlatform.iOS,
          TargetPlatform.android,
          TargetPlatform.macOS,
        }),
      );
    }
  }
}

void _expectWrite(http.Request request, String key, bool archived) {
  expect(request.method, 'PUT');
  expect(
    request.url,
    Uri.parse('$_site/t/7/${archived ? 'archive-message' : 'move-to-inbox'}'),
  );
  expect(request.headers['User-Api-Key'], key);
  expect(jsonDecode(request.body), isEmpty);
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

class _Api extends FakeDiscourseApi {
  _Api({required bool archived})
    : initialArchived = archived,
      super(user: _original, feeds: const {'/latest.json': []}) {
    accounts['replacement-key'] = _replacement;
    transport = DiscourseApi(
      client: MockClient((request) async {
        final key = request.headers['User-Api-Key']!;
        if (request.method == 'PUT') {
          writes.add(request);
          _archived[key] = request.url.path.endsWith('/archive-message');
          return http.Response('{}', 200);
        }
        reads.add(request);
        expect(request.url.path, '/t/7.json');
        return http.Response(
          jsonEncode({
            'id': 7,
            'title': _topic.title,
            'slug': _topic.slug,
            'archetype': 'private_message',
            'message_archived': archivedFor(key),
            'posts_count': 1,
            'highest_post_number': 1,
            'details': {
              'can_create_post': true,
              'allowed_users': [
                {'id': 1, 'username': 'reader'},
                {'id': 2, 'username': 'replacement'},
              ],
            },
            'post_stream': {
              'stream': [70],
              'posts': [
                {
                  'id': 70,
                  'topic_id': 7,
                  'post_number': 1,
                  'username': 'sam',
                  'user_id': 3,
                  'cooked': '<p>Private body</p>',
                },
              ],
            },
          }),
          200,
        );
      }),
    );
  }
  final bool initialArchived;
  final Map<String, bool> _archived = {};
  bool archivedFor(String key) => _archived[key] ?? initialArchived;
  late final DiscourseApi transport;
  final writes = <http.Request>[];
  final reads = <http.Request>[];

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
    Future<void>? abortTrigger,
  }) => transport.topic(
    siteUrl: siteUrl,
    slug: slug,
    id: id,
    postNumber: postNumber,
    summary: summary,
    apiKey: apiKey,
    clientId: clientId,
    abortTrigger: abortTrigger,
  );

  @override
  Future<void> updateMessageArchived({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required bool archived,
    String? clientId,
  }) => transport.updateMessageArchived(
    siteUrl: siteUrl,
    apiKey: apiKey,
    topicId: topicId,
    archived: archived,
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
