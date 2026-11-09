import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/discourse_ui.dart';

import 'gamification_models.dart';

final class GamificationApi {
  const GamificationApi(this.transport);
  final PluginApiTransport transport;
  static const _admin = '/admin/plugins/gamification';
  static const _boards = '/admin/plugins/discourse-gamification/leaderboards';
  Future<Map<String, dynamic>> _get(
    String site,
    PluginRequestCredentials auth,
    String path,
  ) => transport.pluginGetJson(
    siteUrl: site,
    path: path,
    apiKey: auth.apiKey,
    clientId: auth.clientId,
  );
  Future<Map<String, dynamic>> _write(
    String site,
    PluginRequestCredentials auth,
    String method,
    String path,
    Map<String, Object?> body,
  ) {
    final key = auth.apiKey;
    if (key == null || key.isEmpty) {
      throw const WriteException(WriteFailure.forbidden, notSent: true);
    }
    return transport.pluginWriteJson(
      siteUrl: site,
      path: path,
      method: method,
      apiKey: key,
      clientId: auth.clientId,
      body: body,
    );
  }

  Future<LeaderboardRead> readLeaderboard(
    String site,
    PluginRequestCredentials auth,
    GamificationQuery query, {
    int page = 0,
    int? previewUserLimit,
  }) async {
    if (page < 0 ||
        (previewUserLimit != null &&
            (page != 0 || previewUserLimit < 1 || previewUserLimit > 100))) {
      throw ArgumentError('Invalid leaderboard page');
    }
    final target = query.target.id;
    final path = target == null ? '/leaderboard/' : '/leaderboard/$target.json';
    final params = <String, String>{
      if (target == null) 'format': 'json',
      'page': '$page',
      if (query.period != null) 'period': query.period!.wire,
      if (previewUserLimit != null) 'user_limit': '$previewUserLimit',
    };
    final j = await _get(
      site,
      auth,
      Uri(path: path, queryParameters: params).toString(),
    );
    if (j['reason'] is String) {
      final raw = j['leaderboard'];
      return LeaderboardPreparing(
        reason: j['reason'] as String,
        board: raw == null ? null : GamificationLeaderboard.decode(raw),
      );
    }
    final board = GamificationLeaderboard.decode(j['leaderboard']);
    if (target != null && board.id != target) {
      throw const FormatException('Wrong leaderboard');
    }
    final users = gameList(j['users'], GamificationRankedUser.decode);
    final personal = gameObject(j['personal']);
    return LeaderboardReady(
      board,
      users,
      auth.apiKey == null
          ? const AnonymousRank()
          : personal['user'] == null
          ? const UnrankedMember()
          : RankedMember(GamificationRankedUser.decode(personal['user'])),
    );
  }

  Future<GamificationAdminIndex> readAdminIndex(
    String site,
    PluginRequestCredentials auth,
  ) async {
    final j = await _get(site, auth, '$_boards.json');
    return GamificationAdminIndex(
      gameList(j['gamification_leaderboards'], GamificationAdminBoard.decode),
      gameList(j['gamification_groups'], GamificationGroup.decode),
      gameInt(j['gamification_recalculate_scores_remaining'], minimum: 0),
    );
  }

  Future<GamificationAdminBoard> readAdminBoard(
    String site,
    PluginRequestCredentials auth,
    int id,
  ) async => GamificationAdminBoard.decode(
    (await _get(site, auth, '$_boards/$id.json'))['leaderboard'],
  );
  Future<GamificationAdminBoard> createBoard(
    String site,
    PluginRequestCredentials auth, {
    required String name,
    required int creatorId,
  }) async {
    final response = await _write(
      site,
      auth,
      'POST',
      '$_admin/leaderboard.json',
      {'name': name, 'created_by_id': creatorId},
    );
    try {
      return GamificationAdminBoard.decode(response);
    } on Object {
      throw const GamificationAmbiguousWrite();
    }
  }

  Future<void> updateBoard(
    String site,
    PluginRequestCredentials auth,
    int id,
    GamificationBoardDraft draft,
  ) async {
    await _write(
      site,
      auth,
      'PUT',
      '$_admin/leaderboard/$id.json',
      draft.toBody(),
    );
  }

  Future<void> deleteBoard(
    String site,
    PluginRequestCredentials auth,
    int id,
  ) async {
    await _write(
      site,
      auth,
      'DELETE',
      '$_admin/leaderboard/$id.json',
      const {},
    );
  }

