import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_controller.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_participant_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/event_fixtures.dart';

void main() {
  late EventTestPorts ports;
  late Map<String, dynamic> current;
  late EventHandle handle;
  const read = 'GET /discourse-post-event/events/42.json';
  const roster = 'GET /discourse-post-event/events/42/invitees.json?filter';

  setUp(() async {
    ports = EventTestPorts();
    current = eventJson();
    ports.transport.responders[read] = (_) => {'event': current};
    handle = ports.controller.acquire(eventSite, PostEvent.decode(current)!);
    await handle.refresh();
    ports.transport.responders[roster] = (_) => {
      'invitees': [watching()],
    };
  });
  tearDown(() {
    handle.dispose();
    ports.close();
  });

  testWidgets('query changes reject old results throughout debounce', (
    tester,
  ) async {
    final first = Completer<Map<String, dynamic>>();
    ports.transport.responders[roster] = (_) => first.future;
    final session = EventParticipantSession(handle);
    addTearDown(session.dispose);
    await tester.pump();
    var filteredReads = 0;
    ports.transport.responders['$roster=sam'] = (_) {
      filteredReads++;
      return {
        'invitees': [watching()],
      };
    };
    session.changeSearch(' @sam ');
    first.complete({
      'invitees': [watching()],
    });
    await tester.pump();
    expect(session.rows, isNull);
    expect(session.loading, isTrue);
    await tester.pump(const Duration(milliseconds: 249));
    expect(filteredReads, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(filteredReads, 1);
    expect(session.rows!.single.user.username, 'lee');
  });

  testWidgets('type changes capture the latest query and reject stale errors', (
    tester,
  ) async {
    final old = Completer<Map<String, dynamic>>();
    ports.transport.responders[roster] = (_) => old.future;
    final session = EventParticipantSession(handle);
    addTearDown(session.dispose);
    await tester.pump();
    ports.transport.responders['$roster=sam&type=going'] = (_) => {
      'invitees': [watching(status: 'going')],
    };
    session.changeSearch('sam');
    session.selectType('going');
    await tester.pump();
    expect(session.rows!.single.status, 'going');
    old.completeError(const WriteException(WriteFailure.unreachable));
    await tester.pump(const Duration(milliseconds: 250));
    expect(session.error, isNull);
    expect(session.rows!.single.status, 'going');
  });

  testWidgets(
    'withdrawal cancels debounce and recovery reloads the latest query',
    (tester) async {
      final session = EventParticipantSession(handle);
      addTearDown(session.dispose);
      await tester.pump();
      expect(session.rows, isNotEmpty);
      var filteredReads = 0;
      ports.transport.responders['$roster=sam&type=going'] = (_) {
        filteredReads++;
        return {
          'invitees': [watching()],
        };
      };
      session.selectType('going');
      session.changeSearch('sam');
      current = eventJson(overrides: {'should_display_invitees': false});
      await handle.refresh();
      await tester.pump(const Duration(milliseconds: 250));
      expect(session.available, isFalse);
      expect(session.rows, isNull);
      expect(session.loading, isFalse);
      expect(filteredReads, 0);
      current = eventJson();
      await handle.refresh();
      await tester.pump();
      expect(session.available, isTrue);
      expect(session.rows, isNotEmpty);
      expect(filteredReads, 1);
    },
  );

  testWidgets('account recovery rejects the preceding in-flight roster', (
    tester,
  ) async {
    final old = Completer<Map<String, dynamic>>();
    ports.transport.responders[roster] = (_) => old.future;
    final session = EventParticipantSession(handle);
    addTearDown(session.dispose);
    await tester.pump();
    final reread = Completer<Map<String, dynamic>>();
    ports.transport.responders[read] = (_) => reread.future;
    ports.controller.pluginCurrentUserRefreshed(eventSite);
    expect(session.rows, isNull);
    expect(session.available, isFalse);
    ports.transport.responders[roster] = (_) => {'invitees': <Object>[]};
    reread.complete({'event': current});
    await tester.pump();
    old.complete({
      'invitees': [watching()],
    });
    await tester.pump();
    expect(session.rows, isEmpty);
    expect(session.error, isNull);
  });

  testWidgets('failed reads can retry and clear the error', (tester) async {
    ports.transport.responders[roster] = (_) => throw const WriteException(
      WriteFailure.validation,
      errors: ['Roster unavailable.'],
    );
    final session = EventParticipantSession(handle);
    addTearDown(session.dispose);
    await tester.pump();
    expect(session.error, 'Roster unavailable.');
    ports.transport.responders[roster] = (_) => {
      'invitees': [watching()],
    };
    await session.refresh();
    expect(session.error, isNull);
    expect(session.rows, isNotEmpty);
  });

  testWidgets('disposal cancels timers and ignores delayed settlement', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    ports.transport.responders[roster] = (_) => pending.future;
    final session = EventParticipantSession(handle);
    await tester.pump();
    var notices = 0;
    session.addListener(() => notices++);
    session.changeSearch('sam');
    expect(notices, 1);
    session.dispose();
    pending.complete({
      'invitees': [watching()],
    });
    await tester.pump(const Duration(milliseconds: 250));
    expect(notices, 1);
    expect(session.rows, isNull);
  });

  testWidgets('reentrant query changes supersede request admission', (
    tester,
  ) async {
    final session = EventParticipantSession(handle);
    addTearDown(session.dispose);
    await tester.pump();
    var oldReads = 0;
    ports.transport.responders[roster] = (_) {
      oldReads++;
      return {
        'invitees': [watching()],
      };
    };
    ports.transport.responders['$roster&type=going'] = (_) => {
      'invitees': [watching()],
    };
    var changed = false;
    session.addListener(() {
      if (changed) return;
      changed = true;
      session.selectType('going');
    });
    await session.refresh();
    await tester.pump();
    expect(oldReads, 0);
    expect(session.type, 'going');
    expect(session.rows, isNotEmpty);
  });

  testWidgets('replacement handles have independent request lifetimes', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    ports.transport.responders[roster] = (_) => pending.future;
    final old = EventParticipantSession(handle);
    await tester.pump();
    old.dispose();
    final replacementEvent = eventJson(
      overrides: {
        'id': 43,
        'post': {
          'id': 43,
          'topic': {'id': 700},
        },
      },
    );
    ports.transport.responders['GET /discourse-post-event/events/43.json'] =
        (_) => {'event': replacementEvent};
    ports
            .transport
            .responders['GET /discourse-post-event/events/43/invitees.json?filter'] =
        (_) => {'invitees': <Object>[]};
    final replacementHandle = ports.controller.acquire(
      eventSite,
      PostEvent.decode(replacementEvent)!,
    );
    addTearDown(replacementHandle.dispose);
    await replacementHandle.refresh();
    final replacement = EventParticipantSession(replacementHandle);
    addTearDown(replacement.dispose);
    await tester.pump();
    pending.complete({
      'invitees': [watching()],
    });
    await tester.pump();
    expect(replacement.rows, isEmpty);
    expect(old.rows, isNull);
  });
}
