import 'dart:async';

import 'package:flutter/widgets.dart';

import 'composer_triggers.dart';

/// What a suggestion row draws on its left.
///
/// A sealed type rather than more nullable fields on [ComposerSuggestion]:
/// four kinds of art, of which exactly one is ever set, is what a variant is
/// for — and it was already untrue that every row draws an image.
@immutable
sealed class SuggestionArt {
  const SuggestionArt();
}

/// Emoji artwork, drawn square.
class ArtImage extends SuggestionArt {
  const ArtImage(this.url);
  final String url;
}

/// Somebody's face, drawn round.
class ArtAvatar extends SuggestionArt {
  const ArtAvatar(this.url);
  final String? url;
}

/// A category's colour swatch, split for a subcategory.
class ArtSquare extends SuggestionArt {
  const ArtSquare(this.colorValues);

  /// ARGB, in `[parent, child]` order — one entry for a top-level category,
  /// two for a subcategory.
  final List<int> colorValues;
}

/// A glyph, by the name Discourse gave it, optionally in a category's colour.
class ArtIcon extends SuggestionArt {
  const ArtIcon(this.name, {this.colorValue});
  final String? name;
  final int? colorValue;
}

/// One row the popup can offer, and what accepting it writes.
@immutable
class ComposerSuggestion {
  const ComposerSuggestion({
    required this.kind,
    required this.value,
    required this.label,
    this.detail,
    this.art,
  });

  /// Which trigger this answers, which is what accepting it writes the sigils
  /// for.
  final ComposerTriggerKind kind;

  /// The bare token the trigger run is replaced with — a username, an emoji
  /// name, a hashtag ref. Bare because the sigils belong to the completion,
  /// not to the row.
  final String value;

  final String label;

  /// The quieter half of the row: somebody's real name, a tag's topic count.
  final String? detail;

  final SuggestionArt? art;
}

/// Where the composer's completions come from.
///
/// Functions supplied by the shell, which owns the site, the key and the
/// caches — the composer only decides *when* to ask, exactly as it does for
/// `onSaveDraft`. Emoji are synchronous because they are a list already in
/// hand; people and places are not.
typedef ComposerSearch = ({
  Future<List<ComposerSuggestion>> Function(String term) users,
  Future<List<ComposerSuggestion>> Function(String term) hashtags,
  List<ComposerSuggestion> Function(String query) emojis,
});

/// The mention and emoji popup for one composer.
///
/// Its own notifier rather than state on `ComposerController`, for the reason
/// that one gives about `canSubmit`: a keystroke that only moves the
/// suggestion list should redraw the list, not the header, the toolbar and the
/// send button along with it.
class ComposerAutocomplete extends ChangeNotifier {
  ComposerAutocomplete({this.search});

  final ComposerSearch? search;

  /// Waits this long after the last keystroke before asking the site, the way
  /// `ComposerController.draftDebounce` waits before saving — and far shorter
  /// than it, because a draft save nobody is looking at can afford two seconds
  /// and a list somebody is waiting to read cannot.
  ///
  /// No `maxWait` twin either: a draft that is never saved loses text, while a
  /// search that is never made loses nothing, and every keystroke that pushes
  /// the timer out has already made the previous query the wrong one.
  static const Duration debounce = Duration(milliseconds: 150);

  /// One current search plus one answer that may just have become stale.
  ///
  /// A server can take the full request deadline to answer. Without a bound,
  /// typing slowly enough to cross [debounce] starts another HTTP request for
  /// every character while all earlier ones remain in flight. Past this limit
  /// only the newest query is retained and started when either request ends.
  static const int maxConcurrentRemoteSearches = 2;

  /// The most rows offered, chosen so the popup never scrolls. Past this it
  /// stops being a list you can scan, and the answer is another letter.
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

  /// An open trigger with nothing behind it is not a popup — an empty box over
  /// somebody's reply is worse than no box.
  bool get isOpen => _trigger != null && _suggestions.isNotEmpty;

  /// Bumped on every question asked, so a slow answer can tell on arrival that
  /// the one being asked has moved on. A per-site lifecycle lease at the scale
  /// of a keystroke.
  int _epoch = 0;

  Timer? _timer;
  int _remoteSearches = 0;
  ({ComposerTrigger trigger, int epoch})? _queuedRemoteSearch;
  bool _disposed = false;

  /// A trigger Escape was pressed on, so the next keystroke does not reopen
  /// the same list — which would read as the key not working.
  (int, ComposerTriggerKind)? _dismissed;

  /// Re-reads [value] and opens, moves or closes the popup.
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
    _timer?.cancel();
    _timer = null;
    _queuedRemoteSearch = null;
    _trigger = next;
    _epoch++;
    _selected = 0;

    switch (next.kind) {
      case ComposerTriggerKind.emoji:
        // Nothing to race: the list is already here.
        _suggestions = _take(search?.emojis(next.query) ?? const []);
        notifyListeners();
      case ComposerTriggerKind.mention:
      case ComposerTriggerKind.hashtag:
        // The old rows stay up while the new ones are on their way. Blanking
        // the list per keystroke makes the popup flash rather than narrow.
        notifyListeners();
        final epoch = _epoch;
        late final Timer timer;
        timer = Timer(debounce, () {
          if (identical(_timer, timer)) _timer = null;
          _enqueueRemoteSearch((trigger: next, epoch: epoch));
        });
        _timer = timer;
    }
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

  /// Asks the site, for the kinds that have to.
  ///
  /// One path rather than one per kind, so the staleness check below is
  /// written once — it is the part that is easy to get subtly wrong, and two
  /// copies of it would drift.
  Future<void> _searchRemote(
    ({ComposerTrigger trigger, int epoch}) request,
  ) async {
    if (_disposed || request.epoch != _epoch) return;
    final asked = request.trigger;
    final find = switch (asked.kind) {
      ComposerTriggerKind.mention => search?.users,
      ComposerTriggerKind.hashtag => search?.hashtags,
      ComposerTriggerKind.emoji => null,
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

  /// Re-runs the synchronous half, for a list that landed after the popup
  /// opened over it.
  ///
  /// A switch rather than an inequality, so a fourth kind is a compile error
  /// here. Nothing else in this file would have said a word about it.
  void refresh() {
    final open = _trigger;
    if (_disposed || open == null) return;

    switch (open.kind) {
      case ComposerTriggerKind.emoji:
        _suggestions = _take(search?.emojis(open.query) ?? const []);
        _selected = 0;
        notifyListeners();
      // Both of these asked the site, and the site's answer does not go stale
      // because a *different* list arrived.
      case ComposerTriggerKind.mention:
      case ComposerTriggerKind.hashtag:
        return;
    }
  }

  /// Moves the highlight, or reports that there was nothing to move so the key
  /// falls through to the field.
  bool moveSelection(int delta) {
    if (_disposed || !isOpen) return false;
    _selected = (_selected + delta) % _suggestions.length;
    if (_selected < 0) _selected += _suggestions.length;
    notifyListeners();
    return true;
  }

  /// The trigger is over — accepted, or typed past.
  void close() {
    _dismissed = null;
    _clear();
  }

  /// Escape. Closed, and stays closed until this run is left behind.
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
