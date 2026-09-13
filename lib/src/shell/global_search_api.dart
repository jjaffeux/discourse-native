import 'dart:async';

import '../data/discourse_api_contracts.dart';
import '../data/plugin_transport.dart';
import '../models/json.dart';
import '../models/search_results.dart';
import 'global_search_filters.dart';
import 'global_search_models.dart';

/// Requests retain the transport's same-origin, credential and payload bounds.
class GlobalSearchApi {
  const GlobalSearchApi({required this.transport});
  final PluginApiTransport transport;

  /// Keep recoverable failures actionable without displaying raw URLs or
  /// exception text, which may contain a private search expression.
  static String failureMessage(
    Object exception, {
    String fallback = 'Search could not load. Please try again.',
  }) {
    Object? cause = exception;
    for (var depth = 0; depth < 4 && cause != null; depth++) {
      if (cause is TimeoutException) {
        return 'The search timed out. Please try again.';
      }
      if (cause is SiteLookupException) {
        switch (cause.statusCode) {
          case 409:
            return 'The forum is busy. Please try again.';
          case 429:
            return 'Too many searches. Wait a moment before trying again.';
        }
        cause = cause.cause;
        continue;
      }
      if (cause is FormatException) return cause.message;
      break;
    }
    return fallback;
  }

  Future<Map<String, dynamic>> _get(
    String site,
    String path,
    String? key,
    String? client,
  ) => transport.pluginGetJson(
    siteUrl: site,
    path: path,
    apiKey: key,
    clientId: client,
  );

  Future<GlobalSearchCapabilities> capabilities({
    required String siteUrl,
    required String? apiKey,
    String? clientId,
    required GlobalSearchCapabilities base,
  }) async {
    // Dispatch independent reads together while the caller's session lease is
    // current. No later metadata read reuses credentials after an await.
    Future<Map<String, dynamic>?> optionalRead(String path) async {
      try {
        return await _get(siteUrl, path, apiKey, clientId);
      } catch (_) {
        return null;
      }
    }

    final data = await Future.wait<Map<String, dynamic>?>([
      optionalRead('/site/settings.json'),
      if (apiKey != null)
        optionalRead('/session/current.json')
      else
        Future.value(null),
      if (base.userDirectory)
        optionalRead('/directory-columns.json')
      else
        Future.value(null),
    ]);
    var next = base;
    final settings = data[0], user = jsonObject(data[1]?['current_user']);
    if (settings != null) {
      next = base.copyWith(
        chat:
            (base.chatEligible || base.chat) &&
            settings['chat_enabled'] == true &&
            settings['chat_search_enabled'] == true &&
            apiKey != null &&
            user['has_chat_enabled'] == true &&
            user['can_chat'] == true,
        solved: settings['solved_enabled'] == true,
        assign:
            settings['assign_enabled'] == true &&
            user['can_assign_globally'] == true,
        poll: settings['poll_enabled'] == true,
        voting: settings['topic_voting_enabled'] == true,
        unlisted: base.unlisted || jsonInt(user['trust_level']) >= 4,
      );
    }
    final columns = data[2];
    if (columns != null) {
      next = next.copyWith(
        userOrders: List.unmodifiable(
          {
            'username',
            for (final col in jsonObjects(columns['directory_columns']))
              if (col['enabled'] != false && jsonText(col['name']) != null)
                jsonText(col['name'])!,
          }.toList(),
        ),
      );
    }
    return next;
  }

