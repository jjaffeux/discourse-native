import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugins/discourse_events/discourse_events_module.dart';
import 'package:discourse_native/src/plugins/discourse_events/discourse_events_plugin.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_card.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_controller.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_navigation.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

import 'support/event_fixtures.dart';

void main() {
  test(
    'events install alone, and core-only models remain unaware of their schemas',
    () async {
      final plugins = PluginInstaller.install(
        const PluginManifest([discourseEventsModule]),
      );
      addTearDown(plugins.close);
      final json = {
        'id': 42,
        'topic_id': 700,
        'post_number': 1,
        'username': 'sam',
        'cooked': '<div class="discourse-post-event"></div>',
        'event': eventJson(),
      };
      expect(plugins.descriptors.single.dependencies, isEmpty);
      expect(
        plugins.models
            .post(json, eventSite)
            .plugins
            .get(eventPostKey)!
            .event!
            .id,
        42,
      );
      expect(
        const DiscourseModelCodec.core()
            .post(json, eventSite)
            .plugins
            .get(eventPostKey),
        isNull,
      );
      final topic = plugins.models.topic({
        'id': 700,
        'title': 'Managers',
        'event_starts_at': '2026-09-08',
        'event_all_day': true,
      }, eventSite);
      expect(topic.detail.plugins.get(eventTopicKey)!.allDay, isTrue);
    },
  );

  test(
    'notification ownership preserves IDs and does not invent a reminder actor',
    () {
      DiscourseNotification row(int id, Map<String, Object?> data) =>
          DiscourseNotification.fromJson({
            'id': 1,
            'notification_type': id,
            'topic_id': 700,
            'post_number': 1,
            'data': data,
          });
      final reminder = eventNotificationTypes[0].decode(
        row(27, {
          'event_name': 'Planning',
          'display_username': 'recipient',
          'message': 'discourse_post_event.notifications.before_event_reminder',
        }),
      )!;
      expect(reminder.presentation.actor, isNull);
      expect(reminder.presentation.phrase, 'Planning is starting soon');
      expect(reminder.path, contains('700'));
      final invitation = eventNotificationTypes[1].decode(
        row(28, {'event_name': 'Planning', 'display_username': 'sam'}),
      )!;
      expect(invitation.presentation.actor, 'sam');
      expect(invitation.presentation.phrase, 'invited you to Planning');
      final assigned = eventNotificationTypes[1].decode(
        row(28, {
          'event_name': 'Planning',
          'display_username': 'sam',
          'message':
              'discourse_post_event.notifications.invite_user_predefined_attendance_notification',
        }),
      )!;
      expect(
        assigned.presentation.phrase,
        'set your attendance and invited you to Planning',
      );
    },
  );

  test(
    'real host installs timezone and navigation ports with no optional dependencies',
    () async {
      final host = await PluginHostHarness.open(
        transport: RecordingPluginTransport(),
        manifest: const PluginManifest([discourseEventsModule]),
        sites: [
          PluginHostSite(
            url: eventSite,
            apiKey: 'key',
            user: const PluginHostUser(username: 'lee', id: 2),
            config: SiteConfig(
              plugins: PluginData.none.withValue(
                eventSettingsKey,
                const EventSettings(enabled: true),
              ),
            ),
          ),
        ],
      );
      addTearDown(host.close);
      expect(
        host.require(eventControllerKey).zones.location('Europe/Paris'),
        isNotNull,
      );
      final navigation = host.require(eventNavigationKey);
      expect(
        await navigation.openPluginUrl('$eventSite/upcoming-events/mine'),
        isTrue,
      );
      expect(host.currentContent!.id, 'events-mine');
      expect(
        await navigation.openPluginUrl(
          'https://elsewhere.example/upcoming-events',
        ),
        isFalse,
      );
      expect(
        await navigation.openPluginUrl(
          '$eventSite/upcoming-events/month/2026/9/1',
        ),
        isTrue,
      );
      expect(host.currentContent!.id, 'events-upcoming/month/2026/9/1');
      expect(
        await navigation.openPluginUrl(
          '$eventSite/upcoming-events/mine/agendaWeek/2026/9/8',
        ),
        isTrue,
      );
      expect(host.currentContent!.id, 'events-mine/week/2026/9/8');
      expect(
        await navigation.openPluginUrl(
          '$eventSite/upcoming-events/month/2026/2/30',
        ),
        isFalse,
      );
      expect(host.currentContent!.id, 'events-mine/week/2026/9/8');
    },
  );

  testWidgets(
    'manual quotes and nested event markup never inherit post event authority',
    (tester) async {
      const plugin = DiscourseEventsPlugin();
      final post = const DiscourseModelCodec.core()
          .post({'id': 42, 'post_number': 1, 'username': 'sam'}, eventSite)
          .withPlugins(
            PluginData.none.withValue(
              eventPostKey,
              EventPostData(
                event: PostEvent.decode(eventJson()),
                oneboxes: {700: PostEvent.decode(eventJson())!},
              ),
            ),
          );
      Widget? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final fragment = html.parseFragment(
                '<aside class="quote" data-username="sam"><div class="discourse-post-event">Quoted</div></aside>',
              );
              result = plugin.postBodyElement(
                PluginPostBodyContext(
                  buildContext: context,
                  siteUrl: eventSite,
                  post: post,
                ),
                fragment.querySelector('div')!,
              );
              expect(
                plugin.postBodyElement(
                  PluginPostBodyContext(
                    buildContext: context,
                    siteUrl: eventSite,
                    post: post,
                  ),
                  fragment.children.single,
                ),
                isNull,
              );
              return Scaffold(body: result);
            },
          ),
        ),
      );
      expect(result, isA<EventCookedFallback>());
      expect(find.text('Quoted'), findsOneWidget);
    },
  );

  testWidgets(
    'a linked event hydrates and writes to its own post, not the containing post',
    (tester) async {
      final transport = RecordingPluginTransport(
        responses: {
          'GET /discourse-post-event/events/42.json': {'event': eventJson()},
          'POST /discourse-post-event/events/42/invitees.json': {
            'invitee': watching(status: 'interested'),
          },
        },
      );
      final host = await PluginHostHarness.open(
        transport: transport,
        manifest: const PluginManifest([discourseEventsModule]),
        sites: const [
          PluginHostSite(
            url: eventSite,
            apiKey: 'key',
            user: PluginHostUser(username: 'lee', id: 2),
          ),
        ],
      );
      addTearDown(host.close);
      final plugins = PluginInstaller.install(
        const PluginManifest([discourseEventsModule]),
      );
      addTearDown(plugins.close);
      final post = plugins.models.post({
        'id': 900,
        'post_number': 7,
        'username': 'lee',
        'event_oneboxes': {'700': eventJson()},
      }, eventSite);
      final element = html
          .parseFragment(
            '<aside class="quote" data-topic="700" data-post="1">Linked event</aside>',
          )
          .children
          .single;
      await tester.pumpWidget(
        host.scope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Builder(
                  builder: (context) =>
                      plugins.registry.postBodyElement(
                        context,
                        eventSite,
                        post,
                        element,
                      ) ??
                      const Text('Missing event'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PostEventCard), findsOneWidget);
      await tester.tap(find.text('Interested'));
      await tester.pumpAndSettle();
      expect(
        transport.writes.single.path,
        '/discourse-post-event/events/42/invitees.json',
      );
      expect(transport.writes.single.body, {
        'invitee': {'status': 'interested', 'recurring': false},
      });
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
