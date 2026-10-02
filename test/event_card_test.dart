import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_card.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_navigation.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/event_fixtures.dart';
import 'support/fakes.dart';
import 'support/media_pipeline.dart';

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

  for (final linked in [false, true]) {
    testWidgets(
      'renders event title emoji with wrapping and semantics (linked: $linked)',
      (tester) async {
        installTestMediaPipeline(
          client: MockClient((_) async => http.Response('', 404)),
        );
        final controller = ShellController(
          instanceStore: FakeInstanceStore([instance('forum.example')]),
          api: FakeDiscourseApi(
            emojisBySite: {
              eventSite: const [
                SiteEmoji(
                  name: 'pool_8_ball',
                  url: '/images/emoji/pool_8_ball.png',
                ),
                SiteEmoji(name: 'partyparrot', url: '/uploads/parrot.png'),
              ],
            },
          ),
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(controller.dispose);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.view.devicePixelRatio = 1;
        const title =
            'Billiards :pool_8_ball: tournament/game – 2026 (Wednesday) '
            ':partyparrot: :unknown_event_emoji:';
        var opened = 0;

        for (final width in [320.0, 1100.0]) {
          tester.view.physicalSize = Size(width, 1100);
          await tester.pumpWidget(
            ShellScope(
              controller: controller,
              child: MaterialApp(
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: EventCard(
                      event: PostEvent.decode(
                        eventJson(overrides: {'name': title}),
                      )!,
                      siteUrl: eventSite,
                      zones: ports.zones,
                      onOpen: linked ? () => opened++ : null,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            tester
                .widgetList<SiteEmojiImage>(find.byType(SiteEmojiImage))
                .map((emoji) => (emoji.name, emoji.siteUrl)),
            [('pool_8_ball', eventSite), ('partyparrot', eventSite)],
          );
          final titleLabel = find.bySemanticsLabel(
            RegExp(RegExp.escape(title)),
          );
          expect(titleLabel, findsOneWidget);
          expect(
            find.textContaining(':unknown_event_emoji:', findRichText: true),
            findsOneWidget,
          );
          if (linked) {
            await tester.tap(titleLabel);
            expect(opened, width == 320 ? 1 : 2);
          }
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('malformed creator and invitee avatars keep the event usable', (
    tester,
  ) async {
    installTestMediaPipeline(
      client: MockClient((_) async => http.Response('', 404)),
    );
    await pump(
      tester,
      PostEvent.decode(
        eventJson(
          overrides: {
            'creator': {
              'id': 1,
              'username': 'sam',
              'name': 'Sam',
              'avatar_template': 'https://[broken',
            },
            'sample_invitees': [
              {
                'user': {
                  'id': 2,
                  'username': 'lee',
                  'avatar_template': '//[broken',
                },
              },
            ],
          },
        ),
      )!,
      respond: (_, _) {},
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Engineering Managers Call'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    expect(
      find.descendant(of: find.byTooltip('sam'), matching: find.text('S')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byTooltip('lee'), matching: find.text('L')),
      findsOneWidget,
    );
    expect(find.text('Going'), findsOneWidget);
  });

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
        expect(find.text('Going'), findsOneWidget);
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
        find.widgetWithText(DDropdownMenuCheckboxItem, 'Every occurrence'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Choose recurring attendance'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(DDropdownMenuCheckboxItem, 'This occurrence only'),
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
      expect(find.text('Going'), findsNothing);
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
        tester.widget<DButton>(find.widgetWithText(DButton, 'Going')).onPressed,
        isNull,
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
      expect(find.text('Going'), findsNothing);
      await tester.tap(find.text('Connect to respond'));
      expect(connections, 1);
    },
  );

  for (final state in [null, 'is_closed', 'is_expired']) {
    testWidgets(
      'an organizer can export and invite ${state == null ? 'on an open event' : 'nowhere once $state'}',
      (tester) async {
        final current = eventJson(overrides: {?state: true});
        ports.transport.responders['GET /discourse-post-event/events/42.json'] =
            (_) => {'event': current};
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PostEventCard(
                  site: eventSite,
                  event: PostEvent.decode(current)!,
                  controller: ports.controller,
                  navigation: EventNavigation(
                    host: _Routes(),
                    editor: PluginPostEditorHost(
                      open: (_, _, {focusText}) => false,
                    ),
                    controller: ports.controller,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Event actions'));
        await tester.pumpAndSettle();
        expect(find.text('Edit event'), findsOneWidget);
        final offered = state == null ? findsOneWidget : findsNothing;
        expect(find.text('Export calendar'), offered);
        expect(find.text('Invite people'), offered);
      },
    );
  }

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
    expect(find.text('Read the agenda.', findRichText: true), findsOneWidget);
    expect(find.text('Going'), findsNothing);
    expect(ports.transport.requests, isEmpty);
  });
}

final class _Routes extends Fake implements PluginRouteNavigationHost {
  @override
  String? get activeTabId => null;
}
