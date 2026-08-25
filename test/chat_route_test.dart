import 'package:discourse_native/src/plugins/chat/chat_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatRoute', () {
    test('round-trips the stable channel and thread identities', () {
      final channel = ChatRoute.channel(9);
      final thread = ChatRoute.thread(channelId: 9, threadId: 3);
      final settings = ChatRoute.info(channelId: 9);
      final members = ChatRoute.info(
        channelId: 9,
        tab: ChatChannelInfoTab.members,
      );

      expect(channel.routeId, 'chat-c-9');
      expect(ChatRoute.parse(channel.routeId), channel);
      expect(thread.routeId, 'chat-c-9-t-3');
      expect(ChatRoute.parse(thread.routeId), thread);
      expect(settings.routeId, 'chat-c-9-info-settings');
      expect(ChatRoute.parse(settings.routeId), settings);
      expect(members.routeId, 'chat-c-9-info-members');
      expect(ChatRoute.parse(members.routeId), members);
    });

    test('rejects aliases, prefixes, suffixes, and invalid ids', () {
      for (final value in [
        '',
        'chat-c-',
        'chat-c-0',
        'chat-c-01',
        'chat-c--1',
        'chat-c-9-',
        'chat-c-9-t-',
        'chat-c-9-t-0',
        'chat-c-9-t-03',
        'chat-c-9-t-3-extra',
        'chat-c-9-info',
        'chat-c-9-info-other',
        'chat-c-9-info-members-extra',
        'prefix-chat-c-9',
        'chat-c-9999999999999999999999999999999999999999999',
      ]) {
        expect(ChatRoute.parse(value), isNull, reason: value);
      }
    });

    test('factories refuse non-positive ids', () {
      expect(() => ChatRoute.channel(0), throwsArgumentError);
      expect(
        () => ChatRoute.thread(channelId: 9, threadId: -1),
        throwsArgumentError,
      );
    });
  });

  group('ChatLink', () {
    test('parses channel and thread links with optional message anchors', () {
      final cases = <String, (ChatRoute, int?)>{
        'https://meta.discourse.org/chat/c/-/9': (ChatRoute.channel(9), null),
        'https://meta.discourse.org/chat/c/-/9/44': (ChatRoute.channel(9), 44),
        'https://meta.discourse.org/chat/c/bugs/9': (
          ChatRoute.channel(9),
          null,
        ),
        'https://meta.discourse.org/chat/c/-/9/t/3': (
          ChatRoute.thread(channelId: 9, threadId: 3),
          null,
        ),
        'https://meta.discourse.org/chat/c/-/9/t/3/44': (
          ChatRoute.thread(channelId: 9, threadId: 3),
          44,
        ),
        '/chat/c/-/9/t/3/44/?foo=bar#message': (
          ChatRoute.thread(channelId: 9, threadId: 3),
          44,
        ),
        '/chat/c/bugs/9/info/settings': (ChatRoute.info(channelId: 9), null),
        '/chat/c/bugs/9/info/members': (
          ChatRoute.info(channelId: 9, tab: ChatChannelInfoTab.members),
          null,
        ),
      };

      for (final entry in cases.entries) {
        final link = ChatLink.parse(entry.key);
        expect(link, isNotNull, reason: entry.key);
        expect(link!.route, entry.value.$1, reason: entry.key);
        expect(link.messageId, entry.value.$2, reason: entry.key);
      }
    });

    test('rejects nearby web routes instead of claiming them natively', () {
      for (final value in [
        '',
        '/chat',
        '/chat/c/-/0',
        '/chat/c/-/09',
        '/chat/c/-/9/0',
        '/chat/c/-/9/44/extra',
        '/chat/c/-/9/t',
        '/chat/c/-/9/t/0',
        '/chat/c/-/9/t/3/0',
        '/chat/c/-/9/t/3/44/extra',
        '/chat/c/-/9/info',
        '/chat/c/-/9/info/other',
        '/chat/c/-/9/info/members/extra',
        '/t/3/44',
        'ftp://meta.discourse.org/chat/c/-/9',
        'mailto:/chat/c/-/9',
        'https:/chat/c/-/9',
        'https://reader:secret@meta.discourse.org/chat/c/-/9',
      ]) {
        expect(ChatLink.parse(value), isNull, reason: value);
      }
    });

    test('enforces the navigation URL boundary', () {
      expect(ChatLink.parse('/chat/c/-/9?value=${'x' * 2048}'), isNull);
    });
  });

  group('ChatNavigationHandoff', () {
    test('offers and consumes only the matching site and route', () {
      final handoff = ChatNavigationHandoff();
      addTearDown(handoff.dispose);
      final route = ChatRoute.thread(channelId: 9, threadId: 3);
      final target = ChatNavigationTarget(
        siteUrl: 'https://meta.discourse.org',
        route: route,
        messageId: 44,
      );

      handoff.offer(target);

      expect(
        handoff.take(siteUrl: 'https://other.example', route: route),
        isNull,
      );
      expect(handoff.value, same(target));
      expect(
        handoff.take(siteUrl: target.siteUrl, route: ChatRoute.channel(9)),
        isNull,
      );
      expect(handoff.take(siteUrl: target.siteUrl, route: route), same(target));
      expect(handoff.value, isNull);
    });

    test('taking a target does not re-enter listeners', () {
      final handoff = ChatNavigationHandoff();
      addTearDown(handoff.dispose);
      final route = ChatRoute.thread(channelId: 9, threadId: 3);
      var notifications = 0;
      handoff.addListener(() => notifications++);

      handoff.offer(
        ChatNavigationTarget(
          siteUrl: 'https://meta.discourse.org',
          route: route,
          messageId: 44,
        ),
      );
      expect(notifications, 1);

      expect(
        handoff.take(siteUrl: 'https://meta.discourse.org', route: route),
        isNotNull,
      );
      expect(notifications, 1);
    });
  });
}
