import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_api.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_controller.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_models.dart';
import 'package:flutter/foundation.dart';

const gameSite = 'https://forum.example/community';
Map<String, dynamic> gameBoard({
  int id = 1,
  String name = 'Community champions',
  bool disabled = false,
}) => {
  'id': id,
  'name': name,
  'created_by_id': -1,
  'from_date': null,
  'to_date': null,
  'visible_to_groups_ids': [0],
  'included_groups_ids': <int>[],
  'excluded_groups_ids': <int>[],
  'default_period': 0,
  'updated_at': '2026-11-01T11:00:00Z',
  'period_filter_disabled': disabled,
  'score_overrides': <String, Object?>{},
  'scorable_category_ids': <int>[],
  'created_by': {
    'id': -1,
    'username': 'system',
    'name': 'System',
    'avatar_template': null,
  },
};
Map<String, dynamic> gameUser({int id = 1, int rank = 1, int score = 120}) => {
  'id': id,
  'username': 'member$id',
  'name': 'Member $id',
  'avatar_template': null,
  'total_score': score,
  'position': rank,
};
Map<String, dynamic> gameResponse({
  Map<String, dynamic>? board,
  List<Map<String, dynamic>>? users,
  bool personal = true,
}) => {
  'leaderboard': board ?? gameBoard(),
  'users':
      users ??
      [
        gameUser(),
        gameUser(id: 2, rank: 1, score: 120),
        gameUser(id: 3, rank: 3, score: 0),
      ],
  'personal': personal
      ? {'user': gameUser(id: 88, rank: 12, score: -2), 'position': 12}
      : <String, Object?>{},
};
Map<String, dynamic> gameEvent({
  int id = 1,
  int user = 88,
  int points = -3,
  int? category = 4,
}) => {
  'id': id,
  'user_id': user,
  'points': points,
  'category_id': category,
  'date': '2026-10-30',
  'description': 'Manual adjustment',
  'created_at': '2026-10-30T12:00:00Z',
  'updated_at': '2026-10-30T12:00:00Z',
};
const gameAuth = PluginRequestCredentials(apiKey: 'key', clientId: 'client');

