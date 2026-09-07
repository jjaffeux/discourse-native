import 'dart:async';

import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _topicId = 7;
const _originalKey = 'original-key';
const _moderator = DiscourseUser(
  id: 7,
  username: 'moderator',
  canChangePostOwner: true,
);
final _selectedIds = [for (var id = 1; id <= 41; id++) id];

enum _BulkAction { delete, merge, moveExisting, moveNew, changeOwner }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final action in _BulkAction.values) {
    group(action.name, () {
      for (final pendingBatch in [1, 2]) {
        test(
          'stops after batch $pendingBatch completes for a replaced account',
          () async {
            final (:controller, :api, authenticator: _) = await _fixture();
            final response = api.holdRefresh(pendingBatch);
            final writing = _write(controller, action);
            await api.waitForRefreshes(pendingBatch);
            expect(_writtenIds(api, action), [_selectedIds]);
            _expectLocks(controller, true);
            _expectPosts(controller, 'initial');

            await controller.disconnectCurrentInstance();
            await controller.connectCurrentInstance();
            await controller.loadTopic(_topicId, 'topic');
            expect(controller.currentInstance?.user?.id, 8);
            _selectPosts(controller);
            final replacementTopic = controller.store.read<TopicDetail>(
              _siteUrl,
              _topicId,
            );
            final replacementPosts = [
              for (var id = 1; id <= 42; id++)
                controller.store.read<Post>(_siteUrl, id),
            ];

            // The replacement account can write the same topic and post IDs
            // while the old account's transport is still pending.
            final replacementGate = api.deleteGate = Completer<void>();
            final replacementWrite = controller.deleteSelectedTopicPosts(
              _siteUrl,
              _topicId,
            );
            await api.deleteStarted.future;
            _expectLocks(controller, true);

            response.complete(_refreshed(api.refreshes.last.ids));
            await writing;

            expect(api.refreshes, hasLength(pendingBatch));
            expect(
              api.refreshes.map((request) => request.apiKey),
              everyElement(_originalKey),
            );
            expect(
              controller.store.read<TopicDetail>(_siteUrl, _topicId),
              same(replacementTopic),
            );
            for (var id = 1; id <= 42; id++) {
              expect(
                controller.store.read<Post>(_siteUrl, id),
                same(replacementPosts[id - 1]),
              );
            }
            expect(
              controller.selectedTopicPostIds(_siteUrl, _topicId),
              _selectedIds.toSet(),
            );
            _expectLocks(controller, true);

            replacementGate.complete();
            expect(await replacementWrite, isNull);
            expect(api.refreshes, hasLength(pendingBatch + 3));
            expect(
              api.refreshes.skip(pendingBatch).map((request) => request.apiKey),
              everyElement('api-key'),
            );
            _expectLocks(controller, false);
          },
        );

        test(
          'stops after batch $pendingBatch completes following disposal',
          () async {
            final (:controller, :api, authenticator: _) = await _fixture();
            final response = api.holdRefresh(pendingBatch);
            final writing = _write(controller, action);
            await api.waitForRefreshes(pendingBatch);
            expect(_writtenIds(api, action), [_selectedIds]);
            _expectPosts(controller, 'initial');
            final postGeneration = controller.store.generationOf<Post>(
              _siteUrl,
            );
            final topicGeneration = controller.store.generationOf<TopicDetail>(
              _siteUrl,
            );

            response.complete(_refreshed(api.refreshes.last.ids));
            controller.dispose();
            await writing;

            expect(api.refreshes, hasLength(pendingBatch));
            expect(
              controller.store.generationOf<Post>(_siteUrl),
              postGeneration,
            );
            expect(
              controller.store.generationOf<TopicDetail>(_siteUrl),
              topicGeneration,
            );
            _expectPosts(controller, 'initial');
          },
        );
      }

      test(
        'refreshes all 41 selected posts with the captured credential',
        () async {
          final (:controller, :api, :authenticator) = await _fixture();
          final responses = [
            for (var batch = 1; batch <= 3; batch++) api.holdRefresh(batch),
          ];
          final unselected = controller.store.read<Post>(_siteUrl, 42);
          final writing = _write(controller, action);
          await api.waitForRefreshes(1);
          expect(_writtenIds(api, action), [_selectedIds]);

          // A subsequent read would return a different key. Every refresh batch
          // must retain the credential used by this write.
          authenticator.keys[_siteUrl] = 'later-key';
          for (var batch = 1; batch <= 3; batch++) {
            await api.waitForRefreshes(batch);
            _expectPosts(controller, 'initial');
            _expectLocks(controller, true);
            responses[batch - 1].complete(
              _refreshed(api.refreshes[batch - 1].ids),
            );
          }

          expect(await writing, isNull);
          expect(api.refreshes.map((request) => request.ids), [
            _selectedIds.sublist(0, 20),
            _selectedIds.sublist(20, 40),
            [41],
          ]);
          expect(
            api.refreshes.map(
              (request) => (request.siteUrl, request.topicId, request.apiKey),
            ),
            everyElement((_siteUrl, _topicId, _originalKey)),
          );
          for (final id in _selectedIds) {
            if (id == 40) {
              expect(controller.store.read<Post>(_siteUrl, id), isNull);
            } else {
              expect(
                controller.store.read<Post>(_siteUrl, id)?.cooked,
                '<p>refreshed $id</p>',
              );
            }
          }
          expect(
            controller.store.read<TopicDetail>(_siteUrl, _topicId)?.stream,
            [
              for (var id = 1; id <= 42; id++)
                if (id != 40) id,
            ],
          );
          expect(controller.store.read<Post>(_siteUrl, 42), same(unselected));
          expect(controller.store.read<Post>(_siteUrl, 999), isNull);
          _expectLocks(controller, false);
          expect(
            controller.topicPostSelectionEnabled(_siteUrl, _topicId),
            isFalse,
          );
        },
      );
    });
  }

  for (final obsolete in [false, true]) {
    test('refresh failure ${obsolete ? 'after retirement' : 'while current'} '
        'discards partial results and keeps the successful write', () async {
      final diagnostics = await DiagnosticsController.create(
        persistence: MemoryDiagnosticsPersistence(),
        sessionId: 'selected-post-refresh',
      );
      final binding = DiagnosticsSink.install(diagnostics);
      addTearDown(() async {
        binding.close();
        await diagnostics.close();
      });
      final (:controller, :api, authenticator: _) = await _fixture();
      final response = api.holdRefresh(2);
      final writing = controller.deleteSelectedTopicPosts(_siteUrl, _topicId);
      await api.waitForRefreshes(2);
      _expectPosts(controller, 'initial');
      if (obsolete) await controller.disconnectCurrentInstance();
      final postGeneration = controller.store.generationOf<Post>(_siteUrl);
      final topicGeneration = controller.store.generationOf<TopicDetail>(
        _siteUrl,
      );

      response.completeError(StateError('Refresh failed'));

      expect(await writing, isNull);
      expect(api.bulkDeleted, [_selectedIds]);
      expect(api.refreshes, hasLength(2));
      expect(controller.store.generationOf<Post>(_siteUrl), postGeneration);
      expect(
        controller.store.generationOf<TopicDetail>(_siteUrl),
        topicGeneration,
      );
      _expectLocks(controller, false);
      expect(controller.topicPostSelectionEnabled(_siteUrl, _topicId), isFalse);
      final warnings = diagnostics.events
          .whereType<ErrorDiagnosticEvent>()
          .where(
            (event) =>
                event.operation == 'topic.selectedPosts.refreshAfterWrite',
          );
      if (obsolete) {
        expect(warnings, isEmpty);
      } else {
        expect(warnings.single.severity, DiagnosticSeverity.warning);
        _expectPosts(controller, 'initial');
      }
    });
  }
}

