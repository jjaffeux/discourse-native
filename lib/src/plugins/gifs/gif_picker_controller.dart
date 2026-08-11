import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/api_credentials.dart';
import '../../data/discourse_api_contracts.dart';
import '../../data/site_lifecycle.dart';
import 'gif.dart';

/// Request and pagination state for one open GIF picker.
///
/// The picker owns this controller for exactly as long as its modal is open.
/// Keeping the state outside the widget makes delayed searches, stale answers,
/// and pagination independently testable, while the selected [GifResult]
/// remains the modal's only output.
final class GifPickerController extends ChangeNotifier {
  GifPickerController({
    required this.siteUrl,
    required this.api,
    required this.credentials,
    required this.lifecycle,
    required this.fileDetail,
    this.maxResults,
    this.searchDebounce = const Duration(milliseconds: 700),
  });

  static const int minimumQueryLength = 3;

  final String siteUrl;
  final GifsApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final String fileDetail;

  /// Null leaves server pagination unbounded. A positive value caps the
  /// unique results kept by this picker.
  final int? maxResults;

  final Duration searchDebounce;

  List<GifCategory> _categories = const [];
  List<GifResult> _results = const [];
  String _query = '';
  String? _activeQuery;
  String? _nextPosition;
  String? _categoriesError;
  String? _searchError;
  bool _loadingCategories = false;
  bool _searchPending = false;
  bool _searching = false;
  bool _loadingMore = false;
  bool _disposed = false;
  int _categoryRequest = 0;
  int _searchRequest = 0;
  Timer? _debounce;

  List<GifCategory> get categories => _categories;
  List<GifResult> get results => _results;
  String get query => _query;
  bool get hasActiveSearch =>
      _activeQuery != null ||
      _searchPending ||
      _query.trim().length >= minimumQueryLength;
  String? get error => hasActiveSearch ? _searchError : _categoriesError;
  bool get loadingCategories => _loadingCategories;
  bool get searchPending => _searchPending;
  bool get searching => _searching;
  bool get loadingMore => _loadingMore;
  bool get isBusy => _loadingCategories || _searching || _loadingMore;
  bool get showingCategories => !hasActiveSearch && _categories.isNotEmpty;
  bool get canLoadMore =>
      !_searching && !_loadingMore && _nextPosition != null && !_atLimit;

  bool get _atLimit {
    final limit = maxResults;
    return limit != null && limit > 0 && _results.length >= limit;
  }

  /// Loads the featured categories shown before a search has begun.
  Future<void> loadCategories() async {
    if (_disposed || _loadingCategories) return;
    final request = ++_categoryRequest;
    final lease = lifecycle.capture(siteUrl);
    _loadingCategories = true;
    _categoriesError = null;
    _notify();

    try {
      final session = await _session(lease);
      if (!_categoryIsCurrent(request)) return;
      if (!lease.isCurrent) return;
      if (session == null) {
        _categoriesError = _missingCredentials;
        return;
      }
      final categories = await api.gifCategories(
        siteUrl: siteUrl,
        apiKey: session.apiKey,
        clientId: session.clientId,
      );
      if (!_categoryIsCurrent(request) || !lease.isCurrent) return;
      _categories = List.unmodifiable(categories);
    } catch (error) {
      if (_categoryIsCurrent(request) && lease.isCurrent) {
        _categoriesError = _errorMessage(error);
      }
    } finally {
      if (_categoryIsCurrent(request)) {
        _loadingCategories = false;
        _notify();
      }
    }
  }

  /// Updates the free-text query and schedules a fresh first page.
  void updateQuery(String value) {
    if (_disposed || value == _query) return;
    _query = value;
    _debounce?.cancel();
    _debounce = null;
    ++_searchRequest;
    _activeQuery = null;
    _nextPosition = null;
    _results = const [];
    _searchError = null;
    _searching = false;
    _loadingMore = false;

    final query = value.trim();
    if (query.length < minimumQueryLength) {
      _searchPending = false;
      _notify();
      return;
    }

    _searchPending = true;
    final request = _searchRequest;
    _debounce = Timer(searchDebounce, () {
      _debounce = null;
      unawaited(_searchFirstPage(query, request: request));
    });
    _notify();
  }