final class GamificationFixture {
  GamificationFixture({
    bool enabled = true,
    bool installed = true,
    bool connected = true,
    bool admin = true,
    DateTime Function()? clock,
  }) {
    config = ValueNotifier(
      SiteConfig(
        plugins: installed
            ? PluginData.none.withValue(
                gamificationSettingsKey,
                GamificationSettings(enabled: enabled),
              )
            : PluginData.none,
      ),
    );
    user = connected
        ? DiscourseUser(username: 'admin', id: 88, admin: admin, staff: true)
        : null;
    requests = PluginTestRequestHost(apiKeys: {if (connected) gameSite: 'key'});
    global = {
      'discourse_gamification_enabled': enabled ? 'true' : 'false',
      'scorable_categories': '',
      'score_ranking_strategy': 'dense_rank',
      for (final rule in GamificationRule.values) rule.setting: '1',
    };
    transport = RecordingPluginTransport(
      responders: {
        'GET /admin/site_settings.json?plugin=discourse-gamification': (_) => {
          'site_settings': [
            for (final e in global.entries)
              {'setting': e.key, 'value': e.value, 'type': 'string'},
          ],
        },
        'PUT /admin/site_settings/bulk_update.json': (request) {
          for (final e in (request.body['settings'] as Map).entries) {
            global[e.key as String] = '${(e.value as Map)['value']}';
          }
          return <String, dynamic>{};
        },
        'GET /admin/plugins/discourse-gamification/leaderboards.json': (_) =>
            adminIndex,
        'GET /admin/plugins/discourse-gamification/leaderboards/1.json': (_) =>
            {'leaderboard': boards.first},
        'POST /admin/plugins/gamification/leaderboard.json': (request) {
          final board = gameBoard(
            id: boards.length + 1,
            name: request.body['name'] as String,
          );
          board['created_by_id'] = request.body['created_by_id'];
          boards.add(board);
          return board;
        },
        'PUT /admin/plugins/gamification/recalculate-scores.json': (_) {
          remaining--;
          return {'success': true};
        },
        'GET /admin/plugins/gamification/score_events.json': (_) => {
          'events': events,
        },
        'POST /admin/plugins/gamification/score_events.json': (request) {
          final event = gameEvent(id: events.length + 1);
          event.addAll(request.body);
          if (event['category_id'] == '') event['category_id'] = null;
          events.add(event);
          return event;
        },
        'PUT /admin/plugins/gamification/score_events.json': (request) {
          final event = events.firstWhere((e) => e['id'] == request.body['id']);
          event.addAll(request.body);
          if (event['category_id'] == '') event['category_id'] = null;
          return {'success': true};
        },
        'GET /categories/search.json?term=&include_subcategories=true&limit=100':
            (_) => {
              'categories': [
                {'id': 4, 'name': 'General'},
                {'id': 5, 'name': 'Support'},
              ],
            },
      },
    );
    for (final id in [1, 2, 3]) {
      transport
              .responders['PUT /admin/plugins/gamification/leaderboard/$id.json'] =
          (request) {
            boards.firstWhere((b) => b['id'] == id).addAll(request.body);
            return {'success': true};
          };
      transport
              .responders['DELETE /admin/plugins/gamification/leaderboard/$id.json'] =
          (_) {
            boards.removeWhere((b) => b['id'] == id);
            return {'success': true};
          };
    }
    for (final suffix in [
      '',
      ...GamificationPeriod.values.map((p) => '&period=${p.wire}'),
    ]) {
      transport.responders['GET /leaderboard/?format=json&page=0$suffix'] =
          (_) => publicResponse;
      transport.responders['GET /leaderboard/?format=json&page=1$suffix'] =
          (_) => gameResponse(users: []);
      transport.responders['GET /leaderboard/1.json?page=0$suffix'] = (_) =>
          publicResponse;
    }
    controller = GamificationController(
      api: GamificationApi(transport),
      requests: requests,
      siteState: PluginSiteStateHost(
        currentUserFor: (_) => user,
        siteConfigFor: (_) => config.value,
        siteConfigListenableFor: (_) => config,
      ),
      now: clock ?? () => DateTime.utc(2026, 11, 1, 0, 10),
    );
  }
  late final ValueNotifier<SiteConfig> config;
  DiscourseUser? user;
  late final PluginTestRequestHost requests;
  late final RecordingPluginTransport transport;
  late final GamificationController controller;
  late final Map<String, String> global;
  final boards = [gameBoard()];
  final events = [gameEvent()];
  int remaining = 5;
  Map<String, dynamic> publicResponse = gameResponse();
  Map<String, dynamic> get adminIndex => {
    'gamification_leaderboards': boards,
    'gamification_groups': [
      {'id': 0, 'name': 'everyone'},
      {'id': 10, 'name': 'members'},
    ],
    'gamification_recalculate_scores_remaining': remaining,
  };
  void disable() => config.value = const SiteConfig(plugins: PluginData.none);
  void dispose() {
    controller.dispose();
    config.dispose();
  }
}

Future<void> gameFlush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class GamificationTestNavigationHost
    implements PluginRouteNavigationHost {
  GamificationTestNavigationHost({this.connected = true});
  final bool connected;
  int selected = 0;
  @override
  List<PluginRouteSite> get sites => [
    PluginRouteSite(url: gameSite, title: 'Community', isConnected: connected),
    PluginRouteSite(
      url: 'https://second.example/forum',
      title: 'Second',
      isConnected: connected,
    ),
  ];
  @override
  PluginRouteSite get currentSite => sites[selected];
  @override
  String? get activeTabId => 'gamification-tab';
  @override
  ContentRoute? currentContent;
  @override
  void selectInstance(int index) {
    selected = index;
  }

  @override
  bool pushContent(
    ContentRoute route, {
    String? siteUrl,
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
    void Function()? onNavigated,
    void Function(String tabId)? onOpened,
  }) {
    if (siteUrl != null && currentSite.url != siteUrl) {
      final index = sites.indexWhere((site) => site.url == siteUrl);
      if (index < 0) return false;
      selectInstance(index);
    }
    currentContent = route;
    if (currentContent?.sameDestinationAs(route) == true) onNavigated?.call();
    return true;
  }

  @override
  void replaceCurrentContent(ContentRoute route) {
    currentContent = route;
  }

  @override
  void openTopicPost({
    required String siteUrl,
    required int topicId,
    required int postNumber,
    bool highlight = false,
  }) {}
}
