import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugins/assign/assign_api.dart';
import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:discourse_native/src/plugins/assign/assignment_controller.dart';
import 'package:flutter/foundation.dart';
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
  Object? reloadFailure;
  Completer<void>? reloadGate;
  late Completer<void> reloadStarted;

  setUp(() {
    transport = _PluginTransport();
    requests = _RequestHost();
    reloads = [];
    allowed = true;
    invalidatedFallbacks = [];
    reloadFailure = null;
    reloadGate = null;
    reloadStarted = Completer<void>();
    controller = AssignmentController(
      api: AssignApi(transport),
      requests: requests,
      canAssign: (_, _) => allowed,
      reloadTopic: (siteUrl, topicId) async {
        reloads.add((siteUrl: siteUrl, topicId: topicId));
        if (!reloadStarted.isCompleted) reloadStarted.complete();
        await reloadGate?.future;
        if (reloadFailure case final failure?) throw failure;
      },
      invalidateLegacyFallback: invalidatedFallbacks.add,
    );
    addTearDown(controller.dispose);
  });

  test('obsolete undo cannot replace a newer successful assignment', () async {
    final removal = await controller.unassignForUndo(
      _site,
      _topic,
      const Assignment(
        assignee: AssignmentUser(username: 'sam'),
        note: 'Original note',
        status: 'New',
      ),
    );
    expect(removal.permit, isNotNull);
    expect(
      (await controller.assign(
        _site,
        _topic,
        const AssignmentUser(username: 'alex'),
        note: 'New note',
        status: 'In progress',
      )).kind,
      AssignmentWriteKind.applied,
    );

    final undone = await controller.restoreAssignment(removal.permit!);

    expect(undone.kind, AssignmentWriteKind.inactive);
    expect(transport.writes, hasLength(2));
    expect(transport.writes.last.body['username'], 'alex');
    expect(transport.writes.last.body['note'], 'New note');
    expect(transport.writes.last.body['status'], 'In progress');
  });

  group('Undo target authority', () {
    const original = Assignment(
      assignee: AssignmentUser(username: 'sam'),
      note: 'Original note',
      status: 'New',
    );

    test('acceptance revokes Undo before a pending refresh', () async {
      final removal = await controller.unassignForUndo(_site, _topic, original);
      final gate = Completer<void>();
      reloadGate = gate;
      reloadStarted = Completer<void>();
      final pending = controller.assign(
        _site,
        _topic,
        const AssignmentUser(username: 'alex'),
      );
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        await pending;
      });
      await reloadStarted.future;

      expect(controller.isWriting(_site, _topic), isTrue);
      expect(
        (await controller.restoreAssignment(removal.permit!)).kind,
        AssignmentWriteKind.inactive,
      );
      expect(transport.writes, hasLength(2));
      gate.complete();
      expect((await pending).kind, AssignmentWriteKind.applied);
    });

    test('accepted refresh failure still revokes old Undo', () async {
      final removal = await controller.unassignForUndo(_site, _topic, original);
      reloadFailure = StateError('refresh failed');

      expect(
        (await controller.assign(
          _site,
          _topic,
          const AssignmentUser(username: 'alex'),
        )).kind,
        AssignmentWriteKind.acceptedRefreshFailed,
      );
      expect(
        (await controller.restoreAssignment(removal.permit!)).kind,
        AssignmentWriteKind.inactive,
      );
      expect(transport.writes, hasLength(2));
    });

    test('a newer plain removal revokes old Undo', () async {
      final removal = await controller.unassignForUndo(_site, _topic, original);
      expect(
        (await controller.unassign(_site, _topic)).kind,
        AssignmentWriteKind.applied,
      );

      expect(
        (await controller.restoreAssignment(removal.permit!)).kind,
        AssignmentWriteKind.inactive,
      );
      expect(transport.writes, hasLength(2));
    });

    test('only the latest removal can restore its own assignment', () async {
      final first = await controller.unassignForUndo(_site, _topic, original);
      final second = await controller.unassignForUndo(
        _site,
        _topic,
        const Assignment(
          assignee: AssignmentUser(username: 'alex'),
          note: 'New note',
          status: 'In progress',
        ),
      );

      expect(
        (await controller.restoreAssignment(first.permit!)).kind,
        AssignmentWriteKind.inactive,
      );
      expect(
        (await controller.restoreAssignment(second.permit!)).kind,
        AssignmentWriteKind.applied,
      );
      expect(transport.writes, hasLength(3));
      expect(transport.writes.last.body['username'], 'alex');
      expect(transport.writes.last.body['note'], 'New note');
      expect(transport.writes.last.body['status'], 'In progress');
      expect(transport.writes.last.body['should_notify'], 'false');
      expect(
        (await controller.restoreAssignment(second.permit!)).kind,
        AssignmentWriteKind.inactive,
      );
    });

    for (final newer in [
      (siteUrl: _site, target: const AssignmentTarget.topic(8)),
      (siteUrl: _site, target: const AssignmentTarget.post(7, topicId: 7)),
      (siteUrl: 'https://other.example', target: _topic),
    ]) {
      test('a write to $newer preserves unrelated Undo', () async {
        final removal = await controller.unassignForUndo(
          _site,
          _topic,
          original,
        );
        expect(
          (await controller.assign(
            newer.siteUrl,
            newer.target,
            const AssignmentUser(username: 'alex'),
          )).kind,
          AssignmentWriteKind.applied,
        );

        expect(
          (await controller.restoreAssignment(removal.permit!)).kind,
          AssignmentWriteKind.applied,
        );
        expect(transport.writes, hasLength(3));
        expect(transport.writes.last.siteUrl, _site);
        expect(transport.writes.last.body['target_type'], 'Topic');
        expect(transport.writes.last.body['target_id'], 7);
        expect(transport.writes.last.body['username'], 'sam');
      });
    }

    test('another post in the same topic preserves post Undo', () async {
      final removal = await controller.unassignForUndo(
        _site,
        const AssignmentTarget.post(12, topicId: 7),
        original,
      );
      await controller.assign(
        _site,
        const AssignmentTarget.post(13, topicId: 7),
        const AssignmentUser(username: 'alex'),
      );

      expect(
        (await controller.restoreAssignment(removal.permit!)).kind,
        AssignmentWriteKind.applied,
      );
      expect(transport.writes.last.body['target_id'], 12);
    });

    test(
      'a moved post cannot mint Undo after a newer accepted write',
      () async {
        final gate = Completer<void>();
        reloadGate = gate;
        final pending = controller.unassignForUndo(
          _site,
          const AssignmentTarget.post(12, topicId: 7),
          original,
        );
        addTearDown(() async {
          if (!gate.isCompleted) gate.complete();
          await pending;
        });
        await reloadStarted.future;
        reloadGate = null;
        expect(
          (await controller.assign(
            _site,
            const AssignmentTarget.post(12, topicId: 8),
            const AssignmentUser(username: 'alex'),
          )).kind,
          AssignmentWriteKind.applied,
        );
        gate.complete();

        final result = await pending;
        expect(result.outcome.kind, AssignmentWriteKind.applied);
        expect(result.permit, isNull);
        expect(transport.writes, hasLength(2));
      },
    );

    for (final (name, failure, kind) in [
      (
        'server refusal',
        const WriteException(WriteFailure.validation, statusCode: 400),
        AssignmentWriteKind.refused,
      ),
      (
        'write not sent',
        const WriteException(WriteFailure.unreachable, notSent: true),
        AssignmentWriteKind.notSent,
      ),
      (
        'uncertain response',
        const WriteException(WriteFailure.unreachable),
        AssignmentWriteKind.uncertain,
      ),
    ]) {
      test('an unaccepted write preserves Undo after $name', () async {
        final removal = await controller.unassignForUndo(
          _site,
          _topic,
          original,
        );
        transport.writeFailure = failure;
        final result = await controller.unassignForUndo(
          _site,
          _topic,
          original,
        );
        expect(result.outcome.kind, kind);
        expect(result.outcome.accepted, isFalse);
        expect(result.permit, isNull);
        transport.writeFailure = null;

        expect(
          (await controller.restoreAssignment(removal.permit!)).kind,
          AssignmentWriteKind.applied,
        );
        expect(transport.writes, hasLength(3));
      });
    }

    test(
      'permission refusal preserves the established Undo authority',
      () async {
        final removal = await controller.unassignForUndo(
          _site,
          _topic,
          original,
        );
        allowed = false;
        expect(
          (await controller.assign(
            _site,
            _topic,
            const AssignmentUser(username: 'alex'),
          )).kind,
          AssignmentWriteKind.refused,
        );

        expect(
          (await controller.restoreAssignment(removal.permit!)).kind,
          AssignmentWriteKind.applied,
        );
        expect(transport.writes, hasLength(2));
      },
    );

    test('a busy Undo attempt remains one use without dispatch', () async {
      final removal = await controller.unassignForUndo(_site, _topic, original);
      final gate = Completer<void>();
      transport
        ..writeGate = gate
        ..writeFailure = const WriteException(WriteFailure.validation);
      final pending = controller.assign(
        _site,
        _topic,
        const AssignmentUser(username: 'alex'),
      );
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        await pending;
      });
      expect(
        (await controller.restoreAssignment(removal.permit!)).kind,
        AssignmentWriteKind.busy,
      );
      gate.complete();
      expect((await pending).kind, AssignmentWriteKind.refused);
      transport.writeFailure = null;

      expect(
        (await controller.restoreAssignment(removal.permit!)).kind,
        AssignmentWriteKind.inactive,
      );
      expect(transport.writes, hasLength(2));
    });

    test(
      'a completion listener can start a write that supersedes Undo',
      () async {
        Future<AssignmentWriteResult>? newer;
        var started = false;
        controller.addListener(() {
          if (started || controller.isWriting(_site, _topic)) return;
          started = true;
          newer = controller.assign(
            _site,
            _topic,
            const AssignmentUser(username: 'alex'),
          );
        });
        final removal = await controller.unassignForUndo(
          _site,
          _topic,
          original,
        );
        expect(newer, isNotNull);
        expect((await newer!).kind, AssignmentWriteKind.applied);

        if (removal.permit case final permit?) {
          expect(
            (await controller.restoreAssignment(permit)).kind,
            AssignmentWriteKind.inactive,
          );
        }
        expect(transport.writes, hasLength(2));
      },
    );

    test('credential failure preserves an existing Undo permit', () async {
      final removal = await controller.unassignForUndo(_site, _topic, original);
      requests.credentialsGate = Completer<PluginRequestCredentials>();
      final pending = controller.unassignForUndo(_site, _topic, original);
      requests.credentialsGate!.completeError(StateError('credentials failed'));
      final result = await pending;
      expect(result.outcome.kind, AssignmentWriteKind.notSent);
      expect(result.permit, isNull);
      requests.credentialsGate = null;

      expect(
        (await controller.restoreAssignment(removal.permit!)).kind,
        AssignmentWriteKind.applied,
      );
      expect(transport.writes, hasLength(2));
    });

    test(
      'a busy removal preserves Undo when the pending write fails',
      () async {
        final removal = await controller.unassignForUndo(
          _site,
          _topic,
          original,
        );
        final gate = Completer<void>();
        transport
          ..writeGate = gate
          ..writeFailure = const WriteException(WriteFailure.validation);
        final pending = controller.assign(
          _site,
          _topic,
          const AssignmentUser(username: 'alex'),
        );
        addTearDown(() async {
          if (!gate.isCompleted) gate.complete();
          await pending;
        });
        final duplicate = await controller.unassignForUndo(
          _site,
          _topic,
          original,
        );
        expect(duplicate.outcome.kind, AssignmentWriteKind.busy);
        expect(duplicate.permit, isNull);
        gate.complete();
        expect((await pending).kind, AssignmentWriteKind.refused);
        transport.writeFailure = null;

        expect(
          (await controller.restoreAssignment(removal.permit!)).kind,
          AssignmentWriteKind.applied,
        );
        expect(transport.writes, hasLength(3));
      },
    );

    test('a permit expires ten seconds after the removal returns', () async {
      final gate = Completer<void>();
      reloadGate = gate;
      final pending = controller.unassignForUndo(_site, _topic, original);
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        await pending;
      });
      await reloadStarted.future;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final refreshReleasedAt = DateTime.now();
      gate.complete();
      final removal = await pending;
      final permit = removal.permit!;
      expect(
        permit.expiresAt.isBefore(
          refreshReleasedAt.add(const Duration(seconds: 10)),
        ),
        isFalse,
      );
      final remaining = permit.expiresAt.difference(DateTime.now());
      await Future<void>.delayed(remaining + const Duration(milliseconds: 1));

      expect(
        (await controller.restoreAssignment(permit)).kind,
        AssignmentWriteKind.inactive,
      );
      expect(transport.writes, hasLength(1));
    });
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

      expect(error.kind, AssignmentWriteKind.refused);
      expect(error.failure?.failure, WriteFailure.forbidden);
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

        expect(error.kind, AssignmentWriteKind.applied);
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

        expect(error.kind, AssignmentWriteKind.refused);
        expect(error.failure?.errors, ['This user has too many assignments.']);
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

      expect(duplicate.kind, AssignmentWriteKind.busy);
      expect(transport.writes, hasLength(1));

      gate.complete();
      expect((await first).kind, AssignmentWriteKind.applied);
      expect(controller.isWriting(_site, _topic), isFalse);
      expect(reloads, [(siteUrl: _site, topicId: 7)]);
    });
  });

  group('account and request replacement', () {
    test(
      'a write cannot adopt an account selected by its loading listener',
      () async {
        var replaced = false;
        controller.addListener(() {
          if (replaced || !controller.isWriting(_site, _topic)) return;
          replaced = true;
          requests.invalidate();
          controller.forget(_site);
        });

        await controller.assign(
          _site,
          _topic,
          const AssignmentUser(username: 'sam'),
        );

        expect(replaced, isTrue);
        expect(transport.writes, isEmpty);
        expect(reloads, isEmpty);
      },
    );

    for (final rotateLease in [false, true]) {
      test(
        'a forgotten write cannot finish its replacement (rotate lease: $rotateLease)',
        () async {
          final firstReply = Completer<void>();
          final secondReply = Completer<void>();
          final secondStarted = Completer<void>();
          addTearDown(() {
            if (!firstReply.isCompleted) firstReply.complete();
            if (!secondReply.isCompleted) secondReply.complete();
          });
          transport.writeGate = firstReply;
          final first = controller.assign(
            _site,
            _topic,
            const AssignmentUser(username: 'sam'),
          );
          await transport.writeStarted.future;
          if (rotateLease) requests.invalidate();
          controller.forget(_site);
          transport
            ..writeGate = secondReply
            ..onWrite = secondStarted.complete;
          final second = controller.assign(
            _site,
            _topic,
            const AssignmentUser(username: 'lee'),
          );
          await secondStarted.future;

          firstReply.complete();
          await first;
          expect(controller.isWriting(_site, _topic), isTrue);
          expect(reloads, isEmpty);
          expect(
            await controller.assign(
              _site,
              _topic,
              const AssignmentUser(username: 'alex'),
            ),
            isA<AssignmentWriteResult>().having(
              (result) => result.kind,
              'kind',
              AssignmentWriteKind.busy,
            ),
          );
          expect(transport.writes.map((write) => write.body['username']), [
            'sam',
            'lee',
          ]);
          secondReply.complete();
          await second;
          expect(controller.isWriting(_site, _topic), isFalse);
          expect(reloads, [(siteUrl: _site, topicId: 7)]);
        },
      );
    }

    for (final invalidate in ['account lease', 'controller state']) {
      test('an Undo permit is revoked with its $invalidate', () async {
        final result = await controller.unassignForUndo(
          _site,
          _topic,
          const Assignment(assignee: AssignmentUser(username: 'sam')),
        );
        final permit = result.permit;
        expect(permit, isNotNull);
        if (invalidate == 'account lease') {
          requests.invalidate();
        } else {
          controller.forget(_site);
        }
        allowed = false;

        expect(
          (await controller.restoreAssignment(permit!)).kind,
          AssignmentWriteKind.inactive,
        );
        expect(transport.writes.map((write) => write.path), [
          '/assign/unassign.json',
        ]);
      });
    }
  });

  group('write outcome authority', () {
    test(
      'retirement before credentials sends nothing and grants no undo',
      () async {
        requests.credentialsGate = Completer<PluginRequestCredentials>();
        final pending = controller.unassignForUndo(
          _site,
          _topic,
          const Assignment(assignee: AssignmentUser(username: 'sam')),
        );
        requests.invalidate();
        controller.forget(_site);
        requests.credentialsGate!.complete(
          const PluginRequestCredentials(apiKey: 'old-key', clientId: ''),
        );
        final result = await pending;
        expect(result.outcome.kind, AssignmentWriteKind.inactive);
        expect(result.outcome.accepted, isFalse);
        expect(result.permit, isNull);
        expect(transport.writes, isEmpty);
        expect(reloads, isEmpty);
      },
    );

    test(
      'accepted retirement keeps acceptance without undo or reload',
      () async {
        transport.writeGate = Completer<void>();
        final pending = controller.unassignForUndo(
          _site,
          _topic,
          const Assignment(assignee: AssignmentUser(username: 'sam')),
        );
        await transport.writeStarted.future;
        requests.invalidate();
        controller.forget(_site);
        transport.writeGate!.complete();
        final result = await pending;
        expect(result.outcome.kind, AssignmentWriteKind.acceptedRetired);
        expect(result.outcome.accepted, isTrue);
        expect(result.permit, isNull);
        expect(reloads, isEmpty);
      },
    );

    test(
      'a reload 404 cannot revoke accepted removal or undo authority',
      () async {
        reloadFailure = const WriteException(
          WriteFailure.unreachable,
          statusCode: 404,
        );
        final result = await controller.unassignForUndo(
          _site,
          _topic,
          const Assignment(assignee: AssignmentUser(username: 'sam')),
        );
        expect(result.outcome.kind, AssignmentWriteKind.acceptedRefreshFailed);
        expect(result.outcome.accepted, isTrue);
        expect(result.outcome.failure, same(reloadFailure));
        expect(result.permit, isNotNull);
        expect(invalidatedFallbacks, isEmpty);
        reloadFailure = null;
        expect(
          (await controller.restoreAssignment(result.permit!)).kind,
          AssignmentWriteKind.applied,
        );
        expect(transport.writes.last.body['should_notify'], 'false');
        expect(
          (await controller.restoreAssignment(result.permit!)).kind,
          AssignmentWriteKind.inactive,
        );
        expect(transport.writes, hasLength(2));
      },
    );

    test('retirement during reload cannot grant an undo permit', () async {
      reloadGate = Completer<void>();
      final pending = controller.unassignForUndo(
        _site,
        _topic,
        const Assignment(assignee: AssignmentUser(username: 'sam')),
      );
      await reloadStarted.future;
      expect(reloads, hasLength(1));
      requests.invalidate();
      controller.forget(_site);
      reloadGate!.complete();
      final result = await pending;
      expect(result.outcome.kind, AssignmentWriteKind.acceptedRetired);
      expect(result.permit, isNull);
    });

    for (final notSent in [false, true]) {
      test('lost write response distinguishes notSent=$notSent', () async {
        transport.writeFailure = WriteException(
          WriteFailure.unreachable,
          notSent: notSent,
        );
        final result = await controller.unassignForUndo(
          _site,
          _topic,
          const Assignment(assignee: AssignmentUser(username: 'sam')),
        );
        expect(
          result.outcome.kind,
          notSent ? AssignmentWriteKind.notSent : AssignmentWriteKind.uncertain,
        );
        expect(result.outcome.accepted, isFalse);
        expect(result.permit, isNull);
        expect(reloads, isEmpty);
      });
    }

    test(
      'an executor refusal before dispatch is not an uncertain write',
      () async {
        requests.executor = <T>(Future<T> Function() request) async {
          throw const WriteException(WriteFailure.unreachable);
        };
        final result = await controller.unassign(_site, _topic);
        expect(result.kind, AssignmentWriteKind.notSent);
        expect(transport.writes, isEmpty);
        expect(reloads, isEmpty);
      },
    );

    test('a credential failure is not an uncertain write', () async {
      requests.credentialsGate = Completer<PluginRequestCredentials>();
      final pending = controller.unassign(_site, _topic);
      requests.credentialsGate!.completeError(
        StateError('credential read failed'),
      );
      final result = await pending;
      expect(result.kind, AssignmentWriteKind.notSent);
      expect(transport.writes, isEmpty);
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

        expect(error.kind, AssignmentWriteKind.targetUnavailable);
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

      expect(error.kind, AssignmentWriteKind.targetUnavailable);
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

  group('site permission changes', () {
    const otherSite = 'https://other.example.com';

    /// What [read] answered at each notification of [listenable].
    List<T> heard<T>(Listenable listenable, T Function() read) {
      final answers = <T>[];
      void listener() => answers.add(read());
      listenable.addListener(listener);
      addTearDown(() => listenable.removeListener(listener));
      return answers;
    }

    AssignmentController legacyController() {
      transport.writeFailure = const WriteException(
        WriteFailure.unreachable,
        statusCode: 404,
      );
      final legacy = AssignmentController(
        api: AssignApi(transport),
        requests: requests,
        permissionSnapshot: (_, _) =>
            (valid: true, recordPermission: null, freshAccountCanAssign: true),
        reloadTopic: (siteUrl, topicId) async =>
            reloads.add((siteUrl: siteUrl, topicId: topicId)),
      );
      addTearDown(legacy.dispose);
      return legacy;
    }

    test('a write notifies the controller but not its permission', () async {
      final gate = Completer<void>();
      transport.writeGate = gate;
      final writing = heard(
        controller,
        () => controller.isWriting(_site, _topic),
      );
      final permission = heard(
        controller.permissionChanges(_site),
        () => controller.canAssign(_site, _topic),
      );

      final write = controller.assign(
        _site,
        _topic,
        const AssignmentUser(username: 'sam'),
      );
      await transport.writeStarted.future;
      expect(writing, [true]);

      gate.complete();
      expect((await write).kind, AssignmentWriteKind.applied);
      controller.forget(_site);

      expect(writing, [true, false]);
      expect(permission, isEmpty);
    });

    test('a legacy fallback notifies its own site as it moves', () async {
      final legacy = legacyController();
      final permission = heard(
        legacy.permissionChanges(_site),
        () => legacy.canAssign(_site, _topic),
      );
      final elsewhere = heard(
        legacy.permissionChanges(otherSite),
        () => legacy.canAssign(otherSite, _topic),
      );
      expect(
        identical(
          legacy.permissionChanges(_site),
          legacy.permissionChanges(_site),
        ),
        isTrue,
      );

      expect(
        await legacy.unassign(_site, _topic),
        isA<AssignmentWriteResult>().having(
          (result) => result.kind,
          'kind',
          AssignmentWriteKind.targetUnavailable,
        ),
      );
      expect(permission, [false]);

      legacy.pluginCurrentUserRefreshed(_site);
      expect(permission, [false, true]);

      legacy.pluginCurrentUserRefreshed(_site);
      expect(permission, [false, true]);
      expect(elsewhere, isEmpty);
    });

    test(
      'forget notifies only when it restores a withdrawn fallback',
      () async {
        final legacy = legacyController();
        final changes = legacy.permissionChanges(_site);
        final permission = heard(
          changes,
          () => legacy.canAssign(_site, _topic),
        );

        legacy.forget(_site);
        expect(permission, isEmpty);

        await legacy.unassign(_site, _topic);
        legacy.forget(_site);

        expect(permission, [false, true]);
        // A retained row keeps listening across the forget and must still hear
        // the site's next change.
        expect(identical(legacy.permissionChanges(_site), changes), isTrue);
        await legacy.unassign(_site, _topic);
        expect(permission, [false, true, false]);
      },
    );
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

        expect((await assignment).kind, AssignmentWriteKind.inactive);
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
  final _leases = <_Lease>[];
  Completer<PluginRequestCredentials>? credentialsGate;
  PluginRequestExecutor? executor;

  @override
  PluginSiteLease capture(String siteUrl) {
    final lease = _Lease();
    _leases.add(lease);
    return lease;
  }

  void invalidate() {
    for (final lease in _leases) {
      lease.current = false;
    }
  }

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async =>
      credentialsGate == null
      ? PluginRequestCredentials(
          apiKey: 'key',
          clientId: 'test-client',
          execute: executor,
        )
      : await credentialsGate!.future;

  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) async => (
    credentials: const PluginRequestCredentials(apiKey: 'key', clientId: ''),
    failure: null,
  );
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
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) async => (
    credentials: const PluginRequestCredentials(apiKey: 'key', clientId: ''),
    failure: null,
  );

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
  void Function()? onWrite;
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
    onWrite?.call();
    await writeGate?.future;
    if (writeFailure case final failure?) throw failure;
    return const {'success': 'OK'};
  }
}
