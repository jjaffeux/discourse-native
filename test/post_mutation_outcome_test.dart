import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_mutation_outcome.dart';
import 'package:discourse_native/src/shell/post_permanent_delete.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_change_owner.dart';
import 'package:discourse_native/src/shell/topic_move_posts.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/native_ui_evidence.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(
  id: 7,
  username: 'moderator',
  staff: true,
  canChangePostOwner: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final notSent in [false, true]) {
    test(
      'single-post ${notSent ? 'not-sent' : 'refused'} does not start a repair',
      () async {
        final (:shell, :api) = await _fixture();
        api._mutationError = WriteException(
          notSent ? WriteFailure.unreachable : WriteFailure.validation,
          notSent: notSent,
          errors: ['Server detail'],
        );
        final result = await shell.deletePost(api.post(1));
        expect(
          result,
          notSent ? isA<PostMutationNotSent>() : isA<PostMutationRefused>(),
        );
        final problem = switch (result) {
          PostMutationNotSent(:final problem) ||
          PostMutationRefused(:final problem) => problem,
          _ => throw StateError('Expected a known failure'),
        };
        expect(problem.serverMessages, ['Server detail']);
        expect(api.writes, 1);
        expect(api.reads, isEmpty);
        expect(shell.postWriteInFlight(1, siteUrl: _site), isFalse);
      },
    );
  }

  test(
    'invalid deletion remains invalid when disposed before awaiting',
    () async {
      final (:shell, :api) = await _fixture();
      final deleting = shell.deletePost(
        const Post(
          id: 2,
          postNumber: 2,
          username: 'author',
          cooked: '<p>2</p>',
        ),
      );
      shell.dispose();
      expect(
        await deleting,
        isA<PostMutationNotSent>().having(
          (result) => result.problem.kind,
          'problem',
          PostMutationProblemKind.invalidTarget,
        ),
      );
      expect(api.writes, 0);
      expect(api.reads, isEmpty);
    },
  );

  test('an in-flight single-post command excludes another write', () async {
    final (:shell, :api) = await _fixture();
    final hold = api.writeGate = Completer<void>();
    final deleting = shell.deletePost(api.post(2));
    await pumpEventQueue();
    expect(shell.postWriteInFlight(2, siteUrl: _site), isTrue);
    expect(
      await shell.recoverPost(api.post(2)),
      isA<PostMutationNotSent>().having(
        (result) => result.problem.kind,
        'problem',
        PostMutationProblemKind.busyPost,
      ),
    );
    expect(api.writes, 1);
    expect(api.reads, isEmpty);
    hold.complete();
    expect(await deleting, isA<PostMutationAccepted>());
    expect(shell.postWriteInFlight(2, siteUrl: _site), isFalse);
    expect(api.writes, 1);
  });

  test('retirement preserves accepted and uncertain write outcomes', () async {
    for (final uncertain in [false, true]) {
      final (:shell, :api) = await _fixture();
      if (uncertain) {
        api._mutationError = const WriteException(WriteFailure.unreachable);
      }
      final hold = api.writeGate = Completer<void>();
      final deleting = shell.deletePost(api.post(2));
      await pumpEventQueue();
      expect(api.writes, 1);
      await shell.disconnectCurrentInstance();
      hold.complete();
      final outcome = await deleting;
      if (uncertain) {
        expect(outcome, isA<PostMutationUncertain>());
        final result = outcome as PostMutationUncertain;
        expect(result.projection, PostProjectionFreshness.retired);
        expect(
          await result.recovery.refresh(),
          PostProjectionFreshness.retired,
        );
      } else {
        expect(
          outcome,
          isA<PostMutationAccepted>().having(
            (result) => result.projection,
            'projection',
            PostProjectionFreshness.retired,
          ),
        );
      }
      expect(api.reads, isEmpty);
      expect(api.writes, 1);
    }
  });

  test(
    'accepted first-post recovery updates a topic before failed repair',
    () async {
      final (:shell, :api) = await _fixture(initiallyDeleted: true);
      expect(shell.currentTopic?.deletedAt, isNotNull);
      api.readFailure = StateError('Post refresh unavailable');
      api.topicFailure = StateError('Topic refresh unavailable');
      final result =
          await shell.recoverPost(api.post(1)) as PostMutationAccepted;
      expect(result.projection, PostProjectionFreshness.stale);
      expect(shell.currentTopic?.deletedAt, isNull);
      expect(shell.currentTopic?.canRecoverTopic, isFalse);
      expect(api.writes, 1);
      expect(api.reads, [
        [1],
      ]);
    },
  );

  test('explicit targets are revalidated after credential admission', () async {
    for (final permanent in [false, true]) {
      final authenticator = _DeferredAuthenticator();
      final (:shell, :api) = await _fixture(
        initiallyDeleted: permanent,
        authenticator: authenticator,
      );
      final ownerTarget = shell.captureTopicPostOwnerTarget(
        siteUrl: _site,
        topicId: 7,
        postId: 2,
      );
      final permanentTarget = shell.capturePostPermanentDeleteTarget(
        siteUrl: _site,
        topicId: 7,
        post: api.post(2),
      );
      final hold = authenticator.keyReadGate = Completer<void>();
      final changing = permanent
          ? shell.permanentlyDeletePost(permanentTarget)
          : shell.changeTopicPostOwner(ownerTarget, 'recipient');
      await pumpEventQueue();
      expect(shell.postWriteInFlight(2, siteUrl: _site), isTrue);
      expect(api.writes, 0);
      if (!permanent) api.username = 'recipient';
      shell.store.put(_site, api.post(2, deleted: false));
      hold.complete();
      expect(
        await changing,
        isA<PostMutationNotSent>().having(
          (result) => result.problem.kind,
          'problem',
          permanent
              ? PostMutationProblemKind.permanentDeletionUnavailable
              : PostMutationProblemKind.forbidden,
        ),
      );
      expect(api.writes, 0);
      expect(api.reads, isEmpty);
      expect(shell.postWriteInFlight(2, siteUrl: _site), isFalse);
    }
  });

  test('accepted deletion remains accepted when repair fails', () async {
    final (:shell, :api) = await _fixture();
    api.readFailure = StateError('Refresh unavailable');
    final result = await shell.deletePost(api.post(1)) as PostMutationAccepted;
    expect(result.projection, PostProjectionFreshness.stale);
    expect(api.writes, 1);
    api.readFailure = null;
    expect(await result.recovery!.refresh(), PostProjectionFreshness.fresh);
    expect(api.writes, 1);
  });

  test(
    'older topic reads cannot clear unknown admission; explicit recovery permits fresh intent',
    () async {
      final (:shell, :api) = await _fixture();
      final old = api.nextTopic = Completer<TopicPayload>();
      final reading = shell.loadTopic(7, 'topic', force: true);
      await pumpEventQueue();
      api._mutationError = const WriteException(WriteFailure.unreachable);
      api.readFailure = StateError('Refresh unavailable');
      final result =
          await shell.deletePost(api.post(1)) as PostMutationUncertain;
      expect(result.projection, PostProjectionFreshness.stale);
      old.complete(api.payload());
      await reading;
      expect(
        await shell.deletePost(api.post(1)),
        isA<PostMutationNotSent>().having(
          (r) => r.problem.kind,
          'problem',
          PostMutationProblemKind.recoveryRequired,
        ),
      );
      expect(api.writes, 1);
      api.readFailure = null;
      expect(await result.recovery.refresh(), PostProjectionFreshness.fresh);
      expect(api.writes, 1);
      api._mutationError = null;
      expect(await shell.deletePost(api.post(1)), isA<PostMutationAccepted>());
      expect(api.writes, 2);
    },
  );

  test(
    'retired unknown recovery cannot release replacement account admission',
    () async {
      final (:shell, :api) = await _fixture();
      api._mutationError = const WriteException(WriteFailure.unreachable);
      api.readFailure = StateError('Offline');
      final result =
          await shell.deletePost(api.post(1)) as PostMutationUncertain;
      await shell.disconnectCurrentInstance();
      await shell.connectCurrentInstance();
      await shell.loadTopic(7, 'topic');
      shell.openTopicPost(siteUrl: _site, topicId: 7, postNumber: 1);
      api._mutationError = null;
      api.readFailure = null;
      final hold = api.writeGate = Completer<void>();
      final next = shell.deletePost(api.post(1));
      await pumpEventQueue();
      expect(shell.postWriteInFlight(1, siteUrl: _site), isTrue);
      expect(await result.recovery.refresh(), PostProjectionFreshness.retired);
      expect(shell.postWriteInFlight(1, siteUrl: _site), isTrue);
      hold.complete();
      expect(await next, isA<PostMutationAccepted>());
    },
  );

  test(
    'whole-topic unknown deletion retains its barrier on 404 and repairs newly discovered posts',
    () async {
      final (:shell, :api) = await _fixture(initiallyDeleted: true);
      api._mutationError = const WriteException(WriteFailure.unreachable);
      api.topicFailure = const SiteLookupException(
        SiteLookupFailure.notDiscourse,
        'topic',
        statusCode: 404,
      );
      final result =
          await shell.permanentlyDeletePost(
                shell.capturePostPermanentDeleteTarget(
                  siteUrl: _site,
                  topicId: 7,
                  post: api.post(1),
                ),
              )
              as PostMutationUncertain;
      expect(result.projection, PostProjectionFreshness.stale);
      expect(
        await shell.deletePost(api.post(2)),
        isA<PostMutationNotSent>().having(
          (r) => r.problem.kind,
          'problem',
          PostMutationProblemKind.recoveryRequired,
        ),
      );
      expect(api.writes, 1);
      expect(
        await shell.setTopicDeleted(_site, 7, false),
        'An earlier change is still unconfirmed. Refresh before taking another action.',
      );
      expect(api.writes, 1);
      api.topicFailure = null;
      api.postCount = 3;
      expect(await result.recovery.refresh(), PostProjectionFreshness.fresh);
      expect(api.reads.last, [1, 2, 3]);
      expect(shell.store.read<Post>(_site, 3)?.cooked, '<p>fresh 3</p>');
      expect(shell.store.read<Post>(_site, 1)?.cooked, '<p>fresh 1</p>');
      expect(api.writes, 1);
    },
  );

  for (final width in [390.0, 1000.0]) {
    testWidgets(
      'unknown owner dialog at $width offers reads and never resubmits its command',
      (tester) async {
        await prepareNativeUiEvidence(tester);
        final (:shell, :api) = await _fixture();
        api._mutationError = const WriteException(WriteFailure.unreachable);
        api.readFailure = StateError('Offline');
        await _openOwner(tester, shell, api, width);
        await _submit(tester);
        final submit = find.byKey(const ValueKey('topic-change-owner-submit'));
        expect(tester.widget<DButton>(submit).onPressed, isNull);
        expect(
          find.byKey(const ValueKey('post-mutation-refresh')),
          findsOneWidget,
        );
        await captureNativeUi(tester, 'unknown-owner-${width.toInt()}');
        expect(api.writes, 1);
        await tester.tap(find.byKey(const ValueKey('post-mutation-refresh')));
        await tester.pumpAndSettle();
        expect(api.writes, 1);
        expect(
          find.text(
            "Couldn't refresh the view. Refresh again to check its saved state.",
          ),
          findsOneWidget,
        );
        api.readFailure = null;
        await tester.tap(find.byKey(const ValueKey('post-mutation-refresh')));
        await tester.pumpAndSettle();
        expect(tester.widget<DButton>(submit).onPressed, isNull);
        expect(
          find.text(
            'The view was refreshed. Review it before taking another action.',
          ),
          findsOneWidget,
        );
        await captureNativeUi(tester, 'recovered-owner-${width.toInt()}');
        expect(api.writes, 1);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }

  for (final action in ['move', 'permanent']) {
    for (final width in [390.0, 1000.0]) {
      testWidgets('unknown $action at $width refreshes without resubmitting', (
        tester,
      ) async {
        await prepareNativeUiEvidence(tester);
        final (:shell, :api) = await _fixture(
          initiallyDeleted: action == 'permanent',
        );
        api._mutationError = const WriteException(WriteFailure.unreachable);
        api.readFailure = StateError('Offline');
        if (action == 'move') {
          shell.setTopicPostSelectionEnabled(_site, 7, true);
          shell.toggleTopicPostSelected(_site, 7, 1);
        }
        await _openMutation(
          tester,
          shell,
          width,
          (context) => action == 'move'
              ? showTopicMovePosts(
                  context: context,
                  controller: shell,
                  siteUrl: _site,
                  topic: shell.currentTopic!,
                  selectedPosts: [api.post(1)],
                )
              : showPostPermanentDelete(
                  context: context,
                  controller: shell,
                  siteUrl: _site,
                  topicId: 7,
                  post: api.post(1),
                ),
        );
        await tester.enterText(
          find.byKey(
            ValueKey(
              action == 'move'
                  ? 'topic-move-posts-title'
                  : 'post-permanent-delete-confirmation',
            ),
          ),
          action == 'move' ? 'New topic' : 'permanently delete',
        );
        final submit = find.byKey(
          ValueKey(
            action == 'move'
                ? 'topic-move-posts-submit'
                : 'post-permanent-delete-submit',
          ),
        );
        await tester.pump();
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(api.writes, 1);
        expect(tester.widget<DButton>(submit).onPressed, isNull);
        await captureNativeUi(tester, 'unknown-$action-${width.toInt()}');
        api.readFailure = null;
        await tester.tap(find.byKey(const ValueKey('post-mutation-refresh')));
        await tester.pumpAndSettle();
        expect(api.writes, 1);
        expect(tester.widget<DButton>(submit).onPressed, isNull);
        expect(shell.currentTopic?.id, 7);
        expect(
          find.text(
            'The view was refreshed. Review it before taking another action.',
          ),
          findsOneWidget,
        );
        await captureNativeUi(tester, 'recovered-$action-${width.toInt()}');
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
    }
  }

  for (final retirement in ['reader', 'account']) {
    testWidgets(
      'stale recovery toast closes without reading for a successor $retirement',
      (tester) async {
        final (:shell, :api) = await _fixture();
        api.readFailure = StateError('Offline');
        await _openOwner(tester, shell, api, 1000);
        await _submit(tester);
        final message = find.text(
          'The change was saved, but this view could not be refreshed. Refresh to see the latest state.',
        );
        expect(message, findsOneWidget);
        if (retirement == 'reader') {
          shell.openTopicPost(siteUrl: _site, topicId: 8, postNumber: 1);
        } else {
          await shell.disconnectCurrentInstance();
        }
        await tester.pumpAndSettle();
        final reads = api.reads.length;
        await tester.tap(find.widgetWithText(DButton, 'Refresh'));
        await tester.pumpAndSettle();
        expect(message, findsNothing);
        expect(api.reads, hasLength(reads));
        expect(api.writes, 1);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }

  testWidgets(
    'accepted stale owner closes its form and keeps its refresh toast usable',
    (tester) async {
      final (:shell, :api) = await _fixture();
      api.readFailure = StateError('Offline');
      await _openOwner(tester, shell, api, 1000);
      await _submit(tester);
      expect(
        find.byKey(const ValueKey('topic-change-owner-dialog')),
        findsNothing,
      );
      expect(
        find.text(
          'The change was saved, but this view could not be refreshed. Refresh to see the latest state.',
        ),
        findsOneWidget,
      );
      api.readFailure = null;
      await tester.tap(find.widgetWithText(DButton, 'Refresh'));
      await tester.pumpAndSettle();
      expect(shell.store.read<Post>(_site, 1)?.username, 'recipient');
      expect(api.writes, 1);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}

Future<({ShellController shell, _MutationApi api})> _fixture({
  bool initiallyDeleted = false,
  FakeAuthenticator? authenticator,
}) async {
  final api = _MutationApi(initiallyDeleted: initiallyDeleted);
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _user),
    ]),
    api: api,
    authenticator: (authenticator ?? FakeAuthenticator())..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(() {
    if (!shell.accountSessionDisposed) shell.dispose();
  });
  await shell.load();
  await shell.loadTopic(7, 'topic');
  shell.openTopicPost(siteUrl: _site, topicId: 7, postNumber: 1);
  return (shell: shell, api: api);
}

Future<void> _openOwner(
  WidgetTester tester,
  ShellController shell,
  _MutationApi api,
  double width,
) async {
  await _openMutation(
    tester,
    shell,
    width,
    (context) => showTopicChangeOwner(
      context: context,
      controller: shell,
      siteUrl: _site,
      topicId: 7,
      selectedPosts: [api.post(1)],
      usesTopicSelection: false,
    ),
  );
  await tester.enterText(
    find.byKey(const ValueKey('topic-change-owner-search')),
    'recipient',
  );
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

Future<void> _openMutation(
  WidgetTester tester,
  ShellController shell,
  double width,
  Future<void> Function(BuildContext) open,
) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.light,
        builder: nativeUiEvidenceBuilder,
        home: DToaster(
          child: Center(
            child: Builder(
              builder: (context) => DButton(
                label: const Text('Open action'),
                onPressed: () => unawaited(open(context)),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open action'));
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('topic-change-owner-submit')));
  await tester.pumpAndSettle();
}

class _MutationApi extends FakeDiscourseApi {
  _MutationApi({this.initiallyDeleted = false})
    : super(user: _user, feeds: const {'/latest.json': []});
  final bool initiallyDeleted;
  Object? _mutationError;
  Object? readFailure;
  Object? topicFailure;
  Completer<void>? writeGate;
  Completer<TopicPayload>? nextTopic;
  int writes = 0;
  int postCount = 2;
  String username = 'author';
  final reads = <List<int>>[];

  Post post(int id, {String version = 'initial', bool? deleted}) => Post(
    id: id,
    postNumber: id,
    username: username,
    userId: 12,
    cooked: '<p>$version $id</p>',
    canDelete: true,
    canRecover: true,
    canPermanentlyDelete: true,
    deletedAt: (deleted ?? initiallyDeleted) ? DateTime.utc(2026) : null,
  );

  TopicPayload payload() => topicPayload(
    id: 7,
    title: 'Topic',
    posts: [for (var id = 1; id <= postCount; id++) post(id)],
    canSplitMergeTopic: true,
    canMovePosts: true,
    canRecoverTopic: true,
    canDeleteTopic: true,
    canPermanentlyDelete: true,
    deletedAt: initiallyDeleted ? DateTime.utc(2026) : null,
  );

  Future<void> _write() async {
    writes++;
    await writeGate?.future;
    if (_mutationError case final error?) throw error;
  }

  @override
  Future<void> deletePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) => _write();

  @override
  Future<void> recoverPost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) => _write();

  @override
  Future<void> permanentlyDeleteTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) => _write();

  @override
  Future<String> movePosts({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required List<int> postIds,
    int? destinationTopicId,
    String? title,
    int? categoryId,
    List<int> tagIds = const [],
    bool chronologicalOrder = false,
    bool privateMessage = false,
    String? clientId,
  }) async {
    await _write();
    return '/t/new-topic/99';
  }

  @override
  Future<void> changePostOwners({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required List<int> postIds,
    required String username,
    String? clientId,
  }) async {
    await _write();
    this.username = username;
  }

  @override
  Future<List<FoundUser>> searchUsers({
    required String siteUrl,
    required String term,
    int? topicId,
    int limit = 10,
    String? apiKey,
    String? clientId,
  }) async => const [
    FoundUser(id: 12, username: 'recipient', name: 'Recipient'),
  ];

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
  }) async {
    final held = nextTopic;
    nextTopic = null;
    if (held != null) return held.future;
    if (topicFailure case final error?) throw error;
    return payload();
  }

  @override
  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  }) async {
    reads.add(List.of(ids));
    if (readFailure case final error?) throw error;
    return [for (final id in ids) post(id, version: 'fresh')];
  }
}

class _DeferredAuthenticator extends FakeAuthenticator {
  Completer<void>? keyReadGate;

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    await keyReadGate?.future;
    return super.apiKeyFor(siteUrl);
  }
}