Future<String?> _write(ShellController controller, _BulkAction action) async {
  return switch (action) {
    _BulkAction.delete => controller.deleteSelectedTopicPosts(
      _siteUrl,
      _topicId,
    ),
    _BulkAction.merge => controller.mergeSelectedTopicPosts(_siteUrl, _topicId),
    _BulkAction.moveExisting =>
      (await controller.moveSelectedTopicPostsToExisting(
        controller.captureTopicPostMoveTarget(_siteUrl, _topicId),
        99,
      )).error,
    _BulkAction.moveNew => (await controller.moveSelectedTopicPostsToNew(
      controller.captureTopicPostMoveTarget(_siteUrl, _topicId),
      title: 'Moved posts',
    )).error,
    _BulkAction.changeOwner => controller.changeSelectedTopicPostOwner(
      controller.captureTopicPostOwnerTarget(
        siteUrl: _siteUrl,
        topicId: _topicId,
      ),
      'recipient',
    ),
  };
}

Iterable<List<int>> _writtenIds(_RefreshApi api, _BulkAction action) =>
    switch (action) {
      _BulkAction.delete => api.bulkDeleted,
      _BulkAction.merge => api.merged,
      _BulkAction.moveExisting ||
      _BulkAction.moveNew => api.movedTopicPosts.map((write) => write.postIds),
      _BulkAction.changeOwner => api.postOwnersChanged.map(
        (write) => write.postIds,
      ),
    };

