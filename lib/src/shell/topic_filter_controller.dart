import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/topic.dart';
import '../models/topic_filter.dart';

typedef TopicFilterLookup =
    Future<List<TopicFilterLookupValue>> Function(String term);
typedef TopicFilterCategoryLookup =
    Future<List<TopicCategory>> Function(String term);

@immutable
class TopicFilterSuggestion {
  const TopicFilterSuggestion({
    required this.name,
    this.description,
    this.term,
    this.isSuggestion = false,
    this.delimiters = const [],
    this.category,
    this.parentCategory,
  });

  final String name;
  final String? description;
  final String? term;
  final bool isSuggestion;
  final List<TopicFilterModifier> delimiters;
  final TopicCategory? category;
  final TopicCategory? parentCategory;
}

class TopicFilterSuggestions {
  const TopicFilterSuggestions({
    required this.options,
    required this.categories,
    required this.categoryLookup,
    required this.tags,
    required this.tagGroups,
    required this.users,
    required this.groups,
  });

  static const int maxResults = 20;

  final List<TopicFilterOption> options;
  final List<TopicCategory> categories;
  final TopicFilterCategoryLookup categoryLookup;
  final TopicFilterLookup tags;
  final TopicFilterLookup tagGroups;
  final TopicFilterLookup users;
  final TopicFilterLookup groups;

  Future<List<TopicFilterSuggestion>> suggestions(String text) async {
    final segment = _FilterInput(text).lastSegment;
    if (segment.word.isEmpty) {
      final prioritized = [
        for (final option in options)
          if (option.priority == 1) _fromOption(option),
      ]..sort((a, b) => a.name.compareTo(b.name));
      return prioritized.take(maxResults).toList(growable: false);
    }

    if (segment.filterName != null && segment.hasColon) {
      final option = _findOption(segment.filterName!);
      if (option?.type != null) {
        return _ValueSuggester(
          option: option!,
          segment: segment,
          categories: categories,
          categoryLookup: categoryLookup,
          tags: tags,
          tagGroups: tagGroups,
          users: users,
          groups: groups,
        ).suggestions();
      }
    }

    return _filterOptions(segment.word, segment.prefix);
  }

  TopicFilterOption? _findOption(String name) {
    String normalized(String value) =>
        value.endsWith(':') ? value.substring(0, value.length - 1) : value;
    for (final option in options) {
      if (normalized(option.name) == name ||
          (option.alias != null && normalized(option.alias!) == name)) {
        return option;
      }
    }
    return null;
  }

  List<TopicFilterSuggestion> _filterOptions(String word, String prefix) {
    final search = word.toLowerCase().replaceFirst(prefix, '');
    final found = <TopicFilterSuggestion>[];

    for (final option in options) {
      if (found.length >= maxResults) break;
      final matches =
          option.name.toLowerCase().contains(search) ||
          (option.alias?.toLowerCase().contains(search) ?? false);
      if (!matches || option.name.toLowerCase() == search) continue;

      if (option.prefixes.isEmpty) {
        found.add(
          TopicFilterSuggestion(
            name: '$prefix${option.name}',
            description: option.description,
            isSuggestion: true,
            delimiters: option.delimiters,
          ),
        );
        continue;
      }

      if (prefix.isNotEmpty) {
        final modifier = option.prefixes
            .where((item) => item.name == prefix)
            .firstOrNull;
        if (modifier != null) {
          found.add(
            TopicFilterSuggestion(
              name: '$prefix${option.name}',
              description: modifier.description ?? option.description,
              isSuggestion: true,
              delimiters: option.delimiters,
            ),
          );
        }
      } else {
        found.add(_fromOption(option));
        for (final modifier in option.prefixes) {
          found.add(
            TopicFilterSuggestion(
              name: '${modifier.name}${option.name}',
              description: modifier.description ?? option.description,
              isSuggestion: true,
              delimiters: option.delimiters,
            ),
          );
        }
      }
    }

    found.sort((a, b) {
      final aStarts = a.name.toLowerCase().startsWith(search);
      final bStarts = b.name.toLowerCase().startsWith(search);
      if (aStarts != bStarts) return aStarts ? -1 : 1;
      return a.name.length.compareTo(b.name.length);
    });
    return found.take(maxResults).toList(growable: false);
  }

