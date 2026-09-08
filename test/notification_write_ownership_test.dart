import 'dart:async';

import 'package:discourse_native/src/data/account_session_coordinator.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _topic = TopicDetail(id: 7, title: 'Topic', stream: []);
const _category = TopicCategory(id: 5, name: 'Support', color: '0088CC');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final target in _Target.values) {
    group('${target.name} notification ownership', () {
      late _Fixture fixture;

      setUp(() async {
        fixture = await _Fixture.load(target);
        addTearDown(fixture.close);
      });

      for (final source in _Listener.values) {
        test('${source.name} invalidation prevents credential reads', () async {
          fixture.listenOnce(
            source,
            () => fixture.shell.lifecycle.invalidate(_site),
          );

          expect(await fixture.select(0), isFalse);

          expect(fixture.auth.keyReads, 0);
          expect(fixture.auth.clientReads, 0);
          expect(fixture.api.requests, isEmpty);
        });

        test(
          '${source.name} reset cannot lend its reused revision to an old selection',
          () async {
            Future<bool>? replacement;
            fixture.listenOnce(source, () {
              fixture.replaceAccount();
              // The former counters reused revision 1 across this reset.
              replacement = fixture.select(3);
            });

            final old = fixture.select(0);
            fixture.expectLevel(3);
            expect(await old, isFalse);
            expect(await replacement!, isTrue);

            expect(fixture.api.requests.map((request) => request.level), [3]);
            expect(fixture.api.requests.single.apiKey, 'replacement-key');
            expect(fixture.auth.keyReads, 1);
            expect(fixture.auth.clientReads, 1);
            fixture.expectLevel(3);
          },
        );

        test(
          '${source.name} latest selection owns the queue before publication returns',
          () async {
            fixture.api.autoComplete = false;
            Future<bool>? latest;
            fixture.listenOnce(source, () => latest = fixture.select(3));

            bool? oldResult;
            final old = fixture.select(0).then((result) => oldResult = result);
            fixture.expectLevel(3);
            await pumpEventQueue();

            expect(oldResult, isFalse);
            expect(fixture.api.requests.map((request) => request.level), [3]);
            expect(fixture.auth.keyReads, 1);
            fixture.api.requests.single.result.complete();
            expect(await latest!, isTrue);
            expect(await old, isFalse);
            fixture.expectLevel(3);
          },
        );

        test(
          '${source.name} repeated optimistic choice waits for its real outcome',
          () async {
            fixture.api.autoComplete = false;
            Future<bool>? repeated;
            bool? repeatedResult;
            fixture.listenOnce(source, () {
              repeated = fixture
                  .select(0)
                  .then((result) => repeatedResult = result);
            });

            final old = fixture.select(0);
            fixture.expectLevel(0);
            await pumpEventQueue();
            expect(repeatedResult, isNull);
            expect(fixture.api.requests.map((request) => request.level), [0]);

            fixture.api.requests.single.result.completeError(
              const WriteException(WriteFailure.forbidden),
            );
            expect(await old, isFalse);
            expect(await repeated!, isFalse);
            fixture.expectLevel(1);
          },
        );

        test(
          '${source.name} disposal settles without credential or network work',
          () async {
            fixture.listenOnce(source, () {
              try {
                fixture.shell.dispose();
              } on AssertionError catch (error) {
                // Flutter asserts on disposing a ChangeNotifier from its own
                // listener, after FrameSafeNotifier has marked it disposed.
                expect(source, _Listener.shell);
                expect(
                  error.message,
                  contains('was called during the call to'),
                );
                expect(error.message, contains('notifyListeners()'));
              }
            });

            expect(await fixture.select(0), isFalse);
            expect(fixture.shell.accountSessionDisposed, isTrue);
            expect(fixture.auth.keyReads, 0);
            expect(fixture.auth.clientReads, 0);
            expect(fixture.api.requests, isEmpty);
          },
        );
      }

      for (final stage in ['api key', 'client ID']) {
        test(
          'replacement stays independent of an old $stage read and cleanup',
          () async {
            fixture.api.autoComplete = false;
            final gate = Completer<void>();
            if (stage == 'api key') {
              fixture.auth.keyGate = gate;
            } else {
              fixture.auth.clientGate = gate;
            }
            final old = fixture.select(0);
            await pumpEventQueue();
            expect(fixture.api.requests, isEmpty);

            fixture.replaceAccount();
            final replacement = fixture.select(3);
            await pumpEventQueue();
            expect(fixture.api.requests.map((request) => request.level), [3]);
            gate.complete();
            expect(await old, isFalse);
            await pumpEventQueue();

            // Old cleanup must preserve the pending queue and its confirmed
            // Normal level, even though the visible replacement is Watching.
            final latest = fixture.select(2);
            fixture.api.requests.single.result.completeError(
              const WriteException(WriteFailure.forbidden),
            );
            expect(await replacement, isFalse);
            await pumpEventQueue();
            expect(fixture.api.requests.map((request) => request.level), [
              3,
              2,
            ]);
            fixture.api.requests.last.result.completeError(
              StateError('rejected'),
            );
            expect(await latest, isFalse);
            fixture.expectLevel(1);
          },
        );
      }

      for (final succeeds in [true, false]) {
        test(
          'old network ${succeeds ? 'success' : 'failure'} preserves the replacement queue',
          () async {
            fixture.api.autoComplete = false;
            final old = fixture.select(0);
            await pumpEventQueue();
            fixture.replaceAccount();
            final replacement = fixture.select(3);
            await pumpEventQueue();
            expect(fixture.api.requests.map((request) => request.level), [
              0,
              3,
            ]);

            final oldRequest = fixture.api.requests.first;
            if (succeeds) {
              oldRequest.result.complete();
            } else {
              oldRequest.result.completeError(StateError('old account'));
            }
            expect(await old, isFalse);
            await pumpEventQueue();
            fixture.expectLevel(3);

            final latest = fixture.select(2);
            fixture.api.requests.last.result.complete();
            expect(await replacement, isTrue);
            await pumpEventQueue();
            expect(fixture.api.requests.map((request) => request.level), [
              0,
              3,
              2,
            ]);
            fixture.api.requests.last.result.completeError(
              const WriteException(WriteFailure.forbidden),
            );
            expect(await latest, isFalse);
            fixture.expectLevel(3);
          },
        );
      }

      test(
        'coalesces unsent choices in order and rolls back to the last success',
        () async {
          fixture.api.autoComplete = false;
          final first = fixture.select(0);
          fixture.expectLevel(0);
          await pumpEventQueue();
          final middle = fixture.select(3);
          final last = fixture.select(2);
          fixture.expectLevel(2);
          expect(fixture.api.requests.map((request) => request.level), [0]);

          fixture.api.requests.single.result.complete();
          expect(await first, isTrue);
          expect(await middle, isFalse);
          await pumpEventQueue();
          fixture.expectLevel(2);
          expect(fixture.api.requests.map((request) => request.level), [0, 2]);
          fixture.api.requests.last.result.completeError(
            const WriteException(WriteFailure.forbidden),
          );
          expect(await last, isFalse);
          fixture.expectLevel(0);
          await pumpEventQueue();

          // An idle, already-confirmed selection is still a successful no-op.
          expect(await fixture.select(0), isTrue);
          expect(fixture.auth.keyReads, 2);
          fixture.api.autoComplete = true;
          expect(await fixture.select(3), isTrue);
          fixture.expectLevel(3);
        },
      );
    });
  }
}

