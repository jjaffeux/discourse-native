import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/plugin_api/notification_types.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

NotificationPresentation describe(
  NotificationWireType type, {
  String? actor = 'sam',
  String title = 'Better image handling',
  int count = 0,
  String? badgeName,
  String? groupName,
  Map<String, Object?> data = const {},
}) {
  final resolved = resolveCoreNotification(
    DiscourseNotification.fromJson({
      'id': 1,
      'notification_type': type.wireId,
      'fancy_title': title,
      'data': <String, Object?>{
        'display_username': ?actor,
        'count': count,
        'badge_name': ?badgeName,
        'group_name': ?groupName,
        ...data,
      },
    }),
  );
  return resolved.presentation;
}

String line(NotificationPresentation description) => description.actor == null
    ? description.phrase
    : '${description.actor} ${description.phrase}';

void main() {
  group('core notification wording', () {
    test('names who did it and what they did', () {
      expect(
        line(describe(CoreNotificationTypes.replied)),
        'sam replied to Better image handling',
      );
      expect(
        line(describe(CoreNotificationTypes.liked)),
        'sam liked your post in Better image handling',
      );
      expect(
        line(describe(CoreNotificationTypes.mentioned)),
        'sam mentioned you in Better image handling',
      );
      expect(
        line(
          describe(CoreNotificationTypes.privateMessage, title: 'Daily Log'),
        ),
        'sam sent you Daily Log',
      );
    });

    test('counts consolidated core notifications', () {
      expect(
        line(describe(CoreNotificationTypes.likedConsolidated, count: 5)),
        'sam liked 5 of your posts',
      );
      expect(
        line(
          describe(
            CoreNotificationTypes.groupMessageSummary,
            count: 1,
            groupName: 'support',
          ),
        ),
        '1 message in your support inbox',
      );
    });

    test('core notifications without actors stand on their own', () {
      final badge = describe(
        CoreNotificationTypes.grantedBadge,
        badgeName: 'Nice Reply',
      );

      expect(badge.actor, isNull);
      expect(line(badge), 'You earned the Nice Reply badge');
      expect(
        line(describe(CoreNotificationTypes.newFeatures)),
        'New features are available',
      );
      expect(
        line(describe(CoreNotificationTypes.bookmarkReminder)),
        'Reminder: Better image handling',
      );
    });

    test('describes upcoming changes from their notification payload', () {
      expect(
        line(
          describe(
            CoreNotificationTypes.upcomingChangeAvailable,
            data: const {
              'upcoming_change_humanized_names': ['Experimental sidebar'],
              'count': 1,
            },
          ),
        ),
        "'Experimental sidebar' is available for preview",
      );
      expect(
        line(
          describe(
            CoreNotificationTypes.upcomingChangeAutomaticallyPromoted,
            data: const {
              'upcoming_change_humanized_names': [
                'Experimental sidebar',
                'New composer',
              ],
              'count': 2,
            },
          ),
        ),
        "'Experimental sidebar' and 'New composer' were automatically enabled",
      );
      expect(
        line(
          describe(
            CoreNotificationTypes.upcomingChangeAvailable,
            data: const {
              'upcoming_change_humanized_names': ['Experimental sidebar'],
              'count': 4,
            },
          ),
        ),
        "'Experimental sidebar' and 3 more changes are available for preview",
      );
    });

    test('a missing actor uses a safe subject', () {
      expect(
        line(describe(CoreNotificationTypes.replied, actor: null)),
        'Someone replied to Better image handling',
      );
    });
  });

  test('core icons match Discourse', () {
    expect(describe(CoreNotificationTypes.replied).icon, DIcons.reply);
    expect(describe(CoreNotificationTypes.liked).icon, DIcons.heart);
    expect(describe(CoreNotificationTypes.mentioned).icon, DIcons.at);
    expect(describe(CoreNotificationTypes.quoted).icon, DIcons.quoteRight);
    expect(
      describe(CoreNotificationTypes.grantedBadge).icon,
      DIcons.certificate,
    );
    expect(describe(CoreNotificationTypes.linked).icon, DIcons.link);
    expect(
      describe(CoreNotificationTypes.upcomingChangeAvailable).icon,
      DIcons.flask,
    );
    expect(
      describe(CoreNotificationTypes.upcomingChangeAutomaticallyPromoted).icon,
      DIcons.discourseFlaskCheck,
    );
  });

  test('every declared core type has exactly one decoder registration', () {
    expect(
      coreNotificationTypes.map((definition) => definition.wireType),
      CoreNotificationTypes.values,
    );
  });
}
