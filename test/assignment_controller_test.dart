import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugins/assign/assign_api.dart';
import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:discourse_native/src/plugins/assign/assignment_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://example.com';
const _topic = AssignmentTarget.topic(7);
const _forbiddenMessage =
    "You can't post that here — or the connection to this site has expired.";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _PluginTransport transport;
  late _RequestHost requests;
  late List<({String siteUrl, int topicId})> reloads;
  late bool allowed;
  late List<String> invalidatedFallbacks;
  late AssignmentController controller;

  setUp(() {
    transport = _PluginTransport();
    requests = _RequestHost();
    reloads = [];
    allowed = true;
    invalidatedFallbacks = [];
    controller = AssignmentController(
      api: AssignApi(transport),
      requests: requests,
      canAssign: (_, _) => allowed,
      reloadTopic: (siteUrl, topicId) async =>
          reloads.add((siteUrl: siteUrl, topicId: topicId)),
      invalidateLegacyFallback: invalidatedFallbacks.add,
    );
    addTearDown(controller.dispose);
  });

  group('permission enforcement', () {
    test('rejects suggestions before transport access', () async {
      allowed = false;

      await expectLater(
        controller.suggestions(_site, _topic),
        throwsA(
          isA<WriteException>()
              .having(
                (error) => error.failure,
                'failure',
                WriteFailure.forbidden,
              )
              .having((error) => error.message, 'message', _forbiddenMessage),
        ),
      );

      expect(transport.gets, isEmpty);
    });

    test('rejects assignment before transport access', () async {
      allowed = false;

      final error = await controller.assign(
        _site,
        _topic,
        const AssignmentUser(username: 'sam'),
      );

      expect(error, _forbiddenMessage);
      expect(transport.writes, isEmpty);
      expect(reloads, isEmpty);
      expect(invalidatedFallbacks, isEmpty);
    });
  });

  group('assignment writes', () {
    test(
      'reloads the owning topic after a successful post assignment',
      () async {
        final error = await controller.assign(
          _site,
          const AssignmentTarget.post(12, topicId: 7),
          const AssignmentGroup(name: 'triage'),
          note: 'Please investigate',
          status: 'New',
        );

        expect(error, isNull);
        _expectOnlyWrite(
          transport,
          path: '/assign/assign.json',
          body: {
            'target_id': 12,
            'target_type': 'Post',
            'group_name': 'triage',
            'note': 'Please investigate',
            'status': 'New',
          },
        );
        expect(reloads, [(siteUrl: _site, topicId: 7)]);
        expect(invalidatedFallbacks, isEmpty);
      },
    );

    test(
      'returns server validation without reloading or invalidating',
      () async {
        transport.writeFailure = const WriteException(
          WriteFailure.validation,
          errors: ['This user has too many assignments.'],
          statusCode: 400,
        );

        final error = await controller.assign(
          _site,
          _topic,
          const AssignmentUser(username: 'sam'),
        );

        expect(error, 'This user has too many assignments.');
        _expectOnlyWrite(
          transport,
          path: '/assign/assign.json',
          body: {'target_id': 7, 'target_type': 'Topic', 'username': 'sam'},
        );
        expect(reloads, isEmpty);
        expect(invalidatedFallbacks, isEmpty);
      },
    );

    test('rejects a duplicate update while its exact target is busy', () async {
      final gate = Completer<void>();
      transport.writeGate = gate;

      final first = controller.assign(
        _site,
        _topic,
        const AssignmentUser(username: 'sam'),
      );
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        await first;
      });
      await transport.writeStarted.future;

      expect(controller.isWriting(_site, _topic), isTrue);
      final duplicate = await controller.assign(
        _site,
        _topic,
        const AssignmentUser(username: 'alex'),
      );

      expect(duplicate, 'An assignment update is already in progress.');
      expect(transport.writes, hasLength(1));

      gate.complete();
      expect(await first, isNull);
      expect(controller.isWriting(_site, _topic), isFalse);
      expect(reloads, [(siteUrl: _site, topicId: 7)]);
    });
  });

  group('404 reconciliation', () {
    test(
      'returns target-unavailable and reloads after a failed write',
      () async {
        transport.writeFailure = const WriteException(
          WriteFailure.unreachable,
          statusCode: 404,
        );

        final error = await controller.unassign(_site, _topic);

        expect(error, 'This assignment target is no longer available.');
        _expectOnlyWrite(
          transport,
          path: '/assign/unassign.json',
          body: {'target_id': 7, 'target_type': 'Topic'},
        );
        expect(reloads, [(siteUrl: _site, topicId: 7)]);
        expect(invalidatedFallbacks, [_site]);
      },
    );

    test(
      'throws target-unavailable and reloads after a failed lookup',
      () async {
        transport.getFailure = const SiteLookupException(
          SiteLookupFailure.unreachable,
          _site,
          statusCode: 404,
        );

        await expectLater(
          controller.suggestions(_site, _topic),
          throwsA(
            isA<WriteException>()
                .having(
                  (error) => error.failure,
                  'failure',
                  WriteFailure.unreachable,
                )
                .having(
                  (error) => error.message,
                  'message',
                  'This assignment target is no longer available.',
                )
                .having((error) => error.statusCode, 'statusCode', 404),
          ),
        );

        expect(transport.gets, [
          (
            siteUrl: _site,
            path: '/assign/suggestions.json?target_id=7&target_type=Topic',
            apiKey: 'key',
            clientId: 'test-client',
          ),
        ]);
        expect(reloads, [(siteUrl: _site, topicId: 7)]);
        expect(invalidatedFallbacks, [_site]);
      },
    );

    test('invalidates a legacy fallback until current-user refresh', () async {
      transport.writeFailure = const WriteException(
        WriteFailure.unreachable,
        statusCode: 404,
      );
      final snapshotController = AssignmentController(
        api: AssignApi(transport),
        requests: requests,
        permissionSnapshot: (_, _) =>
            (valid: true, recordPermission: null, freshAccountCanAssign: true),
        reloadTopic: (siteUrl, topicId) async =>
            reloads.add((siteUrl: siteUrl, topicId: topicId)),
      );
      addTearDown(snapshotController.dispose);
      final states = <({bool canAssign, bool isWriting})>[];
      snapshotController.addListener(
        () => states.add((
          canAssign: snapshotController.canAssign(_site, _topic),
          isWriting: snapshotController.isWriting(_site, _topic),
        )),
      );

      expect(snapshotController.canAssign(_site, _topic), isTrue);

      final error = await snapshotController.unassign(_site, _topic);

      expect(error, 'This assignment target is no longer available.');
      expect(snapshotController.canAssign(_site, _topic), isFalse);
      expect(states, [
        (canAssign: true, isWriting: true),
        (canAssign: false, isWriting: true),
        (canAssign: false, isWriting: false),
      ]);

      snapshotController.pluginCurrentUserRefreshed(_site);

      expect(snapshotController.canAssign(_site, _topic), isTrue);
      expect(states, [
        (canAssign: true, isWriting: true),
        (canAssign: false, isWriting: true),
        (canAssign: false, isWriting: false),
        (canAssign: true, isWriting: false),
      ]);

      snapshotController.pluginCurrentUserRefreshed(_site);
      expect(states, hasLength(4));
    });
  });

  group('stale async work', () {
    test(
      'disposal during credential lookup suppresses write and reload',
      () async {
        final gatedRequests = _GatedRequestHost();
        final disposedReloads = <({String siteUrl, int topicId})>[];
        final disposedController = AssignmentController(
          api: AssignApi(transport),
          requests: gatedRequests,
          canAssign: (_, _) => true,
          reloadTopic: (siteUrl, topicId) async =>
              disposedReloads.add((siteUrl: siteUrl, topicId: topicId)),
          invalidateLegacyFallback: (_) {},
        );
        var disposed = false;
        addTearDown(() {
          if (!disposed) disposedController.dispose();
          if (!gatedRequests.credentials.isCompleted) {
            gatedRequests.credentials.complete(
              const PluginRequestCredentials(
                apiKey: 'cleanup-key',
                clientId: 'cleanup',
              ),
            );
          }
        });

        final assignment = disposedController.assign(
          _site,
          _topic,
          const AssignmentUser(username: 'sam'),
        );
        await gatedRequests.credentialsRequested.future;

        disposedController.dispose();
        disposed = true;
        gatedRequests.credentials.complete(
          const PluginRequestCredentials(apiKey: 'stale-key', clientId: 'test'),
        );

        expect(await assignment, _forbiddenMessage);
        expect(transport.writes, isEmpty);
        expect(disposedReloads, isEmpty);
      },
    );

    test(
      'an invalidated site lease suppresses its pending plugin read',
      () async {
        final gatedRequests = _GatedRequestHost();
        final staleController = AssignmentController(
          api: AssignApi(transport),
          requests: gatedRequests,
          canAssign: (_, _) => true,
          reloadTopic: (_, _) async {},
          invalidateLegacyFallback: (_) {},
        );
        addTearDown(staleController.dispose);
        addTearDown(() {
          if (!gatedRequests.credentials.isCompleted) {
            gatedRequests.credentials.complete(
              const PluginRequestCredentials(
                apiKey: 'cleanup-key',
                clientId: 'cleanup',
              ),
            );
          }
        });

        final suggestions = staleController.suggestions(_site, _topic);
        await gatedRequests.credentialsRequested.future;

        gatedRequests.invalidate();
        gatedRequests.credentials.complete(
          const PluginRequestCredentials(
            apiKey: 'stale-key',
            clientId: 'stale',
          ),
        );

        await expectLater(
          suggestions,
          throwsA(
            isA<WriteException>()
                .having(
                  (error) => error.failure,
                  'failure',
                  WriteFailure.forbidden,
                )
                .having((error) => error.message, 'message', _forbiddenMessage),
          ),
        );

        expect(transport.gets, isEmpty);
      },
    );
  });
}