void _expectLocks(ShellController controller, bool held) {
  expect(controller.topicPostSelectionWriteInFlight(_siteUrl, _topicId), held);
  for (final id in _selectedIds) {
    expect(controller.postWriteInFlight(id, siteUrl: _siteUrl), held);
  }
}

void _expectPosts(ShellController controller, String label) {
  for (var id = 1; id <= 42; id++) {
    expect(
      controller.store.read<Post>(_siteUrl, id)?.cooked,
      '<p>$label $id</p>',
    );
  }
}

void _selectPosts(ShellController controller) {
  controller.setTopicPostSelectionEnabled(_siteUrl, _topicId, true);
  controller.selectAllLoadedTopicPosts(_siteUrl, _topicId);
  controller.toggleTopicPostSelected(_siteUrl, _topicId, 42);
  expect(
    controller.selectedTopicPostIds(_siteUrl, _topicId),
    _selectedIds.toSet(),
  );
}

Future<
  ({
    ShellController controller,
    _RefreshApi api,
    FakeAuthenticator authenticator,
  })
>
_fixture() async {
  final api = _RefreshApi();
  final authenticator = FakeAuthenticator()..keys[_siteUrl] = _originalKey;
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _moderator),
    ]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(() {
    if (!controller.accountSessionDisposed) controller.dispose();
    api.releasePending();
  });
  await controller.load();
  await controller.loadTopic(_topicId, 'topic');
  _selectPosts(controller);
  return (controller: controller, api: api, authenticator: authenticator);
}

Post _post(int id, String label) => Post(
  id: id,
  postNumber: id,
  username: 'author',
  cooked: '<p>$label $id</p>',
  canDelete: true,
);

List<Post> _refreshed(List<int> ids) => [
  for (final id in ids)
    if (id != 40) _post(id, 'refreshed'),
  _post(42, 'unsolicited'),
  _post(999, 'unsolicited'),
];

class _RefreshApi extends FakeDiscourseApi {
  _RefreshApi() : super(feeds: const {'/latest.json': []});

  final refreshes =
      <({String siteUrl, int topicId, List<int> ids, String? apiKey})>[];
  final _responses = <int, Completer<List<Post>>>{};
  Completer<void> _refreshesChanged = Completer<void>();
  Completer<void>? deleteGate;
  final deleteStarted = Completer<void>();

  Completer<List<Post>> holdRefresh(int batch) =>
      _responses[batch] = Completer<List<Post>>();

  Future<void> waitForRefreshes(int count) async {
    while (refreshes.length < count) {
      await _refreshesChanged.future.timeout(const Duration(seconds: 5));
    }
  }

  void releasePending() {
    for (final response in _responses.values) {
      if (!response.isCompleted) response.complete([]);
    }
    final gate = deleteGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => apiKey == _originalKey
      ? _moderator
      : const DiscourseUser(
          id: 8,
          username: 'replacement',
          canChangePostOwner: true,
        );

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
  }) async => topicPayload(
    id: id,
    posts: [
      for (var id = 1; id <= 42; id++)
        _post(id, apiKey == _originalKey ? 'initial' : 'replacement'),
    ],
    canSplitMergeTopic: true,
    canMovePosts: true,
  );

  @override
  Future<void> deletePosts({
    required String siteUrl,
    required String apiKey,
    required List<int> postIds,
    String? clientId,
  }) async {
    await super.deletePosts(
      siteUrl: siteUrl,
      apiKey: apiKey,
      postIds: postIds,
      clientId: clientId,
    );
    if (deleteGate case final gate?) {
      deleteStarted.complete();
      await gate.future;
    }
  }

  @override
  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  }) {
    refreshes.add((
      siteUrl: siteUrl,
      topicId: topicId,
      ids: List.of(ids),
      apiKey: apiKey,
    ));
    _refreshesChanged.complete();
    _refreshesChanged = Completer<void>();
    return _responses[refreshes.length]?.future ??
        Future.value(_refreshed(ids));
  }
}
