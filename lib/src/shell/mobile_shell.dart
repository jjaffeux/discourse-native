import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../plugin_api/plugin_scope.dart';
import '../theme/d_icons.dart';
import 'forum_search.dart';
import 'forum_theme_surfaces.dart';
import 'instance_rail.dart';
import 'instance_sidebar.dart';
import 'shell_scope.dart';
import 'user_menu_button.dart';

/// The mobile root owns navigation chrome; shared feature pages sit above it.
class MobileForumRoot extends StatefulWidget {
  const MobileForumRoot({super.key, this.content});

  /// Forum availability/sign-in boundaries retain the same root navigation.
  final Widget? content;

  @override
  State<MobileForumRoot> createState() => _MobileForumRootState();
}

class _MobileForumRootState extends State<MobileForumRoot> {
  final _compact = ValueNotifier(false);
  Object? _destination;

  bool _onScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (notification.depth != 0 || metrics.axis != Axis.vertical) return false;
    final atTop = metrics.axisDirection == AxisDirection.down
        ? metrics.pixels <= metrics.minScrollExtent
        : metrics.pixels >= metrics.maxScrollExtent;
    if (atTop) {
      _compact.value = false;
    } else if (notification is ScrollUpdateNotification &&
        !metrics.outOfRange) {
      final delta = notification.scrollDelta ?? 0;
      // Physical scroll direction also works for reversed chat lists.
      final down = metrics.axisDirection == AxisDirection.down ? delta : -delta;
      if (down != 0) _compact.value = down > 0;
    }
    return false;
  }

  @override
  void dispose() {
    _compact.dispose();
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
        ...registry.sidebarPanelListenables(context),
      ]),
      builder: (context, _) {
        final instance = shell.currentInstance;
        if (instance == null) return const SizedBox.shrink();
        final panels = registry
            .sidebarPanels(context)
            .where((entry) => entry.panel.showSwitch)
            .toList();
        final requested = shell.mobileNavigation.panelOwner;
        final owner = panels.any((entry) => entry.owner.value == requested)
            ? requested
            : null;
        if (requested != owner) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted &&
                shell.mobileNavigation.panelOwner == requested) {
              shell.selectMobilePanel(null);
            }
          });
        }
        final destination = (instance.url, shell.currentAccountIdentity, owner);
        if (_destination != destination) {
          _destination = destination;
          _compact.value = false;
        }
        return Column(
          key: const ValueKey('mobile-root'),
          children: [
            Padding(
              key: const ValueKey('mobile-header'),
              padding: const EdgeInsetsDirectional.only(end: DSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: ForumIdentityHeader(
                      siteUrl: instance.url,
                      name: instance.title,
                      iconUrl: instance.iconUrl,
                      monogram: instance.monogram,
                      accentColor: instance.accentColor,
                      compact: true,
                    ),
                  ),
                  const ForumSearch(fullScreen: true),
                  const UserMenuButton(),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: DSpacing.sm),
                child: Row(
                  children: [
                    if (owner == null)
                      const SizedBox(width: 48, child: InstanceRail())
                    else
                      const SizedBox(width: DSpacing.sm),
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _onScroll,
                        child: DCard(
                          spacing: 0,
                          child: Expanded(
                            child:
                                widget.content ??
                                InstanceSidebar(
                                  key: ValueKey((
                                    instance.url,
                                    shell.currentAccountIdentity,
                                  )),
                                  mobile: true,
                                  panelOwner: owner,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(DSpacing.sm),
              child: ForumSidebarTheme(
                child: DTabs<String>.controlled(
                  key: const ValueKey('mobile-bottom-bar'),
                  value: owner ?? 'home',
                  onChanged: (value) =>
                      shell.selectMobilePanel(value == 'home' ? null : value),
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: _compact,
                      builder: (context, compact, _) => DTabList<String>(
                        variant: DTabListVariant.navigation,
                        navigationCompact: compact,
                        expandNavigationTabs: false,
                        trailing: DButton.iconOnly(
                          key: const ValueKey('mobile-new-topic'),
                          icon: const DIcon(DIcons.plus),
                          tooltip: 'New topic',
                          variant: DButtonVariant.primary,
                          onPressed: shell.canCreateTopicFromSidebar
                              ? () => unawaited(shell.openNewTopicFromSidebar())
                              : null,
                        ),
                        children: [
                          const DTabTrigger(
                            key: ValueKey('mobile-mode-home'),
                            value: 'home',
                            semanticLabel: 'Home',
                            child: DIcon(DIcons.house),
                          ),
                          for (final entry in panels)
                            DTabTrigger(
                              key: ValueKey('mobile-mode-${entry.owner.value}'),
                              value: entry.owner.value,
                              semanticLabel: entry.panel.label,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                spacing: DSpacing.controlGap,
                                children: [
                                  DIcon(entry.panel.icon),
                                  if (entry.panel.badge case final badge?)
                                    Flexible(child: badge),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
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
