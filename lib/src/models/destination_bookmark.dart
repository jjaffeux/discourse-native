import 'content_route.dart';

enum DestinationBookmarkKind { page, category, chat }

/// An app-owned destination, independent of Discourse's server bookmarks.
final class DestinationBookmark {
  const DestinationBookmark._(this.kind, this.identity, this.route);

  final DestinationBookmarkKind kind;
  final String identity;
  final ContentRoute route;

  static DestinationBookmark? fromRoute(ContentRoute route) {
    if (route.destination is TopicDestination ||
        route.isPage(CorePage.bookmarks)) {
      return null;
    }
    final channel = route.destination is ExtensionDestination
        ? RegExp(r'^chat-c-([1-9][0-9]*)$').firstMatch(route.destination.key)
        : null;
    if (channel != null) {
      return DestinationBookmark._(
        DestinationBookmarkKind.chat,
        'chat:${channel.group(1)}',
        route,
      );
    }
    if (route.destination is ExtensionDestination &&
        route.id.startsWith('chat-c-')) {
      return null;
    }
    final categoryRoute =
        route.destination is FeedDestination &&
        (route.categoryId != null ||
            route.id.startsWith('category-') ||
            route.id.startsWith('list-/c/'));
    if (categoryRoute) {
      final id =
          route.categoryId ??
          int.tryParse(route.id.replaceFirst('category-', ''));
      return DestinationBookmark._(
        DestinationBookmarkKind.category,
        id == null ? 'category:${route.feedPath ?? route.id}' : 'category:$id',
        route,
      );
    }
    return DestinationBookmark._(
      DestinationBookmarkKind.page,
      'page:${route.id}',
      route,
    );
  }
}
