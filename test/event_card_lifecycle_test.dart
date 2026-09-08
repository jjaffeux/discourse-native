import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_card.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/event_fixtures.dart';

void main() {
  const read = 'GET /discourse-post-event/events/42.json';
  const channel = '/discourse-post-event/700';
  late EventTestPorts ports;
  late Map<String, dynamic> current;
  late EventNavigation navigation;

  setUp(() {
    ports = EventTestPorts();
    current = eventJson(overrides: {'watching_invitee': watching()});
    ports.transport.responders[read] = (_) => {'event': current};
    navigation = EventNavigation(
      host: _Routes(),
      editor: PluginPostEditorHost(open: (_, _, {focusText}) => false),
      controller: ports.controller,
    );
  });
  tearDown(() => ports.close());

  Future<void> pumpCard(
    WidgetTester tester,
    PostEvent seed, {
    String site = eventSite,
    EventTestPorts? owner,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PostEventCard(
            site: site,
            event: seed,
            controller: (owner ?? ports).controller,
            navigation: navigation,
          ),
        ),
      ),
    ),
  );

  void forget() {
    ports.requests.forget(eventSite);
    ports.requests.apiKeys[eventSite] = 'replacement-key';
    ports.controller.forget(eventSite);
  }

  Finder attendanceMenu(bool withdraw) => find.descendant(
    of: find.byTooltip(
      withdraw ? 'Event actions' : 'Choose recurring attendance',
    ),
    matching: find.byWidgetPredicate(
      (widget) => widget is PopupMenuButton<Object?>,
    ),
  );

  Finder attendanceChoice(bool withdraw) => find.ancestor(
    of: find.text(withdraw ? 'Remove my response' : 'Every occurrence'),
    matching: find.byWidgetPredicate(
      (widget) => widget is PopupMenuItem<Object?>,
    ),
  );

  for (final replacement in [
    'event',
    'site',
    'controller',
    'account',
    'reconnect',
  ]) {
    for (final withdraw in [false, true]) {
      testWidgets(
        '${withdraw ? 'withdrawal' : 'recurring RSVP'} menu opened before $replacement replacement cannot change either owner',
        (tester) async {
          current = eventJson(
            overrides: {
              'is_public': true,
              'is_private': false,
              'watching_invitee': watching(),
            },
          );
          final seed = PostEvent.decode(current)!;
          await pumpCard(tester, seed);
          await tester.pumpAndSettle();
          final cardState = tester.state(find.byType(PostEventCard));
          final peer = ports.controller.acquire(eventSite, seed);
          addTearDown(peer.dispose);
          final menu = attendanceMenu(withdraw);
          final menuState = tester.state(menu);
          final choiceItem = attendanceChoice(withdraw);
          await tester.tap(menu);
          await tester.pumpAndSettle();
          expect(choiceItem, findsOneWidget);

          final nextPorts = replacement == 'controller'
              ? EventTestPorts()
              : ports;
          if (nextPorts != ports) addTearDown(nextPorts.close);
          final nextSite = replacement == 'site'
              ? 'https://other.example'
              : eventSite;
          final nextId = replacement == 'event' ? 43 : 42;
          final nextTopic = replacement == 'event' ? 701 : 700;
          final nextJson = {
            ...current,
            'id': nextId,
            'name': 'Replacement event',
            'watching_invitee': {...watching(), 'id': 84},
            'post': {
              'id': nextId,
              'topic': {'id': nextTopic, 'title': 'Replacement topic'},
            },
          };
          nextPorts
                  .transport
                  .responders['GET /discourse-post-event/events/$nextId.json'] =
              (_) => {'event': nextJson};
          if (replacement == 'account') {
            ports.requests.forget(eventSite);
            ports.requests.apiKeys[eventSite] = 'replacement-key';
            ports.controller.pluginCurrentUserRefreshed(eventSite);
          } else if (replacement == 'reconnect') {
            forget();
          }
          final nextSeed = PostEvent.decode(nextJson)!;
          final nextPeer = nextPorts.controller.acquire(nextSite, nextSeed);
          addTearDown(nextPeer.dispose);
          await nextPeer.refresh();
          await pumpCard(tester, nextSeed, site: nextSite, owner: nextPorts);
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(PostEventCard)), same(cardState));
          expect(tester.state(menu), same(menuState));
          expect(find.text('Replacement event'), findsOneWidget);

          await tester.tap(choiceItem);
          await tester.pumpAndSettle();
          expect(ports.transport.writes, isEmpty);
          expect(nextPorts.transport.writes, isEmpty);
          expect(nextPeer.authoritative, isTrue);

          final method = withdraw ? 'DELETE' : 'PUT';
          final path = '/discourse-post-event/events/$nextId/invitees/84.json';
          nextPorts.transport.responses['$method $path'] = {};
          await tester.tap(menu);
          await tester.pumpAndSettle();
          await tester.tap(choiceItem);
          await tester.pumpAndSettle();
          final request = nextPorts.transport.writes.single;
          expect(
            (request.method, request.siteUrl, request.path),
            (method, nextSite, path),
          );
          expect(request.apiKey, nextPorts.requests.apiKeys[nextSite]);
          expect(
            request.body,
            withdraw
                ? <String, Object?>{}
                : {
                    'invitee': {'status': 'going', 'recurring': true},
                  },
          );
          expect(nextPorts.posts.lanes, isEmpty);

          await tester.pumpWidget(const SizedBox.shrink());
          peer.dispose();
          expect(
            nextPorts.channels.subscriberCount(
              '/discourse-post-event/$nextTopic',
            ),
            1,
          );
          nextPeer.dispose();
          expect(ports.channels.channels, isEmpty);
          expect(nextPorts.channels.channels, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final withdraw in [false, true]) {
    testWidgets(
      '${withdraw ? 'withdrawal' : 'recurring RSVP'} remains valid through a live update and an ordinary card rebuild',
      (tester) async {
        current = eventJson(
          overrides: {
            'is_public': true,
            'is_private': false,
            'watching_invitee': watching(),
          },
        );
        final seed = PostEvent.decode(current)!;
        await pumpCard(tester, seed);
        await tester.pumpAndSettle();
        final peer = ports.controller.acquire(eventSite, seed);
        addTearDown(peer.dispose);
        await tester.tap(attendanceMenu(withdraw));
        await tester.pumpAndSettle();

        current = {...current, 'name': 'Live update'};
        ports.channels.deliver(channel, {'id': 42});
        await peer.refresh();
        await pumpCard(tester, PostEvent.decode(current)!);
        await tester.pumpAndSettle();
        expect(find.text('Live update'), findsOneWidget);
        final method = withdraw ? 'DELETE' : 'PUT';
        const path = '/discourse-post-event/events/42/invitees/83.json';
        ports.transport.responders['$method $path'] = (_) {
          current = {
            ...current,
            'watching_invitee': withdraw ? null : watching(recurring: true),
          };
          return {};
        };

        await tester.tap(attendanceChoice(withdraw));
        await tester.pumpAndSettle();

        final request = ports.transport.writes.single;
        expect(
          (request.method, request.path, request.apiKey),
          (method, path, 'key'),
        );
        expect(
          request.body,
          withdraw
              ? <String, Object?>{}
              : {
                  'invitee': {'status': 'going', 'recurring': true},
                },
        );
        expect(peer.event!.watching?.recurring, withdraw ? null : true);
        expect(peer.error, isNull);
        expect(ports.posts.lanes, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(ports.channels.subscriberCount(channel), 1);
        peer.dispose();
        expect(ports.channels.channels, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a retained card recovers from forget only with a fresh snapshot and shares its new entry',
    (tester) async {
      final seed = PostEvent.decode(current)!;
      await pumpCard(tester, seed);
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(PostEventCard));
      final oldCard = tester.widget<EventCard>(find.byType(EventCard));
      expect(find.text('9 going'), findsOneWidget);
      expect(ports.channels.subscriberCount(channel), 1);

      forget();
      await tester.pumpAndSettle();
      final readsBeforeRecovery = ports.transport.reads.length;
      expect(find.byType(EventUnavailableCard), findsOneWidget);
      expect(find.text('9 going'), findsNothing);
      expect(ports.channels.channels, isEmpty);

      await tester.tap(find.text('Refresh event'));
      await pumpCard(tester, seed);
      await tester.pumpAndSettle();
      expect(ports.transport.reads, hasLength(readsBeforeRecovery));
      expect(find.byType(EventUnavailableCard), findsOneWidget);

      // A newly decoded post snapshot can compare equal across accounts.
      final freshSeed = PostEvent.decode(current)!;
      expect(freshSeed, seed);
      expect(freshSeed, isNot(same(seed)));
      final hydration = Completer<Map<String, dynamic>>();
      ports.transport.responders[read] = (_) => hydration.future;
      await pumpCard(tester, freshSeed);
      await tester.pump();
      expect(tester.state(find.byType(PostEventCard)), same(state));
      expect(ports.transport.reads, hasLength(readsBeforeRecovery + 1));
      expect(ports.transport.reads.last.apiKey, 'replacement-key');
      expect(find.byType(EventUnavailableCard), findsOneWidget);
      expect(find.text('9 going'), findsNothing);
      expect(find.byTooltip('lee'), findsNothing);
      expect(ports.channels.subscriberCount(channel), 1);

      final peer = ports.controller.acquire(eventSite, freshSeed);
      addTearDown(peer.dispose);
      current = eventJson(
        overrides: {
          'name': 'Current account event',
          'watching_invitee': null,
          'should_display_invitees': false,
          'sample_invitees': null,
          'stats': null,
        },
      );
      hydration.complete({'event': current});
      await tester.pumpAndSettle();
      final card = tester.widget<EventCard>(find.byType(EventCard));
      expect(card.event, same(peer.event));
      expect(card.onRespond, isNotNull);
      expect(peer.authoritative, isTrue);
      expect(peer.event!.watching, isNull);
      expect(find.text('Current account event'), findsOneWidget);
      expect(find.text('9 going'), findsNothing);
      expect(ports.transport.reads, hasLength(readsBeforeRecovery + 1));

      // A menu callback captured before reset still belongs to the old account.
      oldCard.onRespond!('going', false);
      oldCard.onRetry!();
      await tester.pumpAndSettle();
      expect(ports.transport.writes, isEmpty);
      expect(ports.transport.reads, hasLength(readsBeforeRecovery + 1));

      // An ordinary rebuild keeps the shared owner and does not rehydrate.
      await pumpCard(tester, PostEvent.decode(freshSeed.fields)!);
      await tester.pumpAndSettle();
      expect(ports.transport.reads, hasLength(readsBeforeRecovery + 1));
      expect(ports.channels.subscriberCount(channel), 1);

      ports.transport.responders[read] = (_) => {'event': current};
      current = eventJson(overrides: {'name': 'Live update after recovery'});
      ports.channels.deliver(channel, {'id': 42});
      await tester.pumpAndSettle();
      expect(find.text('Live update after recovery'), findsOneWidget);
      expect(peer.event!.title, 'Live update after recovery');

      await tester.pumpWidget(const SizedBox.shrink());
      expect(ports.channels.subscriberCount(channel), 1);
      peer.dispose();
      peer.dispose();
      expect(ports.channels.channels, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recovery hides an unhydrated seed even when another card acquired the new entry first',
    (tester) async {
      await pumpCard(tester, PostEvent.decode(current)!);
      await tester.pumpAndSettle();
      forget();

      final freshSeed = PostEvent.decode(current)!;
      final hydration = Completer<Map<String, dynamic>>();
      ports.transport.responders[read] = (_) => hydration.future;
      final peer = ports.controller.acquire(eventSite, freshSeed);
      addTearDown(peer.dispose);
      await pumpCard(tester, freshSeed);
      await tester.pump();
      expect(find.byType(EventUnavailableCard), findsOneWidget);
      expect(find.text('9 going'), findsNothing);
      expect(peer.event, isNull);
      expect(ports.transport.reads, hasLength(2));
      expect(ports.channels.subscriberCount(channel), 1);

      hydration.complete({
        'event': eventJson(overrides: {'name': 'Current account event'}),
      });
      await tester.pumpAndSettle();
      expect(find.text('Current account event'), findsOneWidget);
      expect(
        tester.widget<EventCard>(find.byType(EventCard)).event,
        same(peer.event),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(ports.channels.subscriberCount(channel), 1);
      peer.dispose();
      expect(ports.channels.channels, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'participants opened before forget stay unavailable after their card recovers',
    (tester) async {
      final seed = PostEvent.decode(current)!;
      ports
              .transport
              .responders['GET /discourse-post-event/events/42/invitees.json?filter'] =
          (_) => {
            'invitees': [watching()],
          };
      await pumpCard(tester, seed);
      await tester.pumpAndSettle();
      tester.widget<EventCard>(find.byType(EventCard)).onParticipants!();
      await tester.pumpAndSettle();
      expect(find.text('@lee'), findsOneWidget);

      forget();
      await pumpCard(tester, PostEvent.decode(current)!);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EventCard>(find.byType(EventCard, skipOffstage: false))
            .onParticipants,
        isNotNull,
      );
      expect(find.text('@lee'), findsNothing);
      expect(
        find.text('Participant details are no longer available.'),
        findsOneWidget,
      );
      final reads = ports.transport.reads.length;
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(ports.transport.reads, hasLength(reads));
      expect(find.text('@lee'), findsNothing);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(ports.channels.subscriberCount(channel), 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(ports.channels.channels, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invitations opened before forget cannot send through a recovered card',
    (tester) async {
      await pumpCard(tester, PostEvent.decode(current)!);
      await tester.pumpAndSettle();
      tester.widget<EventCard>(find.byType(EventCard)).onInvite!();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sam');

      forget();
      await pumpCard(tester, PostEvent.decode(current)!);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EventCard>(find.byType(EventCard, skipOffstage: false))
            .onInvite,
        isNotNull,
      );
      await tester.tap(find.text('Send invitations'));
      await tester.pumpAndSettle();
      expect(find.text('You can no longer manage this event.'), findsOneWidget);
      expect(ports.transport.writes, isEmpty);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(ports.channels.subscriberCount(channel), 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(ports.channels.channels, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

final class _Routes implements PluginRouteNavigationHost {
  @override
  final sites = const [
    PluginRouteSite(url: eventSite, title: 'Forum', isConnected: true),
  ];
  @override
  PluginRouteSite get currentSite => sites.single;
  @override
  ContentRoute? currentContent;
  @override
  void selectInstance(int index) {}
  @override
  void pushContent(ContentRoute route) => currentContent = route;
  @override
  void replaceCurrentContent(ContentRoute route) => currentContent = route;
  @override
  void openTopicPost({
    required String siteUrl,
    required int topicId,
    required int postNumber,
    bool highlight = false,
  }) {}
}
