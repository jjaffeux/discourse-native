import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/discourse_instance.dart';
import '../models/sidebar.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import '../theme/d_native_icons.dart';
import 'account_menu_scope.dart';
import 'composer/presentation.dart';
import 'forum_search.dart';
import 'forum_theme_surfaces.dart';
import 'instance_rail.dart';
import 'instance_sidebar.dart';
import 'message_create_button.dart';
import 'mobile_dock_panel_scope.dart';
import 'mobile_footer_action.dart';
import 'mobile_navigation.dart';
import 'mobile_place_order.dart';
import 'mobile_scroll_dock.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'user_menu.dart';
import 'user_menu_button.dart';

typedef _DockDestination = ({
  MobileTab tab,
  String label,
  DIconData icon,
  Widget? badge,
  VoidCallback onPressed,
});

const double _mobileRailWidth = 68;

/// Persistent mobile chrome around one live feature renderer.
class MobileForumRoot extends StatefulWidget {
  const MobileForumRoot({
    super.key,
    required this.content,
    this.boundary = false,
  });

  final Widget content;
  final bool boundary;

  @override
  State<MobileForumRoot> createState() => _MobileForumRootState();
}

class _MobileForumRootState extends State<MobileForumRoot> {
  final _navigationPageKey = GlobalKey();
  final MobileFooterActionController _footerAction =
      MobileFooterActionController();

  // The drawer's profile menu, also opened by the dock's profile tile.
  final _accountMenu = DPopoverController();

  @override
  void dispose() {
    _footerAction.dispose();
    _accountMenu.dispose();
    super.dispose();
  }

  // Built once per content. The account button that hands the profile card
  // down wraps the chrome in its menus and rebuilds on its own account,
  // presence and unread counts among them; the chrome, the same widget each
  // time, stays. New content, or a boundary, is the chrome's own change.
  Widget? _chrome;

