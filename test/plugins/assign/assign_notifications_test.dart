import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/assign/assign_icons.dart';
import 'package:discourse_native/src/plugins/assign/assign_notifications.dart';
import 'package:discourse_native/src/plugins/assign/assign_plugin.dart';
import 'package:discourse_native/src/shell/notification_list.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/fakes.dart';
import '../../support/media_pipeline.dart';

void main() {
  test('user topic assignments match core presentation and route', () {
    const registry = PluginRegistry([AssignPlugin()]);
    final notification = DiscourseNotification.fromJson(const {
      'id': 1,
      'notification_type': 34,
      'topic_id': 12,
      'post_number': 1,
      'slug': 'work-list',
      'fancy_title': 'Localized work list',
      'data': {'display_username': 'sam', 'topic_title': 'Raw work list'},
    });

    final resolved = registry.resolveNotification(notification);

    expect(resolved.presentation.actor, isNull);
    expect(resolved.presentation.phrase, 'Localized work list');
    expect(resolved.presentation.icon, DIcons.userPlus);
    expect(resolved.path, '/t/work-list/12');
  });

  test('group post assignments name the group and post', () {
    const registry = PluginRegistry([AssignPlugin()]);
    final notification = DiscourseNotification.fromJson(const {
      'id': 2,
      'notification_type': 34,
      'topic_id': 12,
      'post_number': 4,
      'slug': 'work-list',
      'data': {
        'message': 'discourse_assign.assign_group_notification',
        'display_username': 'Team',
        'topic_title': 'Work list',
      },
    });

    final resolved = registry.resolveNotification(notification);

    expect(resolved.presentation.actor, 'Team');
    expect(resolved.presentation.phrase, 'Work list (#4)');
    expect(resolved.presentation.icon, AssignIcons.groupPlus);
    expect(resolved.path, '/t/work-list/12/4');
  });

  testWidgets('assigned topic title renders a known shortcode as emoji', (
    tester,
  ) async {
    const siteUrl = 'https://meta.example';
    installTestMediaPipeline(
      client: MockClient((_) async => http.Response('', 404)),
    );

    final controller = ShellController(
      instanceStore: FakeInstanceStore([instance('meta.example')]),
      api: FakeDiscourseApi(
        emojisBySite: {
          siteUrl: const [
            SiteEmoji(name: 'heart', url: '/images/emoji/heart.png'),
          ],
        },
      ),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);

    final notification = DiscourseNotification.fromJson(const {
      'id': 3,
      'notification_type': 34,
      'topic_id': 13,
      'post_number': 1,
      'slug': 'heart-work',
      'data': {'topic_title': 'Fix :heart: topic'},
    });
    const registry = PluginRegistry([AssignPlugin()]);

    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: NotificationRow(
              siteUrl: siteUrl,
              notification: notification,
              resolved: registry.resolveNotification(notification),
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final emoji = tester.widget<SiteEmojiImage>(find.byType(SiteEmojiImage));
    expect(emoji.name, 'heart');
    expect(find.text('Fix :heart: topic'), findsNothing);
  });

  test('orders unread assignments by bump and then creation time', () {
    DiscourseNotification notification({
      required int id,
      required bool read,
      required String bumpedAt,
      required String createdAt,
    }) => DiscourseNotification.fromJson({
      'id': id,
      'notification_type': 34,
      'read': read,
      'topic_bumped_at': bumpedAt,
      'created_at': createdAt,
      'data': const {'topic_title': 'Work list'},
    });

    final arranged = assignNotificationFeed.arrange([
      notification(
        id: 1,
        read: false,
        bumpedAt: '2026-01-02T00:00:00Z',
        createdAt: '2026-01-01T00:00:00Z',
      ),
      notification(
        id: 2,
        read: true,
        bumpedAt: '2026-01-05T00:00:00Z',
        createdAt: '2026-01-05T00:00:00Z',
      ),
      notification(
        id: 3,
        read: false,
        bumpedAt: '2026-01-03T00:00:00Z',
        createdAt: '2026-01-01T00:00:00Z',
      ),
      notification(
        id: 4,
        read: false,
        bumpedAt: '2026-01-03T00:00:00Z',
        createdAt: '2026-01-02T00:00:00Z',
      ),
    ]);

    expect(arranged.map((notification) => notification.id), [4, 3, 1, 2]);
  });

  test('declares core-parity typed dismissal copy', () {
    final dismissal = assignNotificationFeed.dismissal!;

    expect(dismissal.notificationTypes, [AssignNotificationTypes.assigned]);
    expect(dismissal.buttonLabel, 'Dismiss');
    expect(
      dismissal.buttonTooltip,
      'Mark all unread assign notifications as read',
    );
    expect(
      dismissal.confirmationMessage(1),
      'Are you sure? You have 1 unread assign notification.',
    );
    expect(
      dismissal.confirmationMessage(3),
      'Are you sure? You have 3 unread assign notifications.',
    );
  });
}