  static TopicFilterSuggestion _fromOption(TopicFilterOption option) =>
      TopicFilterSuggestion(
        name: option.name,
        description: option.description,
        delimiters: option.delimiters,
      );
}

class TopicFilterController extends ChangeNotifier {
  TopicFilterController({
    required String initialQuery,
    required this.submitQuery,
    required this.engine,
    this.debounce = const Duration(milliseconds: 300),
  }) : text = TextEditingController(text: initialQuery);

  final TextEditingController text;
  final Future<void> Function(String query) submitQuery;
  final Duration debounce;

  TopicFilterSuggestions engine;
  Timer? _timer;
  int _request = 0;
  bool _suggestionRunning = false;
  _QueuedTopicFilterSuggestions? _activeSuggestions;
  _QueuedTopicFilterSuggestions? _queuedSuggestions;
  bool _disposed = false;
  String? _lastSuggestionInput;
  List<TopicFilterSuggestion> _suggestions = const [];
  int _selectedIndex = -1;
  bool _open = false;

  List<TopicFilterSuggestion> get suggestions => _suggestions;
  int get selectedIndex => _selectedIndex;
  bool get isOpen => _open && _suggestions.isNotEmpty;
  bool get menuRequested => _open;
  TopicFilterSuggestion? get selected =>
      _selectedIndex >= 0 && _selectedIndex < _suggestions.length
      ? _suggestions[_selectedIndex]
      : null;

  void updateEngine(TopicFilterSuggestions engine) {
    this.engine = engine;
    _lastSuggestionInput = null;
    if (_open) unawaited(refreshSuggestions());
  }

  void inputChanged(String value) {
    _open = true;
    _selectedIndex = -1;
    _timer?.cancel();
    _timer = Timer(debounce, refreshSuggestions);
  }

  Future<void> openSuggestions() async {
    _open = true;
    await ensureFreshSuggestions();
  }

  Future<void> ensureFreshSuggestions() async {
    if (_lastSuggestionInput == text.text) return;
    _timer?.cancel();
    _timer = null;
    await refreshSuggestions();
  }

  Future<void> refreshSuggestions() {
    if (_disposed) return Future<void>.value();
    final input = text.text;
    final request = ++_request;
    final queued = _QueuedTopicFilterSuggestions(input, request);
    if (_suggestionRunning) {
      _queuedSuggestions?.complete();
      _queuedSuggestions = queued;
    } else {
      _startSuggestions(queued);
    }
    return queued.done.future;
  }

  void _startSuggestions(_QueuedTopicFilterSuggestions queued) {
    _suggestionRunning = true;
    _activeSuggestions = queued;
    unawaited(_runSuggestions(queued));
  }

  Future<void> _runSuggestions(_QueuedTopicFilterSuggestions queued) async {
    List<TopicFilterSuggestion> result;
    var failed = false;
    try {
      result = await engine.suggestions(queued.input);
    } catch (_) {
      failed = true;
      result = const [];
    }
    if (!_disposed && queued.request == _request && queued.input == text.text) {
      // A thrown lookup is not an answer for this input: recording it would
      // make ensureFreshSuggestions treat the failure as final and never retry.
      if (!failed) _lastSuggestionInput = queued.input;
      _suggestions = result;
      _selectedIndex = -1;
      notifyListeners();
    }
    queued.complete();
    if (identical(_activeSuggestions, queued)) {
      _activeSuggestions = null;
    }
    _suggestionRunning = false;

    final next = _queuedSuggestions;
    _queuedSuggestions = null;
    if (next == null) return;
    if (_disposed || next.request != _request || next.input != text.text) {
      next.complete();
      return;
    }
    _startSuggestions(next);
  }

