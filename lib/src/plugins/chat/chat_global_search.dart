import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';

GlobalSearchScope get chatSearchScope => GlobalSearchScope.plugin(
  owner: 'chat',
  name: 'chat',
  label: appL10n.chat,
  showAvatar: true,
  singletonFilters: true,
  displayProperties: const {
    GlobalSearchDisplayProperty.excerpt,
    GlobalSearchDisplayProperty.likes,
  },
);

final class ChatGlobalSearch extends GlobalSearchContribution {
  const ChatGlobalSearch() : super('chat');
  @override
  List<GlobalSearchScope> get scopes => [chatSearchScope];
  @override
  List<GlobalSearchFilter> get filters => [
    GlobalSearchFilter(
      id: "chatAuthor",
      lookup: GlobalSearchLookup.users,
      singleIdentifier: true,
      label: appL10n.sentBy,
      scope: chatSearchScope,
      kind: GlobalSearchFilterKind.text,
      icon: "user",
      group: appL10n.people,
      operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
      token: "@",
      placeholder: appL10n.usernameOrMe,
      help: appL10n.findMessagesSentByOnePerson,
    ),
    GlobalSearchFilter(
      id: "chatChannel",
      lookup: GlobalSearchLookup.contributed,
      singleIdentifier: true,
      label: appL10n.channel,
      scope: chatSearchScope,
      kind: GlobalSearchFilterKind.text,
      icon: "hash",
      group: appL10n.where,
      operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
      token: "#",
      placeholder: appL10n.channelSlugOrID,
      help: appL10n.searchOneChannelAvailableToYourAccount,
    ),
    GlobalSearchFilter(
      id: "chatThreads",
      label: appL10n.threadReplies,
      scope: chatSearchScope,
      kind: GlobalSearchFilterKind.choice,
      icon: "post",
      group: appL10n.content,
      operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
      help: appL10n.excludingRepliesStillIncludesMessagesThatStartedAThread,
      choices: [
        GlobalSearchFilterChoice(
          value: "include",
          label: appL10n.includeThreadReplies,
          token: "exclude_threads=false",
        ),
        GlobalSearchFilterChoice(
          value: "exclude",
          label: appL10n.excludeThreadReplies,
          token: "exclude_threads=true",
        ),
      ],
    ),
  ];
  @override
  bool available(
    Map<String, dynamic> settings,
    Map<String, dynamic> user,
    bool authenticated,
  ) =>
      authenticated &&
      settings['chat_enabled'] == true &&
      settings['chat_search_enabled'] == true &&
      user['has_chat_enabled'] == true &&
      user['can_chat'] == true;
  @override
  List<GlobalSearchOrder> orders(GlobalSearchScope scope) =>
      scope == chatSearchScope
      ? [
          GlobalSearchOrder('relevance', appL10n.mostRelevant),
          GlobalSearchOrder('latest', appL10n.latestMessage),
        ]
      : const [];
  @override
  Future<GlobalSearchPage> search(
    GlobalSearchReadContext context,
    GlobalSearchRequest request,
  ) async {
    if (!context.authenticated) {
      throw FormatException(appL10n.chatSearchIsUnavailable);
    }
    final r = request;
    final site = context.siteUrl;
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
          globalSearchConditionToken(
            f,
            username: r.capabilities.username,
            capabilities: r.capabilities,
          ),
    ].where((x) => x.trim().isNotEmpty).join(' ');
    if (terms.isEmpty) {
      return GlobalSearchPage(
        sections: [GlobalSearchSection(scope: chatSearchScope)],
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
    final body = await context.get(
      Uri(path: '/chat/api/search.json', queryParameters: params).toString(),
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
          scope: chatSearchScope,
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
          contextLabel:
              '# ${jsonText(channel['title']) ?? jsonText(channel['name']) ?? jsonText(channel['slug']) ?? ''}',
        ),
      );
    }
    final more = jsonObject(body['meta'])['has_more'] == true;
    return GlobalSearchPage(
      sections: [
        GlobalSearchSection(
          scope: chatSearchScope,
          results: List.unmodifiable(results),
          hasMore: more,
        ),
      ],
      hasMore: more,
      consumedCount: records.length,
    );
  }

  @override
  Future<List<GlobalSearchFilterChoice>> lookup(
    GlobalSearchReadContext context,
    GlobalSearchFilter filter,
    String term,
  ) async {
    if (!context.authenticated || filter.id != 'chatChannel') return const [];
    final body = await context.get(
      Uri(
        path: '/chat/api/channels.json',
        queryParameters: {'filter': term, 'limit': '20'},
      ).toString(),
    );
    return [
      for (final row in jsonObjects(body['channels']).take(30))
        if (jsonText(row['slug']) ?? jsonText(row['name']) case final value?)
          GlobalSearchFilterChoice(
            value: value,
            label: jsonText(row['name']) ?? value,
          ),
    ];
  }
}
