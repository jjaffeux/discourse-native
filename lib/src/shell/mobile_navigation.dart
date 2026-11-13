import '../models/forum_workspace.dart';

/// The identity of a place the phone's bottom bar offers, including the
/// optional ones. Their order is the bar's, not this class's.
final class MobileTab {
  const MobileTab._(this.name) : panelOwner = null;
  const MobileTab.panel(String owner)
    : name = 'panel/$owner',
      panelOwner = owner;
  const MobileTab.destination(String id)
    : name = 'destination/$id',
      panelOwner = null;
  static const topics = MobileTab._('topics');
  static const messages = MobileTab._('messages');
  static const users = MobileTab._('users');

  /// The place [name] names, null for a name no build has written.
  static MobileTab? tryParse(String name) => switch (name) {
    'topics' || 'destination/new-tab' => topics,
    'messages' => messages,
    'users' => users,
    _ when name.startsWith('panel/') && name.length > 6 => MobileTab.panel(
      name.substring(6),
    ),
    _ when name.startsWith('destination/') && name.length > 12 =>
      MobileTab.destination(name.substring(12)),
    _ => null,
  };

  final String name;
  final String? panelOwner;
  @override
  bool operator ==(Object other) => other is MobileTab && other.name == name;
  @override
  int get hashCode => name.hashCode;
}

/// A mobile visit history starts at a tab root, independently of desktop tabs.
/// Entries contain shared route metadata, never widgets or feature data. The
/// shell projects only the current entry into the shared content renderer.
final class MobileNavigation {
  static const maximumPages = ForumTab.maximumHistoryEntries;

  List<({Object id, ForumTabLocation? content})> _entries = [
    (id: Object(), content: null),
  ];
  Object _historyId = Object();
  int _index = 0;
  String? _panelOwner;
  MobileTab _tab = MobileTab.topics;
  bool _sidebarOpen = false;

  MobileTab get tab => _tab;

  MobileNavigationState get state => MobileNavigationState(
    place: _tab.name,
    visits: [for (final entry in _entries) entry.content],
    index: _index,
  );

  /// Returns to a saved [state]. Whether the bar still offers its
  /// place is the bar's to say. Answers false, changing nothing, for a place
  /// no build has written.
  bool restore({required MobileNavigationState state}) {
    final tab = MobileTab.tryParse(state.place);
    if (tab == null) return false;
    closeSidebar();
    _tab = tab;
    _panelOwner = tab.panelOwner;
    _entries = [
      for (final visit in state.visits) (id: Object(), content: visit),
    ];
    _index = state.index;
    _historyId = Object();
    return true;
  }

  bool get sidebarOpen => _sidebarOpen;

  void openSidebar() => _sidebarOpen = true;

  bool closeSidebar() {
    if (!_sidebarOpen) return false;
    _sidebarOpen = false;
    return true;
  }

  String? get panelOwner => _panelOwner;
  ForumTabLocation? get location => _entries[_index].content;
  bool get atRoot => location == null;
  bool get canGoBack => _index > 0;
  bool get canGoForward => _index < _entries.length - 1;

  /// Where Back lands, null when there is no earlier visit or it is the root.
  ForumTabLocation? get previousLocation =>
      canGoBack ? _entries[_index - 1].content : null;

  /// Opaque presentation identities, independent of hydrated route metadata.
  Object get historyId => _historyId;
  Object get entryId => _entries[_index].id;
  Object? get previousEntryId => canGoBack ? _entries[_index - 1].id : null;
  Object? get nextEntryId => canGoForward ? _entries[_index + 1].id : null;

  /// Starts an explicitly selected or restored document journey. Only this
  /// bootstrap operation derives initial ancestry from the document stack.
  void startJourney({required MobileTab tab, required ForumTabLocation? root}) {
    selectTab(tab);
    if (root == null) return;
    _entries = [
      for (var length = 1; length <= root.contentStack.length; length++)
        (
          id: length == 1 ? entryId : Object(),
          content: ForumTabLocation(
            rootDestinationId: root.rootDestinationId,
            contentStack: root.contentStack.take(length).toList(),
          ),
        ),
    ];
    if (_entries.length > maximumPages + 1) {
      _entries.removeRange(1, _entries.length - maximumPages);
    }
    _index = _entries.length - 1;
  }

  void push(ForumTabLocation location) {
    if (_sameDestination(location, this.location)) {
      updateCurrent(location);
      return;
    }
    closeSidebar();
    _entries = [
      ..._entries.take(_index + 1),
      (id: Object(), content: location),
    ];
    if (_entries.length > maximumPages + 1) _entries.removeAt(1);
    _index = _entries.length - 1;
  }

  void replaceCurrent(ForumTabLocation location) {
    closeSidebar();
    if (atRoot) {
      push(location);
      return;
    }
    _entries = [..._entries.take(_index), (id: Object(), content: location)];
  }

  void prependAncestors(List<ForumTabLocation?> ancestors) {
    assert(!canGoBack && !atRoot);
    assert(ancestors.skip(1).every((ancestor) => ancestor != null));
    final retained = ancestors.length <= maximumPages
        ? ancestors
        : [
            ancestors.first,
            ...ancestors.skip(ancestors.length - maximumPages + 1),
          ];
    _entries = [
      for (final ancestor in retained) (id: Object(), content: ancestor),
      ..._entries.take(maximumPages + 1 - retained.length),
    ];
    _index = retained.length;
  }

  void restoreDocumentAncestors() {
    final document = location;
    if (canGoBack || document == null || document.contentStack.length < 2) {
      return;
    }
    prependAncestors([
      for (var length = 1; length < document.contentStack.length; length++)
        ForumTabLocation(
          rootDestinationId: document.rootDestinationId,
          contentStack: document.contentStack.take(length).toList(),
        ),
    ]);
  }

  void returnToPanelRoot() {
    closeSidebar();
    _index = 0;
  }

  void updateCurrent(ForumTabLocation location) {
    _entries[_index] = (id: entryId, content: location);
  }

  static bool _sameDestination(ForumTabLocation? a, ForumTabLocation? b) {
    if (a == null || b == null) return a == b;
    if (a.rootDestinationId != b.rootDestinationId ||
        a.contentStack.length != b.contentStack.length) {
      return false;
    }
    for (var i = 0; i < a.contentStack.length; i++) {
      if (a.contentStack[i].destination.identity !=
          b.contentStack[i].destination.identity) {
        return false;
      }
    }
    return true;
  }

  void selectPanel(String? owner) {
    closeSidebar();
    if (_panelOwner == owner) return;
    _panelOwner = owner;
    _tab = owner == null ? MobileTab.topics : MobileTab.panel(owner);
    _resetHistory();
  }

  void selectTab(MobileTab tab) {
    closeSidebar();
    _tab = tab;
    _panelOwner = tab.panelOwner;
    _resetHistory();
  }

  void reset() {
    closeSidebar();
    _resetHistory();
    _panelOwner = null;
    _tab = MobileTab.topics;
  }

  void _resetHistory() {
    _entries = [(id: Object(), content: null)];
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
