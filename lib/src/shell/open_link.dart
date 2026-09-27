import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/content_route.dart';
import '../models/forum_workspace.dart';
import '../plugin_api/shell_extensions.dart';
import 'external_link.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'site_url.dart';
import 'user_card.dart';

Future<bool> openLink(
  BuildContext context,
  String url, {
  String? title,
  String? siteUrl,
  bool newTab = false,
  ForumPanel? panel,
  int? tabIndex,
}) async {
  final controller = ShellScope.maybeRead(context);

  final target =
      controller?.absoluteUrl(url, siteUrl: siteUrl) ??
      resolveSiteUrl(url, siteUrl);

  final requestedPanel =
      panel ??
      (HardwareKeyboard.instance.isShiftPressed &&
              controller?.desktopPanelsEnabled == true
          ? ForumPanel.secondary
          : null);

  if ((newTab || requestedPanel != null) && controller != null) {
    final result = newTab
        ? controller.openLinkInNewTab(
            target,
            title: title,
            panel: requestedPanel,
            index: tabIndex,
          )
        : controller.openLinkInPanel(
            target,
            title: title,
            panel: requestedPanel!,
          );
    if (result != TabOpenResult.unsupported) {
      return handleTabOpenResult(context, result);
    }
  }

  if (showUserCardForUrl(context, target, siteUrl: siteUrl)) return true;
  if (controller?.openCorePageUrl(target) ?? false) return true;
  if (await controller?.openPluginUrl(
        target,
        origin: switch ((requestedPanel, newTab)) {
          (ForumPanel.main, true) => PluginLinkOrigin.mainPanelNewTab,
          (ForumPanel.main, false) => PluginLinkOrigin.mainPanel,
          (ForumPanel.secondary, true) => PluginLinkOrigin.secondaryPanelNewTab,
          (ForumPanel.secondary, false) => PluginLinkOrigin.secondaryPanel,
          (_, true) => PluginLinkOrigin.newTab,
          _ => PluginLinkOrigin.inApp,
        },
      ) ??
      false) {
    return true;
  }
  if (controller?.openBadgeUrl(target, title: title) ?? false) return true;
  if (controller?.openGroupUrl(target) ?? false) return true;
  if (controller?.openTopicUrl(target) ?? false) return true;
  if (controller?.openListUrl(target, title: title) ?? false) return true;
  return openExternalLink(target);
}

bool handleTabOpenResult(BuildContext context, TabOpenResult result) {
  if (result == TabOpenResult.limitReached) {
    DToast.show(context, 'Close a tab before opening another.');
  }
  return result == TabOpenResult.opened;
}

final ValueNotifier<bool> _shiftHeldForLinks = ValueNotifier(false);
int _shiftWatcherUsers = 0;

bool _updateLinkShift(KeyEvent _) {
  _shiftHeldForLinks.value = HardwareKeyboard.instance.isShiftPressed;
  return false;
}

/// Keeps one link context menu open at a time across link surfaces.
final class LinkContextMenuSession {
  static LinkContextMenuSession? _active;

  final DContextMenuController controller = DContextMenuController();

  void onOpenChange(bool open, DPopoverChangeReason _) {
    if (open) {
      if (!identical(_active, this)) {
        final previous = _active;
        _active = this;
        previous?.controller.close();
      }
    } else if (identical(_active, this)) {
      _active = null;
    }
  }

  void dispose() {
    if (identical(_active, this)) _active = null;
    controller.dispose();
  }
}

void _watchLinkShift() {
  if (_shiftWatcherUsers++ == 0) {
    HardwareKeyboard.instance.addHandler(_updateLinkShift);
    _shiftHeldForLinks.value = HardwareKeyboard.instance.isShiftPressed;
  }
}

void _unwatchLinkShift() {
  if (--_shiftWatcherUsers == 0) {
    HardwareKeyboard.instance.removeHandler(_updateLinkShift);
    _shiftHeldForLinks.value = false;
  }
}