  void moveSelection(int delta) {
    if (_suggestions.isEmpty) return;
    _selectedIndex = _selectedIndex < 0
        ? (delta > 0 ? 0 : _suggestions.length - 1)
        : (_selectedIndex + delta) % _suggestions.length;
    notifyListeners();
  }

  void select(int index) {
    if (index < 0 || index >= _suggestions.length || index == _selectedIndex) {
      return;
    }
    _selectedIndex = index;
    notifyListeners();
  }

  Future<void> acceptSelected() async {
    final choice = selected ?? _suggestions.firstOrNull;
    if (choice != null) await accept(choice);
  }

  Future<void> accept(TopicFilterSuggestion choice) async {
    final input = _FilterInput(text.text);
    var replacement = choice.name;
    if (choice.isSuggestion) {
      if (!replacement.endsWith(':') && choice.delimiters.length < 2) {
        replacement += ' ';
      }
    } else if (!replacement.endsWith(':') && choice.delimiters.isEmpty) {
      replacement += ' ';
    }

    final value = input.replaceLast(replacement);
    text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _lastSuggestionInput = null;
    await refreshSuggestions();
  }

  Future<void> submit() async {
    dismiss();
    await submitQuery(text.text);
  }

  Future<void> clear() async {
    text.clear();
    _lastSuggestionInput = null;
    await submitQuery('');
    _open = true;
    await refreshSuggestions();
  }

  void dismiss() {
    _open = false;
    _suggestions = const [];
    _selectedIndex = -1;
    // The suggestions were just discarded, so the input must not read as
    // already answered: reopening for the same text has to rebuild them.
    _lastSuggestionInput = null;
    _request++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _timer?.cancel();
    _activeSuggestions?.complete();
    _activeSuggestions = null;
    _queuedSuggestions?.complete();
    _queuedSuggestions = null;
    text.dispose();
    super.dispose();
  }
}

final class _QueuedTopicFilterSuggestions {
  _QueuedTopicFilterSuggestions(this.input, this.request);

  final String input;
  final int request;
  final Completer<void> done = Completer();

  void complete() {
    if (!done.isCompleted) done.complete();
  }
}

class _ValueSuggester {
  _ValueSuggester({
    required this.option,
    required this.segment,
    required this.categories,
    required this.categoryLookup,
    required this.tags,
    required this.tagGroups,
    required this.users,
    required this.groups,
  }) {
    _parseMultiValue();
  }

  final TopicFilterOption option;
  final _FilterSegment segment;
  final List<TopicCategory> categories;
  final TopicFilterCategoryLookup categoryLookup;
  final TopicFilterLookup tags;
  final TopicFilterLookup tagGroups;
  final TopicFilterLookup users;
  final TopicFilterLookup groups;

  late List<String> previousValues;
  late String searchTerm;
  late String valuePrefix;

  void _parseMultiValue() {
    final value = segment.value ?? '';
    if (option.delimiters.isEmpty) {
      previousValues = const [];
      searchTerm = value;
      valuePrefix = '';
      return;
    }

    final escaped = option.delimiters
        .map((item) => RegExp.escape(item.name))
        .join();
    final parts = value.split(RegExp('[$escaped]'));
    previousValues = parts
        .take(parts.length - 1)
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    searchTerm = parts.last.trim();
    valuePrefix = value.substring(0, value.length - searchTerm.length);
  }

  String _name(String term) =>
      '${segment.prefix}${segment.filterName}:$valuePrefix$term';

  Future<List<TopicFilterSuggestion>> suggestions() => switch (option.type) {
    'category' => _categories(),
    'tag' => _remote(tags, delimiterAware: true),
    'tag_group' => _remote(tagGroups, quote: true),
    'username' => _remote(users, delimiterAware: true),
    'group' => _remote(groups, delimiterAware: true),
    'username_group_list' => _usersAndGroups(),
    'date' => Future.value(_dates()),
    'number' => Future.value(_numbers()),
    _ => Future.value(const []),
  };