void _expectOnlyWrite(
  _PluginTransport transport, {
  required String path,
  required Map<String, Object?> body,
}) {
  expect(transport.writes, hasLength(1));
  final write = transport.writes.single;
  expect(
    (
      siteUrl: write.siteUrl,
      path: write.path,
      method: write.method,
      apiKey: write.apiKey,
      clientId: write.clientId,
    ),
    (
      siteUrl: _site,
      path: path,
      method: 'PUT',
      apiKey: 'key',
      clientId: 'test-client',
    ),
  );
  expect(write.body, body);
}

final class _RequestHost implements PluginRequestHost {
  @override
  PluginSiteLease capture(String siteUrl) => _Lease();

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async =>
      const PluginRequestCredentials(apiKey: 'key', clientId: 'test-client');

  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) async =>
      (apiKey: 'key', failure: null);
}

final class _GatedRequestHost implements PluginRequestHost {
  final credentials = Completer<PluginRequestCredentials>();
  final credentialsRequested = Completer<void>();
  final _leases = <_Lease>[];

  @override
  PluginSiteLease capture(String siteUrl) {
    final lease = _Lease();
    _leases.add(lease);
    return lease;
  }

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) {
    if (!credentialsRequested.isCompleted) credentialsRequested.complete();
    return credentials.future;
  }

  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) async =>
      (apiKey: 'key', failure: null);

  void invalidate() {
    for (final lease in _leases) {
      lease.current = false;
    }
  }
}

