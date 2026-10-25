import 'dart:convert';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/boards/boards_api.dart';
import 'package:discourse_native/src/plugins/boards/boards_controller.dart';
import 'package:discourse_native/src/plugins/boards/boards_data.dart';
import 'package:discourse_native/src/plugins/boards/boards_navigation.dart';

const boardsSite = 'https://forum.example/community';

Map<String, dynamic> boardFixtureJson({
  bool canWrite = true,
  bool archived = false,
  String sort = 'priority',
  int extraCards = 0,
}) => {
  'board': {
    'id': 1,
    'name': 'Product roadmap',
    'slug': 'product-roadmap',
    'can_write': canWrite,
    'can_manage': canWrite,
    'archived': archived,
    'require_confirmation': false,
    'show_tags': true,
    'columns': [
      {'id': 10, 'title': 'Backlog'},
    ],
  },
  'columns': [
    {
      'id': 10,
      'title': 'Backlog',
      'default_sort': sort,
      'cards': [
        {
          'id': 101,
          'board_id': 1,
          'column_id': 10,
          'card_type': 'topic',
          'topic_id': 500,
          'position': 0,
          'topic': {
            'id': 500,
            'title': 'Improve search',
            'category_id': 5,
            'tags': ['planned'],
            'posts_count': 3,
          },
        },
        {
          'id': 102,
          'board_id': 1,
          'column_id': 10,
          'card_type': 'floater',
          'title': 'Write release notes',
          'notes': 'Review the release with the team.',
          'tags': [
            {'id': 3, 'name': 'docs'},
          ],
          'position': 65536,
        },
        for (var i = 0; i < extraCards; i++)
          {
            'id': 200 + i,
            'column_id': 10,
            'card_type': 'floater',
            'title': 'Task ${i + 1}',
            'position': (i + 2) * 65536,
          },
      ],
    },
    {
      'id': 11,
      'title': 'In progress',
      'default_sort': 'priority',
      'tag_name': 'doing',
      'cards': <Object?>[],
    },
    {
      'id': 12,
      'title': 'Done',
      'default_sort': 'recency',
      'move_to_status': 'closed',
      'cards': <Object?>[],
    },
  ],
};

final class BoardsFixture {
  BoardsFixture({
    bool enabled = true,
    bool connected = true,
    Map<String, dynamic>? json,
  }) {
    config = SiteConfig(
      plugins: PluginData.none.withValue(
        boardsSettingsKey,
        BoardsSettings(enabled: enabled),
      ),
    );
    data = (jsonDecode(jsonEncode(json ?? boardFixtureJson())) as Map)
        .cast<String, dynamic>();
    requests = PluginTestRequestHost(
      apiKeys: {if (connected) boardsSite: 'key'},
    );
    transport = RecordingPluginTransport(
      responders: {
        'GET /boards/api/boards.json': (_) => {
          'boards': [data['board']],
        },
        'GET /boards/api/boards/1.json': (_) => data,
        'PUT /boards/api/boards/1/check-constraint-mismatches': (_) => {
          'categories_needed': <int>[],
          'tags_needed': <String>[],
          'constraints_need_fixing': false,
        },
        'PUT /boards/api/boards/1/cards/101': _move,
        'PUT /boards/api/boards/1/cards/102': _move,
        'POST /boards/api/boards/1/cards': _create,
        'DELETE /boards/api/boards/1/cards/102': (_) {
          for (final column in columns) {
            (column['cards'] as List).removeWhere(
              (Object? card) => boardObject(card)['id'] == 102,
            );
          }
          return <String, dynamic>{};
        },
      },
    );
    controller = BoardsController(
      api: BoardsApi(transport),
      requests: requests,
      siteState: PluginSiteStateHost(
        currentUserFor: (_) =>
            connected ? const DiscourseUser(username: 'lee', id: 2) : null,
        siteConfigFor: (_) => config,
      ),
      trackers: (_) => live,
      topics: PluginTopicRefreshHost(
        reloadTopic: (_, id) async {
          refreshedTopics.add(id);
        },
      ),
    );
    host = BoardsFixtureNavigation(connected: connected);
    navigation = BoardsNavigation(host: host, controller: controller);
  }
  late SiteConfig config;
  late Map<String, dynamic> data;
  late PluginTestRequestHost requests;
  late RecordingPluginTransport transport;
  late BoardsController controller;
  late BoardsFixtureNavigation host;
  late BoardsNavigation navigation;
  final live = RecordingPluginLiveChannels();
  final refreshedTopics = <int>[];
  List<Map<String, dynamic>> get columns =>
      (data['columns'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> _move(PluginTransportRequest request) {
    final fields = (request.body['card'] as Map).cast<String, dynamic>();
    final id = int.parse(request.path.split('/').last);
    Map<String, dynamic>? held;
    for (final column in columns) {
      final cards = column['cards'] as List;
      for (final raw in cards) {
        if ((raw as Map)['id'] == id) held = (raw).cast<String, dynamic>();
      }
      cards.removeWhere((Object? card) => boardObject(card)['id'] == id);
    }
    final card = held!..addAll(fields);
    final target = columns.firstWhere(
      (column) => column['id'] == card['column_id'],
    );
    (target['cards'] as List).add(card);
    return {'card': card};
  }

  Map<String, dynamic> _create(PluginTransportRequest request) {
    final card = {
      'id': 900,
      'board_id': 1,
      'card_type': 'floater',
      ...boardObject(request.body['card']),
    };
    if (card['topic_id'] case final int topicId) {
      card['card_type'] = 'topic';
      card['topic'] = {'id': topicId, 'title': 'Added topic'};
    }
    (columns.firstWhere((column) => column['id'] == card['column_id'])['cards']
            as List)
        .add(card);
    return {'card': card};
  }

  void dispose() => controller.dispose();
}

final class BoardsFixtureNavigation implements PluginRouteNavigationHost {
  BoardsFixtureNavigation({required this.connected});
  final bool connected;
  int? openedTopic;
  @override
  List<PluginRouteSite> get sites => [
    PluginRouteSite(url: boardsSite, title: 'Forum', isConnected: connected),
  ];
  @override
  PluginRouteSite get currentSite => sites.single;
  @override
  String? get activeTabId => 'board-tab';
  @override
  ContentRoute? currentContent;
  @override
  void selectInstance(int index) {}
  @override
  void pushContent(ContentRoute route) => currentContent = route;
  @override
  void replaceCurrentContent(ContentRoute route) => currentContent = route;
  @override
  void openTopicPost({
    required String siteUrl,
    required int topicId,
    required int postNumber,
    bool highlight = false,
  }) => openedTopic = topicId;
}