  Future<void> enqueueRecalculation(
    String site,
    PluginRequestCredentials auth, {
    required DCalendarDate fromDate,
  }) async {
    await _write(site, auth, 'PUT', '$_admin/recalculate-scores.json', {
      'from_date': fromDate.toString(),
    });
  }

  Future<List<GamificationScoreEvent>> readScoreEvents(
    String site,
    PluginRequestCredentials auth,
    ScoreEventQuery query,
  ) async {
    final params = <String, String>{
      if (query.id != null) 'id': '${query.id}',
      if (query.userId != null) 'user_id': '${query.userId}',
      if (query.date != null) 'date': '${query.date}',
    };
    final j = await _get(
      site,
      auth,
      Uri(
        path: '$_admin/score_events.json',
        queryParameters: params.isEmpty ? null : params,
      ).toString(),
    );
    final events = gameList(j['events'], GamificationScoreEvent.decode);
    if (events.length > 100) {
      throw const FormatException('Too many score events');
    }
    return events;
  }

  Future<GamificationScoreEvent> createScoreEvent(
    String site,
    PluginRequestCredentials auth,
    CreateScoreEvent event,
  ) async {
    final response =
        await _write(site, auth, 'POST', '$_admin/score_events.json', {
          'user_id': event.userId,
          'date': '${event.date}',
          'points': event.points,
          'description': event.description ?? '',
          'category_id': event.categoryId ?? '',
        });
    try {
      return GamificationScoreEvent.decode(response);
    } on Object {
      throw const GamificationAmbiguousWrite();
    }
  }

  Future<void> editScoreEvent(
    String site,
    PluginRequestCredentials auth,
    EditScoreEvent event,
  ) async {
    await _write(site, auth, 'PUT', '$_admin/score_events.json', {
      'id': event.id,
      'points': event.points,
      'description': event.description ?? '',
      'category_id': event.categoryId ?? '',
    });
  }

  Future<List<({int id, String name})>> searchCategories(
    String site,
    PluginRequestCredentials auth,
    String term,
  ) async {
    final j = await _get(
      site,
      auth,
      Uri(
        path: '/categories/search.json',
        queryParameters: {
          'term': term,
          'include_subcategories': 'true',
          'limit': '100',
        },
      ).toString(),
    );
    return gameList(j['categories'], (raw) {
      final c = gameObject(raw);
      return (id: gameInt(c['id'], minimum: 1), name: gameString(c['name']));
    });
  }

  Future<GamificationGlobalSettings> readGlobalSettings(
    String site,
    PluginRequestCredentials auth,
  ) async {
    final j = await _get(
      site,
      auth,
      '/admin/site_settings.json?plugin=discourse-gamification',
    );
    final rows = gameList(j['site_settings'], gameObject);
    final settings = {
      for (final row in rows) gameString(row['setting']): row['value'],
    };
    int weight(GamificationRule rule) {
      final value = settings[rule.setting];
      final parsed = value is int ? value : int.tryParse('$value');
      return gameInt(parsed);
    }

    final enabled = settings['discourse_gamification_enabled'];
    if (enabled != true &&
        enabled != false &&
        enabled != 'true' &&
        enabled != 'false') {
      throw const FormatException('Missing plugin setting');
    }
    final categories = gameString(settings['scorable_categories']);
    return GamificationGlobalSettings(
      enabled: enabled == true || enabled == 'true',
      categoryIds: categories.isEmpty
          ? {}
          : gameIds(categories.split('|').map(int.parse).toList()),
      weights: {for (final rule in GamificationRule.values) rule: weight(rule)},
      ranking: GamificationRankingStrategy.decode(
        settings['score_ranking_strategy'],
      ),
    );
  }

  Future<void> saveGlobalSettings(
    String site,
    PluginRequestCredentials auth,
    GamificationGlobalSettings settings,
  ) async {
    if (!settings.valid) throw ArgumentError('Invalid scoring settings');
    await _write(site, auth, 'PUT', '/admin/site_settings/bulk_update.json', {
      'settings': {
        'discourse_gamification_enabled': {'value': settings.enabled},
        'scorable_categories': {'value': settings.categoryIds.join('|')},
        'score_ranking_strategy': {'value': settings.ranking.wire},
        for (final entry in settings.weights.entries)
          entry.key.setting: {'value': entry.value},
      },
    });
  }
}
