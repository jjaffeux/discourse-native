import 'dart:async';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/discourse_events/discourse_events_module.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_directory.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _manifest = PluginManifest([discourseEventsModule]);
const _upcomingPath =
    '/discourse-post-event/events.json?include_details=true&include_ongoing=true&order=asc&limit=200&search&after=now';
const _minePath =
    '/discourse-post-event/events.json?include_details=true&include_ongoing=true&order=asc&limit=200&attending_user=lee&include_interested=true&search&after=now';

SiteConfig _config([Map<String, dynamic> overrides = const {}]) =>
    installedPlugins.models.siteConfig({
      'discourse_events_enabled': true,
      'discourse_post_event_enabled': true,
      'sidebar_show_upcoming_events': true,
      ...overrides,
    }, 'https://forum.example');

void main() {
  for (final (label, size, user) in [
    ('desktop account', desktop, const DiscourseUser(id: 2, username: 'lee')),
    ('anonymous phone', phone, null),
  ]) {
    testWidgets('$label opens native events from the main sidebar', (
      tester,
    ) async {
      final site = instance(
        'forum.example',
      ).copyWith(user: user, config: _config());
      final api = FakeDiscourseApi(
        user: user,
        siteConfigs: {site.url: site.config},
        pluginResponses: const {
          'GET $_upcomingPath': {'events': <Object?>[]},
          'GET $_minePath': {'events': <Object?>[]},
        },
      );
      await pumpShell(
        tester,
        size,
        instances: [site],
        api: api,
        pluginManifest: _manifest,
      );
      final controller = ShellScope.read(
        tester.element(find.byType(InstanceSidebar)),
      );
      final upcoming = sidebarDestination('Upcoming events');
      expect(upcoming, findsOneWidget);
      expect(sidebarDestination('My events'), findsNothing);
      expect(
        tester.getTopLeft(upcoming).dy,
        lessThan(tester.getTopLeft(sidebarDestination('More')).dy),
      );

      await tester.tap(upcoming);
      await tester.pumpAndSettle();

      expect(controller.currentContent?.id, 'events-upcoming');
      expect(controller.destinationId, 'events-upcoming');
      expect(find.byType(EventDirectory), findsOneWidget);
      expect(find.text('No upcoming events.'), findsOneWidget);
      expect(api.pluginReadPaths, [_upcomingPath]);

      if (user != null) {
        await tester.tap(contentText('My events'));
        await tester.pumpAndSettle();

        expect(controller.currentContent?.id, 'events-mine');
        expect(controller.destinationId, 'events-upcoming');
        expect(api.pluginReadPaths, [_upcomingPath, _minePath]);
      } else {
        expect(find.byType(InstanceSidebar), findsNothing);
        controller.handleBack(canReturnToSidebar: true);
        await tester.pumpAndSettle();
        expect(sidebarDestination('Upcoming events'), findsOneWidget);
      }
    });
  }

  testWidgets('site switches hide unavailable or disabled event links', (
    tester,
  ) async {
    final configs = [
      _config(),
      const SiteConfig.unknown(),
      _config({'discourse_events_enabled': false}),
      _config({'discourse_post_event_enabled': false}),
      _config({'sidebar_show_upcoming_events': false}),
    ];
    final sites = [
      for (final (index, config) in configs.indexed)
        instance('forum-$index.example').copyWith(config: config),
    ];
    await pumpShell(
      tester,
      desktop,
      instances: sites,
      api: FakeDiscourseApi(
        siteConfigs: {for (final site in sites) site.url: site.config},
      ),
      pluginManifest: _manifest,
    );
    final controller = ShellScope.read(
      tester.element(find.byType(InstanceSidebar)),
    );
    expect(sidebarDestination('Upcoming events'), findsOneWidget);
    for (var index = 1; index < sites.length; index++) {
      controller.selectInstance(index);
      await tester.pumpAndSettle();
      expect(
        sidebarDestination('Upcoming events'),
        findsNothing,
        reason: 'site configuration $index',
      );
      expect(sidebarDestination('My events'), findsNothing);
    }
    controller.selectInstance(0);
    await tester.pumpAndSettle();
    expect(sidebarDestination('Upcoming events'), findsOneWidget);
  });

  testWidgets('the event link appears when site settings finish loading', (
    tester,
  ) async {
    final gate = Completer<void>();
    final site = instance('forum.example');
    await pumpShell(
      tester,
      desktop,
      instances: [site],
      api: FakeDiscourseApi(
        siteConfigGate: gate,
        siteConfigs: {site.url: _config()},
      ),
      pluginManifest: _manifest,
      beforeSettle: () async {
        expect(sidebarDestination('Upcoming events'), findsNothing);
        gate.complete();
      },
    );
    expect(sidebarDestination('Upcoming events'), findsOneWidget);
  });
}