  @override
  void didUpdateWidget(MobileForumRoot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.content != oldWidget.content ||
        widget.boundary != oldWidget.boundary) {
      _chrome = null;
    }
  }

  @override
  Widget build(BuildContext context) => MobileFooterActionScope(
    controller: _footerAction,
    child: UserMenuButton.drawer(
      builder: _buildWithProfileFooter,
      profileController: _accountMenu,
    ),
  );

  Widget _buildWithProfileFooter(BuildContext context, Widget? profileFooter) =>
      _ProfileFooterScope(
        footer: profileFooter,
        child: _chrome ??= Builder(builder: _buildChrome),
      );

  Widget _buildChrome(BuildContext context) {
    final shell = ShellScope.read(context);
    final registry = PluginScope.of(context).registry;
    // The account's own order of the places; another account's comes with a
    // new controller, and this build with it.
    final placeOrder = MobilePlaceOrderHost.maybeOf(context);
    // The chrome reads facade and plugin state only. Topic feeds notify
    // several times per page, and the widgets that read them listen directly.
    final body = ListenableBuilder(
      listenable: Listenable.merge([
        shell,
        ?placeOrder,
        shell.accountActivity.totalsListenable,
        shell.draftList,
        ...registry.sidebarPanelListenables(context),
        ...registry.communitySidebarListenables(context),
        ...registry.startPageListenables(context),
      ]),
      builder: (context, _) {
        final instance = shell.currentInstance;
        if (instance == null) return const SizedBox.shrink();
        final owner = (instance.url, shell.currentAccountIdentity);
        final sidebarOpen = shell.mobileNavigation.sidebarOpen;
        final foot = MediaQuery.paddingOf(context).bottom;
        final navigationPage = CallbackShortcuts(
          key: _navigationPageKey,
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape):
                shell.closeMobileSidebar,
          },
          child: Focus(
            autofocus: sidebarOpen,
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: Padding(
                key: const ValueKey('mobile-navigation-page'),
                padding: EdgeInsets.only(
                  bottom: DMobileDockGeometry(foot: foot).endLift,
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(
                            width: _mobileRailWidth,
                            child: InstanceRail(),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6, right: 6),
                              child: ForumMobileSurface.sidebar(
                                key: const ValueKey('mobile-navigation-panel'),
                                child: InstanceSidebar(
                                  key: ValueKey(('mobile-navigation', owner)),
                                  mobile: true,
                                  onNavigate: shell.closeMobileSidebar,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const _ProfileFooterSlot(),
                  ],
                ),
              ),
            ),
          ),
        );
        final panels = registry
            .sidebarPanels(context)
            .where((entry) => entry.panel.showSwitch)
            .toList();
        final selected = shell.mobileNavigation.tab;
        final places = _mobilePlaces(
          context,
          shell: shell,
          registry: registry,
          instance: instance,
          panels: panels,
          selected: selected,
          order: placeOrder?.order ?? const [],
        );
        final tabOrder = [for (final place in places) place.tab];
        if (!tabOrder.contains(selected)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && shell.mobileNavigation.tab == selected) {
              shell.selectMobileDestination(
                MobileTab.topics,
                instance.defaultDestination,
              );
            }
          });
        }
        // Resolve the nullable owner before the panel loop. Dart's iOS AOT
        // optimizer can hoist panel.owner past the panelRoot guard and crash
        // on Topics startup, where there is no selected panel.
        final panelOwner = panels
            .where((p) => p.owner.value == selected.panelOwner)
            .firstOrNull
            ?.owner
            .value;
        final panelRoot =
            !widget.boundary &&
            shell.mobileNavigation.atRoot &&
            panelOwner != null;
        final pageSheetOpen =
            !widget.boundary &&
            !panelRoot &&
            switch (shell.currentContent) {
              final route? =>
                route.isTopic || registry.usesMobilePageSheet(context, route),
              null => false,
            };
        final hideDock =
            !widget.boundary &&
            !panelRoot &&
            switch (shell.currentContent) {
              final route? => registry.hidesMobileDock(context, route),
              null => false,
            };
        final source = shell.topicListContent;
        // A board covers the list without starting a new scroll-chrome session.
        final preserveListChrome =
            pageSheetOpen &&
            hideDock &&
            shell
                    .mobileNavigation
                    .previousLocation
                    ?.contentStack
                    .last
                    .isTopicList ==
                true;
        final showReply =
            !widget.boundary &&
            !panelRoot &&
            shell.currentContent?.isTopic == true &&
            shell.canReplyHere;
        final showNewTopic =
            !widget.boundary &&
            selected == MobileTab.topics &&
            shell.currentContent?.isTopic != true &&
            source?.isTopicList == true &&
            source?.isMessages != true &&
            shell.canCreateTopicFromSidebar;
        final showNewMessage =
            !widget.boundary &&
            selected == MobileTab.messages &&
            shell.currentContent?.isMessages == true &&
            instance.isConnected &&
            instance.user?.canSendPrivateMessages == true;
        final panelAction = panelRoot
            ? panels
                  .where((p) => p.owner.value == panelOwner)
                  .firstOrNull
                  ?.panel
                  .mobileAction
            : null;
        Widget frame(BuildContext context, Widget page) => Column(
          key: const ValueKey('mobile-root'),
          children: [
            // Ancestor Material ink layers also repaint on scroll. Retain the
            // fixed header independently of the moving page and dock.
            RepaintBoundary(
              child: DSheetDragRegion(
                child: ForumSidebarTheme(
                  child: Padding(
                    key: const ValueKey('mobile-header'),
                    padding: const EdgeInsetsDirectional.fromSTEB(0, 8, 14, 4),
                    child: Builder(
                      builder: (context) {
                        final navigation = <Widget>[
                          SizedBox(
                            width: _mobileRailWidth,
                            child: Center(
                              child: DButton.iconOnly(
                                key: const ValueKey('mobile-menu-button'),
                                icon: const DIconGlyphTheme(
                                  scale: 1,
                                  naturalWidth: true,
                                  child: DIcon(DNativeIcons.bars, size: 20),
                                ),
                                tooltip: sidebarOpen
                                    ? context.l10n.closeNavigation
                                    : context.l10n.openNavigation,
                                variant: DButtonVariant.inline,
                                expanded: sidebarOpen,
                                onPressed: () {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  shell.toggleMobileSidebar();
                                },
                              ),
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: ForumIdentityHeader(
                                size: 32,
                                name: instance.title,
                                iconUrl: instance.iconUrl,
                                monogram: instance.monogram,
                                accentColor: instance.accentColor,
                              ),
                            ),
                          ),
                          const ForumSearch(fullScreen: true),
                        ];
                        final actions = <Widget>[
                          ...registry.shellHeaderActions(
                            context,
                            surface: PluginHeaderSurface.content,
                            compact: true,
                            ringColor: ForumWindowBackground.chromeColor(
                              context,
                              Theme.of(context).shell.sidebar,
                            ),
                          ),
                          const UserMenuButton(
                            compact: true,
                            presentation: UserMenuPresentation.notifications,
                          ),
                        ];
                        final largeText =
                            MediaQuery.textScalerOf(context).scale(12) > 18;
                        if (largeText) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(spacing: 10, children: navigation),
                              const SizedBox(height: DSpacing.controlGap),
                              Wrap(
                                alignment: WrapAlignment.end,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                runSpacing: DSpacing.controlGap,
                                children: actions,
                              ),
                            ],
                          );
                        }
                        return Row(
                          spacing: 10,
                          children: [
                            ...navigation,
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: actions,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              // The page runs under the home indicator; only the floating dock
              // keeps clear of it, and pages pad their last row by its height.
              // A route without a dock keeps an empty footer of that clearance.
              child: ListenableBuilder(
                listenable: _footerAction,
                child: page,
                builder: (context, content) {
                  final swipe = DHistoryTransition.swipeOf(context);
                  final sidebarEntry = (
                    shell.mobileNavigation.historyId,
                    'sidebar',
                  );
                  final hidden = sidebarOpen
                      ? 1.0 - (swipe?.progress ?? 0.0)
                      : swipe?.entry == sidebarEntry
                      ? swipe!.progress
                      : 0.0;
                  return MobileScrollDock(
                    identity: (
                      owner,
                      selected,
                      preserveListChrome
                          ? shell.mobileNavigation.previousEntryId
                          : shell.mobileNavigation.entryId,
                      widget.boundary,
                    ),
                    visible: hidden < 1,
                    hiddenFraction: hidden,
                    hideOnScroll: !hideDock || preserveListChrome,
                    keepActionVisible: _footerAction.action != null,
                    body: NotificationListener<ScrollNotification>(
                      onNotification: (_) => preserveListChrome,
                      child: content!,
                    ),
                    dockBuilder: (hidden) {
                      // A parked draft waits over the bar, which keeps pages
                      // clear of both.
                      final parked = ComposerDock.parkedDraftRoomOf(context);
                      if (hideDock) {
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom:
                                parked + MediaQuery.paddingOf(context).bottom,
                          ),
                        );
                      }
                      final geometry = DMobileDockGeometry.of(context);
                      return ForumSidebarTheme(
                        child: Padding(
                          padding: geometry.margin.add(
                            EdgeInsets.only(top: parked),
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) => _buildBottomBar(
                              context,
                              constraints,
                              geometry: geometry,
                              destinations: places,
                              selected: selected,
                              instance: instance,
                              showReply: showReply,
                              showNewMessage: showNewMessage,
                              panelAction: panelAction,
                              showNewTopic: showNewTopic,
                              shell: shell,
                              placeOrder: placeOrder,
                              hideDestinations: hidden,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
        return MobileHistoryGestures(
          tab: (id: selected, index: tabOrder.indexOf(selected)),
          navigationPreview: navigationPage,
          frameBuilder: frame,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: sidebarOpen,
                child: TickerMode(
                  enabled: !sidebarOpen,
                  child: ExcludeFocus(
                    excluding: sidebarOpen,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ForumMobileSurface(
                        key: const ValueKey('mobile-content-panel'),
                        coveredBySheet: pageSheetOpen,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            for (final entry in panels)
                              Offstage(
                                offstage:
                                    !(panelRoot &&
                                        panelOwner == entry.owner.value),
                                child: TickerMode(
                                  enabled:
                                      panelRoot &&
                                      panelOwner == entry.owner.value,
                                  child: ExcludeFocus(
                                    excluding:
                                        !(panelRoot &&
                                            panelOwner == entry.owner.value),
                                    child: InstanceSidebar(
                                      key: ValueKey((
                                        'mobile-panel',
                                        entry.owner.value,
                                        owner,
                                      )),
                                      mobile: true,
                                      panelOwner: entry.owner.value,
                                    ),
                                  ),
                                ),
                              ),
                            if (!panelRoot) widget.content,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (sidebarOpen) navigationPage,
            ],
          ),
        );
      },
    );
    return body;
  }

  Widget _buildBottomBar(
    BuildContext context,
    BoxConstraints constraints, {
    required DMobileDockGeometry geometry,
    required List<_DockDestination> destinations,
    required MobileTab selected,
    required DiscourseInstance instance,
    required bool showReply,
    required bool showNewMessage,
    required SidebarPanelAction? panelAction,
    required bool showNewTopic,
    required ShellController shell,
    required MobilePlaceOrderController? placeOrder,
    required bool hideDestinations,
  }) {
    final pageAction = _footerAction.action;
    final actionIcon =
        pageAction?.icon ??
        (showReply
            ? DIcons.reply
            : showNewMessage
            ? DIcons.penToSquare
            : panelAction?.icon ?? DIcons.penToSquare);
    Widget? primaryAction;
    if (pageAction case final action?) {
      primaryAction = _dockAction(
        key: action.key ?? const ValueKey('mobile-page-action'),
        icon: action.icon,
        loading: action.loading,
        label: action.label,
        onPressed: action.onPressed,
      );
    } else if (showReply) {
      primaryAction = _dockAction(
        key: const ValueKey('mobile-topic-reply'),
        icon: DIcons.reply,
        label: context.l10n.reply,
        onPressed: shell.openReply,
      );
    } else if (showNewMessage) {
      primaryAction = const MessageCreateButton(
        showLabel: false,
        pill: true,
        dockAction: true,
      );
    } else if (panelAction != null) {
      primaryAction = _dockAction(
        key: const ValueKey('mobile-panel-action'),
        icon: panelAction.icon,
        label: panelAction.label,
        onPressed: panelAction.onPressed,
      );
    } else if (showNewTopic || shell.canCreateTopicFromSidebar) {
      primaryAction = _dockAction(
        key: const ValueKey('mobile-new-topic'),
        icon: DIcons.penToSquare,
        label: context.l10n.newTopic,
        onPressed: () => unawaited(shell.openNewTopicFromSidebar()),
      );
    }
    final active = destinations
        .where((item) => item.tab == selected)
        .firstOrNull;
    // Found now: the dock also tells it as it is disposed, when this context
    // is no longer one to look up from.
    final panelOut = MobileDockPanelScope.of(context);
    // Notifications paused rings the you tile, and nothing else here.
    return ListenableBuilder(
      listenable: shell.doNotDisturb,
      builder: (context, _) {
        final places = <String, DMobileDockPlace>{
          for (final item in destinations)
            item.tab.name: DMobileDockPlace(
              key: ValueKey('mobile-mode-${item.tab.name}'),
              icon: DIcon(item.icon),
              label: item.label,
              badge: item.badge,
              selected: selected == item.tab,
              onPressed: item.onPressed,
            ),
          'profile': ?_profilePlace(context, shell: shell, instance: instance),
        };
        final order = MobilePlaceOrderController.apply(
          places.keys.toList(),
          placeOrder?.order ?? const [],
          (name) => name,
        );
        return DMobileDock(
          key: const ValueKey('mobile-bottom-bar'),
          geometry: geometry,
          collapsed: hideDestinations && pageAction == null,
          destinationsHidden: hideDestinations && pageAction != null,
          // A composer's sheet covers the shell from inside it; the panel, which
          // paints over the shell, must not stand over the sheet.
          covered: ComposerPresentationHost.hasMobileSheetOf(context),
          collapsedDestination: DMobileDockItem(
            key: const ValueKey('mobile-dock-reveal'),
            collapsed: true,
            icon: DIcon(active?.icon ?? DIcons.ellipsisVertical),
            label:
                '${active?.label ?? context.l10n.more}, ${context.l10n.openNavigation}',
            onPressed: () => DScrollChrome.maybeOf(context)?.reveal(),
          ),
          places: [for (final name in order) places[name]!],
          more: (
            icon: const DIcon(DIcons.ellipsisVertical),
            label: context.l10n.more,
          ),
          onPanelChanged: panelOut == null
              ? null
              : (out) => panelOut.value = out,
          // The order written is the one shown, the moved place in its new
          // slot; a place hidden for now, Drafts between drafts, keeps the
          // slot it had.
          onMoved: placeOrder == null
              ? null
              : (from, to) => unawaited(
                  placeOrder.place(DMobileDockReorder.moved(order, from, to)),
                ),
          action: primaryAction == null
              ? null
              : DActionTransition(
                  key: ValueKey((
                    shell.currentInstance?.url,
                    shell.currentAccountIdentity,
                  )),
                  child: KeyedSubtree(
                    key: ValueKey(actionIcon),
                    child: primaryAction,
                  ),
                ),
        );
      },
    );
  }

  /// The profile is a place with the same ordering as every other dock tile.
  DMobileDockPlace? _profilePlace(
    BuildContext context, {
    required ShellController shell,
    required DiscourseInstance instance,
  }) {
    final user = instance.user;
    final username = user?.username;
    if (!instance.isConnected || username == null) return null;
    final tokens = DTokens.of(context);
    final paused = shell.doNotDisturb
        .stateFor(instance.url)
        .isActiveAt(DateTime.now());
    final hidePresence = shell.hidePresenceFor(instance.url);
    final presence = paused
        ? context.l10n.notificationsPaused
        : hidePresence == false
        ? context.l10n.online
        : hidePresence == true
        ? context.l10n.offline
        : context.l10n.presenceUnavailable;
    return DMobileDockPlace.avatar(
      key: const ValueKey('mobile-mode-profile'),
      face: UserMenuAvatar(
        avatarUrl: user?.avatarUrl,
        initial: username.characters.first.toUpperCase(),
        connecting: shell.connecting,
        dimension: 22,
      ),
      label: user?.displayName ?? username,
      ring: paused
          ? tokens.subtleMark
          : hidePresence == false
          ? tokens.success
          : null,
      semanticLabel: '${context.l10n.yourAccount}, $presence',
      onPressed: () {
        AccountMenuScope.activate(context, _accountMenu);
        _accountMenu.open();
      },
    );
  }

  Widget _dockAction({
    required Key key,
    required DIconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool loading = false,
  }) => DMobileDockAction(
    buttonKey: key,
    icon: DIcon(icon),
    label: label,
    loading: loading,
    onPressed: onPressed,
  );
}

/// Every place the phone offers, in the order its bar shows them and the
/// panel the bar grows into holds the rest: the ones the person has placed,
/// as [order] names them, then the rest in their own order. The bar is the
/// phone's Start page, so this list holds what that page offers elsewhere;
/// the dock and the history gestures read this one order.
List<_DockDestination> _mobilePlaces(
  BuildContext context, {
  required ShellController shell,
  required PluginRegistry registry,
  required DiscourseInstance instance,
  required List<OwnedSidebarPanel> panels,
  required MobileTab selected,
  required List<String> order,
}) {
  final signedIn = instance.isConnected;
  final destinations = instance.sections
      .expand(
        (section) => [...section.destinations, ...section.moreDestinations],
      )
      .toList();
  SidebarDestination? destination(String id) =>
      destinations.where((entry) => entry.id == id).firstOrNull;
  _DockDestination page(SidebarDestination destination, {String? label}) {
    final tab = MobileTab.destination(destination.id);
    return (
      tab: tab,
      label: label ?? destination.label,
      icon: destination.icon,
      badge: null,
      onPressed: () => shell.selectMobileDestination(tab, destination),
    );
  }

  final shortcuts = registry
      .communitySidebarDestinations(context)
      .where(
        (destination) =>
            destination.mobileNavigationLabel != null && destination.enabled,
      )
      .toList();
  // A contributed section can be the shortcut already offered above.
  final startSections = [
    for (final section in registry.startPageSections(context))
      if (section.destination.enabled &&
          !shortcuts.any((shortcut) => shortcut.id == section.destination.id))
        section.destination,
  ];
  final hasResumableDraft = shell.draftList
      .feedFor(instance.url)
      .drafts
      .any((draft) => draft.canResume);
  final places = <_DockDestination>[
    (
      tab: MobileTab.topics,
      label: context.l10n.topics,
      icon: DIcons.layerGroup,
      badge: null,
      onPressed: () => shell.selectMobileDestination(
        MobileTab.topics,
        instance.defaultDestination,
      ),
    ),
    for (final entry in panels)
      (
        tab: MobileTab.panel(entry.owner.value),
        label: entry.panel.label,
        icon: entry.panel.icon,
        badge: entry.panel.mobileBadge ?? entry.panel.badge,
        onPressed: () => shell.selectMobilePanel(entry.owner.value),
      ),
    if (signedIn)
      page(
        SidebarDestination(
          id: 'user-bookmarks',
          label: context.l10n.bookmarks,
          icon: DIcons.bookmark,
        ),
      ),
    if (instance.user?.staff == true) page(SidebarDestination.dashboard()),
    if (destination('messages') case final messages?)
      (
        tab: MobileTab.messages,
        label: context.l10n.inbox,
        icon: DIcons.inbox,
        badge: null,
        onPressed: () =>
            shell.selectMobileDestination(MobileTab.messages, messages),
      ),
    if (destination('users') case final users?)
      (
        tab: MobileTab.users,
        label: context.l10n.users,
        icon: DIcons.users,
        badge: null,
        onPressed: () => shell.selectMobileDestination(MobileTab.users, users),
      ),
    for (final shortcut in shortcuts)
      page(shortcut, label: shortcut.mobileNavigationLabel),
    page(
      SidebarDestination(
        id: 'all-categories',
        label: context.l10n.categories,
        icon: DIcons.tag,
      ),
    ),
    for (final id in ['groups', 'badges'])
      if (destination(id) case final entry?) page(entry),
    page(
      SidebarDestination(
        id: 'appearance',
        label: context.l10n.interface,
        icon: DIcons.gear,
      ),
    ),
    if (signedIn) ...[
      page(
        SidebarDestination(
          id: 'preferences',
          label: context.l10n.preferences,
          icon: DIcons.gear,
        ),
      ),
      page(
        SidebarDestination(
          id: 'summary',
          label: context.l10n.summary,
          icon: DIcons.user,
        ),
      ),
      page(
        SidebarDestination(
          id: 'activity',
          label: context.l10n.activity,
          icon: DIcons.barsStaggered,
        ),
      ),
    ],
    for (final section in startSections) page(section),
    // Deleting the last draft from its own page keeps the page open.
    if (destination('drafts') case final drafts?
        when signedIn &&
            (hasResumableDraft || selected == MobileTab.destination(drafts.id)))
      page(drafts),
  ];
  return MobilePlaceOrderController.apply(
    places,
    order,
    (place) => place.tab.name,
  );
}

/// Adapts mobile visit history to the Native interactive transition.
class MobileHistoryGestures extends StatelessWidget {
  const MobileHistoryGestures({
    super.key,
    required this.child,
    required this.tab,
    required this.navigationPreview,
    required this.frameBuilder,
  });
  final Widget child;

  /// The place the person is on, and where it stands among the places.
  final DHistoryTab tab;
  final Widget navigationPreview;
  final Widget Function(BuildContext context, Widget page) frameBuilder;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final navigation = shell.mobileNavigation;
    final sidebarOpen = navigation.sidebarOpen;
    final sidebarEntry = (navigation.historyId, 'sidebar');
    return DSheetDragScope(
      child: DHistoryTransition(
        frameBuilder: frameBuilder,
        history: navigation.historyId,
        tab: sidebarOpen ? (id: sidebarEntry, index: -1) : tab,
        tabOwner: (shell.currentInstance?.url, shell.currentAccountIdentity),
        tabClipper: sidebarOpen
            ? null
            : const DHistoryTabClipper(
                borderRadius: DSheetViewport.pageBorderRadius,
                insets: EdgeInsets.only(top: 6),
              ),
        entry: sidebarOpen ? sidebarEntry : navigation.entryId,
        backSwipeAnywhere: true,
        navigation: sidebarOpen
            ? null
            : DHistoryNavigation(
                entry: sidebarEntry,
                preview: navigationPreview,
                onOpen: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  shell.toggleMobileSidebar();
                },
              ),
        previousEntry: sidebarOpen ? null : navigation.previousEntryId,
        nextEntry: sidebarOpen ? navigation.entryId : navigation.nextEntryId,
        onBack: !sidebarOpen && navigation.canGoBack
            ? () {
                FocusManager.instance.primaryFocus?.unfocus();
                shell.handleBack();
              }
            : null,
        onForward: sidebarOpen || navigation.canGoForward
            ? () {
                FocusManager.instance.primaryFocus?.unfocus();
                if (sidebarOpen) {
                  shell.closeMobileSidebar();
                } else {
                  shell.handleForward();
                }
              }
            : null,
        child: child,
      ),
    );
  }
}

/// The sidebar's profile card, handed down from the account button whose
/// menus it carries to the slot that shows it, so the button's rebuilds
/// reach the card and not the chrome between them.
class _ProfileFooterScope extends InheritedWidget {
  const _ProfileFooterScope({required this.footer, required super.child});

  final Widget? footer;

  static Widget? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ProfileFooterScope>()?.footer;

  @override
  bool updateShouldNotify(_ProfileFooterScope oldWidget) =>
      !identical(footer, oldWidget.footer);
}

/// The account card spans beneath both drawer columns.
class _ProfileFooterSlot extends StatelessWidget {
  const _ProfileFooterSlot();

  @override
  Widget build(BuildContext context) {
    final footer = _ProfileFooterScope.of(context);
    if (footer == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      child: footer,
    );
  }
}
