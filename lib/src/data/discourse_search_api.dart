part of 'discourse_api.dart';

final class DiscourseSearchApi {
  const DiscourseSearchApi(this._transport);

  final DiscourseTransport _transport;
  static const int maximumSearchTermLength = maximumDiscourseSearchTermLength;
  static const int maximumAutocompleteResults = TopicTagSearch.maximumResults;
  static const int hashtagsPerRequest = maximumDiscourseHashtagsPerRequest;
  static const List<String> hashtagOrder = defaultDiscourseHashtagOrder;

  Future<SearchResults> searchPosts({
    required String siteUrl,
    required String term,
    String? typeFilter,
    int? topicId,
    bool searchForId = false,
    String? restrictToArchetype,
    String? apiKey,
    String? clientId,
  }) async {
    if (term.length > maximumSearchTermLength) {
      // Do not attach the value: search text can contain private names and
      // phrases, and this error may be forwarded to diagnostics.
      throw ArgumentError(
        'Search terms must be at most $maximumSearchTermLength characters.',
      );
    }
    if (topicId != null) _requirePositiveId(topicId, 'topicId');
    final body = await _getObject(
      Uri.parse('$siteUrl/search/query.json').replace(
        queryParameters: {
          'term': term,
          'type_filter': ?typeFilter,
          if (topicId != null) ...{
            'search_context[type]': 'topic',
            'search_context[id]': '$topicId',
          },
          if (searchForId) 'search_for_id': 'true',
          'restrict_to_archetype': ?restrictToArchetype,
        },
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return SearchResults.fromJson(body, siteUrl);
  }

  Future<FoundUsersAndGroups> searchUsersAndGroups({
    required String siteUrl,
    required String term,
    int limit = 6,
    String? apiKey,
    String? clientId,
  }) async {
    _validateAutocompleteRequest(term: term, limit: limit);
    final body = await _getObject(
      Uri.parse('$siteUrl/u/search/users.json').replace(
        queryParameters: {
          if (term.isNotEmpty) 'term': term else 'last_seen_users': 'true',
          'include_groups': 'true',
          'limit': '$limit',
        },
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    return FoundUsersAndGroups(
      users: List.unmodifiable([
        for (final user in jsonObjects(body['users']).take(limit))
          FoundUser.fromJson(user, siteUrl),
      ]),
      groups: List.unmodifiable([
        for (final group in jsonObjects(body['groups']).take(limit))
          FoundGroup.fromJson(group, siteUrl),
      ]),
    );
  }

  Future<List<String>> recentSearches({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    final body = await _getObject(
      Uri.parse('$siteUrl/u/recent-searches.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return List.unmodifiable(
      jsonArray(
        body['recent_searches'],
      ).map(jsonText).whereType<String>().take(5),
    );
  }

  Future<void> resetRecentSearches({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    await _write(
      Uri.parse('$siteUrl/u/recent-searches.json'),
      siteUrl: siteUrl,
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  Future<void> logSearchClick({
    required String siteUrl,
    required String apiKey,
    required int searchLogId,
    required Object resultId,
    required SearchResultKind resultKind,
    String? clientId,
  }) async {
    _requirePositiveId(searchLogId, 'searchLogId');
    await _write(
      Uri.parse('$siteUrl/search/click.json'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'search_log_id': searchLogId,
        'search_result_id': resultId,
        'search_result_type': resultKind.name,
      },
    );
  }

  Future<List<FoundUser>> searchUsers({
    required String siteUrl,
    required String term,
    int? topicId,
    int limit = 10,
    String? apiKey,
    String? clientId,
  }) async {
    _validateAutocompleteRequest(term: term, limit: limit);
    if (topicId != null) _requirePositiveId(topicId, 'topicId');
    final query = {
      if (term.isNotEmpty) 'term': term else 'last_seen_users': 'true',
      'limit': '$limit',
      if (topicId != null) 'topic_id': '$topicId',
    };
    final response = await _get(
      Uri.parse('$siteUrl/u/search/users.json').replace(queryParameters: query),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      return switch (await decodeJsonHttpResponse(response)) {
        {'users': final List<dynamic> users} => [
          for (final user in users.take(limit))
            if (user is Map<String, dynamic>) FoundUser.fromJson(user, siteUrl),
        ],
        _ => const <FoundUser>[],
      };
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  Future<List<TopicFilterLookupValue>> searchFilterTags({
    required String siteUrl,
    required String term,
    int limit = 5,
    String? apiKey,
    String? clientId,
  }) async {
    _validateAutocompleteRequest(term: term, limit: limit);
    final response = await _get(
      Uri.parse(
        '$siteUrl/tags/filter/search.json',
      ).replace(queryParameters: {'q': term, 'limit': '$limit'}),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      final body = await decodeJsonHttpResponse(response);
      if (body is! Map<String, dynamic>) return const [];
      return List.unmodifiable([
        for (final entry in jsonArray(body['results']).take(limit))
          if (entry is Map<String, dynamic>)
            if (jsonText(entry['name']) case final name?)
              TopicFilterLookupValue(
                name: name,
                description: '${jsonInt(entry['count'])}',
              ),
      ]);
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  Future<List<TopicFilterLookupValue>> searchFilterTagGroups({
    required String siteUrl,
    required String term,
    int limit = 10,
    String? apiKey,
    String? clientId,
  }) async {
    _validateAutocompleteRequest(term: term, limit: limit);
    final response = await _get(
      Uri.parse(
        '$siteUrl/tag_groups/filter/search.json',
      ).replace(queryParameters: {'q': term, 'limit': '$limit'}),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      final body = await decodeJsonHttpResponse(response);
      if (body is! Map<String, dynamic>) return const [];
      return List.unmodifiable([
        for (final entry in jsonArray(body['results']).take(limit))
          if (entry is Map<String, dynamic>)
            if (jsonText(entry['name']) case final name?)
              TopicFilterLookupValue(
                name: name,
                description: [
                  for (final tag in jsonArray(
                    entry['tags'],
                  ).take(maximumAutocompleteResults))
                    if (tag is Map<String, dynamic>) ?jsonText(tag['name']),
                ].join(', '),
              ),
      ]);
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  Future<List<TopicFilterLookupValue>> searchFilterGroups({
    required String siteUrl,
    required String term,
    int limit = 10,
    String? apiKey,
    String? clientId,
  }) async {
    _validateAutocompleteRequest(term: term, limit: limit);
    final response = await _get(
      Uri.parse('$siteUrl/groups/search.json').replace(
        queryParameters: {if (term.isNotEmpty) 'term': term, 'limit': '$limit'},
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      final body = await decodeJsonHttpResponse(response);
      if (body is! List<dynamic>) return const [];
      return List.unmodifiable([
        for (final item in body.take(limit))
          if (item is Map<String, dynamic>)
            if (jsonText(item['name']) case final name?)
              TopicFilterLookupValue(
                name: name,
                description: jsonText(item['full_name']) ?? name,
              ),
      ]);
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  Future<List<FoundHashtag>> searchHashtags({
    required String siteUrl,
    required String term,
    List<String> order = hashtagOrder,
    String? apiKey,
    String? clientId,
  }) async {
    _validateComposerLookupValue(term, allowEmpty: true);
    _validateHashtagOrder(order);
    final response = await _get(
      Uri.parse('$siteUrl/hashtags/search.json').replace(
        // `<String, dynamic>` so the list is emitted as a repeated parameter.
        // A `Map<String, String>` would stringify it to `[category, tag]` and
        // the site would reject the lot.
        queryParameters: <String, dynamic>{'term': term, 'order[]': order},
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      return switch (await decodeJsonHttpResponse(response)) {
        {'results': final List<dynamic> results} => [
          for (final item in results.take(maximumAutocompleteResults))
            if (item is Map<String, dynamic>) ?FoundHashtag.fromJson(item),
        ],
        _ => const <FoundHashtag>[],
      };
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  Future<List<FoundHashtag>> lookupHashtags({
    required String siteUrl,
    required Iterable<String> refs,
    List<String> order = hashtagOrder,
    String? apiKey,
    String? clientId,
  }) async {
    _validateHashtagOrder(order);
    final slugs = refs.take(hashtagsPerRequest).toList(growable: false);
    if (slugs.isEmpty) return const [];
    for (final slug in slugs) {
      _validateComposerLookupValue(slug);
    }
    final requested = slugs.toSet();

    final response = await _get(
      Uri.parse('$siteUrl/hashtags.json').replace(
        queryParameters: <String, dynamic>{'slugs[]': slugs, 'order[]': order},
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      final body = await decodeJsonHttpResponse(response);
      if (body is! Map<String, dynamic>) return const [];
      return <FoundHashtag>[
        for (final entry in body.values)
          if (entry is List<dynamic>)
            for (final item in entry)
              if (item is Map<String, dynamic>)
                if (FoundHashtag.fromJson(item) case final hashtag?
                    when requested.contains(hashtag.ref))
                  hashtag,
      ].take(hashtagsPerRequest).toList(growable: false);
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  Future<Set<String>> checkMentions({
    required String siteUrl,
    required Iterable<String> names,
    int? topicId,
    String? apiKey,
    String? clientId,
  }) async {
    final asked = names.take(hashtagsPerRequest).toList(growable: false);
    if (asked.isEmpty) return const {};
    for (final name in asked) {
      _validateComposerLookupValue(name);
    }
    if (topicId != null) _requirePositiveId(topicId, 'topicId');
    final requested = asked.toSet();

    final response = await _get(
      Uri.parse('$siteUrl/composer/mentions').replace(
        queryParameters: <String, dynamic>{
          'names[]': asked,
          if (topicId != null) 'topic_id': '$topicId',
        },
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      final body = await decodeJsonHttpResponse(response);
      if (body is! Map<String, dynamic>) return const {};
      return {
        for (final name in jsonArray(body['users']))
          if (name is String && requested.contains(name)) name,
        for (final name in jsonObject(body['groups']).keys)
          if (requested.contains(name)) name,
      };
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
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

  Future<http.Response> _get(
    Uri url, {
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) =>
      _transport.get(url, siteUrl: siteUrl, apiKey: apiKey, clientId: clientId);

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

  static void _validateHashtagOrder(List<String> order) {
    if (order.isEmpty || order.length > hashtagsPerRequest) {
      throw RangeError.range(
        order.length,
        1,
        hashtagsPerRequest,
        'order.length',
      );
    }
  }

  static void _requirePositiveId(int value, String name) {
    if (value <= 0) throw RangeError.value(value, name, 'Must be positive.');
  }

  static void _validateComposerLookupValue(
    String value, {
    bool allowEmpty = false,
  }) {
    if ((!allowEmpty && value.isEmpty) ||
        value.length > maximumSearchTermLength) {
      throw ArgumentError(
        'Composer lookup values must be ${allowEmpty ? 'at most' : 'between 1 and'} '
        '$maximumSearchTermLength characters.',
      );
    }
  }

  static void _validateAutocompleteRequest({
    required String term,
    required int limit,
  }) {
    if (term.length > maximumSearchTermLength) {
      throw ArgumentError(
        'Autocomplete terms must be at most '
        '$maximumSearchTermLength characters.',
      );
    }
    if (limit < 1 || limit > maximumAutocompleteResults) {
      throw RangeError.range(limit, 1, maximumAutocompleteResults, 'limit');
    }
  }
}
