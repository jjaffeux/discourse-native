import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/plugin_api/notification_types.dart';
import 'package:flutter_test/flutter_test.dart';

DiscourseNotification parse(
  NotificationWireType type, {
  int? topicId,
  String? slug,
  int? postNumber,
  Map<String, dynamic> data = const {},
}) => DiscourseNotification.fromJson({
  'id': 1,
  'notification_type': type.wireId,
  'read': false,
  'topic_id': topicId,
  'slug': slug,
  'post_number': postNumber,
  'data': data,
});

const _siteUrl = 'https://forum.example';

void main() {
  group('opaque notification wire envelope', () {
    test('preserves unknown IDs, names, keys and nested payloads', () {
      final source = <String, dynamic>{
        'id': 7,
        'notification_type': 4242,
        'notification_type_name': 'future_plugin_alert',
        'read': false,
        'future_envelope_key': {'enabled': true},
        'data': {
          'topic_title': 'Future alert',
          'plugin_key': [
            1,
            {'nested': 'value'},
          ],
        },
      };

      final notification = DiscourseNotification.fromJson(source);

      expect(notification.typeId, const NotificationTypeId(4242));
      expect(
        notification.typeName,
        const NotificationTypeName('future_plugin_alert'),
      );
      expect(notification.toJson(), source);
      expect(
        () => notification.data['plugin_key'] = const [],
        throwsUnsupportedError,
      );
      final nested = notification.data['plugin_key']! as List<Object?>;
      expect(() => nested.add(2), throwsUnsupportedError);
      expect(
        () => (nested[1]! as Map<String, Object?>)['nested'] = 'changed',
        throwsUnsupportedError,
      );
    });

    test('marking read changes only read and retains unknown data', () {
      final notification = DiscourseNotification.fromJson(const {
        'id': 7,
        'notification_type': 4242,
        'notification_name': 'unknown_name_variant',
        'read': false,
        'data': {
          'opaque': {'answer': 42},
        },
      });

      final read = notification.asRead();

      expect(read.read, isTrue);
      expect(read.typeId, notification.typeId);
      expect(read.typeName, notification.typeName);
      expect(read.data, notification.data);
      expect(read.toJson(), {...notification.toJson(), 'read': true});
    });
  });

  group('core notification routes', () {
    test('retains an explicit first post instead of resuming the topic', () {
      expect(
        resolveCoreNotification(
          _siteUrl,
          parse(CoreNotificationTypes.liked, topicId: 12, postNumber: 1),
        ).path,
        '/t/topic/12/1',
      );
    });

    test('a topic route comes only from stable envelope fields', () {
      final notification = parse(
        CoreNotificationTypes.replied,
        topicId: 12,
        slug: 'better-image-handling',
        postNumber: 4,
      );

      expect(
        resolveCoreNotification(_siteUrl, notification).path,
        '/t/better-image-handling/12/4',
      );
      expect(
        resolveCoreNotification(
          _siteUrl,
          parse(CoreNotificationTypes.liked, topicId: 12),
        ).path,
        '/t/topic/12',
      );
    });

    test('core-owned payload routes remain in the core resolver', () {
      expect(
        resolveCoreNotification(
          _siteUrl,
          parse(
            CoreNotificationTypes.grantedBadge,
            data: const {
              'badge_id': 24,
              'badge_slug': 'nice-reply',
              'username': 'JoffreyJ',
            },
          ),
        ).path,
        '/badges/24/nice-reply?username=joffreyj',
      );
      expect(
        resolveCoreNotification(
          _siteUrl,
          parse(
            CoreNotificationTypes.membershipRequestAccepted,
            data: const {'group_name': 'support'},
          ),
        ).path,
        '/g/support',
      );
      expect(
        resolveCoreNotification(
          _siteUrl,
          parse(CoreNotificationTypes.adminProblems),
        ).path,
        '/admin',
      );
      expect(
        resolveCoreNotification(
          _siteUrl,
          parse(CoreNotificationTypes.newFeatures),
        ).path,
        '/admin/whats-new',
      );
    });

    test('upcoming change notifications open the filtered admin page', () {
      for (final type in [
        CoreNotificationTypes.upcomingChangeAvailable,
        CoreNotificationTypes.upcomingChangeAutomaticallyPromoted,
      ]) {
        final path = resolveCoreNotification(
          _siteUrl,
          parse(
            type,
            data: const {
              'upcoming_change_names': ['enable_feature_x', 'enable_feature_y'],
            },
          ),
        ).path;

        expect(path, isNotNull);
        final uri = Uri.parse(path!);
        expect(uri.path, '/admin/config/upcoming-changes');
        expect(
          uri.queryParameters['changeNamesFilter'],
          'enable_feature_x,enable_feature_y',
        );
      }
    });

    test(
      'bookmark reminders accept only safe site-relative payload routes',
      () {
        expect(
          resolveCoreNotification(
            _siteUrl,
            parse(
              CoreNotificationTypes.bookmarkReminder,
              data: const {'bookmarkable_url': '/chat/c/-/9/44'},
            ),
          ).path,
          '/chat/c/-/9/44',
        );
        expect(
          resolveCoreNotification(
            _siteUrl,
            parse(
              CoreNotificationTypes.bookmarkReminder,
              data: const {'bookmarkable_url': 'https://evil.example/'},
            ),
          ).path,
          isNull,
        );
        expect(
          resolveCoreNotification(
            _siteUrl,
            parse(
              CoreNotificationTypes.bookmarkReminder,
              data: const {'bookmarkable_url': '//evil.example/t/x/1'},
            ),
          ).path,
          isNull,
        );
      },
    );

    group('on a forum served from a subfolder', () {
      const forum = 'https://example.com/forum';
      String? path(NotificationWireType type, Map<String, Object?> data) =>
          resolveCoreNotification(forum, parse(type, data: data)).path;

      test('reads a link the server wrote from the forum root', () {
        expect(
          path(CoreNotificationTypes.bookmarkReminder, const {
            'bookmarkable_url': '/forum/chat/c/-/9/44',
          }),
          '/chat/c/-/9/44',
        );
        expect(
          path(CoreNotificationTypes.bookmarkReminder, const {
            'bookmarkable_url': '/forum/t/a-topic/7/3?u=sam#reply',
          }),
          '/t/a-topic/7/3?u=sam#reply',
        );
      });

      test('keeps no link the server wrote outside the forum', () {
        for (final written in [
          '/chat/c/-/9/44',
          '/forums/t/a-topic/7',
          'https://example.com/forum/t/a-topic/7',
          '//example.com/forum/t/a-topic/7',
        ]) {
          expect(
            path(CoreNotificationTypes.bookmarkReminder, {
              'bookmarkable_url': written,
            }),
            isNull,
            reason: written,
          );
        }
      });

      test('builds its own paths from the forum root', () {
        expect(
          resolveCoreNotification(
            forum,
            parse(CoreNotificationTypes.replied, topicId: 7, postNumber: 3),
          ).path,
          '/t/topic/7/3',
        );
        expect(
          path(CoreNotificationTypes.membershipRequestAccepted, const {
            'group_name': 'staff',
          }),
          '/g/staff',
        );
        expect(
          path(CoreNotificationTypes.groupMessageSummary, const {
            'username': 'reader',
            'group_name': 'staff',
          }),
          '/u/reader/messages/group/staff',
        );
      });
    });

    test('reads a link the server wrote on a root forum as it was written', () {
      for (final written in [
        '/chat/c/-/9/44',
        '/t/a-topic/7/3?u=sam',
        '/t/caf%C3%A9/7',
      ]) {
        expect(
          resolveCoreNotification(
            'https://example.com',
            parse(
              CoreNotificationTypes.bookmarkReminder,
              data: {'bookmarkable_url': written},
            ),
          ).path,
          written,
        );
      }
    });
  });

  test('an unowned type does not interpret payload title or route keys', () {
    final notification = DiscourseNotification.fromJson(const {
      'id': 1,
      'notification_type': 801,
      'data': {
        'topic_title': 'A followed topic',
        'bookmarkable_url': '/plugin/private/route',
      },
    });

    final resolved = resolveCoreNotification(_siteUrl, notification);

    expect(resolved.presentation.icon.name, 'bell');
    expect(resolved.presentation.actor, isNull);
    expect(notification.title, isEmpty);
    expect(notification.data['topic_title'], 'A followed topic');
    expect(resolved.presentation.phrase, 'New notification');
    expect(resolved.path, isNull);
  });
}
