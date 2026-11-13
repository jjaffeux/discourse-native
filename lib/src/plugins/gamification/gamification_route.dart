import 'gamification_models.dart';

final class GamificationRoute {
  const GamificationRoute({
    this.boardId,
    this.period,
    this.admin = false,
    this.create = false,
  });
  final int? boardId;
  final GamificationPeriod? period;
  final bool admin, create;
  GamificationQuery get query => GamificationQuery(
    target: boardId == null
        ? const DefaultLeaderboard()
        : LeaderboardById(boardId!),
    period: period,
  );
  String get id {
    final path = admin
        ? 'gamification/admin${create
              ? '/new'
              : boardId == null
              ? ''
              : '/$boardId'}'
        : 'gamification${boardId == null ? '' : '/$boardId'}';
    return '$path${period == null || admin ? '' : '?period=${period!.wire}'}';
  }

  static GamificationRoute? parse(String id) {
    final uri = Uri.tryParse(id);
    if (uri == null) return null;
    final admin = RegExp(
      r'^gamification/admin(?:/(new|[1-9][0-9]*))?$',
    ).firstMatch(uri.path);
    if (admin != null) {
      final target = admin[1];
      final create = target == 'new';
      final boardId = int.tryParse(target ?? '');
      if (target != null && !create && boardId == null) return null;
      return GamificationRoute(admin: true, create: create, boardId: boardId);
    }
    final match = RegExp(
      r'^gamification(?:/([1-9][0-9]*))?$',
    ).firstMatch(uri.path);
    if (match == null) return null;
    final boardId = int.tryParse(match[1] ?? '');
    if (match[1] != null && boardId == null) return null;
    try {
      final period = uri.queryParameters['period'];
      return GamificationRoute(
        boardId: boardId,
        period: period == null ? null : GamificationPeriod.decode(period),
      );
    } on FormatException {
      return null;
    } on GamificationUnsupportedResponse {
      return null;
    }
  }

  static GamificationRoute? web(String path, Map<String, String> params) {
    final admin = RegExp(
      r'^/admin/plugins/discourse-gamification(?:/leaderboards(?:/(new|[1-9][0-9]*)(?:/edit)?)?)?(?:\.json)?/?$',
    ).firstMatch(path);
    if (admin != null) {
      final target = admin[1];
      final create = target == 'new';
      final boardId = int.tryParse(target ?? '');
      if (target != null && !create && boardId == null) return null;
      return GamificationRoute(admin: true, create: create, boardId: boardId);
    }
    if (RegExp(r'^/admin/plugins/gamification(?:\.json)?/?$').hasMatch(path)) {
      return const GamificationRoute(admin: true);
    }
    final match = RegExp(
      r'^/leaderboard(?:/([1-9][0-9]*))?(?:\.json)?/?$',
    ).firstMatch(path);
    if (match == null) return null;
    final boardId = int.tryParse(match[1] ?? '');
    if (match[1] != null && boardId == null) return null;
    try {
      return GamificationRoute(
        boardId: boardId,
        period: params['period'] == null
            ? null
            : GamificationPeriod.decode(params['period']),
      );
    } on GamificationUnsupportedResponse {
      return null;
    }
  }
}
