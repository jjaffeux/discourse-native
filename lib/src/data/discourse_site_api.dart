part of 'discourse_api.dart';

final class DiscourseSiteApi {
  const DiscourseSiteApi(this._transport, this._models);

  final DiscourseTransport _transport;
  final DiscourseModelCodec _models;
  static const int minimumApiVersion = 2;
  static const int maximumForumAddressLength = 2048;
  static const int maximumCategorySearchTermLength = 250;
  static const int maximumCategorySearchResults = 25;

  static Uri normalize(String term) {
    var trimmed = term.trim();
    if (trimmed.length > maximumForumAddressLength) {
      // Do not echo or redact a rejected oversized value: it may contain a
      // credential whose terminating delimiter lies beyond any safe prefix.
      throw const SiteLookupException(
        SiteLookupFailure.unreachable,
        'that forum address',
        cause: FormatException('Forum address is too long.'),
      );
    }
    // Do not trim the two slashes that belong to a bare scheme. Turning
    // `https://` into `https:` would make the default-scheme branch reinterpret
    // `https` as a host and send a pointless validation request there.
    final schemeSeparator = trimmed.indexOf('://');
    final minimumEnd = schemeSeparator < 0 ? 0 : schemeSeparator + 3;
    var end = trimmed.length;
    while (end > minimumEnd && trimmed.codeUnitAt(end - 1) == 0x2F) {
      end--;
    }
    if (end != trimmed.length) trimmed = trimmed.substring(0, end);
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)) {
      trimmed = 'https://$trimmed';
    }
    try {
      final url = Uri.parse(trimmed);
      return requireSafeHttpUrl(url);
    } on UnsafeHttpTransportException catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        error.url.toString(),
        cause: error,
        causeStackTrace: stackTrace,
      );
    } on FormatException catch (_, stackTrace) {
      // Uri.parse's exception can retain its complete source, including
      // credentials or query values. Replace it at this user-input boundary.
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        DiagnosticsRedactor.uri(trimmed),
        cause: const FormatException('Invalid forum URL.'),
        causeStackTrace: stackTrace,
      );
    }
  }

  Future<DiscourseInstance> lookup(String term) async {
    // Joined as text, not resolved as an absolute path: a forum served from
    // a subfolder keeps the path the reader typed.
    final probe = Uri.parse('${normalize(term)}/user-api-key/new');

    final DiscourseHeadResponse head;
    try {
      head = await _transport.head(probe);
    } on SiteLookupException {
      rethrow;
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        term,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }

    // A Discourse always has this route; a 404 means we are talking to
    // something else, or to a version that predates the user API.
    if (head.statusCode == 404) {
      throw SiteLookupException(
        SiteLookupFailure.notDiscourse,
        term,
        statusCode: head.statusCode,
      );
    }
    if (head.statusCode != 200) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        term,
        statusCode: head.statusCode,
      );
    }

    final apiVersion =
        int.tryParse(head.headers['auth-api-version'] ?? '') ?? 0;
    if (apiVersion < minimumApiVersion) {
      throw SiteLookupException(SiteLookupFailure.notDiscourse, term);
    }

    // Redirects may have moved us; keep where we landed, not where we started.
    //
    // Unlike DiscourseMobile we keep any port, which it strips — that would
    // break connecting to a site on localhost during development.
    final baseUrl = head.url
        .toString()
        .replaceFirst(RegExp(r'/user-api-key/new/*$'), '')
        .replaceFirst(RegExp(r'/+$'), '');

    final Map<String, dynamic> info;
    try {
      final response = await _transport.request(
        'GET',
        Uri.parse('$baseUrl/site/basic-info.json'),
      );
      if (response.statusCode != 200) {
        throw SiteLookupException(
          SiteLookupFailure.unreachable,
          term,
          statusCode: response.statusCode,
        );
      }
      info = await decodeJsonHttpResponse(response) as Map<String, dynamic>;
    } on SiteLookupException {
      rethrow;
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        term,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }

    final title = jsonText(info['title']);

    return DiscourseInstance(
      url: baseUrl,
      title: title == null || title.isEmpty ? Uri.parse(baseUrl).host : title,
      description: jsonText(info['description']),
      iconUrl: _absoluteIcon(jsonText(info['apple_touch_icon_url']), baseUrl),
      apiVersion: apiVersion,
      loginRequired: info['login_required'] == true,
    );
  }

  Future<SiteAppearance?> siteAppearance({
    required String siteUrl,
    String? username,
    String? apiKey,
    String? clientId,
  }) => _transport.siteAppearance(
    siteUrl: siteUrl,
    username: username,
    apiKey: apiKey,
    clientId: clientId,
  );

  Future<SiteMessageBusBootstrap?> messageBusBootstrap({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    final parsed = Uri.parse(siteUrl);
    final documentUrl = parsed.replace(
      path: parsed.path.endsWith('/') ? parsed.path : '${parsed.path}/',
      query: null,
      fragment: null,
    );
    final response = await _transport.get(
      documentUrl,
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      accept: 'text/html',
    );
    return SiteMessageBusBootstrap.fromHtml(
      response.body,
      siteUrl: siteUrl,
      models: _models,
    );
  }

  Future<SiteConfig> siteConfig({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    final body = await _getObject(
      Uri.parse('$siteUrl/site/settings.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      return _models.siteConfig(body, siteUrl);
    } catch (error, stackTrace) {
      // A payload this cannot read is an answer it cannot use: report it the
      // way every other failure here is reported, rather than letting a decode
      // error escape the contract callers swallow by.
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  Future<Map<String, String>> customEmojis({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    final response = await _get(
      Uri.parse('$siteUrl/site/emoji.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      return switch (await decodeJsonHttpResponse(response)) {
        final Map<String, dynamic> byName => {
          for (final entry in byName.entries)
            if (entry.value is String) entry.key: entry.value as String,
        },
        final List<dynamic> list => {
          for (final item in list)
            if (item case {'name': final String name, 'url': final String url})
              name: url,
        },
        _ => const <String, String>{},
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

  Future<SiteEmojiCatalog> emojiCatalog({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    final response = await _get(
      Uri.parse('$siteUrl/emojis.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      final decoded = await decodeJsonHttpResponse(response);
      if (decoded is! Map<String, dynamic>) return SiteEmojiCatalog.empty;

      final groups = <SiteEmojiGroup>[];
      for (final entry in decoded.entries) {
        if (entry.value is! List<dynamic>) continue;
        final emojis = <SiteEmoji>[];
        for (final row in entry.value as List<dynamic>) {
          if (row is! Map<String, dynamic>) continue;
          final name = row['name'];
          final url = row['url'];
          if (name is! String || name.isEmpty || url is! String) continue;
          final resolved = _absoluteIcon(url, siteUrl);
          if (resolved == null) continue;
          emojis.add(
            SiteEmoji(
              name: name,
              url: resolved,
              tonable: row['tonable'] == true,
            ),
          );
        }
        groups.add(SiteEmojiGroup(id: entry.key, emojis: emojis));
      }
      return SiteEmojiCatalog(groups: groups);
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  Future<Map<String, List<String>>> emojiSearchAliases({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    final response = await _get(
      Uri.parse('$siteUrl/emojis/search-aliases.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      final decoded = await decodeJsonHttpResponse(response);
      if (decoded is! Map<String, dynamic>) return const {};

      final aliases = <String, List<String>>{};
      for (final entry in decoded.entries) {
        if (entry.key.isEmpty || entry.value is! List<dynamic>) continue;
        final unique = <String>{};
        for (final raw in entry.value as List<dynamic>) {
          if (raw is! String) continue;
          final alias = raw.trim();
          if (alias.isNotEmpty) unique.add(alias);
        }
        aliases[entry.key] = List<String>.unmodifiable(unique);
      }
      return Map<String, List<String>>.unmodifiable(aliases);
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  Future<List<TopicCategory>> categories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async => (await loadCategories(
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
    page: page,
  )).categories;
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async {
    if (page < 1) throw RangeError.value(page, 'page', 'Must be positive');

    // Start both page-one requests before yielding. A controller lease is
    // known-current when this method is entered; dispatching the site metadata
    // request only after the category response could send a key whose session
    // was revoked while that response was in flight.
    final categoryRequest = _getObject(
      Uri.parse('$siteUrl/categories.json').replace(
        queryParameters: {
          'include_subcategories': 'true',
          'include_topics': 'true',
          if (page > 1) 'page': '$page',
        },
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    final siteRequest = page > 1
        ? null
        : _categorySiteMetadata(
            siteUrl: siteUrl,
            apiKey: apiKey,
            clientId: clientId,
          );

    final body = await categoryRequest;
    final list = jsonObject(body['category_list']);
    final roots = jsonObjects(list['categories']).toList(growable: false);
    final rootCategoryIds = <int>[
      for (final category in roots)
        if (category['parent_category_id'] == null)
          if (jsonIntOrNull(category['id']) case final id? when id > 0) id,
    ];
    final rawById = <int, Map<String, dynamic>>{};

    for (final category in _flattenCategories(roots)) {
      rawById.putIfAbsent(jsonInt(category['id']), () => category);
    }

    // CategoryList is paginated on sites that lazy-load categories. Core puts
    // a signed-in user's selected sidebar categories and their ancestors in
    // site.json specifically so navigation never loses choices beyond page 1.
    final siteResult = await siteRequest;
    final site = siteResult?.body ?? const <String, dynamic>{};
    for (final category in _flattenCategories(site['categories'])) {
      rawById.putIfAbsent(jsonInt(category['id']), () => category);
    }
    final uncategorizedId = jsonIntOrNull(site['uncategorized_category_id']);

    return CategoryLoadResult(
      [
        for (final entry in rawById.entries)
          TopicCategory.fromJson(
            entry.key == uncategorizedId
                ? {...entry.value, 'is_uncategorized': true}
                : entry.value,
          ),
      ],
      rootCategoryIds: rootCategoryIds,
      complete: siteResult?.complete ?? true,
      canCreateTopic: list['can_create_topic'] == true,
      postActionCatalog: apiKey == null || siteResult?.body == null
          ? null
          : SitePostActionCatalog.fromJson(site),
      siteTopTags: siteResult?.body == null
          ? null
          : _navigationTags(site['navigation_menu_site_top_tags']),
      anonymousDefaultTags: siteResult?.body == null
          ? null
          : _navigationTags(site['anonymous_default_navigation_menu_tags']),
    );
  }

  Future<List<SidebarTag>> tags({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    final body = await _getObject(
      Uri.parse('$siteUrl/tags.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    final byId = <int, SidebarTag>{};

    void add(Object? values) {
      for (final json in jsonObjects(values)) {
        final tag = SidebarTag.fromJson(json);
        if (tag != null) byId.putIfAbsent(tag.id, () => tag);
      }
    }

    add(body['tags']);
    final extras = jsonObject(body['extras']);
    for (final group in jsonObjects(extras['tag_groups'])) {
      add(group['tags']);
    }
    for (final category in jsonObjects(extras['categories'])) {
      add(category['tags']);
    }

    final result = byId.values.toList(growable: false)
      ..sort((left, right) {
        final folded = left.name.toLowerCase().compareTo(
          right.name.toLowerCase(),
        );
        return folded != 0 ? folded : left.name.compareTo(right.name);
      });
    return List.unmodifiable(result);
  }

  Future<List<TopicCategory>> findCategories({
    required String siteUrl,
    required Iterable<int> ids,
    String? apiKey,
    String? clientId,
  }) async {
    final uniqueIds = <int>{};
    for (final id in ids) {
      _requirePositiveId(id, 'categoryId');
      uniqueIds.add(id);
    }
    if (uniqueIds.isEmpty) return const [];

    final body = await _getObject(
      Uri.parse('$siteUrl/categories/find.json').replace(
        queryParameters: {
          'ids[]': uniqueIds.map((id) => '$id').toList(growable: false),
        },
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return List.unmodifiable([
      for (final category in jsonObjects(body['categories']))
        TopicCategory.fromJson(category),
    ]);
  }

  Future<List<TopicCategory>> searchCategories({
    required String siteUrl,
    required String term,
    required String apiKey,
    bool includeUncategorized = true,
    String? clientId,
  }) async {
    final normalized = term.trim();
    final bounded = normalized.length <= maximumCategorySearchTermLength
        ? normalized
        : normalized.substring(0, maximumCategorySearchTermLength);
    final body = await _transport.postObject(
      Uri.parse('$siteUrl/categories/search.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'term': bounded,
        'include_uncategorized': includeUncategorized,
        'include_subcategories': true,
        'limit': maximumCategorySearchResults,
      },
    );
    return List.unmodifiable([
      for (final category in jsonObjects(body['categories']))
        TopicCategory.fromJson(category),
    ]);
  }

  Future<void> updateCategoryNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int categoryId,
    required CategoryNotificationLevel notificationLevel,
    String? clientId,
  }) async {
    _requirePositiveId(categoryId, 'categoryId');
    await _transport.write(
      Uri.parse('$siteUrl/category/$categoryId/notifications'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {'notification_level': notificationLevel.value},
    );
  }

  Future<({Map<String, dynamic>? body, bool complete})> _categorySiteMetadata({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    try {
      final body = await _getObject(
        Uri.parse('$siteUrl/site.json'),
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
      );
      return (body: body, complete: true);
    } on SiteLookupException {
      return (body: null, complete: false);
    }
  }

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

  static void _requirePositiveId(int value, String name) {
    if (value <= 0) throw RangeError.value(value, name, 'Must be positive.');
  }

  static String? _absoluteIcon(String? icon, String baseUrl) {
    if (icon == null || icon.isEmpty) return null;
    if (icon.startsWith('//')) {
      final scheme = Uri.tryParse(baseUrl)?.scheme;
      return '${scheme == null || scheme.isEmpty ? 'https' : scheme}:$icon';
    }
    if (icon.startsWith('http://') || icon.startsWith('https://')) return icon;
    return '$baseUrl${icon.startsWith('/') ? '' : '/'}$icon';
  }

  static Iterable<Map<String, dynamic>> _flattenCategories(
    Object? categories,
  ) sync* {
    final pending = <Map<String, dynamic>>[];

    void pushReversed(Object? value) {
      final values = jsonArray(value);
      for (var index = values.length - 1; index >= 0; index--) {
        final entry = values[index];
        if (entry is Map<String, dynamic>) pending.add(entry);
      }
    }

    pushReversed(categories);
    while (pending.isNotEmpty) {
      final category = pending.removeLast();
      yield category;
      pushReversed(category['subcategory_list']);
    }
  }

  static List<SidebarTag> _navigationTags(Object? values) => List.unmodifiable([
    for (final json in jsonObjects(values)) ?SidebarTag.fromJson(json),
  ]);
}
