import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../plugin_api/plugin_scope.dart';
import '../theme/d_icons.dart';
import 'forum_search.dart';
import 'forum_settings_dialog.dart';
import 'instance_rail.dart';
import 'instance_sidebar.dart';
import 'shell_scope.dart';
import 'user_menu_button.dart';

/// The mobile root owns navigation chrome; shared feature pages sit above it.
class MobileForumRoot extends StatelessWidget {
  const MobileForumRoot({super.key, this.content});

  /// Forum availability/sign-in boundaries retain the same root navigation.
  final Widget? content;

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
        return Column(
          key: const ValueKey('mobile-root'),
          children: [
            Padding(
              key: const ValueKey('mobile-header'),
              padding: const EdgeInsets.symmetric(horizontal: DSpacing.sm),
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
                  const ForumSearch(sheet: true),
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
                      child: DCard(
                        spacing: 0,
                        child: Expanded(
                          child:
                              content ??
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
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(DSpacing.sm),
              child: DTabs<String>.controlled(
                key: const ValueKey('mobile-bottom-bar'),
                value: owner ?? 'home',
                onChanged: (value) =>
                    shell.selectMobilePanel(value == 'home' ? null : value),
                children: [
                  DTabList<String>(
                    variant: DTabListVariant.navigation,
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
                      Center(
                        child: DButton.iconOnly(
                          key: const ValueKey('mobile-forum-settings'),
                          icon: const DIcon(DIcons.gear),
                          tooltip: 'Forum settings',
                          variant: DButtonVariant.ghost,
                          onPressed: () => unawaited(
                            showForumSettingsDialog(
                              context,
                              siteUrl: instance.url,
                              name: instance.title,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Edge gestures observe pointer travel without taking horizontal gestures
/// away from carousels, editors or message actions in the page body.
class MobileHistoryGestures extends StatefulWidget {
  const MobileHistoryGestures({super.key, required this.child});
  final Widget child;

  @override
  State<MobileHistoryGestures> createState() => _MobileHistoryGesturesState();
}

class _MobileHistoryGesturesState extends State<MobileHistoryGestures> {
  int? _pointer;
  Offset? _start;
  bool _back = false;

  void _startGesture(PointerDownEvent event, double width) {
    if (_pointer != null ||
        event.kind != PointerDeviceKind.touch ||
        ModalRoute.of(context)?.isCurrent != true) {
      _start = null;
      return;
    }
    final x = event.localPosition.dx;
    if (x > 24 && x < width - 24) return;
    _pointer = event.pointer;
    _start = event.localPosition;
    _back = Directionality.of(context) == TextDirection.ltr
        ? x <= 24
        : x >= width - 24;
  }

  void _finishGesture(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    final start = _start;
    _pointer = null;
    _start = null;
    if (start == null || ModalRoute.of(context)?.isCurrent != true) return;
    final delta = event.localPosition - start;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final progress = delta.dx * ((_back != rtl) ? 1 : -1);
    if (progress < 64 || delta.dy.abs() > progress / 2) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final shell = ShellScope.read(context);
    if (_back) {
      shell.handleBack();
    } else {
      shell.handleForward();
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _startGesture(event, constraints.maxWidth),
      onPointerUp: _finishGesture,
      onPointerMove: (event) {
        if (_start case final start? when event.pointer == _pointer) {
          if ((event.localPosition.dy - start.dy).abs() > 40) _start = null;
        }
      },
      onPointerCancel: (_) {
        _pointer = null;
        _start = null;
      },
      child: widget.child,
    ),
  );
}
