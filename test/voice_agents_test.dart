import 'dart:async';

import 'package:discourse_native/src/plugins/voice/voice_agents.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('agent permission', () {
    final eligible = <String, dynamic>{
      'id': 7,
      'public': true,
      'expected_transport': 'livekit',
      'active_participants': [
        {'id': 42, 'username': 'human'},
      ],
    };

    test('requires the authenticated negative bot ID', () {
      final room = VoiceRoom.fromJson(eligible);
      for (final value in [
        null,
        false,
        0,
        42,
        -2.5,
        '-2',
        <String, Object?>{},
        <Object>[],
      ]) {
        expect(
          VoiceAgentPermission.read({
            'voice_livekit_agent_bot_id': value,
          }).allows(room),
          isFalse,
          reason: '$value',
        );
      }
      expect(
        VoiceAgentPermission.read({
          'voice_livekit_agent_bot_id': -2,
        }).allows(room),
        isTrue,
      );
      expect(
        VoiceAgentPermission.read({
          'admin': true,
          'voice_livekit_agent_enabled': true,
        }).allows(room),
        isFalse,
      );
    });

    test('rejects private, mesh, unknown, empty and bot-occupied rooms', () {
      for (final changes in <Map<String, dynamic>>[
        {'public': false},
        {'expected_transport': 'mesh'},
        {'expected_transport': null},
        {'active_participants': <Object>[]},
        {
          'active_participants': [
            {'id': -3},
          ],
        },
        {
          'active_participants': [
            {'id': 42},
            {'id': -2},
          ],
        },
      ]) {
        expect(
          const VoiceAgentPermission(
            -2,
          ).allows(VoiceRoom.fromJson({...eligible, ...changes})),
          isFalse,
          reason: '$changes',
        );
      }
    });
  });

  test(
    'catalogue ignores malformed names and preserves distinct dispatch order',
    () {
      expect(
        readVoiceAgentNames({
          'agents': [
            null,
            12,
            {'name': false},
            {'name': ' '},
            {'name': ' assistant '},
            {'name': 'assistant'},
            {'name': 'support'},
            {'name': 'x' * 257},
          ],
        }),
        ['assistant', 'support'],
      );
      for (final value in [null, 12, <String, Object?>{}, 'agents']) {
        expect(readVoiceAgentNames({'agents': value}), isEmpty);
      }
    },
  );

  test(
    'names are required and limited to 256 Unicode characters after trimming',
    () {
      expect(validateVoiceAgentName(' \n '), 'Enter an agent name.');
      expect(validateVoiceAgentName('x' * 257), 'Use 256 characters or fewer.');
      expect(validateVoiceAgentName(' ${'😀' * 256} '), isNull);
    },
  );

  test('newest catalogue refresh wins over an older response', () async {
    final first = Completer<List<String>>();
    final second = Completer<List<String>>();
    var reads = 0;
    final refreshes = <bool>[];
    final state = VoiceAgentInvitation(
      isCurrent: () => true,
      load: (refresh) {
        refreshes.add(refresh);
        return ++reads == 1 ? first.future : second.future;
      },
      invite: (_) async => true,
    );
    addTearDown(state.dispose);
    final a = state.refresh(force: false);
    final b = state.refresh();
    second.complete(['support']);
    await b;
    first.complete(['stale']);
    await a;
    expect(state.names, ['support']);
    expect(refreshes, [false, true]);
    expect(state.loading, isFalse);
  });

  test(
    'failed catalogue supports manual submission and duplicate suppression',
    () async {
      final gate = Completer<bool>();
      final names = <String>[];
      var fail = true;
      final state = VoiceAgentInvitation(
        isCurrent: () => true,
        load: (_) async {
          if (fail) throw StateError('unavailable');
          return ['assistant'];
        },
        invite: (name) {
          names.add(name);
          return gate.future;
        },
      );
      addTearDown(state.dispose);
      await state.refresh();
      expect(state.catalogueError, contains('type a name'));
      expect(state.names, isEmpty);
      await state.submit(' ');
      expect(state.error, 'Enter an agent name.');
      expect(names, isEmpty);
      final sending = state.submit(' custom ');
      await state.submit('duplicate');
      expect(state.sending, isTrue);
      gate.complete(true);
      await sending;
      await state.submit('duplicate');
      expect(names, ['custom']);
      expect(state.sent, isTrue);
      expect(state.error, isNull);
      fail = false;
    },
  );

  test(
    'failed invitation can be retried without retaining the error',
    () async {
      var fail = true;
      final state = VoiceAgentInvitation(
        isCurrent: () => true,
        load: (_) async => [],
        invite: (_) async {
          if (fail) throw StateError('failed');
          return true;
        },
      );
      addTearDown(state.dispose);
      await state.submit('assistant');
      expect(state.error, contains("Couldn't invite"));
      expect(state.sending, isFalse);
      fail = false;
      await state.submit('assistant');
      expect(state.sent, isTrue);
      expect(state.error, isNull);
    },
  );

  for (final operation in ['catalogue', 'invitation']) {
    test('retired owner ignores late $operation success and failure', () async {
      for (final fail in [false, true]) {
        var current = true;
        final gate = Completer<void>();
        final state = VoiceAgentInvitation(
          isCurrent: () => current,
          load: (_) async {
            await gate.future;
            return ['stale'];
          },
          invite: (_) async {
            await gate.future;
            return true;
          },
        );
        final pending = operation == 'catalogue'
            ? state.refresh()
            : state.submit('assistant');
        current = false;
        if (fail) {
          gate.completeError(StateError('late'));
        } else {
          gate.complete();
        }
        await pending;
        expect(state.names, isEmpty);
        expect(state.sent, isFalse);
        expect(state.error, isNull);
        expect(state.catalogueError, isNull);
        state.dispose();
      }
    });
  }
}
