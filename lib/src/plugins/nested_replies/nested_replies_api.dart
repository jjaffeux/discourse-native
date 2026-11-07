import 'package:discourse_native/discourse_plugin_sdk.dart';

import 'nested_replies_data.dart';

final class NestedRepliesApi {
  const NestedRepliesApi(this._transport, this._models);

  final PluginApiTransport _transport;
  final DiscourseModelCodec _models;

  Future<NestedRootPage> roots({
    required String siteUrl,
    required int topicId,
    required String slug,
    required PluginRequestCredentials credentials,
    required NestedRepliesSort sort,
    int page = 0,
    bool trackVisit = false,
  }) async {
    final json =
        await _get(siteUrl, '${_base(slug, topicId)}.json', credentials, {
          'sort': sort.wireValue,
          'page': _page(page).toString(),
          if (trackVisit) 'track_visit': 'true',
        });
    final decoder = _TreeDecoder(_models, siteUrl, topicId);
    final roots = decoder.nodes(json['roots']);
    final op = json['op_post'] == null ? null : decoder.node(json['op_post']);
    return NestedRootPage(
      roots: roots,
      posts: decoder.posts.values,
      page: _responsePage(json, page),
      hasMore: _requiredBool(json, 'has_more_roots'),
      topicMetadata: _topic(json['topic'], topicId, required: page == 0),
      op: op,
      requestedSort: NestedRepliesSort.parse(json['sort']),
      effectiveSort: NestedRepliesSort.parse(json['effective_sort']),
      messageBusLastId: _cursor(json['message_bus_last_id']),
      pinnedPostIds: _ids(json['pinned_post_ids']),
      recommendations: _recommendations(json),
    );
  }

  Future<NestedChildrenPage> children({
    required String siteUrl,
    required int topicId,
    required String slug,
    required int parentPostNumber,
    required PluginRequestCredentials credentials,
    required NestedRepliesSort sort,
    required int depth,
    int page = 0,
  }) async {
    if (parentPostNumber <= 0 || depth < 1 || depth > 100) {
      throw ArgumentError('Invalid child target or depth');
    }
    final json = await _get(
      siteUrl,
      '${_base(slug, topicId)}/children/$parentPostNumber.json',
      credentials,
      {
        'sort': sort.wireValue,
        'page': _page(page).toString(),
        'depth': depth.toString(),
      },
    );
    final decoder = _TreeDecoder(_models, siteUrl, topicId);
    final children = decoder.nodes(json['children']);
    return NestedChildrenPage(
      children: children,
      posts: decoder.posts.values,
      page: _responsePage(json, page),
      hasMore: _requiredBool(json, 'has_more'),
    );
  }

  /// A core post lookup supplies identity only. Visible content always comes
  /// from the tree endpoint, which applies ignored and deleted visibility.
  Future<NestedContextPage> createdContext({
    required String siteUrl,
    required int topicId,
    required String slug,
    required int postId,
    required PluginRequestCredentials credentials,
    required NestedRepliesSort sort,
  }) async {
    if (postId <= 0) throw ArgumentError.value(postId, 'postId');
    if (topicId <= 0) throw ArgumentError.value(topicId, 'topicId');
    final identity = await _get(
      siteUrl,
      '/posts/$postId.json',
      credentials,
      const {},
    );
    final number = nestedPositiveInt(identity['post_number']);
    if (nestedPositiveInt(identity['topic_id']) != topicId ||
        nestedPositiveInt(identity['id']) != postId ||
        number == null) {
      throw const FormatException('Post belongs to another topic');
    }
    final page = await context(
      siteUrl: siteUrl,
      topicId: topicId,
      slug: slug,
      credentials: credentials,
      sort: sort,
      postNumber: number,
      contextDepth: 0,
    );
    if (page.target.postId != postId) {
      throw const FormatException('Mismatched created post identity');
    }
    return page;
  }

  Future<NestedContextPage> context({
    required String siteUrl,
    required int topicId,
    required String slug,
    required int postNumber,
    required PluginRequestCredentials credentials,
    required NestedRepliesSort sort,
    int? contextDepth,
    bool trackVisit = false,
  }) async {
    if (postNumber <= 0 ||
        (contextDepth != null && (contextDepth < 0 || contextDepth > 100))) {
      throw ArgumentError('Invalid context target or depth');
    }
    final json = await _get(
      siteUrl,
      '${_base(slug, topicId)}/context/$postNumber.json',
      credentials,
      {
        'sort': sort.wireValue,
        if (contextDepth != null) 'context': contextDepth.toString(),
        if (trackVisit) 'track_visit': 'true',
      },
    );
    final decoder = _TreeDecoder(_models, siteUrl, topicId);
    final target = decoder.node(json['target_post']);
    if (target.postNumber != postNumber) {
      throw const FormatException('Mismatched context target');
    }
    final op = json['op_post'] == null ? null : decoder.node(json['op_post']);
    final ancestors = decoder.nodes(json['ancestor_chain']);
    final siblings = <int, List<NestedReplyNode>>{};
    for (final entry in nestedObject(json['siblings']).entries) {
      final parent = int.tryParse(entry.key);
      if (parent == null || parent <= 0) {
        throw const FormatException('Invalid sibling parent');
      }
      siblings[parent] = decoder.nodes(entry.value);
    }
    return NestedContextPage(
      topicMetadata: _topic(json['topic'], topicId, required: true)!,
      op: op,
      target: target,
      ancestors: ancestors,
      siblings: siblings,
      posts: decoder.posts.values,
      ancestorsTruncated: _requiredBool(json, 'ancestors_truncated'),
      effectiveSort: NestedRepliesSort.parse(json['effective_sort']) ?? sort,
      messageBusLastId: _cursor(json['message_bus_last_id']),
      recommendations: _recommendations(json),
    );
  }

