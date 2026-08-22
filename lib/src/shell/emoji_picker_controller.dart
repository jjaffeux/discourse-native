import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/emoji_picker_store.dart';
import '../models/site_emoji.dart';

typedef EmojiCatalogLoader = Future<SiteEmojiCatalog?> Function({bool refresh});
typedef EmojiSearchAliasLoader =
    Future<Map<String, List<String>>?> Function({bool refresh});

/// One recently used emoji together with the tone that should be shown.
///
/// A history entry that already carries a tone keeps it. An untoned entry
/// follows the picker's current tone, matching Discourse's web picker.
@immutable
final class FavoriteSiteEmoji {
  const FavoriteSiteEmoji({required this.emoji, required this.tone});

  final SiteEmoji emoji;
  final EmojiSkinTone tone;

  String get code => emoji.codeFor(tone);
  String get url => emoji.urlFor(tone);
}

/// Catalog, search and preference state for one open emoji picker.
///
/// The controller deliberately accepts loaders instead of a shell controller:
/// the same surface can be opened by topic and chat composers, and delayed
/// answers remain owned by the presentation layer that supplied the loaders.
final class EmojiPickerController extends ChangeNotifier {
  EmojiPickerController({
    required this.siteUrl,
    required this.context,
    required this.store,
    required this.loadCatalog,
    required this.loadSearchAliases,
    this.initialQuery = '',
    this.searchDebounce = const Duration(milliseconds: 250),
  }) : _query = initialQuery;

  static const int maxSearchResults = 50;
  static const String loadError =
      "Couldn't load emoji. Check the connection and try again.";

  final String siteUrl;
  final EmojiPickerContext context;
  final EmojiPickerStore store;
  final EmojiCatalogLoader loadCatalog;
  final EmojiSearchAliasLoader loadSearchAliases;
  final String initialQuery;
  final Duration searchDebounce;

  SiteEmojiCatalog? _catalog;
  Map<String, List<String>> _aliases = const {};
  List<SiteEmoji> _searchResults = const [];
  List<String> _favoriteCodes = const [];
  EmojiSkinTone _tone = EmojiSkinTone.neutral;
  String _query;
  String? _error;
  bool _loading = false;
  bool _searchPending = false;
  bool _aliasesAttempted = false;
  bool _aliasesLoading = false;
  bool _refreshAliases = false;
  bool _clearingHistory = false;
  bool _disposed = false;
  int _catalogRequest = 0;
  int _aliasRequest = 0;
  Timer? _debounce;

  SiteEmojiCatalog? get catalog => _catalog;
  List<SiteEmoji> get searchResults => _searchResults;
  EmojiSkinTone get tone => _tone;
  String get query => _query;
  String? get error => _error;
  bool get loading => _loading;
  bool get searchPending => _searchPending;
  bool get aliasesLoading => _aliasesLoading;
  bool get clearingHistory => _clearingHistory;
  bool get hasQuery => _query.trim().isNotEmpty;

  List<FavoriteSiteEmoji> get favorites {
    final catalog = _catalog;
    if (catalog == null) return const [];
    final favorites = <FavoriteSiteEmoji>[];
    // Deduped on the resolved code rather than the recorded one. History keeps
    // `wave` and `wave:t5` apart, but an untoned entry is drawn in the tone
    // that is current, so under t5 both become the same cell — twice over, and
    // spending two of the row's slots on one emoji.
    final drawn = <String>{};
    for (final code in _favoriteCodes) {
      final favorite = _favoriteWithCurrentTone(code, catalog);
      if (favorite == null || !drawn.add(favorite.code)) continue;
      favorites.add(favorite);
    }
    return List.unmodifiable(favorites);
  }

  Future<void> load({bool refresh = false}) async {
    if (_disposed || _loading) return;
    final request = ++_catalogRequest;
    _loading = true;
    _error = null;
    if (refresh) {
      _catalog = null;
      _searchResults = const [];
      _aliases = const {};
      _aliasesAttempted = false;
      _aliasesLoading = false;
      _refreshAliases = true;
      ++_aliasRequest;
    }
    _notify();

    try {
      final catalog = await loadCatalog(refresh: refresh);
      if (!_catalogIsCurrent(request)) return;
      if (catalog == null) {
        _error = loadError;
        return;
      }
      _catalog = catalog;

      try {
        _tone = await store.readSkinTone(siteUrl: siteUrl);
      } catch (_) {
        _tone = EmojiSkinTone.neutral;
      }
      if (!_catalogIsCurrent(request)) return;

      try {
        _favoriteCodes = await store.favoriteEmojiCodes(
          siteUrl: siteUrl,
          context: context,
          catalog: catalog,
        );
      } catch (_) {
        _favoriteCodes = const [];
      }
      if (!_catalogIsCurrent(request)) return;

      if (hasQuery) {
        _scheduleSearch(immediate: true);
      }
    } catch (_) {
      if (_catalogIsCurrent(request)) _error = loadError;
    } finally {
      if (_catalogIsCurrent(request)) {
        _loading = false;
        _notify();
      }
    }
  }

  Future<void> retry() => load(refresh: true);

  void updateQuery(String value) {
    if (_disposed || value == _query) return;
    _query = value;
    _scheduleSearch();
  }

