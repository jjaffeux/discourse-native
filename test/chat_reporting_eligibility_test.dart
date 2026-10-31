import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/chat/chat_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://forum.example';
const _message = ChatMessage(
  id: 9,
  channelId: 2,
  cooked: '<p>Content</p>',
  raw: 'Content',
  author: ChatMessageAuthor(id: 4, username: 'author'),
  reviewableId: 8,
  userFlagStatus: 0,
);

void main() {
  test(
    'DSA reporting is independent of login, ordinary flags, and existing reviewables',
    () {
      final chat = ChatController(
        api: _NoApi(),
        requests: _NoRequests(),
        store: Store(),
        siteConfigFor: (_) => const SiteConfig(dsaReportingEnabled: true),
      );
      expect(chat.canFlagMessage(_site, _message), isFalse);
      expect(chat.canReportMessage(_site, _message), isTrue);
      expect(
        chat.canReportMessage(_site, _message.withDeletedAt(DateTime(2026))),
        isFalse,
      );
      chat.dispose();
    },
  );

  test('own already-flagged messages still allow DSA notices', () {
    final chat = ChatController(
      api: _NoApi(),
      requests: _NoRequests(),
      store: Store(),
      currentUserFor: (_) => const DiscourseUser(id: 4, username: 'author'),
      siteConfigFor: (_) => const SiteConfig(dsaReportingEnabled: true),
    );
    expect(chat.canFlagMessage(_site, _message), isFalse);
    expect(chat.canReportMessage(_site, _message), isTrue);
    chat.dispose();
  });

  test('legacy guests retain explicitly configured email reporting', () {
    final chat = ChatController(
      api: _NoApi(),
      requests: _NoRequests(),
      store: Store(),
      siteConfigFor: (_) => const SiteConfig(
        allowAllUsersToFlagIllegalContent: true,
        illegalContentReportEmail: 'abuse@example.com',
      ),
    );
    expect(chat.canReportMessage(_site, _message), isTrue);
    chat.dispose();
  });

  test('old servers do not expose an unsupported reporting flow', () {
    final chat = ChatController(
      api: _NoApi(),
      requests: _NoRequests(),
      store: Store(),
    );
    expect(chat.canReportMessage(_site, _message), isFalse);
    chat.dispose();
  });
}

class _NoApi implements ChatApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoRequests implements PluginRequestHost {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
