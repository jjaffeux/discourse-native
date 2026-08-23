import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _InstrumentedAuthenticator authenticator;
  late _InstrumentedFailureApi api;
  late _InstrumentedDraftStore drafts;
  late ShellController controller;
  late DiagnosticsController diagnostics;
  late DiagnosticsSinkBinding diagnosticsBinding;

  setUp(() async {
    diagnostics = await DiagnosticsController.create(
      persistence: MemoryDiagnosticsPersistence(),
      sessionId: 'shell-write-credentials',
    );
    diagnosticsBinding = DiagnosticsSink.install(diagnostics);
    addTearDown(() async {
      diagnosticsBinding.close();
      await diagnostics.close();
    });

    authenticator = _InstrumentedAuthenticator()..keys[_siteUrl] = 'api-key';
    api = _InstrumentedFailureApi(feeds: const {'/latest.json': []});
    drafts = _InstrumentedDraftStore();
    controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance(
          'meta.discourse.org',
        ).copyWith(user: const DiscourseUser(id: 7, username: 'reader')),
      ]),
      api: api,
      authenticator: authenticator,
      drafts: drafts,
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(controller.dispose);
    await controller.load();

    controller.pushContent(
      ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
    );
    controller.store.put(
      _siteUrl,
      const TopicDetail(
        id: 7,
        title: 'Topic',
        stream: [1],
        postsCount: 1,
        canCreatePost: true,
      ),
    );
    controller.store.put(
      _siteUrl,
      const Post(
        id: 1,
        postNumber: 1,
        username: 'author',
        cooked: '<p>Body</p>',
        canDelete: true,
        canLike: true,
      ),
    );
  });

  test(
    'post actions translate a keychain failure and release their guard',
    () async {
      final post = controller.store.read<Post>(_siteUrl, 1)!;
      authenticator.apiKeyFailure = StateError('keychain unavailable');

      expect(
        await controller.toggleLike(post, siteUrl: _siteUrl),
        const WriteException(WriteFailure.unreachable).message,
      );
      expect(
        await controller.toggleLike(post, siteUrl: _siteUrl),
        const WriteException(WriteFailure.unreachable).message,
      );
      expect(
        await controller.deletePost(post),
        const WriteException(WriteFailure.unreachable).message,
      );

      expect(api.liked, isEmpty);
      expect(api.deleted, isEmpty);
      expect(controller.store.read<Post>(_siteUrl, 1), same(post));
    },
  );

  test(
    'a keychain failure returns a composer to an editable error state',
    () async {
      controller.openReply();
      final composer = controller.visibleComposer!;
      composer.text.text = 'A reply that should remain local';
      authenticator.apiKeyFailure = StateError('keychain unavailable');

      await controller.submitComposer();

      expect(composer.submitting, isFalse);
      expect(composer.error?.failure, WriteFailure.unreachable);
      expect(composer.raw, 'A reply that should remain local');
      expect(api.created, isEmpty);
    },
  );

  test(
    'a generic like failure is recorded once and rolls back the optimistic UI',
    () async {
      api.likeError = StateError('opaque like transport failure');
      final post = controller.store.read<Post>(_siteUrl, 1)!;

      expect(
        await controller.toggleLike(post, siteUrl: _siteUrl),
        const WriteException(WriteFailure.unreachable).message,
      );

      final held = controller.store.read<Post>(_siteUrl, 1)!;
      expect(held.liked, isFalse);
      expect(held.likeCount, 0);
      expect(held.canLike, isTrue);
      expect(api.liked, [1]);

      final event = _singleOperation(diagnostics, 'post.toggleLike');
      expect(event.severity, DiagnosticSeverity.error);
      expect(event.errorType, 'StateError');
      expect(event.message, contains('opaque like transport failure'));
      expect(event.stackTrace, contains('_InstrumentedFailureApi.likePost'));
    },
  );

  test('a like failure from a disconnected session is excluded', () async {
    final gate = Completer<void>();
    api
      ..likeError = StateError('obsolete like failure')
      ..opaqueLikeGate = gate;
    final post = controller.store.read<Post>(_siteUrl, 1)!;

    final write = controller.toggleLike(post, siteUrl: _siteUrl);
    await api.likeStarted.future;
    expect(await controller.disconnectInstance(_siteUrl), isTrue);
    gate.complete();
    await write;

    expect(controller.store.read<Post>(_siteUrl, 1), isNull);
    expect(_operationEvents(diagnostics, 'post.toggleLike'), isEmpty);
  });

  test(
    'disconnect keeps working when credential read and deletion fail',
    () async {
      // Startup presentation hydration can legitimately use the same injected
      // credential failure. Let that optional work settle before exercising
      // and inspecting the disconnect boundary.
      await pumpEventQueue();
      await diagnostics.clear();
      await diagnostics.flush();
      authenticator
        ..readError = StateError('secure credential read failed')
        ..deleteError = StateError('secure credential delete failed');

      expect(await controller.disconnectInstance(_siteUrl), isTrue);

      expect(controller.currentInstance?.user, isNull);
      expect(authenticator.disconnected, isEmpty);
      final read = _singleOperation(
        diagnostics,
        'authentication.readCredentialForDisconnect',
      );
      expect(read.severity, DiagnosticSeverity.warning);
      expect(read.message, contains('secure credential read failed'));
      expect(read.stackTrace, contains('_InstrumentedAuthenticator.apiKeyFor'));
      final deletion = _singleOperation(
        diagnostics,
        'authentication.deleteCredential',
      );
      expect(deletion.severity, DiagnosticSeverity.warning);
      expect(deletion.message, contains('secure credential delete failed'));
      expect(
        deletion.stackTrace,
        contains('_InstrumentedAuthenticator.disconnect'),
      );
    },
  );

  test(
    'disconnect tolerates and records remote key revocation failure',
    () async {
      api.revokeError = StateError('remote revoke unavailable');

      expect(await controller.disconnectInstance(_siteUrl), isTrue);

      expect(controller.currentInstance?.user, isNull);
      expect(authenticator.disconnected, [_siteUrl]);
      expect(api.revoked, [_siteUrl]);
      final event = _singleOperation(diagnostics, 'authentication.revokeKey');
      expect(event.severity, DiagnosticSeverity.warning);
      expect(event.message, contains('remote revoke unavailable'));
      expect(
        event.stackTrace,
        contains('_InstrumentedFailureApi.revokeApiKey'),
      );
    },
  );

  test(
    'disconnect aborts before credential removal when drafts cannot clear',
    () async {
      const error = FileSystemException('draft boundary unavailable');
      drafts.clearSiteError = error;

      expect(await controller.disconnectInstance(_siteUrl), isFalse);

      expect(controller.currentInstance?.user?.username, 'reader');
      expect(authenticator.keys[_siteUrl], 'api-key');
      expect(authenticator.disconnected, isEmpty);
      expect(api.revoked, isEmpty);
    },
  );

  test(
    'removal aborts before credential removal when drafts cannot clear',
    () async {
      const error = FileSystemException('draft boundary unavailable');
      drafts.clearSiteError = error;

      expect(
        await controller.removeInstance(controller.currentInstance!),
        isFalse,
      );

      expect(controller.instances, hasLength(1));
      expect(controller.currentInstance?.user?.username, 'reader');
      expect(authenticator.keys[_siteUrl], 'api-key');
      expect(authenticator.disconnected, isEmpty);
      expect(api.revoked, isEmpty);
    },
  );
}

