part of 'topic_filter_controller.dart';

/// Presentation over the vocabulary returned by /filter.json. The mockup's
/// search-only operators never become topic-list clauses here.
class TopicFilterMenuField {
  const TopicFilterMenuField(
    this.id,
    this.label,
    this.hint,
    this.group,
    this.icon,
    this.options,
  );
  final String id;
  final String label;
  final String hint;
  final String group;
  final String icon;
  final List<TopicFilterOption> options;

  String get draft => '${options.first.name.split(':').first}:';
  bool get number => options.first.type == 'number';
  bool get date => options.first.type == 'date';
  List<String> get keys =>
      options.map((o) => '${o.name.split(':').first}:').toSet().toList();
}

/// Counts an exact numeric comparison as one field, although the feed API
/// represents it with matching minimum and maximum clauses.
int topicFilterMenuCount(String query) {
  final tokens = splitTopicFilterQuery(query);
  var count = tokens.length;
  for (final token in tokens) {
    final match = RegExp(r'^([\w-]+)-min:(\d+)$').firstMatch(token);
    if (match != null && tokens.contains('${match[1]}-max:${match[2]}')) {
      count--;
    }
  }
  return count;
}

List<TopicFilterMenuField> topicFilterMenuFields(
  List<TopicFilterOption> options,
) {
  final l = appL10n;
  final fields = <TopicFilterMenuField>[];
  void add(
    String id,
    String label,
    String hint,
    String group,
    String icon,
    List<String> keys, {
    bool Function(TopicFilterOption)? where,
  }) {
    final matches = options
        .where(
          (o) =>
              keys.contains(o.name.split(':').first) &&
              (where?.call(o) ?? true),
        )
        .toList();
    if (matches.isEmpty) return;
    fields.add(TopicFilterMenuField(id, label, hint, group, icon, matches));
  }

  add('category', l.category, l.filterCategoryHint, l.where, 'layer-group', [
    'category',
    'categories',
  ]);
  add('tags', l.tags, l.filterTagsHint, l.where, 'tag', [
    'tag',
    'tags',
    'tag-group',
    'tag_group',
  ]);
  add('topic', l.topic, l.filterTopicHint, l.where, 'comments', ['topic']);
  add('author', l.postedBy, l.filterPostedByHint, l.filterWho, 'user', [
    'users',
    'user',
  ]);
  add(
    'starter',
    l.startedBy,
    l.filterStartedByHint,
    l.filterWho,
    'pen-to-square',
    ['created-by'],
  );
  add('group', l.authorSGroup, l.filterGroupHint, l.filterWho, 'users', [
    'group',
    'groups',
  ]);
  add(
    'assigned',
    l.filterAssignedTitle,
    l.filterAssignedHint,
    l.filterWho,
    'user-check',
    ['assigned'],
  );
  add('status', l.status, l.filterStatusHint, l.filterState, 'circle-check', [
    'status',
  ]);
  add('postType', l.postType, l.filterTypeHint, l.filterState, 'file-lines', [
    'in',
  ], where: (o) => o.name == 'in:pinned');
  add('language', l.language, l.filterLanguageHint, l.content, 'language', [
    'locale',
  ]);
  add(
    'posted',
    l.posted,
    l.filterPostedHint,
    l.filterNumbersDates,
    'calendar-days',
    ['created-after', 'created-before'],
  );
  add(
    'replies',
    l.replies,
    l.filterRepliesHint,
    l.filterNumbersDates,
    'reply',
    ['posts-min', 'posts-max'],
  );
  add('views', l.views, l.filterViewsHint, l.filterNumbersDates, 'eye', [
    'views-min',
    'views-max',
  ]);
  add(
    'votes',
    l.filterVotesTitle,
    l.filterVotesHint,
    l.filterNumbersDates,
    'check-to-slot',
    ['votes-min', 'votes-max'],
  );
  add(
    'activity',
    l.myActivity,
    l.filterActivityHint,
    l.filterMine,
    'bookmark',
    ['in'],
    where: (o) => !{'in:', 'in:pinned', 'in:untagged'}.contains(o.name),
  );
  add('order', l.sort, l.filterSortHint, l.staff, 'arrows-up-down', ['order']);
  return fields;
}

String _menuWords(String value) {
  final words = value.replaceAll(RegExp('[-_]'), ' ');
  return words.isEmpty
      ? words
      : '${words[0].toUpperCase()}${words.substring(1)}';
}

