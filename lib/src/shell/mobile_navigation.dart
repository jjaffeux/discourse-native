import '../models/forum_workspace.dart';

/// A mobile visit history starts at the sidebar, independently of desktop tabs.
/// Entries contain shared route metadata, never widgets or feature data. The
/// shell projects only the current entry into the shared content renderer.
final class MobileNavigation {
  static const maximumPages = ForumTab.maximumHistoryEntries;

  Object? _owner;
  List<({ForumTabLocation? content, bool aggregate})?> _entries = [null];
  int _index = 0;
  String? _panelOwner;

  String? get panelOwner => _panelOwner;
  ForumTabLocation? get location => _entries[_index]?.content;
  bool get aggregate => _entries[_index]?.aggregate ?? false;
  bool get atRoot => _entries[_index] == null;
  bool get canGoBack => _index > 0;
  bool get canGoForward => _index < _entries.length - 1;

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
    final target = location == null && !aggregate
        ? null
        : (content: aggregate ? null : location, aggregate: aggregate);
    if (target?.aggregate == _entries[_index]?.aggregate &&
        _sameDestination(target?.content, _entries[_index]?.content)) {
      // Retain refreshed titles and other non-identity route metadata.
      _entries[_index] = target;
      return;
    }
    if (target == null) {
      _index = 0;
      return;
    }
    _entries = [..._entries.take(_index + 1), target];
    if (_entries.length > maximumPages + 1) _entries.removeAt(1);
    _index = _entries.length - 1;
  }

  /// Filter and explicit replacement commands update the current visit.
  /// Replacing from Home still opens the first page during synchronization.
  void replaceCurrent(ForumTabLocation location) {
    if (atRoot) return;
    _entries = [
      ..._entries.take(_index),
      (content: location, aggregate: false),
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
    _entries = [null];
    _index = 0;
  }

  void reset() {
    _entries = [null];
    _index = 0;
    _panelOwner = null;
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
