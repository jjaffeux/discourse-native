import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final registry = PluginRegistry.validated(const [ChatPlugin()]);
  final codec = DiscourseModelCodec(extensions: registry);

  test('Chat owns decoding and presence of its totals wire field', () {
    final present = codec.notificationTotals(const {'chat_notifications': -4});
    final absent = codec.notificationTotals(const {});

    expect(present.hasChatEnabled, isTrue);
    expect(present.chatNotifications, 0);
    expect(absent.hasChatEnabled, isFalse);
    expect(absent.chatNotifications, 0);
  });

  test(
    'the shared API delegates totals decoding to installed plugins',
    () async {
      final api = DiscourseApi(
        models: codec,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'unread_notifications': 2, 'chat_notifications': 4}),
            200,
          ),
        ),
      );

      final totals = await api.notificationTotals(
        siteUrl: 'https://example.com',
        apiKey: 'key',
      );

      expect(totals.unreadNotifications, 2);
      expect(totals.chatNotifications, 4);
      expect(totals.badge, 6);
    },
  );

  test('Chat deltas preserve response presence and never go negative', () {
    final available = chatNotificationTotals(
      unreadNotifications: 2,
      chatNotifications: 6,
      topicTrackingUnread: 4,
    );
    final unavailable = chatNotificationTotals(
      chatNotifications: 2,
      available: false,
    );

    final read = available.withChatNotificationsDelta(-6);
    final replayed = read.withChatNotificationsDelta(-1);
    final heldUnavailable = unavailable.withChatNotificationsDelta(3);

    expect(read.chatNotifications, 0);
    expect(read.unreadNotifications, 2);
    expect(read.topicTrackingUnread, 4);
    expect(read.hasChatEnabled, isTrue);
    expect(replayed.chatNotifications, 0);
    expect(heldUnavailable.chatNotifications, 5);
    expect(heldUnavailable.hasChatEnabled, isFalse);
  });

  test('available Chat totals contribute to the core badge', () {
    expect(
      chatNotificationTotals(
        unreadNotifications: 3,
        unseenReviewables: 1,
        chatNotifications: 4,
      ).badge,
      8,
    );
    expect(
      chatNotificationTotals(
        unreadNotifications: 3,
        chatNotifications: 4,
        available: false,
      ).badge,
      3,
    );
  });

  test('a core-only stored round trip preserves Chat namespace', () {
    final stored = chatNotificationTotals(
      chatNotifications: 7,
    ).toStoredJson(counterCodec: registry);
    final coreOnly = NotificationTotals.fromStoredJson(stored);
    final storedAgain = coreOnly.toStoredJson();
    final restored = NotificationTotals.fromStoredJson(
      storedAgain,
      counterCodec: registry,
    );

    expect(storedAgain['plugins'], {'chat/notifications': 7});
    expect(restored.hasChatEnabled, isTrue);
    expect(restored.chatNotifications, 7);
  });
}