extension _TopicFilterMenuSuggestions on TopicFilterSuggestions {
  Future<List<TopicFilterSuggestion>?> _menuSuggestions(
    _FilterSegment segment,
  ) async {
    final fields = topicFilterMenuFields(options);
    final current = fields.where((f) => f.id == menuField).firstOrNull;
    final key = segment.filterName;
    if (key == null) {
      final term = segment.word.toLowerCase();
      return [
        for (final field in fields)
          if (field.label.toLowerCase().contains(term) ||
              field.options.any(
                (o) =>
                    o.name.toLowerCase().contains(term) ||
                    (o.alias?.toLowerCase().contains(term) ?? false),
              ))
            TopicFilterSuggestion(
              name: field.draft,
              displayName: field.label,
              description: field.hint,
              menuField: field.id,
              menuGroup: field.group,
              menuIcon: field.icon,
            ),
      ];
    }
    final field = current != null && current.keys.contains('$key:')
        ? current
        : null;
    if (field == null) return null;
    final value = segment.value ?? '';
    if (field.id == 'tags' && const {'tag', 'tags'}.contains(key)) {
      final groupOption = field.options
          .where((o) => o.type == 'tag_group')
          .firstOrNull;
      final result = <TopicFilterSuggestion>[
        for (final tag
            in (await tags(value)).toList()..sort((a, b) {
              final usage = (int.tryParse(b.description ?? '') ?? 0).compareTo(
                int.tryParse(a.description ?? '') ?? 0,
              );
              return usage != 0
                  ? usage
                  : a.name.toLowerCase().compareTo(b.name.toLowerCase());
            }))
          TopicFilterSuggestion(
            name: '$key:${_ValueSuggester._quoteIfNeeded(tag.name)}',
            displayName: tag.name,
            description: tag.description,
            term: _ValueSuggester._quoteIfNeeded(tag.name),
            menuGroup: appL10n.tags,
          ),
        if (groupOption != null)
          for (final group in await tagGroups(value))
            TopicFilterSuggestion(
              name:
                  '${groupOption.name}${_ValueSuggester._quoteIfNeeded(group.name)}',
              displayName: group.name,
              term: _ValueSuggester._quoteIfNeeded(group.name),
              menuGroup: appL10n.filterTagGroups,
              menuIcon: 'tags',
            ),
        if (value.isEmpty && options.any((o) => o.name == 'in:tagged'))
          TopicFilterSuggestion(
            name: 'in:tagged',
            displayName: appL10n.filterTagged,
            term: 'tagged',
            menuGroup: appL10n.other,
          ),
        if (value.isEmpty && options.any((o) => o.name == 'in:untagged'))
          TopicFilterSuggestion(
            name: 'in:untagged',
            displayName: appL10n.filterUntagged,
            term: 'untagged',
            menuGroup: appL10n.other,
          ),
      ];
      return result;
    }
    if (field.number) {
      final typed = int.tryParse(value);
      final values = typed == null
          ? (field.id == 'replies'
                ? [10, 50, 5]
                : field.id == 'views'
                ? [100, 1000, 50]
                : [5, 20])
          : [typed];
      final minimum = field.options
          .where((o) => o.name.endsWith('-min:'))
          .firstOrNull;
      final maximum = field.options
          .where((o) => o.name.endsWith('-max:'))
          .firstOrNull;
      return [
        for (final n in values) ...[
          if (minimum != null)
            TopicFilterSuggestion(
              name: '${minimum.name}${n + (field.id == 'replies' ? 1 : 0)}',
              displayName: '${_menuWords(appL10n.atLeast)} $n',
              term: '$n',
              replaceKeys: field.keys,
            ),
          if (maximum != null && (typed != null || n == values.last))
            TopicFilterSuggestion(
              name: '${maximum.name}${n + (field.id == 'replies' ? 1 : 0)}',
              displayName: '${_menuWords(appL10n.atMost)} $n',
              term: '$n',
              replaceKeys: field.keys,
            ),
          if (typed != null &&
              field.id != 'views' &&
              minimum != null &&
              maximum != null)
            TopicFilterSuggestion(
              name:
                  '${minimum.name}${n + (field.id == 'replies' ? 1 : 0)} ${maximum.name}${n + (field.id == 'replies' ? 1 : 0)}',
              displayName: '${appL10n.filterExactly} $n',
              term: '$n',
              replaceKeys: field.keys,
            ),
        ],
      ];
    }
    if (field.date) {
      if (menuDateSelected) return const [];
      return [
        for (final relation in ['before', 'after'])
          for (final option in field.options.where(
            (o) => o.name.endsWith('-$relation:'),
          ))
            TopicFilterSuggestion(
              name: option.name,
              displayName: option.name.contains('before')
                  ? appL10n.filterBefore
                  : appL10n.filterAfter,
              menuField: field.id,
              menuIcon: 'calendar-days',
            ),
        for (final days in [7, 30, 365])
          if (field.options.any((o) => o.name.endsWith('-after:')))
            TopicFilterSuggestion(
              name:
                  '${field.options.firstWhere((o) => o.name.endsWith('-after:')).name}$days',
              displayName: days == 7
                  ? appL10n.lastWeek
                  : days == 30
                  ? appL10n.lastMonth
                  : appL10n.lastYear,
              term: '$days',
              replaceKeys: field.keys,
            ),
      ];
    }
    final choices = field.options
        .where((o) => o.name.startsWith('$key:') && o.name != '$key:')
        .toList();
    if (choices.isEmpty) return null;
    final term = value.toLowerCase();
    return [
      for (final option in choices)
        if (option.name.toLowerCase().contains(term) ||
            (option.description?.toLowerCase().contains(term) ?? false))
          TopicFilterSuggestion(
            name: option.name,
            displayName: _menuChoiceLabel(option.name),
            term: option.name.substring(option.name.indexOf(':') + 1),
            replaceKeys: field.keys,
          ),
    ];
  }
}

String _menuChoiceLabel(String token) {
  final value = token.substring(token.indexOf(':') + 1);
  return switch (value) {
    'open' => appL10n.open,
    'closed' => appL10n.closed,
    'archived' => appL10n.archived,
    'noreplies' => appL10n.noReplies,
    'single-user' || 'single_user' => appL10n.oneParticipant,
    'public' => appL10n.publicCategories,
    'pinned' => appL10n.postsInPinnedTopics,
    'bookmarked' => appL10n.bookmarkedPosts,
    'watching' => appL10n.watching,
    'tracking' => appL10n.trackingOrWatching,
    'untagged' => appL10n.noTags,
    _ => _menuWords(value),
  };
}
