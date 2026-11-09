import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';

import 'chat_controller.dart';
import 'chat_route.dart';

/// Shared links retain Chat's message permissions and scoped bookmark host.
final class ChatBookmarkLinkResolver implements PluginBookmarkLinkResolver {
  const ChatBookmarkLinkResolver(this.chat, this.host);

  final ChatController chat;
  final PluginBookmarkHost host;

  @override
  Future<BookmarkLinkAction?> resolveBookmarkLink(
    String siteUrl,
    String url,
  ) async {
    final link = ChatLink.parse(url, siteUrl: siteUrl);
    if (link == null || link.messageId == null) return null;
    final session = host.captureSession(siteUrl);
    final message = await chat.resolveBookmarkMessage(siteUrl, link);
    if (!session.isCurrent ||
        message == null ||
        host.bookmarkWriteInFlight(siteUrl: siteUrl, targetId: message.id)) {
      return null;
    }
    final bookmark = message.bookmark;
    return BookmarkLinkAction(
      bookmark: bookmark,
      invoke: () async {
        final current = chat.message(siteUrl, message.id);
        if (!session.isCurrent ||
            current == null ||
            !chat.canBookmarkMessage(siteUrl, current) ||
            current.bookmark != bookmark) {
          return BookmarkWriteResult.refused(
            appL10n.bookmarkChangedRefreshMenu,
          );
        }
        return bookmark == null
            ? host.createBookmark(siteUrl: siteUrl, targetId: message.id)
            : host.deleteBookmark(siteUrl: siteUrl, bookmark: bookmark);
      },
    );
  }
}
