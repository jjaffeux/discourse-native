import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/shell/notification_list.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

NotificationDescription describe(
  NotificationKind kind, {
  String? actor = 'sam',
  String title = 'Better image handling',
  int count = 0,
  String? badgeName,
  String? groupName,
  String? channelTitle,
}) {
  return NotificationDescription.of(
    DiscourseNotification(
      id: 1,
      kind: kind,
      actor: actor,
      title: title,
      count: count,
      badgeName: badgeName,
      groupName: groupName,
      channelTitle: channelTitle,
    ),
  );
}

/// The whole line, as the row draws it.
String line(NotificationDescription description) => description.actor == null
    ? description.phrase
    : '${description.actor} ${description.phrase}';

void main() {
  group('what a notification says', () {
    test('names who did it and what they did', () {
      expect(
        line(describe(NotificationKind.replied)),
        'sam replied to Better image handling',
      );
      expect(
        line(describe(NotificationKind.liked)),
        'sam liked your post in Better image handling',
      );
      expect(
        line(describe(NotificationKind.mentioned)),
        'sam mentioned you in Better image handling',
      );
      expect(
        line(describe(NotificationKind.privateMessage, title: 'Daily Log')),
        'sam sent you Daily Log',
      );
    });

    test('counts what a consolidated notification stands for', () {
      expect(
        line(describe(NotificationKind.likedConsolidated, count: 5)),
        'sam liked 5 of your posts',
      );
      expect(
        line(
          describe(
            NotificationKind.groupMessageSummary,
            count: 1,
            groupName: 'support',
          ),
        ),
        '1 message in your support inbox',
      );
      expect(
        line(
          describe(
            NotificationKind.groupMessageSummary,
            count: 4,
            groupName: 'support',
          ),
        ),
        '4 messages in your support inbox',
      );
    });

    test('the kinds nobody did to you stand on their own', () {
      final badge = describe(
        NotificationKind.grantedBadge,
        badgeName: 'Nice Reply',
      );

      expect(badge.actor, isNull);
      expect(line(badge), 'You earned the Nice Reply badge');
      expect(
        line(describe(NotificationKind.newFeatures)),
        'New features are available',
      );
      expect(
        line(describe(NotificationKind.bookmarkReminder)),
        'Reminder: Better image handling',
      );
    });

    test('a kind from a plugin still says what it is about', () {
      expect(
        line(describe(NotificationKind.unknown, title: 'Something happened')),
        'Something happened',
      );
      // ...and nothing at all still fills the row.
      expect(
        line(describe(NotificationKind.unknown, title: '')),
        'New notification',
      );
    });

    test('a missing actor does not leave a sentence headless', () {
      expect(
        line(describe(NotificationKind.replied, actor: null)),
        'Someone replied to Better image handling',
      );
    });

    test('chat is about a channel rather than a topic', () {
      expect(
        line(
          describe(
            NotificationKind.chatMention,
            title: '',
            channelTitle: 'dev',
          ),
        ),
        'sam mentioned you in dev',
      );
    });
  });

  group('the icon a notification gets', () {
    test('is the one Discourse gives it', () {
      // From the REPLACEMENTS table tool/icons.txt mirrors.
      expect(describe(NotificationKind.replied).icon, DIcons.reply);
      expect(describe(NotificationKind.liked).icon, DIcons.heart);
      expect(describe(NotificationKind.mentioned).icon, DIcons.at);
      expect(describe(NotificationKind.quoted).icon, DIcons.quoteRight);
      expect(describe(NotificationKind.grantedBadge).icon, DIcons.certificate);
      expect(describe(NotificationKind.linked).icon, DIcons.link);
    });

    test('falls back to a bell rather than to nothing', () {
      expect(describe(NotificationKind.unknown).icon, DIcons.bell);
    });

    test('is drawn for every kind we know', () {
      for (final kind in NotificationKind.values) {
        expect(describe(kind).icon, isNotNull, reason: kind.wireName);
      }
    });
  });
}