class LinkTarget extends StatefulWidget {
  const LinkTarget({
    super.key,
    required this.url,
    required this.child,
    this.title,
    this.siteUrl,
    this.longPressEnabled = true,
  }) : content = null,
       action = null;

  const LinkTarget.content({
    super.key,
    required ContentRoute this.content,
    required this.child,
    this.siteUrl,
    this.longPressEnabled = true,
  }) : url = null,
       title = null,
       action = null;

  const LinkTarget.action({
    super.key,
    required this.action,
    required this.child,
    this.longPressEnabled = true,
  }) : url = null,
       title = null,
       siteUrl = null,
       content = null;

  final String? url;
  final String? title;
  final String? siteUrl;
  final ContentRoute? content;
  final void Function({required bool newTab, ForumPanel? panel})? action;
  final Widget child;

  /// False where a touch long press already means something else, such as
  /// starting a drag in a reorderable list; secondary clicks still open the
  /// menu.
  final bool longPressEnabled;

  @override
  State<LinkTarget> createState() => _LinkTargetState();
}

class _LinkTargetState extends State<LinkTarget> {
  final _menu = LinkContextMenuSession();

  @override
  void initState() {
    super.initState();
    _watchLinkShift();
  }

  @override
  void dispose() {
    _unwatchLinkShift();
    _menu.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void activate({required bool newTab, ForumPanel? panel}) {
      if (widget.action case final open?) {
        open(newTab: newTab, panel: panel);
      } else if (widget.content case final route?) {
        final controller = ShellScope.read(context);
        if (newTab) {
          handleTabOpenResult(
            context,
            controller.openContentInNewTab(
              route,
              siteUrl: widget.siteUrl,
              panel: panel,
              select: false,
              source: controller.activeTab,
            ),
          );
        } else if (panel != null) {
          handleTabOpenResult(
            context,
            controller.openContentInPanel(route, panel: panel),
          );
        } else {
          controller.pushContent(route);
        }
      } else if (widget.url case final link?) {
        unawaited(
          openLink(
            context,
            link,
            title: widget.title,
            siteUrl: widget.siteUrl,
            newTab: newTab,
            panel: panel,
          ),
        );
      }
    }

    return ValueListenableBuilder<bool>(
      valueListenable: _shiftHeldForLinks,
      builder: (context, shiftHeld, _) {
        final shifted =
            shiftHeld &&
            ShellScope.maybeRead(context)?.desktopPanelsEnabled == true;
        return DContextMenu(
          controller: _menu.controller,
          onOpenChange: _menu.onOpenChange,
          content: DContextMenuContent(
            semanticLabel: 'Open link',
            children: [
              DContextMenuItem(
                onPressed: () =>
                    activate(newTab: false, panel: ForumPanel.main),
                child: const Text('Open in main panel'),
              ),
              DContextMenuItem(
                onPressed: () =>
                    activate(newTab: false, panel: ForumPanel.secondary),
                child: const Text('Open in secondary panel'),
              ),
              DContextMenuItem(
                onPressed: () => activate(newTab: true, panel: ForumPanel.main),
                child: const Text('Open in new main tab'),
              ),
              DContextMenuItem(
                onPressed: () =>
                    activate(newTab: true, panel: ForumPanel.secondary),
                child: const Text('Open in new secondary tab'),
              ),
            ],
          ),
          child: DContextMenuTrigger(
            focusable: false,
            captureSecondaryTap: true,
            longPressEnabled: widget.longPressEnabled,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: shifted
                  ? () => activate(newTab: false, panel: ForumPanel.secondary)
                  : null,
              onTertiaryTapUp: (_) => activate(
                newTab: true,
                panel: shifted ? ForumPanel.secondary : null,
              ),
              child: IgnorePointer(ignoring: shifted, child: widget.child),
            ),
          ),
        );
      },
    );
  }
}
