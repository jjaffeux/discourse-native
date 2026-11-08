import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
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
import 'mobile_page_title.dart';
import 'mobile_place_order.dart';
import 'mobile_presentation.dart';
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
  late final Widget _navigationPage = Builder(builder: _buildNavigationPage);
  final _navigationFocus = FocusNode(debugLabel: 'Mobile navigation');
  bool _navigationWasOpen = false;
  final _panelRoots = <(Object, String), Widget>{};
  List<MobileTab> _tabOrder = const [];
  ({Object owner, Object entry, DPageHeader header})? _navigationHeader;

  final MobileFooterActionController _footerAction =
      MobileFooterActionController();

  // The drawer's profile menu, also opened by the dock's profile tile.
  final _accountMenu = DPopoverController();

  // The notifications menu, which a phone opens from the bar's own place
  // for it; the header hosts the menu and draws no bell.
  final _notificationsMenu = DPopoverController();

  @override
  void dispose() {
    _navigationFocus.dispose();
    _footerAction.dispose();
    _accountMenu.dispose();
    _notificationsMenu.dispose();
    super.dispose();
  }

  // Built once per content. The account button that hands the profile card
  // down wraps the chrome in its menus and rebuilds on its own account and
  // presence; the chrome, the same widget each time, stays. New content, or a
  // boundary, is the chrome's own change.
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

  // Badge changes rebuild the dock. Retained pages keep their widget identity;
  // their own selectors still receive navigation, account and content updates.
  Widget _buildNavigationPage(BuildContext context) => ShellSelector(
    select: (shell) =>
        (shell.currentInstance?.url, shell.currentAccountIdentity),
    builder: (context, owner, _) {
      final shell = ShellScope.read(context);
      final instance = shell.currentInstance;
      if (instance == null) return const SizedBox.shrink();
      final foot = MediaQuery.paddingOf(context).bottom;
      return DScrollFootScope(
        // Navigation has its own footer. Its scroll fades must not follow
        // the page dock as that dock slides away during a reveal.
        foot: null,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape):
                shell.closeMobileSidebar,
          },
          child: ShellSelector<bool>(
            select: (shell) => shell.mobileNavigation.sidebarOpen,
            builder: (context, open, child) {
              if (_navigationWasOpen != open) {
                _navigationWasOpen = open;
                if (open) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _navigationWasOpen) {
                      _navigationFocus.requestFocus();
                    }
                  });
                }
              }
              return Focus(focusNode: _navigationFocus, child: child!);
            },
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
                                  mobilePlaceOf: _placeOf,
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
        ),
      );
    },
  );

  MobileTab _placeOf(SidebarDestination destination) {
    final tab = switch (destination.id) {
      'latest' => MobileTab.topics,
      'messages' => MobileTab.messages,
      'users' => MobileTab.users,
      _ => MobileTab.destination(destination.id),
    };
    return _tabOrder.contains(tab) ? tab : MobileTab.topics;
  }

  Widget _buildChrome(BuildContext context) {
    final shell = ShellScope.read(context);
    final registry = PluginScope.of(context).registry;
    // The account's own order of the places; another account's comes with a
    // new controller, and this build with it.
    final placeOrder = MobilePlaceOrderHost.maybeOf(context);
    // The chrome reads facade and plugin state only. Topic feeds notify
    // several times per page, and the widgets that read them listen directly.
    Widget body() => ListenableBuilder(
      listenable: Listenable.merge([
        ?placeOrder,
        shell.draftList,
        ...registry.sidebarPanelListenables(context),
        ...registry.communitySidebarListenables(context),
        ...registry.mobileNavigationListenables(context),
      ]),
      builder: (context, _) {
        final instance = shell.currentInstance;
        if (instance == null) return const SizedBox.shrink();
        final owner = (instance.url, shell.currentAccountIdentity);
        final sidebarOpen = shell.mobileNavigation.sidebarOpen;
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
        _tabOrder = tabOrder;
        _panelRoots.removeWhere(
          (key, _) =>
              key.$1 != owner ||
              !panels.any((entry) => entry.owner.value == key.$2),
        );
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
        final presentation = MobilePresentation.resolve(
          context,
          shell: shell,
          registry: registry,
          panelRoot: panelRoot,
          boundary: widget.boundary,
        );
        final route = presentation.route;
        final pageSheetOpen = presentation.pageSheetOpen;
        final hideDock = presentation.hideDock;
        final preservePageChrome = presentation.preservePageChrome;
        final source = shell.topicListContent;
        final showReply =
            !widget.boundary &&
            !panelRoot &&
            route?.isTopic == true &&
            shell.canReplyHere;
        final showNewTopic =
            !widget.boundary &&
            selected == MobileTab.topics &&
            route?.isTopic != true &&
            source?.isTopicList == true &&
            source?.isMessages != true &&
            shell.canCreateTopicFromSidebar;
        final showNewMessage =
            !widget.boundary &&
            selected == MobileTab.messages &&
            route?.isMessages == true &&
            instance.isConnected &&
            instance.user?.canSendPrivateMessages == true;
        final panelAction = widget.boundary
            ? null
            : panels
                  .where(
                    (p) => panelRoot
                        ? p.owner.value == panelOwner
                        : p.panel.active,
                  )
                  .firstOrNull
                  ?.panel
                  .mobileAction;
        Widget frameWithHeader(
          BuildContext context,
          ValueListenable<DPageHeader?> header,
          Widget page,
        ) => _MobileFrame(
          headerVisible: route?.isGlobalSearch != true,
          navigationOpen: sidebarOpen,
          raised: !sidebarOpen && pageSheetOpen && route?.isTopic == true,
          key: const ValueKey('mobile-root'),
          // Ancestor Material ink layers also repaint on scroll. Retain the
          // fixed header independently of the moving page and dock.
          header: RepaintBoundary(
            child: DSheetDragRegion(
              child: ForumSidebarTheme(
                child: Padding(
                  key: const ValueKey('mobile-header'),
                  padding: const EdgeInsetsDirectional.fromSTEB(0, 8, 14, 4),
                  child: Builder(
                    builder: (context) {
                      final navigation = <Widget>[
                        SizedBox(
                          width: 44,
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
                              onPressed: () {
                                FocusManager.instance.primaryFocus?.unfocus();
                                shell.toggleMobileSidebar();
                              },
                            ),
                          ),
                        ),
                        Expanded(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: MobilePageTitle.minimumExtentOf(
                                context,
                              ),
                            ),
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Row(
                                children: [
                                  DReferenceTextScale(
                                    child: DButton.iconOnly(
                                      key: const ValueKey('mobile-home-button'),
                                      tooltip: context.l10n.latestTopics,
                                      variant: DButtonVariant.inline,
                                      size: DButtonSize.segment,
                                      onPressed: () {
                                        if (!sidebarOpen &&
                                            selected == MobileTab.topics &&
                                            route?.isTopicList == true &&
                                            route?.id == 'latest' &&
                                            route!.topicFilterQuery.isEmpty) {
                                          unawaited(
                                            header.value?.scrollToTop(),
                                          );
                                        } else {
                                          shell.openMobileHome();
                                        }
                                      },
                                      icon: ForumIdentityHeader(
                                        size: 32,
                                        name: instance.title,
                                        iconUrl: instance.iconUrl,
                                        monogram: instance.monogram,
                                        accentColor: instance.accentColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ValueListenableBuilder<DPageHeader?>(
                                      valueListenable: header,
                                      builder: (context, current, _) {
                                        final entry =
                                            shell.mobileNavigation.entryId;
                                        if (current != null) {
                                          _navigationHeader = (
                                            owner: owner,
                                            entry: entry,
                                            header: current,
                                          );
                                        }
                                        final retained = _navigationHeader;
                                        final showingNavigation =
                                            DHistoryTransition.navigationProgressOf(
                                              context,
                                            ) >
                                            0;
                                        var titleHeader = header;
                                        if (current == null &&
                                            showingNavigation &&
                                            retained != null &&
                                            retained.owner == owner &&
                                            retained.entry == entry) {
                                          titleHeader =
                                              AlwaysStoppedAnimation<
                                                DPageHeader?
                                              >(retained.header);
                                        }
                                        return MobilePageTitle(
                                          entry: entry,
                                          history: (
                                            owner,
                                            shell.mobileNavigation.historyId,
                                          ),
                                          header: titleHeader,
                                          siteUrl: instance.url,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const ForumSearch(fullScreen: true),
                      ];
                      final notificationsMenu = UserMenuButton(
                        compact: true,
                        presentation: UserMenuPresentation.dockNotifications,
                        menuController: _notificationsMenu,
                      );
                      // Signed in, the menu draws nothing, the bar's place
                      // opening it, so it is hosted beside the row and takes
                      // none of its room. Signed out, it draws the sign-in
                      // actions, which the row lays out.
                      final signedIn = instance.user != null;
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
                        if (!signedIn) notificationsMenu,
                      ];
                      final largeText =
                          MediaQuery.textScalerOf(context).scale(12) > 18;
                      return Stack(
                        fit: StackFit.passthrough,
                        children: [
                          if (largeText)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(spacing: 10, children: navigation),
                                if (actions.isNotEmpty) ...[
                                  const SizedBox(height: DSpacing.controlGap),
                                  Wrap(
                                    alignment: WrapAlignment.end,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    runSpacing: DSpacing.controlGap,
                                    children: actions,
                                  ),
                                ],
                              ],
                            )
                          else
                            Row(
                              spacing: 10,
                              children: [
                                ...navigation,
                                if (actions.isNotEmpty)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: actions,
                                  ),
                              ],
                            ),
                          if (signedIn)
                            PositionedDirectional(
                              end: 0,
                              child: notificationsMenu,
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          page: page,
        );
        // The page runs under the home indicator; only the floating dock
        // keeps clear of it, and pages pad their last row by its height.
        // A route without a dock keeps an empty footer of that clearance.
        Widget foreground(
          BuildContext context,
          Widget page,
        ) => ListenableBuilder(
          listenable: _footerAction,
          child: page,
          builder: (context, content) {
            // Retain both dock presentations while navigation moves them.
            // Progress changes the wrapper, not the controls inside it.
            final docks = <bool, Widget>{};
            Widget dockBuilder(bool hidden) => docks.putIfAbsent(hidden, () {
              if (route?.isGlobalSearch == true && !sidebarOpen) {
                return const SizedBox.shrink();
              }
              // A parked draft waits over the bar, which keeps pages
              // clear of both.
              final parked = ComposerDock.parkedDraftRoomOf(context);
              if (hideDock) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: parked + MediaQuery.paddingOf(context).bottom,
                  ),
                );
              }
              final geometry = DMobileDockGeometry.of(context);
              return ForumSidebarTheme(
                child: Padding(
                  padding: geometry.margin.add(EdgeInsets.only(top: parked)),
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
            });
            return Builder(
              builder: (context) {
                final hidden = DHistoryTransition.navigationProgressOf(context);
                final dock = MobileScrollDock(
                  identity: (
                    owner,
                    selected,
                    preservePageChrome
                        ? shell.mobileNavigation.previousEntryId
                        : shell.mobileNavigation.entryId,
                    widget.boundary,
                  ),
                  visible: hidden < 1,
                  hiddenFraction: hidden,
                  hideOnScroll: !hideDock || preservePageChrome,
                  keepActionVisible: _footerAction.action != null,
                  body: NotificationListener<ScrollNotification>(
                    onNotification: (_) => preservePageChrome,
                    child: content!,
                  ),
                  dockBuilder: dockBuilder,
                );
                return DHeaderMotionSettings(
                  tuning: route?.isTopicListFilter == true
                      ? const DHeaderTuning(
                          settle: DHeaderSettle.stay,
                          slack: 0,
                          hold: 0,
                          smoothing: 0,
                        )
                      : DHeaderMotionSettings.of(context),
                  child: dock,
                );
              },
            );
          },
        );
        Widget frame(BuildContext context, Widget page) => DPageHeaderHost(
          key: ValueKey(('mobile-page-header', owner)),
          identity: (owner, shell.mobileNavigation.entryId, sidebarOpen),
          previousIdentity: (
            owner,
            shell.mobileNavigation.previousEntryId,
            false,
          ),
          titlesInBar: true,
          builder: frameWithHeader,
          child: page,
        );
        return MobilePresentationScope(
          presentation: presentation,
          child: MobileHistoryGestures(
            tab: (id: selected, index: tabOrder.indexOf(selected)),
            navigationPreview: _navigationPage,
            frameBuilder: frame,
            foregroundBuilder: foreground,
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
                        padding: EdgeInsets.only(
                          top:
                              route?.isGlobalSearch == true ||
                                  pageSheetOpen && route?.isTopic == true
                              ? 0
                              : 6,
                        ),
                        child: ForumMobileSurface(
                          key: const ValueKey('mobile-content-panel'),
                          sheet: route?.isGlobalSearch == true
                              ? ForumMobileSheet.page
                              : !pageSheetOpen
                              ? ForumMobileSheet.none
                              : route?.isTopic == true
                              ? ForumMobileSheet.raised
                              : ForumMobileSheet.page,
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
                                      child: _panelRoots.putIfAbsent(
                                        (owner, entry.owner.value),
                                        () => InstanceSidebar(
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
                                ),
                              if (!panelRoot) widget.content,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return ShellSelector(
      select: _mobileChromePresentation,
      builder: (context, _, _) => body(),
    );
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
    final panelScope = MobileDockPanelScope.of(context);
    final panelOut = panelScope?.out;
    // Notifications paused rings the you tile; what has arrived, and the
    // menu opening, count on the notifications place. Nothing else here.
    return ListenableBuilder(
      listenable: Listenable.merge([
        shell.doNotDisturb,
        shell.accountActivity.totalsSelection(
          () => UserMenuButton.unreadCountOf(shell, instance.url),
        ),
        _notificationsMenu,
      ]),
      builder: (context, _) {
        final places = <String, DMobileDockPlace>{
          for (final item in destinations)
            item.tab.name: DMobileDockPlace(
              key: ValueKey('mobile-mode-${item.tab.name}'),
              icon: DIcon(item.icon),
              label: item.label,
              badge: item.badge,
              selected: selected == item.tab,
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                item.onPressed();
              },
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
          peek: panelScope?.peek,
          collapsedDestination: DMobileDockItem(
            key: const ValueKey('mobile-dock-reveal'),
            collapsed: true,
            icon: DIcon(active?.icon ?? DIcons.ellipsisVertical),
            label:
                '${active?.label ?? context.l10n.more}, ${context.l10n.openNavigation}',
            onPressed: () => DScrollChrome.maybeOf(context)?.reveal(),
          ),
          places: [for (final name in order) places[name]!],
          notifications: _notificationsPlace(
            context,
            shell: shell,
            instance: instance,
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

  /// Notifications, fixed in the bar before the action once signed in: its
  /// count is what has arrived since the menu was last open, said as the
  /// header's bell said it, and hidden while the menu is open; pressing it
  /// toggles the menu, which the header hosts.
  DMobileDockPlace? _notificationsPlace(
    BuildContext context, {
    required ShellController shell,
    required DiscourseInstance instance,
  }) {
    if (!instance.isConnected || instance.user == null) return null;
    final open = _notificationsMenu.isOpen;
    final count = UserMenuButton.unreadCountOf(shell, instance.url);
    return DMobileDockPlace(
      key: const ValueKey('mobile-mode-notifications'),
      icon: const DIcon(DIcons.inbox),
      label: context.l10n.notifications,
      badge: count > 0 && !open
          ? DBadge.unreadChip(
              key: UserMenuButton.unreadDotKey,
              count: count,
              semanticLabel: context.l10n.notificationsUnread(count),
            )
          : null,
      selected: open,
      onPressed: () {
        if (open) {
          _notificationsMenu.close();
          return;
        }
        AccountMenuScope.activate(context, _notificationsMenu);
        _notificationsMenu.open();
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

// Forum read counters do not change the frame. Badges and contributed panels
// listen to their own state; keep navigation, identity and permissions current.
Object _mobileChromePresentation(ShellController shell) {
  final instance = shell.currentInstance;
  final navigation = shell.mobileNavigation;
  return (
    instance: (
      instance?.url,
      instance?.title,
      instance?.description,
      instance?.iconUrl,
      instance?.apiVersion,
      instance?.loginRequired,
      instance?.user,
      instance?.localDraftAccount,
      instance?.appearance,
      instance?.config,
    ),
    account: shell.currentAccountIdentity,
    connecting: shell.connecting,
    hidePresence: instance == null
        ? false
        : shell.hidePresenceFor(instance.url),
    route: shell.currentContent,
    source: shell.topicListContent,
    tab: shell.activeTab?.location,
    navigation: navigation.state,
    sidebarOpen: navigation.sidebarOpen,
    history: navigation.historyId,
    entry: navigation.entryId,
    previous: navigation.previousEntryId,
    next: navigation.nextEntryId,
    canReply: shell.canReplyHere,
    canCreateTopic: shell.canCreateTopicFromSidebar,
  );
}

/// Every place the phone offers, in the order its bar shows them and the
/// panel the bar grows into holds the rest: the ones the person has placed,
/// as [order] names them, then the rest in their own order. The dock and
/// the history gestures read this one order.
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
  final mobileDestinations = [
    for (final destination in registry.mobileNavigationDestinations(context))
      if (destination.enabled &&
          !shortcuts.any((shortcut) => shortcut.id == destination.id))
        destination,
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
        icon: DIcons.envelope,
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
    for (final destination in mobileDestinations) page(destination),
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
    required this.foregroundBuilder,
  });
  final Widget child;

  /// The place the person is on, and where it stands among the places.
  final DHistoryTab tab;
  final Widget navigationPreview;
  final Widget Function(BuildContext context, Widget page) frameBuilder;
  final Widget Function(BuildContext context, Widget frame) foregroundBuilder;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    final navigation = shell.mobileNavigation;
    final sidebarOpen = navigation.sidebarOpen;
    final sidebarEntry = (navigation.historyId, 'sidebar');
    return DSheetDragScope(
      child: Builder(
        builder: (context) => DHistoryTransition(
          frameBuilder: frameBuilder,
          foregroundBuilder: foregroundBuilder,
          history: navigation.historyId,
          tab: sidebarOpen ? (id: sidebarEntry, index: -1) : tab,
          tabOwner: (shell.currentInstance?.url, shell.currentAccountIdentity),
          tabClipper: sidebarOpen
              ? null
              : DHistoryTabClipper(
                  borderRadius: shell.currentContent?.isGlobalSearch == true
                      ? BorderRadius.zero
                      : DSheetViewport.pageBorderRadius(context),
                  insets: shell.currentContent?.isGlobalSearch == true
                      ? EdgeInsets.zero
                      : const EdgeInsets.only(top: 6),
                ),
          entry: sidebarOpen ? sidebarEntry : navigation.entryId,
          backSwipeAnywhere: true,
          navigation: DHistoryNavigation(
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

enum _MobileFrameSlot { header, page }

class _MobileFrame extends StatelessWidget {
  const _MobileFrame({
    super.key,
    required this.header,
    required this.headerVisible,
    required this.navigationOpen,
    required this.page,
    required this.raised,
  });
  final Widget header;
  final bool headerVisible;
  final bool navigationOpen;
  final Widget page;
  final bool raised;
  @override
  Widget build(BuildContext context) {
    final reveal = DHistoryTransition.navigationProgressOf(context);
    final hidden = !headerVisible || reveal >= 1;
    final pageSlot = LayoutId(
      key: const ValueKey(_MobileFrameSlot.page),
      id: _MobileFrameSlot.page,
      child: page,
    );
    final headerSlot = LayoutId(
      key: const ValueKey(_MobileFrameSlot.header),
      id: _MobileFrameSlot.header,
      child: Offstage(
        offstage: hidden,
        child: Opacity(
          key: const ValueKey('mobile-header-opacity'),
          opacity: 1 - reveal,
          child: ExcludeFocus(excluding: hidden, child: header),
        ),
      ),
    );
    return CustomMultiChildLayout(
      delegate: _MobileFrameLayout(
        raised,
        navigationOpen,
        reveal,
        (extent) => DSheetDragScope.reportTopBar(context, extent),
      ),
      children: raised ? [headerSlot, pageSlot] : [pageSlot, headerSlot],
    );
  }
}

class _MobileFrameLayout extends MultiChildLayoutDelegate {
  _MobileFrameLayout(
    this.raised,
    this.navigationOpen,
    this.navigationProgress,
    this.report,
  );
  final bool raised;
  final bool navigationOpen;
  final double navigationProgress;
  final ValueChanged<double> report;
  @override
  void performLayout(Size size) {
    final header = layoutChild(
      _MobileFrameSlot.header,
      BoxConstraints.tightFor(width: size.width),
    );
    positionChild(
      _MobileFrameSlot.header,
      Offset(0, -header.height * navigationProgress),
    );
    report(header.height * (1 - navigationProgress));
    final top = navigationOpen
        ? 0.0
        : (raised ? 8.0 : header.height) * (1 - navigationProgress);
    layoutChild(
      _MobileFrameSlot.page,
      BoxConstraints.tight(Size(size.width, math.max(0, size.height - top))),
    );
    positionChild(_MobileFrameSlot.page, Offset(0, top));
  }

  @override
  bool shouldRelayout(_MobileFrameLayout oldDelegate) =>
      raised != oldDelegate.raised ||
      navigationOpen != oldDelegate.navigationOpen ||
      navigationProgress != oldDelegate.navigationProgress;
}
