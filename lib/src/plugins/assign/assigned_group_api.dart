import '../../data/plugin_transport.dart';
import '../../models/topic.dart';
import '../../plugin_api/discourse_model_codec.dart';
import 'assigned_group.dart';

/// Read contract for the group assignment dashboard.
abstract interface class AssignedGroupApi {
  Future<AssignedGroupMembersPage> members({
    required String siteUrl,
    required String apiKey,
    required String groupName,
    String search = '',
    int offset = 0,
    int limit = AssignedGroupApiClient.memberPageSize,
    String? clientId,
  });

  Future<TopicList> topics({
    required String siteUrl,
    required String apiKey,
    required String groupName,
    required AssignedGroupFilter filter,
    AssignedGroupTopicQuery query = const AssignedGroupTopicQuery(),
    String? clientId,
  });

  Future<TopicList> topicPage({
    required String siteUrl,
    required String apiKey,
    required String path,
    String? clientId,
  });
}

/// Authenticated client for discourse-assign's group dashboard endpoints.
final class AssignedGroupApiClient implements AssignedGroupApi {
  const AssignedGroupApiClient(this._transport, this._models);

  static const int memberPageSize = 50;
  static const int maximumMemberPageSize = 1000;
  static const int maximumGroupNameLength = 255;
  static const int maximumMemberSearchLength = 255;
  static const int maximumTopicSearchLength = 500;

  final PluginApiTransport _transport;
  final DiscourseModelCodec _models;

  @override
  Future<AssignedGroupMembersPage> members({
    required String siteUrl,
    required String apiKey,
    required String groupName,
    String search = '',
    int offset = 0,
    int limit = memberPageSize,
    String? clientId,
  }) async {
    final group = _validateGroupName(groupName);
    if (offset < 0) {
      throw RangeError.value(offset, 'offset', 'Must be non-negative.');
    }
    if (limit < 1 || limit > maximumMemberPageSize) {
      throw RangeError.range(limit, 1, maximumMemberPageSize, 'limit');
    }
    final term = search.trim();
    if (term.length > maximumMemberSearchLength) {
      throw ArgumentError.value(
        term.length,
        'search',
        'Member searches must be at most $maximumMemberSearchLength characters.',
      );
    }

    final path = Uri(
      path: '/assign/members/${Uri.encodeComponent(group)}.json',
      queryParameters: {
        'offset': '$offset',
        'limit': '$limit',
        if (term.isNotEmpty) 'filter': term,
      },
    ).toString();
    final body = await _transport.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
    return AssignedGroupMembersPage.fromJson(
      body,
      siteUrl,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<TopicList> topics({
    required String siteUrl,
    required String apiKey,
    required String groupName,
    required AssignedGroupFilter filter,
    AssignedGroupTopicQuery query = const AssignedGroupTopicQuery(),
    String? clientId,
  }) async {
    final group = _validateGroupName(groupName);
    final search = query.search.trim();
    if (search.length > maximumTopicSearchLength) {
      throw ArgumentError.value(
        search.length,
        'query.search',
        'Topic searches must be at most $maximumTopicSearchLength characters.',
      );
    }

    final endpoint = switch (filter) {
      AssignedGroupEveryoneFilter() || AssignedGroupDirectFilter() =>
        '/topics/group-topics-assigned/${Uri.encodeComponent(group)}.json',
      AssignedGroupMemberFilter(:final usernameLower) =>
        '/topics/messages-assigned/'
            '${Uri.encodeComponent(usernameLower)}.json',
    };
    final direct = filter is! AssignedGroupEveryoneFilter;
    final path = Uri(
      path: endpoint,
      queryParameters: {
        if (direct) 'direct': 'true',
        if (query.order case final order?) 'order': order.wireName,
        if (query.ascending) 'ascending': 'true',
        if (search.isNotEmpty) 'search': search,
      },
    ).toString();
    return _topicList(
      siteUrl: siteUrl,
      apiKey: apiKey,
      path: path,
      clientId: clientId,
    );
  }

  @override
  Future<TopicList> topicPage({
    required String siteUrl,
    required String apiKey,
    required String path,
    String? clientId,
  }) {
    final safePath = TopicList.asJsonPath(path);
    if (safePath == null) {
      throw ArgumentError.value(path, 'path', 'Invalid topic-list cursor.');
    }
    return _topicList(
      siteUrl: siteUrl,
      apiKey: apiKey,
      path: safePath,
      clientId: clientId,
    );
  }

  Future<TopicList> _topicList({
    required String siteUrl,
    required String apiKey,
    required String path,
    String? clientId,
  }) async {
    final body = await _transport.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
    return _models.topicList(body, siteUrl);
  }

  static String _validateGroupName(String value) {
    final group = value.trim();
    if (group.isEmpty ||
        group.length > maximumGroupNameLength ||
        group.contains('/')) {
      throw ArgumentError.value(value, 'groupName', 'Invalid group name.');
    }
    return group;
  }
}
