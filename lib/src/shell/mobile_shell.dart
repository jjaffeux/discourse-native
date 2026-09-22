import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/sidebar.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/d_icons.dart';
import 'category_notifications.dart';
import 'forum_search.dart';
import 'forum_theme_surfaces.dart';
import 'instance_rail.dart';
import 'instance_sidebar.dart';
import 'message_create_button.dart';
import 'mobile_navigation.dart';
import 'shell_scope.dart';
import 'topic_list_bottom_bar.dart';
import 'user_menu_button.dart';

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
  final _drawer = DSheetController<void>();
  Object? _drawerLocation;

  @override
  void dispose() {
    _drawer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    final registry = PluginScope.of(context).registry;
    return ListenableBuilder(
      listenable: Listenable.merge([
        shell,
        shell.accountActivity.totalsListenable,
        shell.topicFeeds,
        ...registry.sidebarPanelListenables(context),
        ...registry.communitySidebarListenables(context),
      ]),
      builder: (context, _) {
        final instance = shell.currentInstance;
        if (instance == null) return const SizedBox.shrink();
        final owner = (instance.url, shell.currentAccountIdentity);
        final drawerLocation = (owner, shell.rootMode);
        if (_drawerLocation != drawerLocation) {
          _drawerLocation = drawerLocation;
          if (_drawer.isOpen) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _drawer.close();
            });
          }
        }
        final chat = registry
            .sidebarPanels(context)
            .where(
              (entry) => entry.owner.value == 'chat' && entry.panel.showSwitch,
            )
            .firstOrNull;
        final events = registry
            .communitySidebarDestinations(context)
            .where(
              (destination) =>
                  destination.id == 'events-upcoming' && destination.enabled,
            )
            .firstOrNull;
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
        if ((selected == MobileTab.chat && chat == null) ||
            (selected == MobileTab.events && events == null) ||
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
        final chatRoot =
            !widget.boundary &&
            selected == MobileTab.chat &&
            shell.mobileNavigation.atRoot &&
            chat != null;
        final buttons = <Widget>[
          _tabButton(
            context,
            MobileTab.topics,
            'Topics',
            DIcons.layerGroup,
            () => shell.selectMobileDestination(
              MobileTab.topics,
              instance.defaultDestination,
            ),
          ),
          if (chat != null)
            Stack(
              clipBehavior: Clip.none,
              children: [
                _tabButton(
                  context,
                  MobileTab.chat,
                  'Chat',
                  chat.panel.icon,
                  () => shell.selectMobilePanel(chat.owner.value),
                ),
                if (chat.panel.badge case final badge?)
                  PositionedDirectional(
                    bottom: 0,
                    end: 0,
                    child: IgnorePointer(child: badge),
                  ),
              ],
            ),
          if (destination('messages') case final messages?)
            _tabButton(
              context,
              MobileTab.messages,
              'Messages',
              DIcons.inbox,
              () => shell.selectMobileDestination(MobileTab.messages, messages),
            ),
          if (destination('users') case final users?)
            _tabButton(
              context,
              MobileTab.users,
              'Users',
              DIcons.user,
              () => shell.selectMobileDestination(MobileTab.users, users),
            ),
          if (events != null)
            _tabButton(
              context,
              MobileTab.events,
              'Events',
              events.icon,
              () => shell.selectMobileDestination(MobileTab.events, events),
            ),
          DDropdownMenu(
            content: DDropdownMenuContent(
              semanticLabel: 'More destinations',
              side: DPopoverSide.top,
              align: DPopoverAlign.end,
              children: [
                for (final id in ['groups', 'badges'])
                  if (destination(id) case final entry?)
                    DDropdownMenuItem(
                      leading: DIcon(entry.icon),
                      onPressed: () =>
                          shell.selectMobileDestination(MobileTab.more, entry),
                      child: Text(entry.label),
                    ),
                if (instance.isConnected)
                  DDropdownMenuItem(
                    leading: const DIcon(DIcons.bookmark),
                    onPressed: () => shell.selectMobileDestination(
                      MobileTab.more,
                      const SidebarDestination(
                        id: 'user-bookmarks',
                        label: 'Bookmarks',
                        icon: DIcons.bookmark,
                      ),
                    ),
                    child: const Text('Bookmarks'),
                  ),
              ],
            ),
            child: DDropdownMenuTrigger(
              builder: (context, state) => Semantics(
                selected: selected == MobileTab.more,
                child: DButton.iconOnly(
                  key: const ValueKey('mobile-mode-more'),
                  icon: const DIcon(DIcons.ellipsisVertical),
                  tooltip: 'More',
                  onPressed: state.toggle,
                  focusNode: state.focusNode,
                  hasPopup: true,
                  expanded: state.open,
                  shape: DButtonShape.pill,
                  variant: selected == MobileTab.more
                      ? DButtonVariant.primary
                      : DButtonVariant.ghost,
                  backgroundColor: selected == MobileTab.more
                      ? null
                      : DTokens.of(context).muted,
                ),
              ),
            ),
          ),
        ];
        final source = shell.topicListContent;
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
        final showCategoryNotifications =
            !widget.boundary &&
            shell.currentContent?.isTopic != true &&
            instance.isConnected &&
            source?.categoryId != null;
        final showDismiss =
            !widget.boundary &&
            shell.currentContent?.isTopic != true &&
            (shell.canDismissNewTopics || shell.dismissingNewTopics);
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
                      DSheet<void>(
                        controller: _drawer,
                        content: DSheetContent(
                          side: DSheetSide.start,
                          sidePanelWidth: MediaQuery.sizeOf(context).width,
                          sidePanelMaxWidth: 384,
                          semanticLabel: 'Forum navigation',
                          showCloseButton: false,
                          scrollWholeSheet: false,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 48,
                                    child: InstanceRail(),
                                  ),
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Align(
                                          alignment:
                                              AlignmentDirectional.centerEnd,
                                          child: DButton.iconOnly(
                                            icon: const Icon(Icons.close),
                                            tooltip: 'Close navigation',
                                            variant: DButtonVariant.ghost,
                                            onPressed: _drawer.close,
                                          ),
                                        ),
                                        Expanded(
                                          child: InstanceSidebar(
                                            key: ValueKey((
                                              'mobile-drawer',
                                              owner,
                                            )),
                                            mobile: true,
                                            onNavigate: _drawer.close,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        trigger: DSheetTrigger(
                          builder: (context, open) => DButton.iconOnly(
                            key: const ValueKey('mobile-menu-button'),
                            icon: const Icon(Icons.menu),
                            tooltip: 'Open navigation',
                            variant: DButtonVariant.ghost,
                            onPressed: open,
                          ),
                        ),
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
                      const UserMenuButton(),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: DSpacing.xs),
                child: DPageSurface(
                  key: const ValueKey('mobile-content-panel'),
                  backgroundColor: ForumWindowBackground.panelColor(context),
                  child: MobileHistoryGestures(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (chat != null)
                          Offstage(
                            offstage: !chatRoot,
                            child: TickerMode(
                              enabled: chatRoot,
                              child: ExcludeFocus(
                                excluding: !chatRoot,
                                child: InstanceSidebar(
                                  key: ValueKey(('mobile-chat', owner)),
                                  mobile: true,
                                  panelOwner: chat.owner.value,
                                ),
                              ),
                            ),
                          ),
                        if (!chatRoot) widget.content,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ForumSidebarTheme(
              child: Padding(
                padding: const EdgeInsets.all(DSpacing.xs),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final actions = [
                      ...buttons,
                      if (showDismiss)
                        const DismissNewTopicsButton(compact: true),
                      if (showCategoryNotifications)
                        CategoryNotificationLevelButton(
                          siteUrl: instance.url,
                          categoryId: source!.categoryId!,
                          showLabel: false,
                        ),
                    ];
                    final showLabel = _creationLabelFits(
                      context,
                      constraints.maxWidth,
                      actions.length,
                      showNewMessage ? 'New message' : 'New topic',
                    );
                    return Row(
                      key: const ValueKey('mobile-bottom-bar'),
                      spacing: DSpacing.controlGap,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              spacing: DSpacing.controlGap,
                              children: actions,
                            ),
                          ),
                        ),
                        if (showNewMessage)
                          MessageCreateButton(showLabel: showLabel, pill: true)
                        else if (showNewTopic)
                          if (showLabel)
                            DButton(
                              key: const ValueKey('mobile-new-topic'),
                              icon: const DIcon(DIcons.plus),
                              label: const Text('New topic'),
                              shape: DButtonShape.pill,
                              onPressed: () =>
                                  unawaited(shell.openNewTopicFromSidebar()),
                            )
                          else
                            DButton.iconOnly(
                              key: const ValueKey('mobile-new-topic'),
                              icon: const DIcon(DIcons.plus),
                              tooltip: 'New topic',
                              shape: DButtonShape.pill,
                              onPressed: () =>
                                  unawaited(shell.openNewTopicFromSidebar()),
                            ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

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
    ).clamp(48.0, double.infinity);
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

  Widget _tabButton(
    BuildContext context,
    MobileTab tab,
    String label,
    DIconData icon,
    VoidCallback onPressed,
  ) {
    final selected = ShellScope.read(context).mobileNavigation.tab == tab;
    return Semantics(
      selected: selected,
      child: DButton.iconOnly(
        key: ValueKey('mobile-mode-${tab.name}'),
        icon: DIcon(icon),
        tooltip: label,
        onPressed: onPressed,
        shape: selected ? DButtonShape.rounded : DButtonShape.pill,
        variant: selected ? DButtonVariant.primary : DButtonVariant.ghost,
        backgroundColor: selected ? null : DTokens.of(context).muted,
      ),
    );
  }
}

/// Adapts mobile visit history to the Native interactive transition.
class MobileHistoryGestures extends StatelessWidget {
  const MobileHistoryGestures({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final navigation = shell.mobileNavigation;
    return DHistoryTransition(
      history: navigation.historyId,
      tabIndex: navigation.tab.index,
      tabOwner: (shell.currentInstance?.url, shell.currentAccountIdentity),
      entry: navigation.entryId,
      previousEntry: navigation.previousEntryId,
      nextEntry: navigation.nextEntryId,
      onBack: navigation.canGoBack
          ? () {
              FocusManager.instance.primaryFocus?.unfocus();
              shell.handleBack();
            }
          : null,
      onForward: navigation.canGoForward
          ? () {
              FocusManager.instance.primaryFocus?.unfocus();
              shell.handleForward();
            }
          : null,
      child: child,
    );
  }
}