List<ErrorDiagnosticEvent> _operationEvents(
  DiagnosticsController diagnostics,
  String operation,
) => diagnostics.events
    .whereType<ErrorDiagnosticEvent>()
    .where((event) => event.operation == operation)
    .toList();

ErrorDiagnosticEvent _singleOperation(
  DiagnosticsController diagnostics,
  String operation,
) => _operationEvents(diagnostics, operation).single;

final class _InstrumentedAuthenticator extends FakeAuthenticator {
  Object? readError;
  Object? deleteError;

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    if (readError case final error?) throw error;
    return super.apiKeyFor(siteUrl);
  }

  @override
  Future<void> disconnect(String siteUrl) async {
    if (deleteError case final error?) throw error;
    return super.disconnect(siteUrl);
  }
}

final class _InstrumentedDraftStore extends FakeDraftStore {
  Object? clearSiteError;

  @override
  Future<void> clearSite(String siteUrl, {bool Function()? ifCurrent}) async {
    if (clearSiteError case final error?) throw error;
    await super.clearSite(siteUrl, ifCurrent: ifCurrent);
  }
}

final class _InstrumentedFailureApi extends FakeDiscourseApi {
  _InstrumentedFailureApi({required super.feeds});

  Object? likeError;
  Completer<void>? opaqueLikeGate;
  final Completer<void> likeStarted = Completer<void>();
  Object? revokeError;

  @override
  Future<Post?> likePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    if (likeError == null && opaqueLikeGate == null) {
      return super.likePost(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: postId,
        clientId: clientId,
      );
    }
    liked.add(postId);
    if (!likeStarted.isCompleted) likeStarted.complete();
    await opaqueLikeGate?.future;
    if (likeError case final error?) throw error;
    return likeResponses[postId];
  }

  @override
  Future<void> revokeApiKey({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    revoked.add(siteUrl);
    if (revokeError case final error?) throw error;
  }
}
