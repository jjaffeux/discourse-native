part of 'discourse_api.dart';

final class DiscourseTopicApi {
  const DiscourseTopicApi(this._transport, this._models);

  final DiscourseTransport _transport;
  final DiscourseModelCodec _models;

  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    final body = await _getObject(
      Uri.parse('$siteUrl$path'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    return _models.topicList(body, siteUrl);
  }

  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
  }) async {
    _requirePositiveId(id, 'id');
    if (postNumber != null) {
      _requirePositiveId(postNumber, 'postNumber');
    }
    final query = <String, String>{
      if (postNumber != null) 'post_number': '$postNumber',
      if (summary) 'summary': 'true',
    };
    final body = await _getObject(
      // Topic ids are stable; slugs are presentation metadata and can become
      // stale after a title change. Discourse redirects `/t/{old-slug}/{id}`
      // to the current slug, while the authenticated transport deliberately
      // refuses automatic redirects. Its id-only JSON route skips that
      // canonicalization, and `post_number` keeps the numbered form
      // unambiguous with `/t/{slug}/{id}`.
      Uri.parse(
        '$siteUrl/t/$id.json',
      ).replace(queryParameters: query.isEmpty ? null : query),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    return _models.topic(body, siteUrl);
  }

  Future<void> recordTopicRead({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required int postNumber,
    int milliseconds = 500,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    _requirePositiveId(postNumber, 'postNumber');
    if (milliseconds <= 0) {
      throw RangeError.value(milliseconds, 'milliseconds', 'Must be positive.');
    }
    await _write(
      Uri.parse('$siteUrl/topics/timings.json'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'topic_id': topicId,
        'topic_time': milliseconds,
        'timings': {'$postNumber': milliseconds},
      },
    );
  }

  Future<void> updateTopicNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required TopicNotificationLevel notificationLevel,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    await _write(
      Uri.parse('$siteUrl/t/$topicId/notifications'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {'notification_level': notificationLevel.value},
    );
  }

  Future<void> updateTopicPinForUser({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required bool pinned,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    await _write(
      Uri.parse('$siteUrl/t/$topicId/${pinned ? 're-pin' : 'clear-pin'}'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  Future<void> updateTopicStatus({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required TopicStatusProperty status,
    required bool enabled,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    await _write(
      Uri.parse('$siteUrl/t/$topicId/status'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'status': status.wireName, 'enabled': enabled},
    );
  }

  Future<void> deleteTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    await _write(
      Uri.parse('$siteUrl/t/$topicId.json'),
      siteUrl: siteUrl,
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: {'context': '/t/$topicId'},
    );
  }

  Future<void> permanentlyDeleteTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    await _write(
      Uri.parse('$siteUrl/t/$topicId.json'),
      siteUrl: siteUrl,
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: {'context': '/t/$topicId', 'force_destroy': true},
    );
  }

  Future<void> recoverTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    await _write(
      Uri.parse('$siteUrl/t/$topicId/recover.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'context': '/t/$topicId'},
    );
  }

  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  }) async {
    if (ids.isEmpty) return const [];
    _validatePostWindow(topicId, ids);

    return (await _topicPosts(
      siteUrl: siteUrl,
      topicId: topicId,
      ids: ids,
      includeRaw: includeRaw,
      includeSuggested: false,
      apiKey: apiKey,
      clientId: clientId,
    )).posts;
  }

  Future<TopicPostsPayload> topicPosts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    String? apiKey,
    String? clientId,
  }) {
    if (ids.isEmpty) {
      return Future.value((posts: const <Post>[], recommendations: null));
    }
    _validatePostWindow(topicId, ids);
    return _topicPosts(
      siteUrl: siteUrl,
      topicId: topicId,
      ids: ids,
      includeRaw: false,
      includeSuggested: true,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

  Future<TopicPostsPayload> _topicPosts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    required bool includeRaw,
    required bool includeSuggested,
    String? apiKey,
    String? clientId,
  }) async {
    final query = [
      ...ids.map((id) => 'post_ids[]=$id'),
      if (includeRaw) 'include_raw=true',
      if (includeSuggested) 'include_suggested=true',
    ].join('&');
    final body = await _getObject(
      Uri.parse('$siteUrl/t/$topicId/posts.json?$query'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    final stream = jsonObject(body['post_stream']);
    return (
      posts: List<Post>.unmodifiable([
        for (final post in jsonObjects(stream['posts']))
          _models.post(post, siteUrl),
      ]),
      recommendations: _models.topicRecommendations(body, siteUrl),
    );
  }

  Future<PostRevision> postRevision({
    required String siteUrl,
    required int postId,
    int? revision,
    String? apiKey,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    if (revision != null && revision < 2) {
      throw ArgumentError.value(revision, 'revision', 'must be at least 2');
    }
    final target = revision?.toString() ?? 'latest';
    final body = await _getObject(
      Uri.parse('$siteUrl/posts/$postId/revisions/$target.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return PostRevision.fromJson(body, siteUrl);
  }

  Future<void> updateTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required String title,
    required String originalTitle,
    required Iterable<TopicTag> tags,
    required Iterable<TopicTag> originalTags,
    int? categoryId,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    if (categoryId != null) _requirePositiveId(categoryId, 'categoryId');
    await _write(
      Uri.parse('$siteUrl/t/$topicId.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'title': title,
        'category_id': categoryId,
        'tags': tags.map((tag) => tag.toJson()).toList(),
        'original_title': originalTitle,
        'original_tags': originalTags.map((tag) => tag.toJson()).toList(),
      },
    );
  }

  Future<void> updateTopicTags({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required Iterable<TopicTag> tags,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    await _write(
      Uri.parse('$siteUrl/t/$topicId/tags.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'tags': tags.map((tag) => tag.toJson()).toList()},
    );
  }

  Future<void> deletePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    await _write(
      Uri.parse('$siteUrl/posts/$postId.json'),
      siteUrl: siteUrl,
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  Future<({bool allowed, String? reason})> checkPermanentPostDeletion({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    final body = await _getObject(
      Uri.parse('$siteUrl/posts/$postId/permanently_delete_check.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return (
      allowed: body['can_permanently_delete'] == true,
      reason: jsonText(body['reason']),
    );
  }

  Future<void> permanentlyDeletePost({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required int postId,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    _requirePositiveId(postId, 'postId');
    await _write(
      Uri.parse('$siteUrl/posts/$postId.json'),
      siteUrl: siteUrl,
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: {'context': '/t/$topicId', 'force_destroy': true},
    );
  }

  Future<void> deletePosts({
    required String siteUrl,
    required String apiKey,
    required List<int> postIds,
    String? clientId,
  }) async {
    _validateSelectedPostIds(postIds);
    await _write(
      Uri.parse('$siteUrl/posts/destroy_many.json'),
      siteUrl: siteUrl,
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: {'post_ids': postIds, 'agree_with_first_reply_flag': true},
    );
  }

  Future<void> mergePosts({
    required String siteUrl,
    required String apiKey,
    required List<int> postIds,
    String? clientId,
  }) async {
    _validateSelectedPostIds(postIds, minimum: 2);
    await _write(
      Uri.parse('$siteUrl/posts/merge_posts.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'post_ids': postIds},
    );
  }

  Future<String> movePosts({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required List<int> postIds,
    int? destinationTopicId,
    String? title,
    int? categoryId,
    List<int> tagIds = const [],
    bool chronologicalOrder = false,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    _validateSelectedPostIds(postIds);
    if (destinationTopicId != null) {
      _requirePositiveId(destinationTopicId, 'destinationTopicId');
    }
    if (categoryId != null) _requirePositiveId(categoryId, 'categoryId');
    if (tagIds.any((id) => id <= 0)) {
      throw ArgumentError.value(tagIds, 'tagIds', 'must contain positive ids');
    }
    final trimmedTitle = title?.trim();
    if ((destinationTopicId == null) ==
        (trimmedTitle == null || trimmedTitle.isEmpty)) {
      throw ArgumentError(
        'Exactly one of destinationTopicId or a non-empty title is required.',
      );
    }
    if (destinationTopicId == topicId) {
      throw ArgumentError.value(
        destinationTopicId,
        'destinationTopicId',
        'must differ from topicId',
      );
    }

    final body = await _write(
      Uri.parse('$siteUrl/t/$topicId/move-posts.json'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'post_ids': postIds,
        'destination_topic_id': ?destinationTopicId,
        if (trimmedTitle != null && trimmedTitle.isNotEmpty)
          'title': trimmedTitle,
        'category_id': ?categoryId,
        if (tagIds.isNotEmpty) 'tag_ids': tagIds,
        if (destinationTopicId != null)
          'chronological_order': chronologicalOrder,
      },
    );
    final url = jsonText(body['url']);
    if (body['success'] != true || url == null) {
      throw const WriteException(WriteFailure.unreachable);
    }
    return url;
  }

  Future<void> changePostOwners({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required List<int> postIds,
    required String username,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    _validateSelectedPostIds(postIds);
    final trimmedUsername = username.trim();
    if (trimmedUsername.isEmpty) {
      throw ArgumentError.value(
        username.length,
        'username',
        'must not be empty',
      );
    }
    final body = await _write(
      Uri.parse('$siteUrl/t/$topicId/change-owner.json'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {'post_ids': postIds, 'username': trimmedUsername},
    );
    if (body['success'] != true) {
      throw const WriteException(WriteFailure.unreachable);
    }
  }

  Future<void> updatePostWiki({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required bool wiki,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    await _write(
      Uri.parse('$siteUrl/posts/$postId/wiki.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'wiki': wiki},
    );
  }

  Future<void> updatePostLocked({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required bool locked,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    await _write(
      Uri.parse('$siteUrl/posts/$postId/locked.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'locked': locked},
    );
  }

  Future<void> unhidePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    await _write(
      Uri.parse('$siteUrl/posts/$postId/unhide.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  Future<void> updatePostType({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required int postType,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    if (postType != Post.regularPostType &&
        postType != Post.moderatorPostType) {
      throw ArgumentError.value(postType, 'postType', 'must be 1 or 2');
    }
    await _write(
      Uri.parse('$siteUrl/posts/$postId/post_type.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'post_type': postType},
    );
  }

  Future<void> updatePostNotice({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? notice,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    final trimmed = notice?.trim();
    await _write(
      Uri.parse('$siteUrl/posts/$postId/notice.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {if (trimmed != null && trimmed.isNotEmpty) 'notice': trimmed},
    );
  }

  Future<Post?> likePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    return _actedPost(
      await _write(
        Uri.parse('$siteUrl/post_actions.json'),
        siteUrl: siteUrl,
        method: 'POST',
        apiKey: apiKey,
        clientId: clientId,
        body: {'id': postId, 'post_action_type_id': Post.likeActionId},
      ),
      siteUrl,
    );
  }

  Future<Post> createPostFlag({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required int postActionTypeId,
    String? message,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    _requirePositiveId(postActionTypeId, 'postActionTypeId');
    final post = _actedPost(
      await _write(
        Uri.parse('$siteUrl/post_actions.json'),
        siteUrl: siteUrl,
        method: 'POST',
        apiKey: apiKey,
        clientId: clientId,
        body: {
          'id': postId,
          'post_action_type_id': postActionTypeId,
          'message': ?message,
        },
      ),
      siteUrl,
    );
    if (post == null) {
      throw const WriteException(WriteFailure.unreachable);
    }
    return post;
  }

  Future<void> createTopicFlag({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required int postActionTypeId,
    String? message,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    _requirePositiveId(postActionTypeId, 'postActionTypeId');
    await _write(
      Uri.parse('$siteUrl/post_actions.json'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'id': topicId,
        'post_action_type_id': postActionTypeId,
        'flag_topic': true,
        'message': ?message,
      },
    );
  }

  Future<Post?> unlikePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    return _actedPost(
      await _write(
        Uri.parse(
          '$siteUrl/post_actions/$postId.json'
          '?post_action_type_id=${Post.likeActionId}',
        ),
        siteUrl: siteUrl,
        method: 'DELETE',
        apiKey: apiKey,
        clientId: clientId,
        body: const {},
      ),
      siteUrl,
    );
  }

  Post? _actedPost(Map<String, dynamic> body, String siteUrl) =>
      body['id'] == null ? null : _models.post(body, siteUrl);
  Future<PostLikers> postLikers({
    required String siteUrl,
    required int postId,
    int limit = 25,
    String? apiKey,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    if (limit < 1 || limit > PostLikers.maximumPageSize) {
      throw RangeError.range(limit, 1, PostLikers.maximumPageSize, 'limit');
    }
    final body = await _getObject(
      Uri.parse(
        '$siteUrl/post_action_users.json'
        '?id=$postId&post_action_type_id=${Post.likeActionId}&limit=$limit',
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    return PostLikers.parse(body, postId: postId, siteUrl: siteUrl);
  }

  Future<void> recoverPost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    await _write(
      Uri.parse('$siteUrl/posts/$postId/recover.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  Future<Map<String, dynamic>> _write(
    Uri url, {
    required String siteUrl,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) => _transport.write(
    url,
    siteUrl: siteUrl,
    method: method,
    apiKey: apiKey,
    body: body,
    clientId: clientId,
  );

  Future<Map<String, dynamic>> _getObject(
    Uri url, {
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) => _transport.getObject(
    url,
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
  );

  static void _requirePositiveId(int value, String name) {
    if (value <= 0) throw RangeError.value(value, name, 'Must be positive.');
  }

  static void _validateSelectedPostIds(List<int> postIds, {int minimum = 1}) {
    if (postIds.length < minimum ||
        postIds.any((id) => id <= 0) ||
        postIds.toSet().length != postIds.length) {
      throw ArgumentError.value(
        postIds,
        'postIds',
        'must contain at least $minimum unique positive ids',
      );
    }
  }

  static void _validatePostWindow(int topicId, List<int> ids) {
    _requirePositiveId(topicId, 'topicId');
    if (ids.length > TopicDetail.maximumInitialPosts) {
      throw RangeError.range(
        ids.length,
        1,
        TopicDetail.maximumInitialPosts,
        'ids.length',
      );
    }
    for (final id in ids) {
      _requirePositiveId(id, 'ids');
    }
  }
}