enum _Target { topic, category }

enum _Listener { store, shell }

final class _Fixture {
  _Fixture(this.target, this.shell, this.api, this.auth);

  final _Target target;
  final ShellController shell;
  final _NotificationApi api;
  final _Authenticator auth;

  static Future<_Fixture> load(_Target target) async {
    final api = _NotificationApi();
    final auth = _Authenticator()..keys[_site] = 'original-key';
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance(
          'meta.discourse.org',
        ).copyWith(user: const DiscourseUser(id: 7, username: 'reader')),
      ]),
      api: api,
      authenticator: auth,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    await shell.load();
    await pumpEventQueue();
    shell.store.put(_site, _topic);
    shell.store.put(_site, _category);
    auth.keyReads = 0;
    auth.clientReads = 0;
    return _Fixture(target, shell, api, auth);
  }

  Future<bool> select(int level) => switch (target) {
    _Target.topic => shell.updateTopicNotificationLevel(
      _site,
      _topic.id,
      TopicNotificationLevel.fromJson(level),
    ),
    _Target.category => shell.updateCategoryNotificationLevel(
      _site,
      _category.id,
      CategoryNotificationLevel.fromJson(level),
    ),
  };

  void expectLevel(int level) {
    switch (target) {
      case _Target.topic:
        expect(
          shell.store
              .read<TopicDetail>(_site, _topic.id)
              ?.notificationLevel
              .value,
          level,
        );
      case _Target.category:
        expect(shell.categoryFor(_category.id)?.notificationLevel.value, level);
        expect(
          shell
              .filterCategoriesFor(_site)
              .singleWhere((category) => category.id == _category.id)
              .notificationLevel
              .value,
          level,
        );
    }
  }

  void listenOnce(_Listener source, VoidCallback listener) {
    final Listenable listenable = switch (source) {
      _Listener.shell => shell,
      _Listener.store => switch (target) {
        _Target.topic => shell.store.ref<TopicDetail>(_site, _topic.id),
        _Target.category => shell.store.ref<TopicCategory>(_site, _category.id),
      },
    };
    void onChange() {
      listenable.removeListener(onChange);
      listener();
    }

    listenable.addListener(onChange);
    addTearDown(() => listenable.removeListener(onChange));
  }

  void replaceAccount() {
    shell.lifecycle.invalidate(_site);
    shell.clearAccountSessionState(_site);
    auth.keys[_site] = 'replacement-key';
    shell.applyAccountSessionInstance(
      shell.currentInstance!.copyWith(
        user: const DiscourseUser(id: 8, username: 'replacement'),
      ),
      AccountSessionPhase.connecting,
    );
    shell.store.put(_site, _topic);
    shell.store.put(_site, _category);
  }

  Future<void> close() async {
    if (!shell.accountSessionDisposed) shell.dispose();
    for (final request in api.requests) {
      if (!request.result.isCompleted) request.result.complete();
    }
    await pumpEventQueue();
  }
}

