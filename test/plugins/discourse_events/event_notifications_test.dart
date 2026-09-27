import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

DiscourseNotification notification({
  int type = 27,
  Map<String, Object?> data = const {},
  int? topicId = 700,
  int? postNumber = 3,
  String slug = 'planning',
}) => DiscourseNotification.fromJson({
  'id': 42,
  'notification_type': type,
  'topic_id': topicId,
  'post_number': postNumber,
  'slug': slug,
  'data': data,
});

const _siteUrl = 'https://forum.example';

void main() {
  for (final manifest in [
    bundledPluginManifest,
    bundledPluginManifestWithoutDiagnostics,
  ]) {
    group(
      'bundled events (${manifest == bundledPluginManifest ? 'diagnostics' : 'no diagnostics'})',
      () {
        late InstalledPlugins plugins;

        setUp(() {
          plugins = PluginInstaller.install(manifest);
          addTearDown(plugins.close);
        });

        test('owns reminder and invitation wire types', () {
          for (final (id, name) in [
            (27, 'event_reminder'),
            (28, 'event_invitation'),
          ]) {
            final definition = plugins.registry.notificationType(
              NotificationTypeId(id),
            )!;
            expect(definition.id.owner.value, 'discourse-events');
            expect(definition.wireType.wireName, name);
          }
        });

        for (final (phase, phrase) in [
          ('before', 'Planning is starting soon'),
          ('ongoing', 'Planning is happening now'),
          ('after', 'Planning has ended'),
        ]) {
          test('renders the upstream $phase reminder payload', () {
            final resolved = plugins.registry.resolveNotification(
              _siteUrl,
              notification(
                data: {
                  'topic_title': 'Planning',
                  'display_username': 'recipient',
                  'message':
                      'discourse_post_event.notifications.${phase}_event_reminder',
                },
              ),
            );
            expect(resolved.presentation.phrase, phrase);
            expect(resolved.presentation.actor, isNull);
            expect(resolved.presentation.icon, EventIcons.calendar);
            expect(resolved.path, '/t/planning/700/3');
          });
        }

        test('reminder uses the server display title ahead of event_name', () {
          final resolved = plugins.registry.resolveNotification(
            _siteUrl,
            notification(
              data: {
                'topic_title': 'Planning',
                'event_name': 'Old name',
                'message':
                    'discourse_post_event.notifications.before_event_reminder',
              },
            ),
          );
          expect(resolved.presentation.phrase, 'Planning is starting soon');
        });

        test('unknown messages have readable title fallbacks', () {
          for (final (data, title) in <(Map<String, Object?>, String)>[
            ({'topic_title': 'Planning'}, 'Planning'),
            ({'topic_title': '', 'event_name': 'Planning'}, 'Planning'),
            ({'topic_title': 123, 'event_name': false}, 'an event'),
            ({}, 'an event'),
          ]) {
            final resolved = plugins.registry.resolveNotification(
              _siteUrl,
              notification(data: {...data, 'message': 'future.reminder'}),
            );
            expect(resolved.presentation.phrase, 'Reminder for $title');
            expect(resolved.presentation.icon, EventIcons.calendar);
          }
        });

        test('invitations retain their actor and event name', () {
          final resolved = plugins.registry.resolveNotification(
            _siteUrl,
            notification(
              type: 28,
              data: {
                'topic_title': 'Discussion',
                'event_name': 'Planning',
                'display_username': 'sam',
              },
            ),
          );
          expect(resolved.presentation.actor, 'sam');
          expect(resolved.presentation.phrase, 'invited you to Planning');
          expect(resolved.presentation.icon, EventIcons.calendar);
          expect(resolved.path, '/t/planning/700/3');
        });

        test('routing requires a topic and tolerates absent slug and post', () {
          for (final type in [27, 28]) {
            expect(
              plugins.registry
                  .resolveNotification(
                    _siteUrl,
                    notification(type: type, topicId: null),
                  )
                  .path,
              isNull,
            );
            expect(
              plugins.registry
                  .resolveNotification(
                    _siteUrl,
                    notification(type: type, slug: '', postNumber: null),
                  )
                  .path,
              '/t/topic/700',
            );
          }
        });
      },
    );
  }
}