  Future<GlobalSearchPage> search({
    required String siteUrl,
    required String? apiKey,
    String? clientId,
    required GlobalSearchRequest request,
  }) async {
    final r = request, c = r.capabilities;
    if (r.query.length > 2048 || r.conditions.length > 30) {
      throw const FormatException('Search is too long.');
    }
    for (final condition in r.conditions) {
      if (globalSearchFilter(condition.filterId)?.scope != r.scope) {
        throw const FormatException(
          'Use a filter from the selected search type.',
        );
      }
      final error = validateGlobalSearchCondition(condition, c);
      if (error != null) throw FormatException(error);
    }
    if (globalSearchTerm(r).length > 2048) {
      throw const FormatException('Search is too long.');
    }
    if (r.page < 0 ||
        (r.scope == GlobalSearchScope.forum
            ? r.page >= 10
            : r.scope == GlobalSearchScope.users
            ? r.page > 10
            : r.page > 100) ||
        r.offset < 0) {
      throw const FormatException('Search page is out of range.');
    }
    if (!globalSearchOrders(r.scope, c).any((o) => o.value == r.order)) {
      throw const FormatException('This ordering is unavailable.');
    }
    if (r.scope == GlobalSearchScope.all) {
      final sections = <GlobalSearchSection>[];
      final tasks = <Future<void>>[
        (() async {
          try {
            final body = await _get(
              siteUrl,
              _path('/search/query.json', {'term': r.query}),
              apiKey,
              clientId,
            );
            sections.addAll(_core(body, siteUrl).sections);
          } catch (error) {
            sections.add(
              GlobalSearchSection(
                scope: GlobalSearchScope.forum,
                error: failureMessage(
                  error,
                  fallback: 'Topics, users and groups could not load.',
                ),
              ),
            );
          }
        })(),
        if (c.chat && r.query.trim().isNotEmpty)
          (() async {
            try {
              final page = await _chat(
                siteUrl,
                apiKey,
                clientId,
                GlobalSearchRequest(
                  scope: GlobalSearchScope.chat,
                  query: r.query,
                  capabilities: c,
                ),
              );
              sections.addAll(page.sections);
            } catch (error) {
              sections.add(
                GlobalSearchSection(
                  scope: GlobalSearchScope.chat,
                  error: failureMessage(
                    error,
                    fallback: 'Chat search could not load.',
                  ),
                ),
              );
            }
          })(),
      ];
      await Future.wait(tasks);
      sections.sort((a, b) => a.scope.index.compareTo(b.scope.index));
      return GlobalSearchPage(sections: List.unmodifiable(sections));
    }
    if (r.scope == GlobalSearchScope.chat) {
      return _chat(siteUrl, apiKey, clientId, r);
    }
    if (r.scope == GlobalSearchScope.forum) {
      final body = await _get(
        siteUrl,
        _path('/search.json', {
          'q': globalSearchTerm(r),
          'page': '${r.page + 1}',
        }),
        apiKey,
        clientId,
      );
      return _core(
        body,
        siteUrl,
        scope: GlobalSearchScope.forum,
        canPage: r.page < 9,
      );
    }
    final users = r.scope == GlobalSearchScope.users,
        available = users ? c.userDirectory : c.groupDirectory;
    if (!available) {
      final body = await _get(
        siteUrl,
        _path('/search/query.json', {
          'term': r.query,
          if (users) 'type_filter': 'user',
        }),
        apiKey,
        clientId,
      );
      return _core(body, siteUrl, scope: r.scope, canPage: false);
    }
    final params = <String, String>{
      users ? 'name' : 'filter': r.query,
      'order': r.order,
      'page': '${r.page}',
      if (users) 'period': 'all',
      if (!users || r.ascending) 'asc': '${r.ascending}',
    };
    for (final f in r.conditions) {
      final token = globalSearchConditionToken(f, username: c.username),
          i = token.indexOf('=');
      if (i < 0) continue;
      final key = token.substring(0, i);
      var value = token.substring(i + 1);
      if (params.containsKey(key) &&
          ['exclude_groups', 'exclude_usernames'].contains(key)) {
        final separator = key == 'exclude_groups' ? '|' : ',';
        value = {
          ...params[key]!.split(separator),
          ...value.split(separator),
        }.join(separator);
      }
      params[key] = value;
    }
    final body = await _get(
      siteUrl,
      _path(users ? '/directory_items.json' : '/groups.json', params),
      apiKey,
      clientId,
    );
    final records = jsonObjects(
      body[users ? 'directory_items' : 'groups'],
    ).take(50).toList();
    final results = <GlobalSearchResult>[];
    for (final row in records) {
      final source = users
          ? SearchUserHit.fromJson(jsonObject(row['user']), siteUrl)
          : SearchGroupHit.fromJson(row, siteUrl);
      if (source == null) continue;
      final hit = _result(source);
      results.add(
        GlobalSearchResult(
          id: hit.id,
          scope: hit.scope,
          title: hit.title,
          path: hit.path,
          username: hit.username,
          avatarUrl: hit.avatarUrl,
          source: source,
          excerpt: users
              ? jsonString(jsonObject(row['user'])['title'])
              : SearchExcerpt.fromHtml(
                  jsonString(row['bio_excerpt']),
                ).plainText,
          memberCount: users ? null : jsonIntOrNull(row['user_count']),
          likes: users ? jsonIntOrNull(row['likes_received']) : null,
          replies: users ? jsonIntOrNull(row['post_count']) : null,
        ),
      );
    }
    final metadata = users ? jsonObject(body['meta']) : body;
    final total = jsonIntOrNull(
      metadata[users ? 'total_rows_directory_items' : 'total_rows_groups'],
    );
    final hasMore =
        r.page < (users ? 10 : 100) &&
        records.isNotEmpty &&
        (total != null
            ? (r.offset + records.length) < total
            : jsonText(
                    metadata[users
                        ? 'load_more_directory_items'
                        : 'load_more_groups'],
                  ) !=
                  null);
    return GlobalSearchPage(
      sections: [
        GlobalSearchSection(
          scope: r.scope,
          results: List.unmodifiable(results),
          hasMore: hasMore,
        ),
      ],
      hasMore: hasMore,
      consumedCount: records.length,
      groupMemberOrder: users
          ? null
          : records.isNotEmpty && records.every((r) => r['user_count'] != null),
    );
  }

