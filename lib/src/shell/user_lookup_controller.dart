import 'dart:async';

import 'package:flutter/foundation.dart';

import '../foundation/latest_wins_queued_lookup_controller.dart';
import '../models/found_user.dart';

/// The people a picker offers for what its reader has typed so far.
///
/// A lookup waits for typing to pause, and an answer to an earlier query never
/// replaces the answer to a later one.
final class UserLookupController extends ChangeNotifier {
  UserLookupController({
    required this.searchUsers,
    this.debounce = const Duration(milliseconds: 250),
  });

  /// The site's user search answers nothing useful for one letter.
  static const int minimumQueryLength = 2;

  final Future<List<FoundUser>> Function(String term) searchUsers;
  final Duration debounce;

  late final _lookup =
      LatestWinsQueuedLookupController<String, List<FoundUser>>(
        lookup: searchUsers,
        onResult: _publish,
        onError: (_, _) => _publish(const []),
      );

  Timer? _pending;
  List<FoundUser> _results = const [];
  String _query = '';
  bool _searching = false;
  bool _disposed = false;

  List<FoundUser> get results => _results;
  String get query => _query;
  bool get searching => _searching;
  bool get queryIsTooShort => _query.trim().length < minimumQueryLength;

  void search(String value) {
    if (_disposed || value == _query) return;
    _query = value;
    _results = const [];
    _pending?.cancel();
    _lookup.invalidate();
    final term = value.trim();
    _searching = !queryIsTooShort;
    if (_searching) _pending = Timer(debounce, () => _lookup.request(term));
    notifyListeners();
  }

  void _publish(List<FoundUser> found) {
    if (_disposed) return;
    _results = List.unmodifiable(found);
    _searching = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pending?.cancel();
    _lookup.dispose();
    super.dispose();
  }
}
