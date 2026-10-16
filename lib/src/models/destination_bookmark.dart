import 'content_route.dart';

enum DestinationBookmarkKind { page, category, chat }

/// An app-owned destination, independent of Discourse's server bookmarks.
final class DestinationBookmark {
  const DestinationBookmark._(this.kind, this.identity, this.route);

  final DestinationBookmarkKind kind;
  final String identity;
  final ContentRoute route;

  static DestinationBookmark? fromRoute(ContentRoute route) {
    if (route.isTopic || route.id == 'user-bookmarks') return null;
    final channel = RegExp(r'^chat-c-([1-9][0-9]*)$').firstMatch(route.id);
    if (channel != null) {
      return DestinationBookmark._(
        DestinationBookmarkKind.chat,
        'chat:${channel.group(1)}',
        _snapshot(route),
      );
    }
    if (route.id.startsWith('chat-c-')) return null;
    final categoryRoute =
        route.categoryId != null ||
        route.id.startsWith('category-') ||
        route.id.startsWith('list-/c/');
    if (categoryRoute) {
      final id =
          route.categoryId ??
          int.tryParse(route.id.replaceFirst('category-', ''));
      return DestinationBookmark._(
        DestinationBookmarkKind.category,
        id == null ? 'category:${route.feedPath ?? route.id}' : 'category:$id',
        _snapshot(route),
      );
    }
    return DestinationBookmark._(
      DestinationBookmarkKind.page,
      'page:${route.id}',
      _snapshot(route),
    );
  }

  static ContentRoute _snapshot(ContentRoute route) => ContentRoute.fromJson({
    ...route.toJson(),
    'open_in_secondary_panel': false,
    'open_in_main_panel': false,
  });
}
