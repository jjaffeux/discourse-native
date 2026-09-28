import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/sidebar.dart';
import '../plugin_api/plugin_scope.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/d_icons.dart';
import 'forum_search.dart';
import 'forum_theme_surfaces.dart';
import 'instance_rail.dart';
import 'instance_sidebar.dart';
import 'message_create_button.dart';
import 'mobile_footer_action.dart';
import 'mobile_navigation.dart';
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
  final MobileFooterActionController _footerAction =
      MobileFooterActionController();

  @override
  void dispose() {
    _footerAction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        final panels = registry
            .sidebarPanels(context)
            .where((entry) => entry.panel.showSwitch)
            .toList();
        final shortcuts = registry
            .communitySidebarDestinations(context)
            .where(
              (destination) =>
                  destination.mobileNavigationLabel != null &&
                  destination.enabled,
            )
            .toList();
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
        final selected = shell.mobileNavigation.tab;
        final tabOrder = [
          MobileTab.start,
          MobileTab.topics,
          for (final entry in panels) MobileTab.panel(entry.owner.value),
          if (destination('messages') != null) MobileTab.messages,
          if (destination('users') != null) MobileTab.users,
          for (final shortcut in shortcuts) MobileTab.destination(shortcut.id),
          MobileTab.more,
        ];
        if ((selected.panelOwner != null &&
                !panels.any((p) => p.owner.value == selected.panelOwner)) ||
            (selected.name.startsWith('destination/') &&
                !shortcuts.any(
                  (d) => MobileTab.destination(d.id) == selected,
                )) ||
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
        final dockDestinations = <_DockDestination>[
          (
            tab: MobileTab.start,
            label: 'Start',
            icon: DIcons.house,
            badge: null,
            onPressed: () => shell.selectMobileDestination(
              MobileTab.start,
              const SidebarDestination(
                id: 'new-tab',
                label: 'Start page',
                icon: DIcons.house,
              ),
            ),
          ),
          (
            tab: MobileTab.topics,
            label: 'Topics',
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
              label: 'Inbox',
              icon: DIcons.inbox,
              badge: null,
              onPressed: () =>
                  shell.selectMobileDestination(MobileTab.messages, messages),
            ),
          if (destination('users') case final users?)
            (
              tab: MobileTab.users,
              label: 'Users',
              icon: DIcons.user,
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
        ];
        final source = shell.topicListContent;
        final showReply =
            !widget.boundary &&
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
        return Column(
          key: const ValueKey('mobile-root'),
          children: [
            ForumSidebarTheme(
              child: Padding(
                key: const ValueKey('mobile-header'),
                padding: const EdgeInsets.all(DSpacing.xs),
                child: LayoutBuilder(
                  builder: (context, constraints) => Row(
                    spacing: DSpacing.controlGap,
                    children: [
                      DButton.iconOnly(
                        key: const ValueKey('mobile-menu-button'),
                        icon: const Icon(Icons.menu, size: 20),
                        tooltip: sidebarOpen
                            ? 'Close navigation'
                            : 'Open navigation',
                        variant: DButtonVariant.ghost,
                        expanded: sidebarOpen,
                        onPressed: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          shell.toggleMobileSidebar();
                        },
                      ),
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: ForumIdentityHeader(
                            siteUrl: instance.url,
                            name: instance.title,
                            iconUrl: instance.iconUrl,
                            monogram: instance.monogram,
                            accentColor: instance.accentColor,
                            compact: true,
                            showName: constraints.maxWidth >= 350,
                          ),
                        ),
                      ),
                      const ForumSearch(fullScreen: true),
                      const UserMenuButton(compact: true),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: DSpacing.xs),
                child: MobileHistoryGestures(
                  tabIndex: tabOrder.indexOf(selected),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Offstage(
                        offstage: sidebarOpen,
                        child: TickerMode(
                          enabled: !sidebarOpen,
                          child: ExcludeFocus(
                            excluding: sidebarOpen,
                            child: DPageSurface(
                              key: const ValueKey('mobile-content-panel'),
                              backgroundColor: ForumWindowBackground.panelColor(
                                context,
                              ),
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
                                                  panelOwner ==
                                                      entry.owner.value),
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
                      if (sidebarOpen)
                        CallbackShortcuts(
                          bindings: {
                            const SingleActivator(LogicalKeyboardKey.escape):
                                shell.closeMobileSidebar,
                          },
                          child: Focus(
                            autofocus: true,
                            child: Row(
                              key: const ValueKey('mobile-navigation-page'),
                              children: [
                                const SizedBox(
                                  width: 48,
                                  child: InstanceRail(),
                                ),
                                Expanded(
                                  child: DPageSurface(
                                    border: false,
                                    child: InstanceSidebar(
                                      key: ValueKey((
                                        'mobile-navigation',
                                        owner,
                                      )),
                                      mobile: true,
                                      onNavigate: shell.closeMobileSidebar,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            DCollapsible(
              open: !sidebarOpen,
              child: DCollapsibleContent(
                duration: DMotion.change,
                curve: Curves.easeInOutCubic,
                keepMounted: true,
                child: ForumSidebarTheme(
                  child: Padding(
                    padding: const EdgeInsets.all(DSpacing.xs),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return ListenableBuilder(
                          listenable: _footerAction,
                          builder: (context, _) => _buildBottomBar(
                            context,
                            constraints,
                            destinations: dockDestinations,
                            selected: selected,
                            moreDestinations: [
                              for (final id in ['groups', 'badges'])
                                ?destination(id),
                              if (instance.isConnected)
                                const SidebarDestination(
                                  id: 'user-bookmarks',
                                  label: 'Bookmarks',
                                  icon: DIcons.bookmark,
                                ),
                            ],
                            showReply: showReply,
                            showNewMessage: showNewMessage,
                            panelAction: panelAction,
                            showNewTopic: showNewTopic,
                            shell: shell,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    return MobileFooterActionScope(controller: _footerAction, child: body);
  }

  Widget _buildBottomBar(
    BuildContext context,
    BoxConstraints constraints, {
    required List<_DockDestination> destinations,
    required MobileTab selected,
    required List<SidebarDestination> moreDestinations,
    required bool showReply,
    required bool showNewMessage,
    required SidebarPanelAction? panelAction,
    required bool showNewTopic,
    required ShellController shell,
  }) {
    final pageAction = _footerAction.action;
    final labelGrowth = MediaQuery.textScalerOf(context).scale(11) - 11;
    final itemMin = 66.0 + labelGrowth * 2;
    final itemMax = 72.0 + labelGrowth * 2;
    const actionMin = 48.0;
    const gap = DSpacing.controlGap;
    // The dock is sized from the width, the text scale and the destinations
    // alone, always leaving room for one trailing action. Sizing it from the
    // active tab's actions resized and re-spilled every slot on each switch.
    final dockRoom = (constraints.maxWidth - actionMin - gap).clamp(
      0.0,
      double.infinity,
    );
    final fits = (dockRoom / itemMin).floor();
    final minimumSlots = labelGrowth > 3 ? 3 : 4;
    final shownCount = (math.max(fits, minimumSlots) - 1).clamp(
      1,
      destinations.length,
    );
    final shown = destinations.take(shownCount).toList();
    final spilled = destinations.skip(shownCount).toList();
    final dockWidth = (itemMax * (shown.length + 1)).clamp(0.0, dockRoom);
    final actionWidth = (constraints.maxWidth - dockWidth - gap).clamp(
      actionMin,
      220.0,
    );
    final showLabel = _creationLabelFits(
      context,
      actionWidth,
      0,
      showReply
          ? 'Reply'
          : showNewMessage
          ? 'New message'
          : panelAction?.label ?? 'New topic',
    );
    Widget? primaryAction;
    if (pageAction case final action?) {
      primaryAction = DButton(
        key: action.key ?? const ValueKey('mobile-page-action'),
        icon: DIcon(action.icon),
        label: Text(action.label),
        loadingLabel: Text(action.label),
        loading: action.loading,
        tooltip: action.label,
        shape: DButtonShape.pill,
        density: DButtonDensity.mobileDockAction,
        onPressed: action.onPressed,
      );
    } else if (showReply) {
      primaryAction = showLabel
          ? DButton(
              key: const ValueKey('mobile-topic-reply'),
              icon: const DIcon(DIcons.reply),
              label: const Text('Reply'),
              tooltip: 'Reply to this topic',
              shape: DButtonShape.pill,
              density: DButtonDensity.mobileDockAction,
              onPressed: shell.openReply,
            )
          : DButton.iconOnly(
              key: const ValueKey('mobile-topic-reply'),
              icon: const DIcon(DIcons.reply),
              tooltip: 'Reply to this topic',
              shape: DButtonShape.pill,
              density: DButtonDensity.mobileDockAction,
              onPressed: shell.openReply,
            );
    } else if (showNewMessage) {
      primaryAction = MessageCreateButton(
        showLabel: showLabel,
        pill: true,
        dockAction: true,
      );
    } else if (panelAction != null) {
      primaryAction = _dockAction(
        key: const ValueKey('mobile-panel-action'),
        icon: panelAction.icon,
        label: panelAction.label,
        showLabel: showLabel,
        onPressed: panelAction.onPressed,
      );
    } else if (showNewTopic) {
      primaryAction = _dockAction(
        key: const ValueKey('mobile-new-topic'),
        icon: DIcons.plus,
        label: 'New topic',
        showLabel: showLabel,
        onPressed: () => unawaited(shell.openNewTopicFromSidebar()),
      );
    }
    return Row(
      key: const ValueKey('mobile-bottom-bar'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        SizedBox(
          width: dockWidth,
          child: Row(
            children: [
              for (final item in shown)
                Expanded(
                  child: DMobileDockItem(
                    key: ValueKey('mobile-mode-${item.tab.name}'),
                    icon: DIcon(item.icon),
                    label: item.label,
                    badge: item.badge,
                    selected: selected == item.tab,
                    onPressed: item.onPressed,
                  ),
                ),
              Expanded(
                child: DDropdownMenu(
                  content: DDropdownMenuContent(
                    semanticLabel: 'More destinations',
                    side: DPopoverSide.top,
                    align: DPopoverAlign.end,
                    children: [
                      for (final item in spilled)
                        DDropdownMenuItem(
                          leading: DIcon(item.icon),
                          onPressed: item.onPressed,
                          child: Text(
                            item.label == 'Inbox' ? 'Messages' : item.label,
                          ),
                        ),
                      for (final entry in moreDestinations)
                        DDropdownMenuItem(
                          leading: DIcon(entry.icon),
                          onPressed: () => shell.selectMobileDestination(
                            MobileTab.more,
                            entry,
                          ),
                          child: Text(entry.label),
                        ),
                    ],
                  ),
                  child: DDropdownMenuTrigger(
                    builder: (context, state) => DMobileDockItem(
                      key: const ValueKey('mobile-mode-more'),
                      icon: const DIcon(DIcons.ellipsisVertical),
                      label: 'More',
                      selected:
                          selected == MobileTab.more ||
                          spilled.any((item) => item.tab == selected),
                      focusNode: state.focusNode,
                      hasPopup: true,
                      expanded: state.open,
                      onPressed: state.toggle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (primaryAction != null)
          SizedBox(width: actionWidth, child: primaryAction),
      ],
    );
  }

  Widget _dockAction({
    required Key key,
    required DIconData icon,
    required String label,
    required bool showLabel,
    required VoidCallback onPressed,
  }) => showLabel
      ? DButton(
          key: key,
          icon: DIcon(icon),
          label: Text(label),
          shape: DButtonShape.pill,
          density: DButtonDensity.mobileDockAction,
          onPressed: onPressed,
        )
      : DButton.iconOnly(
          key: key,
          icon: DIcon(icon),
          tooltip: label,
          shape: DButtonShape.pill,
          density: DButtonDensity.mobileDockAction,
          onPressed: onPressed,
        );

  bool _creationLabelFits(
    BuildContext context,
    double width,
    int actionCount,
    String label,
  ) {
    const size = DControlSize.regular;
    final scaler = MediaQuery.textScalerOf(context);
    final controlWidth = DControlStyle.scaledHeight(
      size,
      scaler,
      context: context,
    );
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: Theme.of(context).textTheme.labelLarge!.copyWith(
          fontSize: DControlStyle.fontSize(size, context: context),
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
      textScaler: scaler,
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    // Reserve enough room for the Native button's icon and content insets.
    // The control retains ownership of its actual dimensions and touch target.
    final labelWidth =
        text.width +
        2 * DControlStyle.iconDimension(size, context: context) +
        DControlStyle.contentGap(size);
    text.dispose();
    return width >=
        actionCount * (controlWidth + DSpacing.controlGap) + labelWidth;
  }
}

/// Adapts mobile visit history to the Native interactive transition.
class MobileHistoryGestures extends StatelessWidget {
  const MobileHistoryGestures({
    super.key,
    required this.child,
    required this.tabIndex,
  });
  final Widget child;
  final int tabIndex;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final navigation = shell.mobileNavigation;
    final sidebarOpen = navigation.sidebarOpen;
    return DHistoryTransition(
      history: navigation.historyId,
      tabIndex: sidebarOpen ? -1 : tabIndex,
      tabOwner: (shell.currentInstance?.url, shell.currentAccountIdentity),
      entry: sidebarOpen
          ? (navigation.historyId, 'sidebar')
          : navigation.entryId,
      previousEntry: navigation.previousEntryId,
      nextEntry: navigation.nextEntryId,
      onBack: !sidebarOpen && navigation.canGoBack
          ? () {
              FocusManager.instance.primaryFocus?.unfocus();
              shell.handleBack();
            }
          : null,
      onForward: !sidebarOpen && navigation.canGoForward
          ? () {
              FocusManager.instance.primaryFocus?.unfocus();
              shell.handleForward();
            }
          : null,
      child: child,
    );
  }
}
