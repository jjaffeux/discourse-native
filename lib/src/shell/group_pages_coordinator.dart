import '../models/group_route.dart';

typedef GroupPagesOwner = ({
  String siteUrl,
  String accountIdentity,
  String? tabId,
});

typedef GroupPagesChildIdentity = ({GroupPagesOwner owner, String pageId});

final class GroupPagesDirectoryQuery {
  const GroupPagesDirectoryQuery({this.filter = '', this.type});

  final String filter;
  final String? type;

  GroupPagesDirectoryQuery copyWith({String? filter, String? type}) =>
      GroupPagesDirectoryQuery(
        filter: filter ?? this.filter,
        type: type ?? this.type,
      );

  GroupPagesDirectoryQuery withoutType() =>
      GroupPagesDirectoryQuery(filter: filter);

  @override
  bool operator ==(Object other) =>
      other is GroupPagesDirectoryQuery &&
      other.filter == filter &&
      other.type == type;

  @override
  int get hashCode => Object.hash(filter, type);
}

final class GroupPagesMemberQuery {
  const GroupPagesMemberQuery({
    this.filter = '',
    this.order = 'last_seen_at',
    this.ascending = false,
  });

  final String filter;
  final String order;
  final bool ascending;

  GroupPagesMemberQuery copyWith({
    String? filter,
    String? order,
    bool? ascending,
  }) => GroupPagesMemberQuery(
    filter: filter ?? this.filter,
    order: order ?? this.order,
    ascending: ascending ?? this.ascending,
  );

  @override
  bool operator ==(Object other) =>
      other is GroupPagesMemberQuery &&
      other.filter == filter &&
      other.order == order &&
      other.ascending == ascending;

  @override
  int get hashCode => Object.hash(filter, order, ascending);
}

enum GroupPagesPageKind { none, directory, detail, unknown }

enum GroupPagesBackIntent { popContent, showSidebar, none }

final class GroupPagesPage {
  const GroupPagesPage._({required this.kind, this.route, this.unknownRouteId});

  const GroupPagesPage.none() : this._(kind: GroupPagesPageKind.none);

  const GroupPagesPage.directory(GroupRoute route)
    : this._(kind: GroupPagesPageKind.directory, route: route);

  const GroupPagesPage.detail(GroupRoute route)
    : this._(kind: GroupPagesPageKind.detail, route: route);

  const GroupPagesPage.unknown(String routeId)
    : this._(kind: GroupPagesPageKind.unknown, unknownRouteId: routeId);

  final GroupPagesPageKind kind;
  final GroupRoute? route;
  final String? unknownRouteId;

  bool get isOwned => kind != GroupPagesPageKind.none;
}

final class GroupPagesRouteSnapshot {
  const GroupPagesRouteSnapshot({
    required this.owner,
    required this.routeId,
    required this.groupNamespace,
    required this.route,
    required this.canPopContent,
  });

  final GroupPagesOwner owner;
  final String routeId;
  final bool groupNamespace;
  final GroupRoute? route;
  final bool canPopContent;
}

abstract interface class GroupPagesCoordinatorPort {
  bool isCurrent(GroupPagesOwner owner);

  String? usernameFor(GroupPagesOwner owner);

  Future<void> loadDirectory(
    GroupPagesOwner owner,
    GroupPagesDirectoryQuery query, {
    required bool refresh,
    required bool more,
  });

  Future<void> loadDetail(
    GroupPagesOwner owner,
    GroupRoute route, {
    required bool refresh,
  });

  Future<void> loadSection(
    GroupPagesOwner owner,
    GroupRoute route,
    GroupPagesMemberQuery memberQuery, {
    required bool refresh,
    required bool more,
  });

  void selectRoute(GroupRoute route, {String? feedPath});

  void replaceWithGroup(String groupName);

  void replaceWithDirectory();

  bool handleBack({required bool canReturnToSidebar});
}

/// Owns the non-rendering lifecycle of the native Groups surface.
///
/// The coordinator retains only route and session identities plus page-local
/// filters. The shell adapter performs I/O and navigation, while widgets render
/// the resulting controller state and dispatch user intent here.
final class GroupPagesCoordinator {
  GroupPagesCoordinator();

  GroupPagesCoordinatorPort? _port;
  GroupPagesRouteSnapshot? _snapshot;
  GroupPagesPage _page = const GroupPagesPage.none();
  GroupPagesChildIdentity? _childIdentity;
  GroupPagesDirectoryQuery _directoryQuery = const GroupPagesDirectoryQuery();
  GroupPagesMemberQuery _memberQuery = const GroupPagesMemberQuery();
  int _generation = 0;
  ({int generation, GroupRoute? route})? _requestedLoad;
  bool _disposed = false;

  GroupPagesPage get page => _page;

  GroupPagesChildIdentity? get childIdentity => _childIdentity;

  GroupPagesDirectoryQuery get directoryQuery => _directoryQuery;

  GroupPagesMemberQuery get memberQuery => _memberQuery;

  void bind(GroupPagesCoordinatorPort port, GroupPagesRouteSnapshot snapshot) {
    if (_disposed) return;
    final page = _resolve(snapshot);
    final childIdentity = _identityFor(snapshot.owner, page);
    final previousSnapshot = _snapshot;
    final routeChanged = previousSnapshot?.route != snapshot.route;
    final childChanged = _childIdentity != childIdentity;
    final ownerChanged = previousSnapshot?.owner != snapshot.owner;

    _port = port;
    _snapshot = snapshot;
    _page = page;
    _childIdentity = childIdentity;
    if (routeChanged || childChanged || ownerChanged) {
      _generation++;
      _requestedLoad = null;
    }
    if (childChanged || ownerChanged) {
      _directoryQuery = const GroupPagesDirectoryQuery();
      _memberQuery = const GroupPagesMemberQuery();
    }
  }