  Future<NestedActivityPage> activity({
    required String siteUrl,
    required int topicId,
    required String slug,
    required PluginRequestCredentials credentials,
    int page = 0,
  }) async {
    final json = await _get(
      siteUrl,
      '${_base(slug, topicId)}/activity.json',
      credentials,
      {'page': _page(page).toString()},
    );
    if (json['small_actions'] is! List) {
      throw const FormatException('Invalid activity response');
    }
    final entries = <NestedActivityEntry>[];
    for (final value in json['small_actions'] as List) {
      final entry = nestedObject(value);
      final synthetic = entry['synthetic'] == true;
      final code = entry['action_code'];
      if (code is! String || code.isEmpty) {
        throw const FormatException('Invalid activity action');
      }
      if (!synthetic &&
          (nestedPositiveInt(entry['id']) == null ||
              nestedPositiveInt(entry['post_number']) == null ||
              entry['topic_id'] != topicId)) {
        throw const FormatException('Invalid activity post');
      }
      entries.add(
        NestedActivityEntry(
          synthetic: synthetic,
          actionCode: code,
          createdAt: DateTime.tryParse('${entry['created_at'] ?? ''}'),
          post: synthetic ? null : _models.post(entry, siteUrl),
          username: entry['username'] is String
              ? entry['username'] as String
              : null,
          avatarTemplate: entry['avatar_template'] is String
              ? entry['avatar_template'] as String
              : null,
        ),
      );
    }
    return NestedActivityPage(
      entries: entries,
      hasMore: _requiredBool(json, 'has_more'),
      page: page,
    );
  }

  Future<String> revealIgnored({
    required String siteUrl,
    required int postId,
    required PluginRequestCredentials credentials,
  }) async {
    if (postId <= 0) throw ArgumentError.value(postId, 'postId');
    final json = await _get(
      siteUrl,
      '/posts/$postId/cooked.json',
      credentials,
      const {},
    );
    final cooked = json['cooked'];
    if (cooked is! String) {
      throw const FormatException('Invalid cooked response');
    }
    return cooked;
  }

  Future<List<int>> togglePin({
    required String siteUrl,
    required int topicId,
    required String slug,
    required int postId,
    required PluginRequestCredentials credentials,
  }) async {
    if (postId <= 0) throw ArgumentError.value(postId, 'postId');
    final json = await _write(
      siteUrl,
      '${_base(slug, topicId)}/pin.json',
      credentials,
      'PUT',
      {'post_id': postId},
    );
    if (json['pinned_post_ids'] is! List) {
      throw const FormatException('Invalid pin response');
    }
    return _ids(json['pinned_post_ids']);
  }

  Future<bool> toggleTopic({
    required String siteUrl,
    required int topicId,
    required String slug,
    required bool enabled,
    required PluginRequestCredentials credentials,
  }) async {
    final json = await _write(
      siteUrl,
      '${_base(slug, topicId)}/toggle.json',
      credentials,
      'PUT',
      {'enabled': enabled},
    );
    return _requiredBool(json, 'is_nested_view');
  }

  Future<NestedBulkResult> bulkTopicMode({
    required String siteUrl,
    required Iterable<int> topicIds,
    required bool enabled,
    required PluginRequestCredentials credentials,
  }) async {
    final ids = topicIds.toSet().toList();
    if (ids.isEmpty || ids.any((id) => id <= 0)) {
      throw ArgumentError.value(topicIds, 'topicIds');
    }
    final json = await _write(
      siteUrl,
      '/topics/bulk.json',
      credentials,
      'PUT',
      {
        'topic_ids': ids,
        'operation': {
          'type': enabled ? 'enable_nested_view' : 'disable_nested_view',
        },
      },
    );
    if (json['topic_ids'] is! List) {
      throw const FormatException('Invalid bulk response');
    }
    return NestedBulkResult(
      changedTopicIds: _ids(json['topic_ids']),
      errors: json['errors'],
    );
  }