  Future<GlobalSearchPage> _chat(
    String site,
    String? key,
    String? client,
    GlobalSearchRequest r,
  ) async {
    if (!r.capabilities.chat || key == null) {
      throw const FormatException('Chat search is unavailable.');
    }
    final channelId = r.conditions
        .where((f) => f.filterId == 'chatChannel')
        .map((f) => int.tryParse(f.text))
        .whereType<int>()
        .where((id) => id > 0)
        .firstOrNull;
    final terms = [
      r.query,
      for (final f in r.conditions)
        if (f.filterId != 'chatThreads' &&
            !(f.filterId == 'chatChannel' && channelId != null))
          globalSearchConditionToken(f, username: r.capabilities.username),
    ].where((x) => x.trim().isNotEmpty).join(' ');
    if (terms.isEmpty) {
      return const GlobalSearchPage(
        sections: [GlobalSearchSection(scope: GlobalSearchScope.chat)],
      );
    }
    final params = {
      'query': terms,
      'sort': r.order,
      'offset': '${r.offset}',
      'limit': '20',
      if (channelId != null) 'channel_id': '$channelId',
    };
    for (final f in r.conditions) {
      if (f.filterId == 'chatThreads') {
        params['exclude_threads'] = '${f.text == 'exclude'}';
      }
    }
    final body = await _get(
      site,
      _path('/chat/api/search.json', params),
      key,
      client,
    );
    final records = jsonObjects(body['messages']).take(40).toList(),
        results = <GlobalSearchResult>[];
    for (final row in records) {
      final channel = jsonObject(row['channel']),
          user = jsonObject(row['user']);
      final id = jsonIntOrNull(row['id']),
          channelId = jsonIntOrNull(channel['id']);
      if (id == null ||
          id <= 0 ||
          channelId == null ||
          channelId <= 0 ||
          jsonInt(row['chat_channel_id']) != channelId) {
        continue;
      }
      final username =
              jsonText(user['username']) ?? jsonText(row['username']) ?? '',
          threadId = switch (jsonIntOrNull(row['thread_id'])) {
            final id? when id > 0 => id,
            _ => null,
          };
      final threadSegment = threadId == null ? '' : '/t/$threadId';
      results.add(
        GlobalSearchResult(
          id: 'chat:$id',
          scope: GlobalSearchScope.chat,
          title: jsonText(user['name']) ?? username,
          path:
              '/chat/c/${Uri.encodeComponent(jsonText(channel['slug']) ?? '-')}/$channelId$threadSegment/$id',
          excerpt: SearchExcerpt.fromHtml(
            jsonText(row['excerpt']) ??
                jsonText(row['cooked']) ??
                jsonString(row['message']),
          ).plainText,
          username: username,
          avatarUrl: resolveAvatarUrl(jsonText(user['avatar_template']), site),
          createdAt: jsonDate(row['created_at']),
          channelId: channelId,
          messageId: id,
          threadId: threadId,
          channelTitle:
              jsonText(channel['title']) ??
              jsonText(channel['name']) ??
              jsonText(channel['slug']),
        ),
      );
    }
    final more = jsonObject(body['meta'])['has_more'] == true;
    return GlobalSearchPage(
      sections: [
        GlobalSearchSection(
          scope: GlobalSearchScope.chat,
          results: List.unmodifiable(results),
          hasMore: more,
        ),
      ],
      hasMore: more,
      consumedCount: records.length,
    );
  }

