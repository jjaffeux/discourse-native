import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_participants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/event_fixtures.dart';

void main() {
  late EventTestPorts ports;
  late Map<String, dynamic> current;
  setUp(() {
    ports = EventTestPorts();
    current = eventJson();
    ports.transport.responders['GET /discourse-post-event/events/42.json'] =
        (_) => {'event': current};
  });
  tearDown(() => ports.close());

  Future<void> pump(
    WidgetTester tester,
    Future<void> Function(BuildContext) show,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => show(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a malformed participant avatar keeps the roster usable', (
    tester,
  ) async {
    final handle = ports.controller.acquire(
      eventSite,
      PostEvent.decode(current)!,
    );
    addTearDown(handle.dispose);
    await handle.refresh();
    ports
            .transport
            .responders['GET /discourse-post-event/events/42/invitees.json?filter'] =
        (_) => {
          'invitees': [
            {
              ...watching(),
              'user': {
                'id': 2,
                'username': 'lee',
                'avatar_template': 'https://[broken',
              },
            },
            {
              'id': 84,
              'status': 'going',
              'user': {'id': 3, 'username': 'mia'},
            },
          ],
        };
    await pump(tester, (context) => showEventParticipants(context, handle));
    expect(tester.takeException(), isNull);
    expect(find.text('@lee'), findsOneWidget);
    expect(find.text('@mia'), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('@lee'), findsNothing);
  });

  testWidgets(
    'participant sheet clears a private roster and ignores a pending search when access changes',
    (tester) async {
      final handle = ports.controller.acquire(
        eventSite,
        PostEvent.decode(current)!,
      );
      addTearDown(handle.dispose);
      await handle.refresh();
      ports
              .transport
              .responders['GET /discourse-post-event/events/42/invitees.json?filter'] =
          (_) => {
            'invitees': [watching()],
          };
      await pump(tester, (context) => showEventParticipants(context, handle));
      expect(find.text('@lee'), findsOneWidget);
      final pending = Completer<Map<String, dynamic>>();
      ports
              .transport
              .responders['GET /discourse-post-event/events/42/invitees.json?filter=sam'] =
          (_) => pending.future;
      await tester.enterText(find.byType(TextField), 'sam');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      current = eventJson(
        overrides: {
          'should_display_invitees': false,
          'sample_invitees': null,
          'stats': null,
        },
      );
      await handle.refresh();
      await tester.pump();
      expect(find.text('@lee'), findsNothing);
      pending.complete({
        'invitees': [watching()],
      });
      await tester.pumpAndSettle();
      expect(find.text('@lee'), findsNothing);
      expect(
        find.text('Participant details are no longer available.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(ports.channels.subscriberCount('/discourse-post-event/700'), 1);
    },
  );

  testWidgets(
    'participant sheet reloads its roster when access returns after a failed re-read or account refresh',
    (tester) async {
      final handle = ports.controller.acquire(
        eventSite,
        PostEvent.decode(current)!,
      );
      addTearDown(handle.dispose);
      await handle.refresh();
      ports
              .transport
              .responders['GET /discourse-post-event/events/42/invitees.json?filter'] =
          (_) => {
            'invitees': [watching()],
          };
      await pump(tester, (context) => showEventParticipants(context, handle));
      expect(find.text('@lee'), findsOneWidget);
      bool searchEnabled() =>
          tester.widget<DInput>(find.byType(DInput)).enabled;
      bool tabsEnabled() =>
          tester.widget<DTabs<String>>(find.byType(DTabs<String>)).enabled;
      void expectWithdrawn() {
        expect(find.text('@lee'), findsNothing);
        expect(
          find.text('Participant details are no longer available.'),
          findsOneWidget,
        );
        expect(searchEnabled(), isFalse);
        expect(tabsEnabled(), isFalse);
      }

      void expectRestored() {
        expect(find.text('@lee'), findsOneWidget);
        expect(
          find.text('Participant details are no longer available.'),
          findsNothing,
        );
        expect(searchEnabled(), isTrue);
        expect(tabsEnabled(), isTrue);
      }

      const read = 'GET /discourse-post-event/events/42.json';
      final respond = ports.transport.responders[read]!;
      ports.transport.responders[read] = (_) =>
          throw const WriteException(WriteFailure.unreachable);
      await handle.refresh();
      await tester.pumpAndSettle();
      expectWithdrawn();
      ports.transport.responders[read] = respond;
      await handle.refresh();
      await tester.pumpAndSettle();
      expectRestored();

      final reread = Completer<Map<String, dynamic>>();
      ports.transport.responders[read] = (_) => reread.future;
      ports.controller.pluginCurrentUserRefreshed(eventSite);
      await tester.pump();
      expectWithdrawn();
      reread.complete({'event': current});
      await tester.pumpAndSettle();
      expectRestored();
    },
  );

  testWidgets(
    'organizer invitation errors stay visible and successful retry sends exact usernames',
    (tester) async {
      final handle = ports.controller.acquire(
        eventSite,
        PostEvent.decode(current)!,
      );
      addTearDown(handle.dispose);
      await handle.refresh();
      const invite = 'POST /discourse-post-event/events/42/invite';
      ports.transport.responders[invite] = (_) => throw const WriteException(
        WriteFailure.validation,
        errors: ['User not found.'],
      );
      await pump(tester, (context) => showEventInvitations(context, handle));
      await tester.enterText(find.byType(TextField), 'sam, lee, sam');
      await tester.tap(find.text('Send invitations'));
      await tester.pumpAndSettle();
      expect(find.text('User not found.'), findsOneWidget);
      expect(ports.transport.writes.single.body, {
        'invites': ['sam', 'lee'],
      });
      ports.transport.responders[invite] = (_) => <String, dynamic>{};
      await tester.tap(find.text('Send invitations'));
      await tester.pumpAndSettle();
      expect(find.text('Invite people'), findsNothing);
    },
  );

  testWidgets(
    'organizer invitations send usernames without their mention prefix',
    (tester) async {
      final handle = ports.controller.acquire(
        eventSite,
        PostEvent.decode(current)!,
      );
      addTearDown(handle.dispose);
      await handle.refresh();
      ports
          .transport
          .responders['POST /discourse-post-event/events/42/invite'] = (_) =>
          <String, dynamic>{};
      await pump(tester, (context) => showEventInvitations(context, handle));
      // The server matches usernames exactly and answers success for none.
      await tester.enterText(find.byType(TextField), '@sam, lee, @sam sam, @');
      await tester.tap(find.text('Send invitations'));
      await tester.pumpAndSettle();
      expect(ports.transport.writes.single.body, {
        'invites': ['sam', 'lee'],
      });
      expect(find.text('Invite people'), findsNothing);
    },
  );

  testWidgets('a busy owning post cannot silently dismiss unsent invitations', (
    tester,
  ) async {
    final handle = ports.controller.acquire(
      eventSite,
      PostEvent.decode(current)!,
    );
    addTearDown(handle.dispose);
    await handle.refresh();
    await pump(tester, (context) => showEventInvitations(context, handle));
    ports.posts.beginWrite(eventSite, 42);
    await tester.enterText(find.byType(TextField), 'sam');
    await tester.tap(find.text('Send invitations'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to send invitations.'), findsOneWidget);
    expect(find.text('Invite people'), findsOneWidget);
    expect(ports.transport.writes, isEmpty);
  });
}
