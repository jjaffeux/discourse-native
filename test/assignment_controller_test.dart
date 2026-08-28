import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugins/assign/assign_api.dart';
import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:discourse_native/src/plugins/assign/assignment_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://example.com';
const _topic = AssignmentTarget.topic(7);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _PluginTransport transport;
  late _RequestHost requests;
  late List<int> reloads;
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
      reloadTopic: (_, topicId) async => reloads.add(topicId),
      invalidateLegacyFallback: invalidatedFallbacks.add,
    );
  });

  tearDown(() => controller.dispose());

  test(
    'refuses lookup and mutation when the target record denies them',
    () async {
      allowed = false;

      await expectLater(
        controller.suggestions(_site, _topic),
        throwsA(
          isA<WriteException>().having(
            (error) => error.failure,
            'failure',
            WriteFailure.forbidden,
          ),
        ),
      );
      final error = await controller.assign(
        _site,
        _topic,
        const AssignmentUser(username: 'sam'),
      );

      expect(error, contains("can't post"));
      expect(transport.writes, isEmpty);
      expect(reloads, isEmpty);
    },
  );

  test('successful assignment reloads the complete owning topic', () async {
    final error = await controller.assign(
      _site,
      const AssignmentTarget.post(12, topicId: 7),
      const AssignmentGroup(name: 'triage'),
      note: 'Please investigate',
      status: 'New',
    );

    expect(error, isNull);
    expect(reloads, [7]);
    expect(invalidatedFallbacks, isEmpty);
    expect(transport.writes.single.path, '/assign/assign.json');
  });

  test(
    'a refusal remains visible and does not reload unrelated state',
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
      expect(reloads, isEmpty);
    },
  );

  test(
    'a 404 triggers scoped reconciliation without disabling the site',
    () async {
      transport.writeFailure = const WriteException(
        WriteFailure.unreachable,
        statusCode: 404,
      );

      final error = await controller.unassign(_site, _topic);

      expect(error, 'This assignment target is no longer available.');
      expect(reloads, [7]);
      expect(invalidatedFallbacks, [_site]);
    },
  );

  test(
    'a fresh current user restores the invalidated legacy fallback and rebuilds',
    () async {
      transport.writeFailure = const WriteException(
        WriteFailure.unreachable,
        statusCode: 404,
      );
      final snapshotController = AssignmentController(
        api: AssignApi(transport),
        requests: requests,
        permissionSnapshot: (_, _) =>
            (valid: true, recordPermission: null, freshAccountCanAssign: true),
        reloadTopic: (_, topicId) async => reloads.add(topicId),
      );
      addTearDown(snapshotController.dispose);
      var rebuilds = 0;
      snapshotController.addListener(() => rebuilds++);

      expect(snapshotController.canAssign(_site, _topic), isTrue);

      final error = await snapshotController.unassign(_site, _topic);

      expect(error, 'This assignment target is no longer available.');
      expect(snapshotController.canAssign(_site, _topic), isFalse);
      expect(rebuilds, greaterThan(0));
      final rebuildsBeforeRefresh = rebuilds;

      snapshotController.pluginCurrentUserRefreshed(_site);

      expect(snapshotController.canAssign(_site, _topic), isTrue);
      expect(rebuilds, rebuildsBeforeRefresh + 1);

      snapshotController.pluginCurrentUserRefreshed(_site);
      expect(
        rebuilds,
        rebuildsBeforeRefresh + 1,
        reason: 'an already-current fallback is unchanged',
      );
    },
  );

  test('a suggestions 404 also reconciles stale plugin controls', () async {
    transport.getFailure = const SiteLookupException(
      SiteLookupFailure.unreachable,
      _site,
      statusCode: 404,
    );

    await expectLater(
      controller.suggestions(_site, _topic),
      throwsA(
        isA<WriteException>().having(
          (error) => error.message,
          'message',
          'This assignment target is no longer available.',
        ),
      ),
    );

    expect(reloads, [7]);
    expect(invalidatedFallbacks, [_site]);
  });

  test('serializes duplicate writes for the same exact target', () async {
    final gate = Completer<void>();
    transport.writeGate = gate;

    final first = controller.assign(
      _site,
      _topic,
      const AssignmentUser(username: 'sam'),
    );
    await _waitUntil(() => transport.writes.isNotEmpty);

    final duplicate = await controller.assign(
      _site,
      _topic,
      const AssignmentUser(username: 'alex'),
    );
    expect(duplicate, 'An assignment update is already in progress.');
    expect(transport.writes, hasLength(1));

    gate.complete();
    expect(await first, isNull);
    expect(reloads, [7]);
  });

  test(
    'dispose during credential lookup prevents assignment side effects',
    () async {
      final gatedRequests = _GatedRequestHost();
      final disposedReloads = <int>[];
      final disposedController = AssignmentController(
        api: AssignApi(transport),
        requests: gatedRequests,
        canAssign: (_, _) => true,
        reloadTopic: (_, topicId) async => disposedReloads.add(topicId),
        invalidateLegacyFallback: (_) {},
      );

      final assignment = disposedController.assign(
        _site,
        _topic,
        const AssignmentUser(username: 'sam'),
      );
      await _waitUntil(() => gatedRequests.credentialCalls == 1);

      disposedController.dispose();
      gatedRequests.credentials.complete(
        const PluginRequestCredentials(apiKey: 'stale-key', clientId: 'test'),
      );

      expect(await assignment, contains("can't post"));
      expect(transport.writes, isEmpty);
      expect(disposedReloads, isEmpty);
    },
  );

  test('an invalidated site lease prevents a stale plugin read', () async {
    final gatedRequests = _GatedRequestHost();
    final staleController = AssignmentController(
      api: AssignApi(transport),
      requests: gatedRequests,
      canAssign: (_, _) => true,
      reloadTopic: (_, _) async {},
      invalidateLegacyFallback: (_) {},
    );
    addTearDown(staleController.dispose);

    final suggestions = staleController.suggestions(_site, _topic);
    await _waitUntil(() => gatedRequests.credentialCalls == 1);

    gatedRequests.invalidate();
    gatedRequests.credentials.complete(
      const PluginRequestCredentials(apiKey: 'stale-key', clientId: 'stale'),
    );

    await expectLater(
      suggestions,
      throwsA(
        isA<WriteException>().having(
          (error) => error.failure,
          'failure',
          WriteFailure.forbidden,
        ),
      ),
    );

    expect(transport.gets, isEmpty);
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not reached.');
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
  final _leases = <_Lease>[];
  int credentialCalls = 0;

  @override
  PluginSiteLease capture(String siteUrl) {
    final lease = _Lease();
    _leases.add(lease);
    return lease;
  }

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) {
    credentialCalls++;
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
  final List<String> gets = [];
  final List<({String method, String path, Map<String, Object?> body})> writes =
      [];
  WriteException? writeFailure;
  SiteLookupException? getFailure;
  Completer<void>? writeGate;

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    gets.add(path);
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
    writes.add((method: method, path: path, body: body));
    await writeGate?.future;
    if (writeFailure case final failure?) throw failure;
    return const {'success': 'OK'};
  }
}