  Future<List<TopicFilterSuggestion>> _categories() async {
    final query = searchTerm.toLowerCase();
    final remote = searchTerm.isEmpty
        ? const <TopicCategory>[]
        : await categoryLookup(searchTerm.split(':').last);
    final byId = <int, TopicCategory>{
      for (final category in remote) category.id: category,
    };
    for (final category in categories) {
      byId.putIfAbsent(category.id, () => category);
    }
    final result = <TopicFilterSuggestion>[];
    for (final category in byId.values) {
      final path = _categoryPath(category, byId);
      final slugPath = path.map((item) => item.slug).join(':');
      final label = path.map((item) => item.name).join(' › ');
      if (query.isNotEmpty &&
          !category.name.toLowerCase().contains(query) &&
          !category.slug.toLowerCase().contains(query) &&
          !slugPath.toLowerCase().contains(query) &&
          !label.toLowerCase().contains(query)) {
        continue;
      }
      result.add(
        TopicFilterSuggestion(
          name: _name(slugPath),
          description: label,
          term: slugPath,
          isSuggestion: true,
          category: category,
          parentCategory: path.length > 1 ? path[path.length - 2] : null,
        ),
      );
      if (result.length == _maximumCategorySuggestions) break;
    }
    return result;
  }

  static List<TopicCategory> _categoryPath(
    TopicCategory category,
    Map<int, TopicCategory> byId,
  ) {
    final reversed = <TopicCategory>[];
    final visited = <int>{};
    TopicCategory? current = category;
    while (current != null && visited.add(current.id)) {
      reversed.add(current);
      current = current.parentCategoryId == null
          ? null
          : byId[current.parentCategoryId!];
    }
    return reversed.reversed.toList(growable: false);
  }

  static const int _maximumCategorySuggestions = 10;

  Future<List<TopicFilterSuggestion>> _remote(
    TopicFilterLookup lookup, {
    bool delimiterAware = false,
    bool quote = false,
  }) async {
    final used = delimiterAware
        ? previousValues.map((item) => item.toLowerCase()).toSet()
        : const <String>{};
    var result = <TopicFilterSuggestion>[];
    for (final value in await lookup(searchTerm)) {
      if (used.contains(value.name.toLowerCase())) continue;
      final term = quote ? _quoteIfNeeded(value.name) : value.name;
      result.add(
        TopicFilterSuggestion(
          name: _name(term),
          description: value.description,
          term: term,
          isSuggestion: true,
        ),
      );
      if (result.length == TopicFilterSuggestions.maxResults) break;
    }
    if (delimiterAware) result = _prepareDelimiters(result);
    return result
        .take(TopicFilterSuggestions.maxResults)
        .toList(growable: false);
  }

  Future<List<TopicFilterSuggestion>> _usersAndGroups() async {
    final used = previousValues.map((item) => item.toLowerCase()).toSet();
    var result = <TopicFilterSuggestion>[
      if (used.isEmpty)
        for (final entry in option.extraEntries)
          if (searchTerm.isEmpty ||
              entry.name.toLowerCase().contains(searchTerm.toLowerCase()) ||
              (entry.description?.toLowerCase().contains(
                    searchTerm.toLowerCase(),
                  ) ??
                  false))
            TopicFilterSuggestion(
              name: _name(entry.name),
              description: entry.description,
              term: entry.name,
              isSuggestion: true,
            ),
    ];

    final responses = await Future.wait([
      users(searchTerm),
      groups(searchTerm),
    ]);
    for (final values in responses) {
      for (final value in values) {
        if (used.contains(value.name.toLowerCase())) continue;
        result.add(
          TopicFilterSuggestion(
            name: _name(value.name),
            description: value.description,
            term: value.name,
            isSuggestion: true,
          ),
        );
      }
    }
    result = _prepareDelimiters(result);
    result.sort((a, b) {
      final query = searchTerm.toLowerCase();
      final aExact = a.term?.toLowerCase() == query;
      final bExact = b.term?.toLowerCase() == query;
      return aExact == bExact ? 0 : (aExact ? -1 : 1);
    });
    return result
        .take(TopicFilterSuggestions.maxResults)
        .toList(growable: false);
  }