  void _scheduleSearch({bool immediate = false}) {
    _debounce?.cancel();
    _debounce = null;
    _searchResults = const [];

    if (!hasQuery || _catalog == null) {
      _searchPending = false;
      _notify();
      return;
    }

    _searchPending = true;
    if (immediate || searchDebounce == Duration.zero) {
      _runSearch();
      return;
    }
    _debounce = Timer(searchDebounce, _runSearch);
    _notify();
  }

  void _runSearch() {
    _debounce = null;
    if (_disposed) return;
    final catalog = _catalog;
    final query = _query.trim().toLowerCase();
    if (catalog == null || query.isEmpty) {
      _searchPending = false;
      _searchResults = const [];
      _notify();
      return;
    }

    _searchResults = _search(catalog, query, _aliases);
    _searchPending = false;
    _notify();
    if (!_aliasesAttempted) unawaited(_loadAliases());
  }

  Future<void> _loadAliases() async {
    if (_disposed || _aliasesAttempted) return;
    _aliasesAttempted = true;
    _aliasesLoading = true;
    final refresh = _refreshAliases;
    _refreshAliases = false;
    final request = ++_aliasRequest;
    _notify();
    try {
      final aliases = await loadSearchAliases(refresh: refresh);
      if (!_aliasIsCurrent(request)) return;
      _aliases = _freezeAliases(aliases);
      if (hasQuery && _catalog != null) {
        _searchResults = _search(
          _catalog!,
          _query.trim().toLowerCase(),
          _aliases,
        );
      }
    } catch (_) {
      // Name search is complete and useful without locale aliases.
      if (_aliasIsCurrent(request)) _aliases = const {};
    } finally {
      if (_aliasIsCurrent(request)) {
        _aliasesLoading = false;
        _notify();
      }
    }
  }

  void setTone(EmojiSkinTone value) {
    if (_disposed || value == _tone) return;
    _tone = value;
    _notify();
    unawaited(
      store.writeSkinTone(siteUrl: siteUrl, tone: value).catchError((_) {}),
    );
  }

  Future<void> clearHistory() async {
    if (_disposed || _clearingHistory) return;
    _clearingHistory = true;
    _notify();
    try {
      await store.clearHistory(siteUrl: siteUrl, context: context);
      if (!_disposed) _favoriteCodes = const [];
    } catch (_) {
      // History is optional presentation state. A persistence failure must not
      // make the picker unusable.
    } finally {
      if (!_disposed) {
        _clearingHistory = false;
        _notify();
      }
    }
  }

  static List<SiteEmoji> _search(
    SiteEmojiCatalog catalog,
    String query,
    Map<String, List<String>> aliases,
  ) {
    final alphabetical = [...catalog.all]
      ..sort((left, right) => left.name.compareTo(right.name));
    final found = <String>{};
    final results = <SiteEmoji>[];

    void takeWhere(bool Function(SiteEmoji emoji) matches) {
      if (results.length >= maxSearchResults) return;
      for (final emoji in alphabetical) {
        if (results.length >= maxSearchResults) return;
        if (!found.contains(emoji.name) && matches(emoji)) {
          found.add(emoji.name);
          results.add(emoji);
        }
      }
    }

    takeWhere((emoji) => emoji.name.toLowerCase().startsWith(query));
    takeWhere(
      (emoji) =>
          aliases[emoji.name]?.any(
            (alias) => alias.toLowerCase().startsWith(query),
          ) ??
          false,
    );
    takeWhere((emoji) {
      final index = emoji.name.toLowerCase().indexOf(query);
      return index > 0;
    });

    return List.unmodifiable(results);
  }

  static FavoriteSiteEmoji? _favorite(
    String rawCode,
    SiteEmojiCatalog catalog,
  ) {
    final code = rawCode.replaceAll(RegExp(r'^:+|:+$'), '');
    final match = RegExp(r'^(.+?):(t[2-6])$').firstMatch(code);
    final name = match?.group(1) ?? code;
    final emoji = catalog.emojiNamed(name);
    if (emoji == null) return null;
    final explicitTone = match == null
        ? null
        : EmojiSkinTone.fromCode(match.group(2));
    return FavoriteSiteEmoji(
      emoji: emoji,
      tone: explicitTone ?? EmojiSkinTone.neutral,
    );
  }

  FavoriteSiteEmoji? _favoriteWithCurrentTone(
    String rawCode,
    SiteEmojiCatalog catalog,
  ) {
    final favorite = _favorite(rawCode, catalog);
    if (favorite == null) return null;
    final hasExplicitTone = RegExp(r':t[2-6]:?$').hasMatch(rawCode);
    if (hasExplicitTone) return favorite;
    return FavoriteSiteEmoji(emoji: favorite.emoji, tone: _tone);
  }

  static Map<String, List<String>> _freezeAliases(
    Map<String, List<String>>? aliases,
  ) {
    if (aliases == null || aliases.isEmpty) return const {};
    return Map.unmodifiable({
      for (final entry in aliases.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    });
  }

  bool _catalogIsCurrent(int request) =>
      !_disposed && request == _catalogRequest;
  bool _aliasIsCurrent(int request) => !_disposed && request == _aliasRequest;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    ++_catalogRequest;
    ++_aliasRequest;
    super.dispose();
  }
}
