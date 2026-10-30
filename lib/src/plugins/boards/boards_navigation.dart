import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';

import 'boards_controller.dart';
import 'boards_data.dart';

const boardsNavigationKey = PluginServiceKey<BoardsNavigation>(
  owner: boardsPluginId,
  name: 'navigation',
);
// Font Awesome Free 7.3.1, table-columns. Icons: CC BY 4.0.
// https://fontawesome.com/license/free
const boardsIcon = DIconData(
  'boards',
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 448 512"><path fill="currentColor" d="M0 96C0 60.7 28.7 32 64 32l320 0c35.3 0 64 28.7 64 64l0 320c0 35.3-28.7 64-64 64L64 480c-35.3 0-64-28.7-64-64L0 96zm64 64l0 256 128 0 0-256-128 0zm320 0l-128 0 0 256 128 0 0-256z"/></svg>',
);

final class BoardsRoute {
  const BoardsRoute({this.boardId, this.cardId});
  final int? boardId, cardId;
  String get id => boardId == null
      ? 'boards'
      : 'boards/$boardId${cardId == null ? '' : '/cards/$cardId'}';
  static BoardsRoute? parse(String id) {
    if (id == 'boards') return const BoardsRoute();
    final match = RegExp(
      r'^boards/([1-9][0-9]*)(?:/cards/([1-9][0-9]*))?$',
    ).firstMatch(id);
    final boardId = boardInt(int.tryParse(match?[1] ?? ''));
    if (boardId == null) return null;
    return BoardsRoute(
      boardId: boardId,
      cardId: boardInt(int.tryParse(match?[2] ?? '')),
    );
  }
}

final class BoardsNavigation implements PluginLinkHandler {
  const BoardsNavigation({
    required this.host,
    required this.topicLists,
    required this.controller,
  });
  final PluginRouteNavigationHost host;
  final PluginTopicListNavigationHost topicLists;
  final BoardsController controller;

  /// Boards then open in the shared page sheet, which owns the way back.
  bool get mobileNavigationEnabled => switch (host) {
    final PluginRoutePresentationHost presentation =>
      presentation.mobileNavigationEnabled,
    _ => false,
  };

  void open({BoardSnapshot? board, int? cardId}) {
    final site = host.currentSite;
    if (site == null || !controller.enabled(site.url)) return;
    host.pushContent(
      ContentRoute(
        destination: ExtensionDestination(
          BoardsRoute(boardId: board?.id, cardId: cardId).id,
        ),
        title: board?.name ?? appL10n.boardsTitle,
        icon: boardsIcon,
      ),
    );
  }

  void openMembership(String site, BoardMembership membership) {
    if (!controller.enabled(site) || host.currentSite?.url != site) return;
    host.pushContent(
      ContentRoute(
        destination: ExtensionDestination(
          BoardsRoute(
            boardId: membership.boardId,
            cardId: membership.cardId,
          ).id,
        ),
        title: membership.name,
        icon: boardsIcon,
      ),
    );
  }

  void openTopic(String site, BoardCard card) {
    if (!controller.enabled(site) || card.topicId == null) return;
    host.openTopicPost(siteUrl: site, topicId: card.topicId!, postNumber: 1);
  }

  void openTag(String site, String tag) {
    if (!controller.enabled(site) || host.currentSite?.url != site) return;
    final path = Uri(pathSegments: ['', 'tag', '$tag.json']).toString();
    topicLists.openTopicList(
      ContentRoute(
        destination: FeedDestination.fromPath(key: 'list-$path', path: path),
        title: tag,
        icon: DIcons.tag,
      ),
    );
  }

  void openCategory(String site, int id, String name) {
    if (!controller.enabled(site) || host.currentSite?.url != site) return;
    final path = '/c/$id.json';
    topicLists.openTopicList(
      ContentRoute(
        destination: FeedDestination.fromPath(key: 'list-$path', path: path),
        title: name,
        icon: DIcons.folder,
      ),
    );
  }

  Future<bool> configure(String site, BoardSnapshot board) => openExternalLink(
    resolveSitePath(
      site,
      'boards/${Uri.encodeComponent(board.slug)}/${board.id}/configure',
    ),
  );
  @override
  Future<bool> openPluginUrl(
    String url, {
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
    void Function()? onNavigated,
  }) async {
    final target = Uri.tryParse(url);
    if (target == null) return false;
    final owner = mostSpecificServingForum(
      host.sites,
      target,
      siteUrl: (site) => site.url,
    );
    if (owner == null || !controller.enabled(owner.forum.url)) return false;
    final path = owner.forum.pathWithin(target);
    if (path == null) return false;
    BoardsRoute? route;
    if (path == '/boards' || path == '/boards/') {
      route = const BoardsRoute();
    } else {
      final match = RegExp(
        r'^/boards/[^/]+/([1-9][0-9]*)(?:/cards/([1-9][0-9]*))?/?$',
      ).firstMatch(path);
      final boardId = boardInt(int.tryParse(match?[1] ?? ''));
      if (boardId != null) {
        route = BoardsRoute(
          boardId: boardId,
          cardId: boardInt(
            int.tryParse(match?[2] ?? target.queryParameters['card'] ?? ''),
          ),
        );
      }
    }
    if (route == null) return false;
    if (host.currentSite?.url != owner.forum.url) {
      host.selectInstance(owner.index);
    }
    host.pushContent(
      ContentRoute(
        destination: ExtensionDestination(route.id),
        title: appL10n.boardsTitle,
        icon: boardsIcon,
      ),
    );
    if (host.currentSite?.url == owner.forum.url &&
        host.currentContent?.id == route.id) {
      onNavigated?.call();
    }
    return true;
  }
}
