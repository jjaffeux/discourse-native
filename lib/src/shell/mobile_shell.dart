import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/sidebar.dart';
import '../plugin_api/plugin_scope.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'composer/presentation.dart';
import 'forum_search.dart';
import 'forum_theme_surfaces.dart';
import 'instance_rail.dart';
import 'instance_sidebar.dart';
import 'message_create_button.dart';
import 'mobile_footer_action.dart';
import 'mobile_navigation.dart';
import 'mobile_scroll_dock.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'user_menu_button.dart';

typedef _DockDestination = ({
  MobileTab tab,
  String label,
  DIconData icon,
  Widget? badge,
  VoidCallback onPressed,
});

const double _mobileRailWidth = 53;

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
  int _shownDockCount = 3;
  final MobileFooterActionController _footerAction =
      MobileFooterActionController();

  @override
  void dispose() {
    _footerAction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MobileFooterActionScope(
    controller: _footerAction,
    child: UserMenuButton.drawer(builder: _buildWithProfileFooter),
  );

  Widget _buildWithProfileFooter(BuildContext context, Widget? profileFooter) {
    final shell = ShellScope.read(context);
    final registry = PluginScope.of(context).registry;
    // The chrome reads facade and plugin state only. Topic feeds notify
    // several times per page, and the widgets that read them listen directly.
    final body = ListenableBuilder(
      listenable: Listenable.merge([
        shell,
        shell.accountActivity.totalsListenable,
        ...registry.sidebarPanelListenables(context),
        ...registry.communitySidebarListenables(context),
      ]),
      builder: (context, _) {
        final instance = shell.currentInstance;
        if (instance == null) return const SizedBox.shrink();
        final owner = (instance.url, shell.currentAccountIdentity);
        final sidebarOpen = shell.mobileNavigation.sidebarOpen;
        final navigationPage = CallbackShortcuts(
          key: _navigationPageKey,
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape):
                shell.closeMobileSidebar,
          },
          child: Focus(
            autofocus: sidebarOpen,
            // The inset navigation panel floats above the home indicator.
            child: SafeArea(
              top: false,
              left: false,
              right: false,
              child: Row(
                key: const ValueKey('mobile-navigation-page'),
                children: [
                  const SizedBox(
                    width: _mobileRailWidth,
                    child: InstanceRail(),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: ForumMobileSurface.sidebar(
                        key: const ValueKey('mobile-navigation-panel'),
                        child: InstanceSidebar(
                          key: ValueKey(('mobile-navigation', owner)),
                          mobile: true,
                          onNavigate: shell.closeMobileSidebar,
                          footer: profileFooter == null
                              ? null
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const DSeparator(),
                                    Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: profileFooter,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final panels = registry
            .sidebarPanels(context)
            .where((entry) => entry.panel.showSwitch)
            .toList();
        final shortcuts = [
          ...registry
              .communitySidebarDestinations(context)
              .where(
                (destination) =>
                    destination.mobileNavigationLabel != null &&
                    destination.enabled,
              ),
          if (instance.user?.staff == true) SidebarDestination.dashboard(),
        ];
        final destinations = instance.sections
            .expand(
              (section) => [
                ...section.destinations,
                ...section.moreDestinations,
              ],
            )
            .toList();
        SidebarDestination? destination(String id) =>
            destinations.where((entry) => entry.id == id).firstOrNull;
        final extraDestinations = <SidebarDestination>[
          SidebarDestination(
            id: 'all-categories',
            label: context.l10n.categories,
            icon: DIcons.layerGroup,
          ),
          for (final id in ['groups', 'badges']) ?destination(id),
          if (instance.isConnected)
            SidebarDestination(
              id: 'user-bookmarks',
              label: context.l10n.bookmarks,
              icon: DIcons.bookmark,
            ),
          SidebarDestination(
            id: 'appearance',
            label: context.l10n.settings,
            icon: DIcons.gear,
          ),
          if (instance.isConnected && instance.user != null)
            SidebarDestination(
              id: 'preferences',
              label: context.l10n.preferences,
              icon: DIcons.gear,
            ),
        ];
        final selected = shell.mobileNavigation.tab;
        final tabOrder = [
          MobileTab.start,
          MobileTab.topics,
          for (final entry in panels) MobileTab.panel(entry.owner.value),
          if (destination('messages') != null) MobileTab.messages,
          if (destination('users') != null) MobileTab.users,
          for (final shortcut in shortcuts) MobileTab.destination(shortcut.id),
          for (final extra in extraDestinations)
            MobileTab.destination(extra.id),
          MobileTab.more,
        ];
        if ((selected.panelOwner != null &&
                !panels.any((p) => p.owner.value == selected.panelOwner)) ||
            (selected.name.startsWith('destination/') &&
                !([
                  ...shortcuts,
                  ...extraDestinations,
                ]).any((d) => MobileTab.destination(d.id) == selected)) ||
            (selected == MobileTab.messages &&
                destination('messages') == null) ||
            (selected == MobileTab.users && destination('users') == null)) {
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
        final dockDestinations = <_DockDestination>[
          (
            tab: MobileTab.start,
            label: context.l10n.start,
            icon: DIcons.house,
            badge: null,
            onPressed: () => shell.selectMobileDestination(
              MobileTab.start,
              SidebarDestination(
                id: 'new-tab',
                label: context.l10n.startPage,
                icon: DIcons.house,
              ),
            ),
          ),
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
              onPressed: () =>
                  shell.selectMobileDestination(MobileTab.users, users),
            ),
          for (final shortcut in shortcuts)
            (
              tab: MobileTab.destination(shortcut.id),
              label: shortcut.mobileNavigationLabel!,
              icon: shortcut.icon,
              badge: null,
              onPressed: () => shell.selectMobileDestination(
                MobileTab.destination(shortcut.id),
                shortcut,
              ),
            ),
          for (final extra in extraDestinations)
            (
              tab: MobileTab.destination(extra.id),
              label: extra.label,
              icon: extra.icon,
              badge: null,
              onPressed: () => shell.selectMobileDestination(
                MobileTab.destination(extra.id),
                extra,
              ),
            ),
        ];
        final source = shell.topicListContent;
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
                              icon: const Icon(Icons.menu, size: 20),
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
                              size: 28,
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
            Expanded(
              // The page runs under the home indicator; only the floating dock
              // keeps clear of it, and pages pad their last row by its height.
              // A route without a dock keeps an empty footer of that clearance.
              child: ListenableBuilder(
                listenable: _footerAction,
                child: page,
                builder: (context, content) => MobileScrollDock(
                  identity: (
                    owner,
                    selected,
                    shell.mobileNavigation.entryId,
                    widget.boundary,
                  ),
                  visible: !sidebarOpen,
                  hideOnScroll: !hideDock,
                  keepActionVisible: _footerAction.action != null,
                  body: content!,
                  dockBuilder: (hidden) {
                    final clearance =
                        ComposerDock.bottomOverlayInsetOf(context) +
                        MediaQuery.paddingOf(context).bottom;
                    if (hideDock) {
                      return Padding(
                        padding: EdgeInsets.only(bottom: clearance),
                      );
                    }
                    return ForumSidebarTheme(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(6, 6, 6, 6 + clearance),
                        child: LayoutBuilder(
                          builder: (context, constraints) => _buildBottomBar(
                            context,
                            constraints,
                            destinations: dockDestinations,
                            selected: selected,
                            showReply: showReply,
                            showNewMessage: showNewMessage,
                            panelAction: panelAction,
                            showNewTopic: showNewTopic,
                            shell: shell,
                            hideDestinations: hidden,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
        return MobileHistoryGestures(
          tabIndex: tabOrder.indexOf(selected),
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
    required List<_DockDestination> destinations,
    required MobileTab selected,
    required bool showReply,
    required bool showNewMessage,
    required SidebarPanelAction? panelAction,
    required bool showNewTopic,
    required ShellController shell,
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
    final activeOverflow =
        active == null || destinations.indexOf(active) >= _shownDockCount;
    return DMobileDock(
      key: const ValueKey('mobile-bottom-bar'),
      collapsed: hideDestinations && pageAction == null,
      destinationsHidden: hideDestinations && pageAction != null,
      onOverflowChanged: (shown) {
        if (mounted && _shownDockCount != shown) {
          setState(() => _shownDockCount = shown);
        }
      },
      collapsedDestination: DMobileDockItem(
        key: const ValueKey('mobile-dock-reveal'),
        collapsed: true,
        icon: DIcon(activeOverflow ? DIcons.ellipsisVertical : active.icon),
        label:
            '${activeOverflow ? context.l10n.more : active.label}, ${context.l10n.openNavigation}',
        onPressed: () => DScrollChrome.maybeOf(context)?.reveal(),
      ),
      destinations: [
        for (final item in destinations)
          DMobileDockItem(
            key: ValueKey('mobile-mode-${item.tab.name}'),
            icon: DIcon(item.icon),
            label: item.label,
            badge: item.badge,
            selected: selected == item.tab,
            onPressed: item.onPressed,
          ),
      ],
      more: DDropdownMenu(
        sheetOnMobile: true,
        mobileSheetVariant: DSheetVariant.adaptiveMenu,
        content: DDropdownMenuContent(
          semanticLabel: context.l10n.moreDestinations,
          side: DPopoverSide.top,
          align: DPopoverAlign.end,
          children: [
            for (final item in destinations.skip(_shownDockCount))
              DDropdownMenuItem(
                leading: DIcon(item.icon),
                onPressed: item.onPressed,
                child: Text(
                  item.tab == MobileTab.messages
                      ? context.l10n.messages
                      : item.label,
                ),
              ),
          ],
        ),
        child: DDropdownMenuTrigger(
          builder: (context, state) => DMobileDockItem(
            key: const ValueKey('mobile-mode-more'),
            bare: true,
            icon: const DIcon(DIcons.ellipsisVertical),
            label: context.l10n.more,
            selected: activeOverflow,
            focusNode: state.focusNode,
            hasPopup: true,
            expanded: state.open,
            onPressed: state.toggle,
          ),
        ),
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

/// Adapts mobile visit history to the Native interactive transition.
class MobileHistoryGestures extends StatelessWidget {
  const MobileHistoryGestures({
    super.key,
    required this.child,
    required this.tabIndex,
    required this.navigationPreview,
    required this.frameBuilder,
  });
  final Widget child;
  final int tabIndex;
  final Widget navigationPreview;
  final Widget Function(BuildContext context, Widget page) frameBuilder;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final navigation = shell.mobileNavigation;
    final sidebarOpen = navigation.sidebarOpen;
    final sidebarEntry = (navigation.historyId, 'sidebar');
    final root = !navigation.canGoBack;
    final topicOpen = !sidebarOpen && shell.currentContent?.isTopic == true;
    return DHistoryTransition(
      frameBuilder: frameBuilder,
      history: navigation.historyId,
      tabIndex: sidebarOpen ? -1 : tabIndex,
      tabOwner: (shell.currentInstance?.url, shell.currentAccountIdentity),
      entry: sidebarOpen ? sidebarEntry : navigation.entryId,
      // Navigation is adjacent to the tab root without becoming a visit in
      // its history. Deeper pages keep their normal Back/Forward targets.
      previousEntry: sidebarOpen
          ? null
          : root
          ? sidebarEntry
          : navigation.previousEntryId,
      nextEntry: sidebarOpen ? navigation.entryId : navigation.nextEntryId,
      previousPreview: !sidebarOpen && root ? navigationPreview : null,
      onBack: !sidebarOpen && !topicOpen
          ? () {
              FocusManager.instance.primaryFocus?.unfocus();
              if (root) {
                shell.toggleMobileSidebar();
              } else {
                shell.handleBack();
              }
            }
          : null,
      onForward: !topicOpen && (sidebarOpen || navigation.canGoForward)
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
    );
  }
}