final class _Lease implements PluginSiteLease {
  bool current = true;

  @override
  bool get isCurrent => current;

  @override
  bool commit(void Function() mutation) {
    if (!current) return false;
    mutation();
    return true;
  }
}

class _PluginTransport implements PluginApiTransport {
  final List<({String siteUrl, String path, String? apiKey, String? clientId})>
  gets = [];
  final List<
    ({
      String siteUrl,
      String method,
      String path,
      String apiKey,
      Map<String, Object?> body,
      String? clientId,
    })
  >
  writes = [];
  WriteException? writeFailure;
  SiteLookupException? getFailure;
  Completer<void>? writeGate;
  final writeStarted = Completer<void>();

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    gets.add((
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    ));
    if (getFailure case final failure?) throw failure;
    return const {
      'suggestions': <Object?>[],
      'assign_allowed_on_groups': <Object?>[],
      'assign_allowed_for_groups': <Object?>[],
    };
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
    writes.add((
      siteUrl: siteUrl,
      method: method,
      path: path,
      apiKey: apiKey,
      body: body,
      clientId: clientId,
    ));
    if (!writeStarted.isCompleted) writeStarted.complete();
    await writeGate?.future;
    if (writeFailure case final failure?) throw failure;
    return const {'success': 'OK'};
  }
}
