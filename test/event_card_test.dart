import 'package:discourse_native/src/plugins/discourse_events/event_card.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

import 'support/event_fixtures.dart';

void main() {
  late EventTestPorts ports;
  setUp(() => ports = EventTestPorts());
  tearDown(() => ports.close());

  Future<void> pump(
    WidgetTester tester,
    PostEvent event, {
    void Function(String, bool)? respond,
    EventSettings settings = const EventSettings(),
    VoidCallback? participants,
    VoidCallback? connect,
    bool pending = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: EventCard(
            event: event,
            siteUrl: eventSite,
            zones: ports.zones,
            accountTimezone: 'Europe/Paris',
            onRespond: respond,
            settings: settings,
            onParticipants: participants,
            onConnect: connect,
            pending: pending,
          ),
        ),
      ),
    ),
  );

  for (final (username, initial) in [
    ('sam', 'S'),
    ('𐐨ser', '𐐀'),
    ('मित्र', 'मि'),
  ]) {
    testWidgets(
      'creator and invitee avatar initials keep the first grapheme of $username',
      (tester) async {
        final user = {'id': 1, 'username': username, 'name': 'Event creator'};
        await pump(
          tester,
          PostEvent.decode(
            eventJson(
              overrides: {
                'creator': user,
                'sample_invitees': [
                  {'user': user},
                ],
              },
            ),
          )!,
        );

        expect(tester.takeException(), isNull);
        final avatars = find.byTooltip(username);
        expect(avatars, findsNWidgets(2));
        expect(
          find.descendant(of: avatars, matching: find.text(initial)),
          findsNWidgets(2),
        );
        expect(find.text('Event creator'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'private recurring card matches the key screenshot features at narrow and wide widths',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      for (final width in [320.0, 1100.0]) {
        tester.view.physicalSize = Size(width, 1100);
        await pump(
          tester,
          PostEvent.decode(eventJson())!,
          respond: (_, _) {},
          participants: () {},
        );
        await tester.pumpAndSettle();
        expect(find.text('Engineering Managers Call'), findsOneWidget);
        expect(find.text('Private'), findsOneWidget);
        expect(find.text('Sam'), findsOneWidget);
        expect(find.text('Every week'), findsOneWidget);
        expect(find.textContaining('(Europe/Paris)'), findsOneWidget);
        expect(find.text('9 going'), findsOneWidget);
        expect(find.text('Going ▾'), findsOneWidget);
        expect(find.text('Interested'), findsOneWidget);
        expect(find.text('Not going'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'recurring choice and interested emit explicit recurrence values',
    (tester) async {
      final responses = <(String, bool)>[];
      await pump(
        tester,
        PostEvent.decode(eventJson())!,
        respond: (status, recurring) => responses.add((status, recurring)),
      );
      await tester.tap(find.byTooltip('Choose recurring attendance'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          CheckedPopupMenuItem<VoidCallback>,
          'Every occurrence',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Choose recurring attendance'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          CheckedPopupMenuItem<VoidCallback>,
          'This occurrence only',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Interested'));
      await tester.pumpAndSettle();
      expect(responses, [
        ('going', true),
        ('going', false),
        ('interested', false),
      ]);
    },
  );

  testWidgets(
    'private roster omission and minimal setting conceal attendance details',
    (tester) async {
      await pump(
        tester,
        PostEvent.decode(
          eventJson(overrides: {'should_display_invitees': false}),
        )!,
        respond: (_, _) {},
      );
      expect(find.text('9 going'), findsNothing);
      expect(find.byTooltip('lee'), findsNothing);
      await pump(
        tester,
        PostEvent.decode(eventJson(overrides: {'minimal': true}))!,
        respond: (_, _) {},
      );
      expect(find.text('Going ▾'), findsNothing);
      expect(find.text('Not going'), findsNothing);
      expect(find.text('Interested'), findsOneWidget);
      expect(find.byTooltip('lee'), findsNothing);
    },
  );

  testWidgets(
    'capacity disables new going but keeps interested; pending prevents changes',
    (tester) async {
      final responses = <String>[];
      final event = PostEvent.decode(
        eventJson(overrides: {'at_capacity': true}),
      )!;
      await pump(tester, event, respond: (status, _) => responses.add(status));
      expect(
        tester
            .widget<PopupMenuButton<VoidCallback>>(
              find.byType(PopupMenuButton<VoidCallback>),
            )
            .enabled,
        isFalse,
      );
      await tester.pumpAndSettle();
      expect(find.text('Every occurrence'), findsNothing);
      await tester.tap(find.text('Interested'));
      expect(responses, ['interested']);
      await pump(
        tester,
        event,
        respond: (status, _) => responses.add(status),
        pending: true,
      );
      await tester.tap(find.text('Interested'));
      expect(responses, ['interested']);
    },
  );

  testWidgets(
    'organizer without attendance permission gets no RSVP and connection stays a host action',
    (tester) async {
      var connections = 0;
      final event = PostEvent.decode(
        eventJson(overrides: {'can_update_attendance': false}),
      )!;
      await pump(
        tester,
        event,
        respond: (_, _) {},
        connect: () => connections++,
      );
      expect(find.text('Going ▾'), findsNothing);
      await tester.tap(find.text('Connect to respond'));
      expect(connections, 1);
    },
  );

  testWidgets('cooked fallback remains readable without hydration or actions', (
    tester,
  ) async {
    final element = html
        .parseFragment(
          '<div class="discourse-post-event" data-name="Planning" data-start="2026-09-08">Read the agenda.</div>',
        )
        .children
        .single;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EventCookedFallback(element: element)),
      ),
    );
    expect(find.text('Planning'), findsOneWidget);
    expect(find.text('Read the agenda.'), findsOneWidget);
    expect(find.text('Going'), findsNothing);
    expect(ports.transport.requests, isEmpty);
  });
}