  GlobalSearchPage _core(
    Map<String, dynamic> body,
    String site, {
    GlobalSearchScope? scope,
    bool canPage = true,
  }) {
    final parsed = SearchResults.fromJson(body, site);
    if (parsed.error != null) throw FormatException(parsed.error!);
    final posts = {
          for (final p in jsonObjects(body['posts'])) jsonInt(p['id']): p,
        },
        topics = {
          for (final t in jsonObjects(body['topics'])) jsonInt(t['id']): t,
        };
    final sections = <GlobalSearchSection>[];
    for (final section in parsed.effectiveSections) {
      final target = switch (section.kind) {
        SearchResultKind.topic => GlobalSearchScope.forum,
        SearchResultKind.user => GlobalSearchScope.users,
        SearchResultKind.group => GlobalSearchScope.groups,
        _ => null,
      };
      if (target == null || scope != null && scope != target) continue;
      final rows = <GlobalSearchResult>[];
      for (final source in section.results) {
        final base = _result(source, searchLogId: parsed.searchLogId);
        if (source is SearchPostHit) {
          final post = posts[source.postId] ?? const <String, dynamic>{},
              topic = topics[source.topicId] ?? const <String, dynamic>{};
          rows.add(
            GlobalSearchResult(
              id: base.id,
              scope: target,
              title: base.title,
              path: base.path,
              excerpt: base.excerpt,
              username: base.username,
              avatarUrl: base.avatarUrl,
              source: source,
              categoryId: source.categoryId,
              tags: source.tags.map((t) => t.name).toList(),
              createdAt: source.createdAt,
              likes: jsonIntOrNull(post['like_count']),
              replies: switch (jsonIntOrNull(topic['posts_count'])) {
                final count? when count > 0 => count - 1,
                _ => null,
              },
              searchLogId: parsed.searchLogId,
              privateMessage: source.privateMessage,
              closed: source.closed,
              archived: source.archived,
            ),
          );
        } else {
          rows.add(base);
        }
      }
      sections.add(
        GlobalSearchSection(
          scope: target,
          results: List.unmodifiable(rows),
          hasMore: canPage && section.hasMore,
        ),
      );
    }
    return GlobalSearchPage(
      sections: List.unmodifiable(sections),
      hasMore: sections.any((s) => s.hasMore),
      consumedCount: jsonObjects(body['posts']).length,
    );
  }

  GlobalSearchResult _result(SearchResult source, {int? searchLogId}) =>
      switch (source) {
        SearchPostHit hit => GlobalSearchResult(
          id: 'forum:${hit.postId}',
          scope: GlobalSearchScope.forum,
          title: hit.topicTitle,
          path: hit.path,
          excerpt: hit.excerpt.plainText,
          username: hit.username,
          avatarUrl: hit.avatarUrl,
          source: source,
          searchLogId: searchLogId,
        ),
        SearchUserHit hit => GlobalSearchResult(
          id: 'users:${hit.id}',
          scope: GlobalSearchScope.users,
          title: hit.name ?? hit.username,
          path: hit.path,
          username: hit.username,
          avatarUrl: hit.avatarUrl,
          source: source,
          searchLogId: searchLogId,
        ),
        SearchGroupHit hit => GlobalSearchResult(
          id: 'groups:${hit.id}',
          scope: GlobalSearchScope.groups,
          title: hit.fullName ?? hit.name,
          path: hit.path,
          username: hit.name,
          avatarUrl: hit.flairUrl,
          source: source,
          searchLogId: searchLogId,
        ),
        _ => throw const FormatException('Unsupported search result.'),
      };

