import '../models/forum_workspace.dart';

/// A mobile visit history starts at the sidebar, independently of desktop tabs.
/// Entries contain shared route metadata, never widgets or feature data. The
/// shell projects only the current entry into the shared content renderer.
final class MobileNavigation {
  static const maximumPages = ForumTab.maximumHistoryEntries;

  Object? _owner;
  List<({Object id, ForumTabLocation? content, bool aggregate})> _entries = [
    (id: Object(), content: null, aggregate: false),
  ];
  Object _historyId = Object();
  int _index = 0;
  String? _panelOwner;

  String? get panelOwner => _panelOwner;
  ForumTabLocation? get location => _entries[_index].content;
  bool get aggregate => _entries[_index].aggregate;
  bool get atRoot => location == null && !aggregate;
  bool get canGoBack => _index > 0;
  bool get canGoForward => _index < _entries.length - 1;

  /// Opaque presentation identities, independent of hydrated route metadata.
  Object get historyId => _historyId;
  Object get entryId => _entries[_index].id;
  Object? get previousEntryId => canGoBack ? _entries[_index - 1].id : null;
  Object? get nextEntryId => canGoForward ? _entries[_index + 1].id : null;

  /// Called after a navigation command, before the shell notifies its views.
  /// Account/site changes discard history so Back cannot expose another owner.
  void synchronize({
    required Object? owner,
    required ForumTabLocation? location,
    bool aggregate = false,
  }) {
    if (_owner != owner) {
      _owner = owner;
      reset();
    }
    final content = aggregate ? null : location;
    if (aggregate == _entries[_index].aggregate &&
        _sameDestination(content, _entries[_index].content)) {
      // Retain refreshed titles and other non-identity route metadata.
      _entries[_index] = (id: entryId, content: content, aggregate: aggregate);
      return;
    }
    if (content == null && !aggregate) {
      _index = 0;
      return;
    }
    _entries = [
      ..._entries.take(_index + 1),
      (id: Object(), content: content, aggregate: aggregate),
    ];
    if (_entries.length > maximumPages + 1) _entries.removeAt(1);
    _index = _entries.length - 1;
  }

  /// Filter and explicit replacement commands update the current visit.
  /// Replacing from Home still opens the first page during synchronization.
  void replaceCurrent(ForumTabLocation location) {
    if (atRoot) return;
    _entries = [
      ..._entries.take(_index),
      (id: Object(), content: location, aggregate: false),
    ];
  }

  static bool _sameDestination(ForumTabLocation? a, ForumTabLocation? b) {
    if (a == null || b == null) return a == b;
    if (a.rootDestinationId != b.rootDestinationId ||
        a.contentStack.length != b.contentStack.length) {
      return false;
    }
    for (var i = 0; i < a.contentStack.length; i++) {
      if (a.contentStack[i].id != b.contentStack[i].id ||
          a.contentStack[i].feedPath != b.contentStack[i].feedPath) {
        return false;
      }
    }
    return true;
  }

  void selectPanel(String? owner) {
    if (_panelOwner == owner) return;
    _panelOwner = owner;
    _resetHistory();
  }

  void reset() {
    _resetHistory();
    _panelOwner = null;
  }

  void _resetHistory() {
    _entries = [(id: Object(), content: null, aggregate: false)];
    _index = 0;
    _historyId = Object();
  }

  bool goBack() {
    if (!canGoBack) return false;
    _index--;
    return true;
  }

  bool goForward() {
    if (!canGoForward) return false;
    _index++;
    return true;
  }
}
