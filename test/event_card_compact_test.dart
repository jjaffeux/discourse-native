import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_card.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/event_fixtures.dart';

void main() {
  late EventTestPorts ports;
  setUp(() => ports = EventTestPorts());
  tearDown(() => ports.close());

  Future<void> pump(
    WidgetTester tester, {
    Map<String, Object?> fields = const {},
    double width = 680,
    double textScale = 1,
    TextDirection direction = TextDirection.ltr,
    void Function(String, bool)? respond,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
                child: Directionality(
                  textDirection: direction,
                  child: EventCard(
                    event: PostEvent.decode(eventJson(overrides: fields))!,
                    siteUrl: eventSite,
                    zones: ports.zones,
                    onRespond: respond,
                    onParticipants: () {},
                    onOpen: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('description disclosure preserves rich content and event state', (
    tester,
  ) async {
    const source =
        '<p>Read the agenda before joining.</p>'
        '<p>Bring your questions.</p>'
        '<p><a href="/t/agenda/1">Full agenda</a> and <strong>notes</strong>.</p>';
    final fields = <String, Object?>{'description_html': source};
    await pump(tester, fields: fields);
    await tester.pumpAndSettle();
    expect(find.text('Show full description'), findsOneWidget);
    expect(find.byType(CookedHtml), findsNothing);
    await tester.tap(find.text('Show full description'));
    await tester.pumpAndSettle();
    expect(tester.widget<CookedHtml>(find.byType(CookedHtml)).html, source);
    expect(
      find.textContaining('Full agenda', findRichText: true),
      findsWidgets,
    );

    // A server RSVP update must not collapse a description being read.
    await pump(
      tester,
      fields: {
        ...fields,
        'watching_invitee': watching(status: 'interested'),
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Show less'), findsOneWidget);
    await tester.tap(find.text('Show less'));
    await tester.pumpAndSettle();
    expect(find.byType(CookedHtml), findsNothing);

    // A different event starts collapsed, even at the same place in the tree.
    await tester.tap(find.text('Show full description'));
    await tester.pumpAndSettle();
    await pump(tester, fields: {...fields, 'id': 43, 'post': null});
    await tester.pumpAndSettle();
    expect(find.text('Show full description'), findsOneWidget);
  });

  testWidgets(
    'short rich descriptions stay directly available; absent fields omit',
    (tester) async {
      const source = '<p><a href="/t/agenda/1">Agenda</a></p>';
      await pump(tester, fields: {'description_html': source});
      await tester.pumpAndSettle();
      expect(tester.widget<CookedHtml>(find.byType(CookedHtml)).html, source);
      expect(find.text('Show full description'), findsNothing);
      await pump(tester, fields: {'url': null, 'description': null});
      await tester.pumpAndSettle();
      expect(find.byType(CookedHtml), findsNothing);
      expect(find.text('Show full description'), findsNothing);
      expect(find.text('Open event chat'), findsNothing);
    },
  );

  testWidgets('compact content reflows at 320px with large text and RTL', (
    tester,
  ) async {
    for (final direction in TextDirection.values) {
      await pump(
        tester,
        width: 320,
        textScale: 2,
        direction: direction,
        respond: (_, _) {},
        fields: {
          'description': 'First line\nSecond line\nThird line',
          'location': 'Community room on the ground floor',
          'channel': {'id': 1},
        },
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Open event chat'), findsOneWidget);
      await tester.ensureVisible(find.text('Show full description'));
      await tester.tap(find.text('Show full description'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Show less'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'RSVP selection comes from the event without a duplicate status line',
    (tester) async {
      final responses = <(String, bool)>[];
      final fields = <String, Object?>{
        'recurrence': null,
        'watching_invitee': watching(status: 'interested'),
      };
      await pump(
        tester,
        fields: fields,
        respond: (status, recurring) => responses.add((status, recurring)),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DToggle>(find.widgetWithText(DToggle, 'Interested'))
            .pressed,
        isTrue,
      );
      expect(find.textContaining('Your response:'), findsNothing);
      await tester.tap(find.text('Going'));
      expect(responses, [('going', false)]);
      await pump(
        tester,
        fields: {...fields, 'watching_invitee': watching()},
        respond: (_, _) {},
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<DToggle>(find.widgetWithText(DToggle, 'Going')).pressed,
        isTrue,
      );
      expect(
        tester
            .widget<DToggle>(find.widgetWithText(DToggle, 'Interested'))
            .pressed,
        isFalse,
      );
    },
  );
}