  Future<void> clearRecentSearches({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    await transport.pluginWriteJson(
      siteUrl: siteUrl,
      path: '/u/recent-searches.json',
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  Future<List<GlobalSearchFilterChoice>> lookupChoices({
    required String siteUrl,
    required String? apiKey,
    String? clientId,
    required GlobalSearchFilter filter,
    required String term,
  }) async {
    if (filter.choices.isNotEmpty) return filter.choices;
    if (term.length > 255) return const [];
    String path, key;
    if (filter.id == 'category') {
      path = '/site.json';
      key = 'categories';
    } else if (filter.id == 'tags') {
      path = _path('/tags/filter/search.json', {'q': term, 'limit': '20'});
      key = 'results';
    } else if ([
      'authorGroup',
      'groupInbox',
      'userGroup',
      'assignee',
    ].contains(filter.id)) {
      path = _path('/groups.json', {
        'filter': term,
        'order': 'name',
        'asc': 'true',
      });
      key = 'groups';
    } else if (filter.id == 'chatChannel') {
      path = _path('/chat/api/channels.json', {'filter': term, 'limit': '20'});
      key = 'channels';
    } else if ([
      'author',
      'topicAuthor',
      'chatAuthor',
      'userName',
      'groupMember',
      'adminUserMessages',
    ].contains(filter.id)) {
      path = _path('/u/search/users.json', {'term': term, 'limit': '20'});
      key = 'users';
    } else {
      return const [];
    }
    final body = await _get(siteUrl, path, apiKey, clientId);
    if (filter.id == 'category') return _categoryChoices(body, term);
    final rows = jsonObjects(body[key]);
    return List.unmodifiable(
      [
        for (final row in rows)
          if (filter.id == 'tags'
                  ? jsonText(row['name'])
                  : jsonText(row['username']) ??
                        jsonText(row['slug']) ??
                        jsonText(row['name'])
              case final value?)
            if (term.isEmpty ||
                value.toLowerCase().contains(term.toLowerCase()) ||
                jsonString(
                  row['name'],
                ).toLowerCase().contains(term.toLowerCase()))
              GlobalSearchFilterChoice(
                value: value,
                label: jsonText(row['name']) ?? value,
              ),
      ].take(30),
    );
  }

  List<GlobalSearchFilterChoice> _categoryChoices(
    Map<String, dynamic> body,
    String term,
  ) {
    // Core's category: filter accepts IDs. Slugs can repeat under different
    // parents, so identity and the command item key must use the category ID.
    final categories = <int, Map<String, dynamic>>{};
    for (final row in jsonObjects(body['categories'])) {
      final id = jsonIntOrNull(row['id']);
      if (id != null && id > 0) categories[id] = row;
    }
    String labelFor(int id) {
      final names = <String>[], visited = <int>{};
      int? current = id;
      while (current != null && visited.add(current)) {
        final row = categories[current];
        if (row == null) break;
        names.add(jsonText(row['name']) ?? jsonText(row['slug']) ?? '$current');
        current = jsonIntOrNull(row['parent_category_id']);
      }
      return names.reversed.join(' / ');
    }

    final query = term.trim().toLowerCase();
    return List.unmodifiable(
      [
            for (final entry in categories.entries)
              GlobalSearchFilterChoice(
                value: '${entry.key}',
                label: labelFor(entry.key),
              ),
          ]
          .where(
            (choice) =>
                query.isEmpty ||
                choice.value.contains(query) ||
                choice.label.toLowerCase().contains(query) ||
                jsonString(
                  categories[int.parse(choice.value)]?['slug'],
                ).toLowerCase().contains(query),
          )
          .take(30),
    );
  }

  Future<void> logClick({
    required String siteUrl,
    required String apiKey,
    String? clientId,
    required GlobalSearchResult result,
  }) async {
    final source = result.source, logId = result.searchLogId;
    if (source == null || logId == null) return;
    await transport.pluginWriteJson(
      siteUrl: siteUrl,
      path: '/search/click.json',
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'search_log_id': logId,
        'search_result_id': source.id,
        'search_result_type': source.kind.name,
      },
    );
  }

  static String _path(String path, Map<String, String> params) =>
      Uri(path: path, queryParameters: params).toString();
}
