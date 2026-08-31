import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/user_status.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'composer_triggers.dart';

@immutable
sealed class SuggestionArt {
  const SuggestionArt();
}

class ArtImage extends SuggestionArt {
  const ArtImage(this.url);
  final String url;
}

class ArtAvatar extends SuggestionArt {
  const ArtAvatar(this.url);
  final String? url;
}

class ArtSquare extends SuggestionArt {
  const ArtSquare(this.colorValues);

  final List<int> colorValues;
}

class ArtIcon extends SuggestionArt {
  const ArtIcon(this.name, {this.colorValue, this.fallback = DIcons.tag});

  final String? name;
  final int? colorValue;

  final DIconData fallback;
}

enum ComposerSuggestionAction { openEmojiPicker }

@immutable
class ComposerSuggestion {
  const ComposerSuggestion({
    required this.kind,
    required this.value,
    required this.label,
    this.detail,
    this.art,
    this.action,
    this.siteUrl,
    this.userId,
    this.userStatus,
  });

  final ComposerTriggerKind kind;

  final String value;

  final String label;

  final String? detail;

  final SuggestionArt? art;

  final ComposerSuggestionAction? action;

  final String? siteUrl;
  final int? userId;
  final UserStatus? userStatus;
}

typedef ComposerSearch = ({
  Future<List<ComposerSuggestion>> Function(String term) users,
  Future<List<ComposerSuggestion>> Function(String term) hashtags,
  Future<List<ComposerSuggestion>> Function(String query) emojis,
});

class ComposerAutocomplete extends ChangeNotifier {
  ComposerAutocomplete({this.search});

  final ComposerSearch? search;

  static const Duration debounce = Duration(milliseconds: 150);

  static const int maxConcurrentRemoteSearches = 2;

  static const int maxSuggestions = 7;

  ComposerTrigger? _trigger;
  ComposerTrigger? get trigger => _trigger;

  List<ComposerSuggestion> _suggestions = const [];
  List<ComposerSuggestion> get suggestions => _suggestions;

  int _selected = 0;
  int get selectedIndex => _selected;

  ComposerSuggestion? get selected =>
      _selected >= 0 && _selected < _suggestions.length
      ? _suggestions[_selected]
      : null;

  bool get isOpen => _trigger != null && _suggestions.isNotEmpty;

  int _epoch = 0;

  Timer? _timer;
  int _remoteSearches = 0;
  ({ComposerTrigger trigger, int epoch})? _queuedRemoteSearch;
  bool _disposed = false;

  (int, ComposerTriggerKind)? _dismissed;

  void update(TextEditingValue value) {
    if (_disposed) return;

    final next = composerTriggerAt(value);
    if (next == null) {
      _dismissed = null;
      _clear();
      return;
    }
    if (_dismissed case final dismissed?) {
      if (dismissed.$1 == next.start && dismissed.$2 == next.kind) return;
      _dismissed = null;
    }

    if (next == _trigger) return;
    final previousKind = _trigger?.kind;
    _timer?.cancel();
    _timer = null;
    _queuedRemoteSearch = null;
    _trigger = next;
    _epoch++;
    _selected = 0;

    // Rows from the same kind stay visible while the new answer is loading;
    // that avoids a flash on every keystroke. A different kind's rows would
    // be actively misleading, so those are cleared immediately.
    if (previousKind != next.kind) _suggestions = const [];
    notifyListeners();
    final epoch = _epoch;
    late final Timer timer;
    timer = Timer(debounce, () {
      if (identical(_timer, timer)) _timer = null;
      _enqueueRemoteSearch((trigger: next, epoch: epoch));
    });
    _timer = timer;
  }

  void _enqueueRemoteSearch(({ComposerTrigger trigger, int epoch}) request) {
    if (_disposed || request.epoch != _epoch) return;
    if (_remoteSearches >= maxConcurrentRemoteSearches) {
      _queuedRemoteSearch = request;
      return;
    }

    _remoteSearches++;
    _searchRemote(request).whenComplete(_remoteSearchFinished).ignore();
  }

  void _remoteSearchFinished() {
    _remoteSearches--;
    if (_disposed) {
      _queuedRemoteSearch = null;
      return;
    }

    final queued = _queuedRemoteSearch;
    _queuedRemoteSearch = null;
    if (queued != null) _enqueueRemoteSearch(queued);
  }

  Future<void> _searchRemote(
    ({ComposerTrigger trigger, int epoch}) request,
  ) async {
    if (_disposed || request.epoch != _epoch) return;
    final asked = request.trigger;
    final find = switch (asked.kind) {
      ComposerTriggerKind.mention => search?.users,
      ComposerTriggerKind.hashtag => search?.hashtags,
      ComposerTriggerKind.emoji => search?.emojis,
    };
    if (find == null) return;

    List<ComposerSuggestion> found;
    try {
      found = await find(asked.query);
    } catch (_) {
      if (_disposed || request.epoch != _epoch) return;
      _suggestions = const [];
      _selected = 0;
      notifyListeners();
      return;
    }

    // Covers all four ways a late answer can be wrong at once: a newer query,
    // a dismissed popup, an accepted suggestion, a disposed composer.
    if (_disposed || request.epoch != _epoch) return;

    _suggestions = _take(found);
    _selected = 0;
    notifyListeners();
  }

  void refresh() {
    final open = _trigger;
    if (_disposed || open == null) return;

    switch (open.kind) {
      case ComposerTriggerKind.emoji:
        _timer?.cancel();
        _timer = null;
        _queuedRemoteSearch = null;
        _epoch++;
        _selected = 0;
        notifyListeners();
        _enqueueRemoteSearch((trigger: open, epoch: _epoch));
        return;
      // Both of these asked the site, and the site's answer does not go stale
      // because a *different* list arrived.
      case ComposerTriggerKind.mention:
      case ComposerTriggerKind.hashtag:
        return;
    }
  }

  bool moveSelection(int delta) {
    if (_disposed || !isOpen) return false;
    _selected = (_selected + delta) % _suggestions.length;
    if (_selected < 0) _selected += _suggestions.length;
    notifyListeners();
    return true;
  }

  void close() {
    _dismissed = null;
    _clear();
  }

  void dismiss() {
    final open = _trigger;
    if (open != null) _dismissed = (open.start, open.kind);
    _clear();
  }

  void _clear() {
    _timer?.cancel();
    _timer = null;
    _queuedRemoteSearch = null;
    _epoch++;
    if (_trigger == null && _suggestions.isEmpty) return;
    _trigger = null;
    _suggestions = const [];
    _selected = 0;
    if (!_disposed) notifyListeners();
  }

  List<ComposerSuggestion> _take(List<ComposerSuggestion> found) =>
      found.length <= maxSuggestions ? found : found.sublist(0, maxSuggestions);

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _queuedRemoteSearch = null;
    _epoch++;
    super.dispose();
  }
}