  List<TopicFilterSuggestion> _prepareDelimiters(
    List<TopicFilterSuggestion> source,
  ) {
    if (option.delimiters.isEmpty) return source;
    final used = previousValues.map((item) => item.toLowerCase()).toSet();
    final result = [
      for (final item in source)
        if (!used.contains(item.term?.toLowerCase()))
          TopicFilterSuggestion(
            name: item.name,
            description: item.description,
            term: item.term,
            isSuggestion: item.isSuggestion,
            delimiters: option.delimiters,
            category: item.category,
          ),
    ];

    final query = searchTerm.toLowerCase();
    if (query.isNotEmpty &&
        result.any((item) => item.term?.toLowerCase() == query)) {
      for (final delimiter in option.delimiters) {
        result.add(
          TopicFilterSuggestion(
            name: _name('$searchTerm${delimiter.name}'),
            description: delimiter.description,
            isSuggestion: true,
            delimiters: option.delimiters,
          ),
        );
      }
    }
    return result;
  }

  List<TopicFilterSuggestion> _dates() {
    const values = [
      ('1', 'Yesterday'),
      ('7', 'Last week'),
      ('30', 'Last month'),
      ('365', 'Last year'),
    ];
    final query = searchTerm.toLowerCase();
    return [
      for (final (value, description) in values)
        if (query.isEmpty ||
            value.contains(query) ||
            description.toLowerCase().contains(query))
          TopicFilterSuggestion(
            name: _name(value),
            description: description,
            term: value,
            isSuggestion: true,
          ),
    ];
  }

  List<TopicFilterSuggestion> _numbers() => [
    for (final value in const ['0', '1', '5', '10', '20'])
      if (searchTerm.isEmpty || value.contains(searchTerm))
        TopicFilterSuggestion(
          name: _name(value),
          term: value,
          isSuggestion: true,
        ),
  ];

  static String _quoteIfNeeded(String name) {
    if (!RegExp(r'''[\s&\-()'\"]''').hasMatch(name)) return name;
    final doubleQuote = name.contains('"');
    final singleQuote = name.contains("'");
    if (doubleQuote && !singleQuote) return "'$name'";
    if (singleQuote && !doubleQuote) return '"$name"';
    if (doubleQuote && singleQuote) {
      return "'${name.replaceAll("'", r"\'")}'";
    }
    return '"$name"';
  }
}

class _FilterInput {
  _FilterInput(this.text) {
    final matches = RegExp(
      r'''(?:-=|=-|-|=)?[\w-]+:(?:"[^"]*"|'[^']*'|\S+)|"[^"]*"|'[^']*'|\S+''',
    ).allMatches(text).toList();
    _lastMatch = text.endsWith(' ') || matches.isEmpty ? null : matches.last;
  }

  final String text;
  late final RegExpMatch? _lastMatch;

  _FilterSegment get lastSegment {
    final word = _lastMatch?.group(0) ?? '';
    final prefix = RegExp(r'^(-=|=-|-|=)').firstMatch(word)?.group(0) ?? '';
    final withoutPrefix = word.substring(prefix.length);
    final colon = withoutPrefix.indexOf(':');
    return _FilterSegment(
      word: word,
      prefix: prefix,
      filterName: colon > 0 ? withoutPrefix.substring(0, colon) : null,
      value: colon > 0 ? withoutPrefix.substring(colon + 1) : null,
      hasColon: colon > 0,
    );
  }

  String replaceLast(String replacement) {
    final match = _lastMatch;
    if (match == null) return '$text$replacement';
    return text.replaceRange(match.start, match.end, replacement);
  }
}

@immutable
class _FilterSegment {
  const _FilterSegment({
    required this.word,
    required this.prefix,
    required this.filterName,
    required this.value,
    required this.hasColon,
  });

  final String word;
  final String prefix;
  final String? filterName;
  final String? value;
  final bool hasColon;
}
