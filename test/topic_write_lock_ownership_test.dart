import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _topicId = 7;
const _originalKey = 'original-key';
const _originalUser = DiscourseUser(id: 7, username: 'original', staff: true);
const _replacementUser = DiscourseUser(
  id: 8,
  username: 'replacement',
  staff: true,
);

enum _Action { pin, closed, archived, visible, delete, recover }

enum _Completion { success, refusal, failure }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final action in _Action.values) {
    group(action.name, () {
      for (final completion in _Completion.values) {
        test(
          'retired $completion cannot release a replacement write lock',
          () async {
            final (:shell, :api) = await _fixture(action);
            final oldWrite = _write(shell, action, true);
            await api.waitForWrites(1);
            expect(_busy(shell, action), isTrue);

            await shell.disconnectCurrentInstance();
            await shell.connectCurrentInstance();
            await shell.loadTopic(_topicId, 'topic');
            expect(shell.currentInstance?.user, _replacementUser);
            expect(_busy(shell, action), isFalse);

            final replacementWrite = _write(shell, action, true);
            await api.waitForWrites(2);
            await pumpEventQueue();
            expect(_busy(shell, action), isTrue);
            expect(api.writes.map((write) => write.apiKey), [
              _originalKey,
              'api-key',
            ]);
            expect(
              api.writes.map((write) => (write.siteUrl, write.topicId)),
              everyElement((_siteUrl, _topicId)),
            );
            final replacementTopic = shell.store.read<TopicDetail>(
              _siteUrl,
              _topicId,
            );
            final replacementRow = shell.store.read<Topic>(_siteUrl, _topicId);
            var notifications = 0;
            void listener() => notifications++;
            shell.addListener(listener);

            _complete(api.writes.first.result, completion);
            expect(await oldWrite, _result(completion));

            // A stale success must not project into the new account, and a
            // stale pin failure must not roll its optimistic state back.
            expect(
              shell.store.read<TopicDetail>(_siteUrl, _topicId),
              same(replacementTopic),
            );
            expect(
              shell.store.read<Topic>(_siteUrl, _topicId),
              same(replacementRow),
            );
            expect(_busy(shell, action), isTrue);
            expect(notifications, 0);
            shell.removeListener(listener);

            // Pin is optimistic, so request the opposite value to exercise
            // admission rather than the already-pinned no-op.
            expect(
              await _write(shell, action, action != _Action.pin),
              _busyMessage(action),
            );
            expect(api.writes, hasLength(2));
            expect(_busy(shell, action), isTrue);

            _complete(api.writes.last.result, completion);
            expect(await replacementWrite, _result(completion));
            expect(_busy(shell, action), isFalse);
            _expectState(shell, action, completion == _Completion.success);

            final retry = _write(
              shell,
              action,
              completion != _Completion.success,
            );
            await api.waitForWrites(3);
            expect(_busy(shell, action), isTrue);
            expect(api.writes.last.apiKey, 'api-key');
            api.writes.last.result.complete();
            expect(await retry, isNull);
            expect(_busy(shell, action), isFalse);
            _expectState(shell, action, completion != _Completion.success);
          },
        );

        test('current account releases its lock after $completion', () async {
          final (:shell, :api) = await _fixture(action);
          final writing = _write(shell, action, true);
          await api.waitForWrites(1);
          expect(_busy(shell, action), isTrue);
          _expectState(shell, action, action == _Action.pin);
          expect(
            await _write(shell, action, action != _Action.pin),
            _busyMessage(action),
          );
          expect(api.writes, hasLength(1));

          _complete(api.writes.single.result, completion);
          expect(await writing, _result(completion));
          expect(_busy(shell, action), isFalse);
          _expectState(shell, action, completion == _Completion.success);
        });
      }

      test('refuses an action without its topic permission', () async {
        final (:shell, :api) = await _fixture(action);
        shell.store.put(
          _siteUrl,
          topicPayload(
            id: _topicId,
            visible: false,
            deletedAt: action == _Action.recover ? DateTime.utc(2026) : null,
          ).detail,
        );

        expect(await _write(shell, action, true), isNotNull);
        expect(api.writes, isEmpty);
        expect(_busy(shell, action), isFalse);
      });
    });
  }
}

Future<String?> _write(ShellController shell, _Action action, bool enabled) =>
    switch (action) {
      _Action.pin => shell.updateTopicPinPreference(
        _siteUrl,
        _topicId,
        enabled,
      ),
      _Action.closed || _Action.archived || _Action.visible =>
        shell.updateTopicStatus(_siteUrl, _topicId, _status(action), enabled),
      _Action.delete || _Action.recover => shell.setTopicDeleted(
        _siteUrl,
        _topicId,
        action == _Action.delete ? enabled : !enabled,
      ),
    };