final class _Request {
  _Request(this.level, this.apiKey);

  final int level;
  final String apiKey;
  final result = Completer<void>();
}

final class _NotificationApi extends FakeDiscourseApi {
  _NotificationApi()
    : super(feeds: const {'/latest.json': []}, categoryList: const [_category]);

  final requests = <_Request>[];
  bool autoComplete = true;

  Future<void> _request(int level, String apiKey) {
    final request = _Request(level, apiKey);
    requests.add(request);
    if (autoComplete) request.result.complete();
    return request.result.future;
  }

  @override
  Future<void> updateTopicNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required TopicNotificationLevel notificationLevel,
    String? clientId,
  }) => _request(notificationLevel.value, apiKey);

  @override
  Future<List<int>?> updateCategoryNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int categoryId,
    required CategoryNotificationLevel notificationLevel,
    String? clientId,
  }) async {
    await _request(notificationLevel.value, apiKey);
    return const [];
  }
}

final class _Authenticator extends FakeAuthenticator {
  int keyReads = 0;
  int clientReads = 0;
  Completer<void>? keyGate;
  Completer<void>? clientGate;

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    keyReads++;
    final gate = keyGate;
    keyGate = null;
    if (gate != null) await gate.future;
    return super.apiKeyFor(siteUrl);
  }

  @override
  Future<String> clientId() async {
    clientReads++;
    final gate = clientGate;
    clientGate = null;
    if (gate != null) await gate.future;
    return super.clientId();
  }
}