  Future<NestedCategoryConversion> convertCategory({
    required String siteUrl,
    required int categoryId,
    required PluginRequestCredentials credentials,
  }) async {
    if (categoryId <= 0) throw ArgumentError.value(categoryId, 'categoryId');
    final json = await _write(
      siteUrl,
      '/categories/$categoryId/convert_nested_replies.json',
      credentials,
      'POST',
      const {},
    );
    if (json['success'] != 'OK' || json['converted_topic_count'] is! int) {
      throw const FormatException('Invalid conversion response');
    }
    return NestedCategoryConversion(
      convertedTopicCount: nestedCount(json['converted_topic_count']),
      completed: _requiredBool(json, 'nested_replies_conversion_completed'),
    );
  }

  Future<Map<String, dynamic>> _get(
    String siteUrl,
    String path,
    PluginRequestCredentials credentials,
    Map<String, String> query,
  ) => credentials.run(
    () => _transport.pluginGetJson(
      siteUrl: siteUrl,
      path: query.isEmpty
          ? path
          : Uri.parse(path).replace(queryParameters: query).toString(),
      apiKey: credentials.apiKey,
      clientId: credentials.clientId,
    ),
  );

  Future<Map<String, dynamic>> _write(
    String siteUrl,
    String path,
    PluginRequestCredentials credentials,
    String method,
    Map<String, Object?> body,
  ) {
    final key = credentials.apiKey;
    if (key == null) throw const WriteException(WriteFailure.forbidden);
    return credentials.run(
      () => _transport.pluginWriteJson(
        siteUrl: siteUrl,
        path: path,
        method: method,
        apiKey: key,
        body: body,
        clientId: credentials.clientId,
      ),
    );
  }

  static String _base(String slug, int topicId) {
    if (topicId <= 0) throw ArgumentError.value(topicId, 'topicId');
    final safeSlug = slug.isEmpty ? 'topic' : Uri.encodeComponent(slug);
    return '/n/$safeSlug/$topicId';
  }

  static int _page(int page) {
    if (page < 0 || page > 1000) throw ArgumentError.value(page, 'page');
    return page;
  }

  static int _responsePage(Map<String, dynamic> json, int requested) {
    if (json['page'] != requested) {
      throw const FormatException('Mismatched page');
    }
    return requested;
  }

  static bool _requiredBool(Map<String, dynamic> json, String field) {
    if (json[field] is! bool) throw FormatException('Invalid $field');
    return json[field] as bool;
  }

  static int? _cursor(Object? value) =>
      value is int && value >= -1 ? value : null;

  static List<int> _ids(Object? value) => value is List
      ? List.unmodifiable(value.whereType<int>().where((id) => id > 0).toSet())
      : const [];

  static Map<String, dynamic>? _topic(
    Object? value,
    int topicId, {
    required bool required,
  }) {
    if (value == null && !required) return null;
    final json = nestedObject(value);
    if (json['id'] != topicId) {
      throw const FormatException('Invalid topic metadata');
    }
    return _frozenMap(json);
  }

  static Map<String, dynamic>? _recommendations(Map<String, dynamic> json) {
    const keys = [
      'suggested_topics',
      'suggested_group_name',
      'related_topics',
      'related_messages',
    ];
    if (!keys.any(json.containsKey)) return null;
    return _frozenMap({
      for (final key in keys)
        if (json.containsKey(key)) key: json[key],
    });
  }

  static Map<String, dynamic> _frozenMap(Map<String, dynamic> value) {
    final frozen = freezeJson(value);
    if (!frozen.valid) throw const FormatException('Invalid JSON value');
    return Map<String, dynamic>.unmodifiable(frozen.value as Map);
  }
}

final class _TreeDecoder {
  _TreeDecoder(this.models, this.siteUrl, this.topicId);
  final DiscourseModelCodec models;
  final String siteUrl;
  final int topicId;
  final Map<int, NestedPostPayload> posts = {};
  final Map<int, int> _postNumbers = {};
  final Map<int, int> _postIds = {};

  List<NestedReplyNode> nodes(Object? value, [int depth = 0]) {
    if (value is! List) throw const FormatException('Invalid post list');
    return [for (final child in value) node(child, depth)];
  }

  NestedReplyNode node(Object? value, [int depth = 0]) {
    if (depth > 100) throw const FormatException('Post tree is too deep');
    final json = nestedObject(value);
    final id = nestedPositiveInt(json['id']);
    final number = nestedPositiveInt(json['post_number']);
    if (id == null ||
        number == null ||
        (json.containsKey('topic_id') && json['topic_id'] != topicId)) {
      throw const FormatException('Invalid post identity');
    }
    if ((_postIds[id] != null && _postIds[id] != number) ||
        (_postNumbers[number] != null && _postNumbers[number] != id)) {
      throw const FormatException('Conflicting post identity');
    }
    _postNumbers[number] = id;
    _postIds[id] = number;
    final data = NestedPostData.fromJson(json);
    final children = json.containsKey('children')
        ? nodes(json['children'], depth + 1)
        : const <NestedReplyNode>[];
    posts[id] = NestedPostPayload(
      post: models.post({...json, 'topic_id': topicId}, siteUrl),
      data: data,
    );
    return NestedReplyNode(
      postId: id,
      postNumber: number,
      data: data,
      children: children,
    );
  }
}