  static GroupPagesPage resolve(GroupPagesRouteSnapshot snapshot) =>
      _resolve(snapshot);

  static GroupPagesPage _resolve(GroupPagesRouteSnapshot snapshot) {
    if (!snapshot.groupNamespace) return const GroupPagesPage.none();
    final route = snapshot.route;
    if (route == null) return GroupPagesPage.unknown(snapshot.routeId);
    if (route.isDirectory) return GroupPagesPage.directory(route);
    if (route.groupName != null && route.section != null) {
      return GroupPagesPage.detail(route);
    }
    return GroupPagesPage.unknown(snapshot.routeId);
  }

  static GroupPagesChildIdentity? _identityFor(
    GroupPagesOwner owner,
    GroupPagesPage page,
  ) => switch (page.kind) {
    GroupPagesPageKind.none => null,
    GroupPagesPageKind.directory => (owner: owner, pageId: 'directory'),
    GroupPagesPageKind.detail => (
      owner: owner,
      pageId: 'group:${page.route!.groupName}',
    ),
    GroupPagesPageKind.unknown => (
      owner: owner,
      pageId: 'unknown:${page.unknownRouteId}',
    ),
  };

  GroupPagesBackIntent backIntent({required bool canReturnToSidebar}) {
    final snapshot = _snapshot;
    if (!_page.isOwned || snapshot == null) return GroupPagesBackIntent.none;
    if (snapshot.canPopContent) return GroupPagesBackIntent.popContent;
    return canReturnToSidebar
        ? GroupPagesBackIntent.showSidebar
        : GroupPagesBackIntent.none;
  }

  bool handleBack({required bool canReturnToSidebar}) {
    final intent = backIntent(canReturnToSidebar: canReturnToSidebar);
    if (intent == GroupPagesBackIntent.none) return false;
    return _port?.handleBack(canReturnToSidebar: canReturnToSidebar) ?? false;
  }

  Future<void> requestLoad({bool refresh = false}) async {
    final snapshot = _snapshot;
    final port = _port;
    final route = _page.route;
    if (_disposed || snapshot == null || port == null || route == null) return;
    final request = (generation: _generation, route: route);
    if (!refresh && _requestedLoad == request) return;
    _requestedLoad = request;

    if (_page.kind == GroupPagesPageKind.directory) {
      await port.loadDirectory(
        snapshot.owner,
        _directoryQuery,
        refresh: refresh,
        more: false,
      );
      return;
    }
    if (_page.kind != GroupPagesPageKind.detail) return;

    await port.loadDetail(snapshot.owner, route, refresh: refresh);
    if (!_isCurrent(request)) return;
    await port.loadSection(
      snapshot.owner,
      route,
      _memberQuery,
      refresh: refresh,
      more: false,
    );
  }

  Future<void> loadMore() async {
    final snapshot = _snapshot;
    final port = _port;
    final route = _page.route;
    if (_disposed || snapshot == null || port == null || route == null) return;
    if (_page.kind == GroupPagesPageKind.directory) {
      await port.loadDirectory(
        snapshot.owner,
        _directoryQuery,
        refresh: false,
        more: true,
      );
    } else if (_page.kind == GroupPagesPageKind.detail) {
      await port.loadSection(
        snapshot.owner,
        route,
        _memberQuery,
        refresh: false,
        more: true,
      );
    }
  }

  bool replaceDirectoryQuery(GroupPagesDirectoryQuery query) {
    if (_disposed || query == _directoryQuery) return false;
    _directoryQuery = query;
    _generation++;
    _requestedLoad = null;
    return true;
  }

  bool replaceMemberQuery(GroupPagesMemberQuery query) {
    if (_disposed || query == _memberQuery) return false;
    _memberQuery = query;
    _generation++;
    _requestedLoad = null;
    return true;
  }

  void selectRoute(GroupRoute route) {
    final snapshot = _snapshot;
    final current = _page.route;
    final port = _port;
    if (_disposed ||
        snapshot == null ||
        port == null ||
        _page.kind != GroupPagesPageKind.detail ||
        current?.groupName != route.groupName ||
        current == route ||
        !port.isCurrent(snapshot.owner)) {
      return;
    }
    port.selectRoute(
      route,
      feedPath: route.topicFeedPath(port.usernameFor(snapshot.owner)),
    );
  }

  void switchGroup(String groupName) {
    final snapshot = _snapshot;
    if (_disposed ||
        snapshot == null ||
        _page.kind != GroupPagesPageKind.detail ||
        !(_port?.isCurrent(snapshot.owner) ?? false)) {
      return;
    }
    _port?.replaceWithGroup(groupName);
  }

  void showDirectory() {
    final snapshot = _snapshot;
    if (_disposed ||
        snapshot == null ||
        !(_port?.isCurrent(snapshot.owner) ?? false)) {
      return;
    }
    _port?.replaceWithDirectory();
  }

  bool _isCurrent(({int generation, GroupRoute? route}) request) {
    final snapshot = _snapshot;
    return !_disposed &&
        request.generation == _generation &&
        request.route == _page.route &&
        snapshot != null &&
        (_port?.isCurrent(snapshot.owner) ?? false);
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _requestedLoad = null;
    _port = null;
    _snapshot = null;
    _page = const GroupPagesPage.none();
    _childIdentity = null;
  }
}
