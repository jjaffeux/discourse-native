import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_directory.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/event_fixtures.dart';

void main() {
  const read =
      'GET /discourse-post-event/events.json?include_details=true&include_ongoing=true&order=asc&limit=200&search';
  late EventTestPorts ports;
  late Map<String, dynamic> current;
  setUp(() {
    ports = EventTestPorts();
    current = eventJson();
    ports.transport.responders[read] = (request) => {
      'events': [current],
    };
  });
  tearDown(() => ports.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventDirectory(
            site: eventSite,
            mine: false,
            controller: ports.controller,
            navigation: EventNavigation(
              host: _Routes(),
              editor: PluginPostEditorHost(open: (_, _, {focusText}) => false),
              controller: ports.controller,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'directory repaints reader dates and refreshes on resume without mounted post cards',
    (tester) async {
      ports.user = null;
      await pump(tester);
      expect(find.textContaining('21:00'), findsOneWidget);
      ports.environment.setDeviceTimezone('Europe/Paris');
      await tester.pumpAndSettle();
      expect(find.textContaining('23:00'), findsOneWidget);
      ports.controller.setForeground(false);
      current = eventJson(overrides: {'name': 'Updated while away'});
      ports.controller.setForeground(true);
      await tester.pumpAndSettle();
      expect(find.text('Updated while away'), findsOneWidget);
      expect(find.text('Engineering Managers Call'), findsNothing);
    },
  );

  testWidgets(
    'account refresh clears old directory data and drops a superseded response',
    (tester) async {
      await pump(tester);
      final stale = Completer<Map<String, dynamic>>();
      ports.transport.responders[read] = (_) => stale.future;
      await tester.tap(find.text('Refresh'));
      await tester.pump();
      final next = Completer<Map<String, dynamic>>();
      ports.transport.responders[read] = (_) => next.future;
      ports.controller.pluginCurrentUserRefreshed(eventSite);
      await tester.pump();
      expect(find.text('Engineering Managers Call'), findsNothing);
      next.complete({
        'events': [
          eventJson(overrides: {'name': 'Current account event'}),
        ],
      });
      await tester.pumpAndSettle();
      stale.complete({
        'events': [current],
      });
      await tester.pumpAndSettle();
      expect(find.text('Current account event'), findsOneWidget);
      expect(find.text('Engineering Managers Call'), findsNothing);
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
