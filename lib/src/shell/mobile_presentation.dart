import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/content_route.dart';
import '../plugin_api/plugin_registry.dart';
import 'shell_controller.dart';

typedef _MobilePagePolicy = ({bool sheet, bool ownChrome});

final class MobilePresentation {
  MobilePresentation._(
    this._policies,
    this._predecessors, {
    required this.route,
    required this.searchRoute,
    required this.searchSourceRoute,
    required this.retainedListRoute,
    required this.pageSheetOpen,
    required this.hideDock,
    required this.preservePageChrome,
  });

  factory MobilePresentation.resolve(
    BuildContext context, {
    required ShellController shell,
    required PluginRegistry registry,
    required bool panelRoot,
    bool boundary = false,
  }) {
    final route = boundary ? null : shell.currentContent;
    final navigation = shell.mobileNavigation;
    final history = navigation.state;
    final visits = history.visits.take(history.index + 1).toList();
    final stack = shell.activeTab?.contentStack ?? const <ContentRoute>[];
    final predecessors = <Object, ContentRoute?>{};
    for (var i = 0; i < visits.length; i++) {
      if (visits[i]?.contentStack.last case final page?) {
        predecessors[page.destination.identity] = i > 0
            ? visits[i - 1]?.contentStack.last
            : null;
      }
    }
    final policies = <Object, _MobilePagePolicy>{};
    _MobilePagePolicy policy(ContentRoute page) => policies.putIfAbsent(
      page.destination.identity,
      () => (
        sheet: page.isTopic || registry.usesMobilePageSheet(context, page),
        ownChrome: registry.ownsContentChrome(context, page),
      ),
    );
    final search = stack.where((page) => page.isGlobalSearch).lastOrNull;
    final searchSource = search == null
        ? null
        : predecessors[search.destination.identity];
    ContentRoute? source;
    for (final visit in visits.reversed) {
      final page = visit?.contentStack.last;
      if (page == null) break;
      if (page.isTopicList && stack.any(page.sameDestinationAs)) {
        source = page;
        break;
      }
      if (!policy(page).sheet) break;
    }
    final previous = navigation.previousLocation?.contentStack.last;
    for (final page in {?route, ?previous, ?searchSource, ?source}) {
      policy(page);
      if (predecessors[page.destination.identity] case final preceding?) {
        policy(preceding);
      }
    }
    final sheet =
        !boundary && !panelRoot && route != null && policy(route).sheet;
    final hideDock =
        !boundary &&
        !panelRoot &&
        route != null &&
        registry.hidesMobileDock(context, route);
    return MobilePresentation._(
      policies,
      predecessors,
      route: route,
      searchRoute: search,
      searchSourceRoute: searchSource,
      retainedListRoute: source,
      pageSheetOpen: sheet,
      hideDock: hideDock,
      preservePageChrome:
          sheet &&
          hideDock &&
          (previous?.isTopicList == true || previous?.isTopic == true),
    );
  }

  final ContentRoute? route;
  final ContentRoute? searchRoute;
  final ContentRoute? searchSourceRoute;
  final ContentRoute? retainedListRoute;
  final bool pageSheetOpen;
  final bool hideDock;
  final bool preservePageChrome;
  final Map<Object, _MobilePagePolicy> _policies;
  final Map<Object, ContentRoute?> _predecessors;

  ContentRoute? previousOf(ContentRoute? route) =>
      route == null ? null : _predecessors[route.destination.identity];
  bool usesSheet(ContentRoute route) =>
      _policies[route.destination.identity]?.sheet ?? false;
  bool ownsChrome(ContentRoute route) =>
      _policies[route.destination.identity]?.ownChrome ?? false;
}

class MobilePresentationScope extends InheritedWidget {
  const MobilePresentationScope({
    super.key,
    required this.presentation,
    required super.child,
  });

  final MobilePresentation presentation;

  static MobilePresentation? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<MobilePresentationScope>()
      ?.presentation;

  @override
  bool updateShouldNotify(MobilePresentationScope oldWidget) {
    final previous = oldWidget.presentation;
    return !identical(presentation.route, previous.route) ||
        !identical(presentation.searchRoute, previous.searchRoute) ||
        !identical(
          presentation.searchSourceRoute,
          previous.searchSourceRoute,
        ) ||
        !identical(
          presentation.retainedListRoute,
          previous.retainedListRoute,
        ) ||
        presentation.pageSheetOpen != previous.pageSheetOpen ||
        presentation.hideDock != previous.hideDock ||
        presentation.preservePageChrome != previous.preservePageChrome ||
        !mapEquals(presentation._policies, previous._policies) ||
        !mapEquals(presentation._predecessors, previous._predecessors);
  }
}