TopicStatusProperty _status(_Action action) => switch (action) {
  _Action.closed => TopicStatusProperty.closed,
  _Action.archived => TopicStatusProperty.archived,
  _Action.visible => TopicStatusProperty.visible,
  _ => throw ArgumentError.value(action),
};

bool _busy(ShellController shell, _Action action) => switch (action) {
  _Action.pin => shell.topicPinWriteInFlight(_siteUrl, _topicId),
  _Action.closed ||
  _Action.archived ||
  _Action.visible => shell.topicStatusWriteInFlight(_siteUrl, _topicId),
  _Action.delete ||
  _Action.recover => shell.topicDeletionWriteInFlight(_siteUrl, _topicId),
};

String _busyMessage(_Action action) => action == _Action.pin
    ? 'Another pin change is still finishing.'
    : 'Another topic action is still finishing.';

String? _result(_Completion completion) => switch (completion) {
  _Completion.success => null,
  _Completion.refusal => const WriteException(WriteFailure.forbidden).message,
  _Completion.failure => const WriteException(WriteFailure.unreachable).message,
};

void _complete(Completer<void> response, _Completion completion) {
  switch (completion) {
    case _Completion.success:
      response.complete();
    case _Completion.refusal:
      response.completeError(const WriteException(WriteFailure.forbidden));
    case _Completion.failure:
      response.completeError(StateError('Connection failed'));
  }
}

void _expectState(ShellController shell, _Action action, bool changed) {
  final topic = shell.store.read<TopicDetail>(_siteUrl, _topicId)!;
  final row = shell.store.read<Topic>(_siteUrl, _topicId)!;
  switch (action) {
    case _Action.pin:
      expect(topic.pinned, changed);
      expect(topic.unpinned, !changed);
      expect(row.pinned, changed);
    case _Action.closed || _Action.archived || _Action.visible:
      expect(topic.statusValue(_status(action)), changed);
      if (action == _Action.closed) expect(row.closed, changed);
    case _Action.delete || _Action.recover:
      final deleted = action == _Action.delete ? changed : !changed;
      expect(topic.deletedAt != null, deleted);
      expect(topic.canDeleteTopic, !deleted);
      expect(topic.canRecoverTopic, deleted);
  }
}

Future<({ShellController shell, _GatedTopicApi api})> _fixture(
  _Action action,
) async {
  final deleted = action == _Action.recover;
  final api = _GatedTopicApi(
    topicPayload(
      id: _topicId,
      title: 'Topic',
      unpinned: true,
      visible: false,
      deletedAt: deleted ? DateTime.utc(2026) : null,
      canCloseTopic: true,
      canArchiveTopic: true,
      canToggleTopicVisibility: true,
      canDeleteTopic: !deleted,
      canRecoverTopic: deleted,
    ),
  );
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _originalUser),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_siteUrl] = _originalKey,
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(() {
    shell.dispose();
    for (final write in api.writes) {
      if (!write.result.isCompleted) write.result.complete();
    }
  });
  await shell.load();
  await shell.loadTopic(_topicId, 'topic');
  return (shell: shell, api: api);
}

class _GatedTopicApi extends FakeDiscourseApi {
  _GatedTopicApi(TopicPayload topic)
    : super(
        feeds: const {
          '/latest.json': [Topic(id: _topicId, title: 'Topic', slug: 'topic')],
        },
        topics: {_topicId: topic},
      );

  final writes =
      <
        ({String siteUrl, String apiKey, int topicId, Completer<void> result})
      >[];
  Completer<void> _writesChanged = Completer<void>();

  Future<void> waitForWrites(int count) async {
    while (writes.length < count) {
      await _writesChanged.future.timeout(const Duration(seconds: 5));
    }
  }

  Future<void> _hold(String siteUrl, String apiKey, int topicId) {
    final result = Completer<void>();
    writes.add((
      siteUrl: siteUrl,
      apiKey: apiKey,
      topicId: topicId,
      result: result,
    ));
    _writesChanged.complete();
    _writesChanged = Completer<void>();
    return result.future;
  }

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => apiKey == _originalKey ? _originalUser : _replacementUser;

  @override
  Future<void> updateTopicPinForUser({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required bool pinned,
    String? clientId,
  }) => _hold(siteUrl, apiKey, topicId);

  @override
  Future<void> updateTopicStatus({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required TopicStatusProperty status,
    required bool enabled,
    String? clientId,
  }) => _hold(siteUrl, apiKey, topicId);

  @override
  Future<void> deleteTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) => _hold(siteUrl, apiKey, topicId);

  @override
  Future<void> recoverTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) => _hold(siteUrl, apiKey, topicId);
}