  /// Searches a featured category immediately, even if its server-provided
  /// search term is shorter than the normal free-text minimum.
  Future<void> selectCategory(GifCategory category) {
    if (_disposed) return Future.value();
    _query = category.searchTerm;
    _debounce?.cancel();
    _debounce = null;
    final request = ++_searchRequest;
    _activeQuery = null;
    _nextPosition = null;
    _results = const [];
    _searchError = null;
    _searchPending = false;
    _searching = false;
    _loadingMore = false;
    _notify();
    return _searchFirstPage(
      category.searchTerm,
      request: request,
      bypassLengthCheck: true,
    );
  }

  Future<void> _searchFirstPage(
    String query, {
    required int request,
    bool bypassLengthCheck = false,
  }) async {
    if (_disposed || request != _searchRequest) return;
    if (!bypassLengthCheck && query.length < minimumQueryLength) return;
    _activeQuery = query;
    _searchPending = false;
    _searching = true;
    _loadingMore = false;
    _searchError = null;
    _results = const [];
    _nextPosition = null;
    _notify();
    await _loadPage(query, request: request, position: '0', replace: true);
  }

  /// Appends the next page, if the server and configured client cap allow it.
  Future<void> loadMore() async {
    final query = _activeQuery;
    final position = _nextPosition;
    if (_disposed || query == null || position == null || !canLoadMore) return;
    _loadingMore = true;
    _searchError = null;
    _notify();
    await _loadPage(
      query,
      request: _searchRequest,
      position: position,
      replace: false,
    );
  }

  /// Repeats whichever category or search request currently failed.
  Future<void> retry() {
    if (_disposed) return Future.value();
    final query = _activeQuery;
    if (query == null) return loadCategories();
    if (_results.isNotEmpty && _nextPosition != null) return loadMore();
    return _searchFirstPage(
      query,
      request: _searchRequest,
      bypassLengthCheck: true,
    );
  }

  Future<void> _loadPage(
    String query, {
    required int request,
    required String position,
    required bool replace,
  }) async {
    final lease = lifecycle.capture(siteUrl);
    try {
      final session = await _session(lease);
      if (!_searchIsCurrent(request)) return;
      if (!lease.isCurrent) return;
      if (session == null) {
        _searchError = _missingCredentials;
        return;
      }
      final page = await api.searchGifs(
        siteUrl: siteUrl,
        apiKey: session.apiKey,
        clientId: session.clientId,
        query: query,
        fileDetail: fileDetail,
        position: position,
      );
      if (!_searchIsCurrent(request) || !lease.isCurrent) return;

      final unique = <String, GifResult>{
        if (!replace)
          for (final result in _results) result.url: result,
      };
      for (final result in page.results) {
        unique.putIfAbsent(result.url, () => result);
      }
      var results = unique.values.toList(growable: false);
      final limit = maxResults;
      if (limit != null && limit > 0 && results.length > limit) {
        results = results.take(limit).toList(growable: false);
      }
      _results = List.unmodifiable(results);
      _nextPosition = page.hasMore && !_atLimit ? page.nextPosition : null;
      _searchError = null;
    } catch (error) {
      if (_searchIsCurrent(request) && lease.isCurrent) {
        _searchError = _errorMessage(error);
      }
    } finally {
      if (_searchIsCurrent(request)) {
        _searching = false;
        _loadingMore = false;
        _notify();
      }
    }
  }

  Future<_GifSession?> _session(SiteLease lease) async {
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (apiKey == null || !lease.isCurrent) return null;
    final clientId = await credentials.clientId();
    if (!lease.isCurrent) return null;
    return _GifSession(apiKey: apiKey, clientId: clientId);
  }

  bool _categoryIsCurrent(int request) =>
      !_disposed && request == _categoryRequest;
  bool _searchIsCurrent(int request) => !_disposed && request == _searchRequest;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _debounce?.cancel();
    _debounce = null;
    super.dispose();
  }
}

const String _missingCredentials =
    'Connect to this site before searching for GIFs.';

String _errorMessage(Object error) {
  if (error is SiteLookupException) {
    return switch (error.statusCode) {
      400 || 414 => 'That GIF search is too long.',
      401 || 403 =>
        'GIF search is not configured for this site, or its API key is invalid.',
      404 => 'GIF search is not enabled for this site.',
      429 => 'Too many GIF searches. Try again in a moment.',
      _ => "Couldn't load GIFs. Check the connection and try again.",
    };
  }
  return "Couldn't load GIFs. Check the connection and try again.";
}

@immutable
final class _GifSession {
  const _GifSession({required this.apiKey, required this.clientId});

  final String apiKey;
  final String clientId;
}
