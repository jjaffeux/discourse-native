import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_shortcuts.dart';
import '../theme/d_icons.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

class ContentNavigationControls extends StatelessWidget {
  const ContentNavigationControls({super.key});

  static const backKey = ValueKey('content-navigation-back');
  static const forwardKey = ValueKey('content-navigation-forward');
  static const refreshKey = ValueKey('content-navigation-refresh');

  static bool get isSupported => switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) =>
      ShellSelector<({bool back, bool forward, bool refresh, bool refreshing})>(
        select: (controller) => (
          back:
              controller.rootMode == ShellRootMode.forum &&
              controller.canPopContent,
          forward:
              controller.rootMode == ShellRootMode.forum &&
              controller.canForwardContent,
          refresh: controller.canRefreshCurrentTab,
          refreshing: controller.refreshingCurrentTab,
        ),
        builder: (context, state, _) {
          final controller = ShellScope.read(context);
          final tokens = DTokens.of(context);
          return IntrinsicWidth(
            child: DCard(
              spacing: 0,
              borderRadius: BorderRadius.circular(DRadius.pill),
              backgroundColor: tokens.hover,
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                label: context.l10n.navigation,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DButton.iconOnly(
                      key: backKey,
                      icon: const DIcon(DIcons.arrowLeft),
                      tooltip: context.l10n.backMouseBackButton,
                      semanticLabel: context.l10n.back,
                      shortcut: DShortcut(
                        contentBackShortcutForPlatform(defaultTargetPlatform),
                      ),
                      variant: DButtonVariant.ghost,
                      size: DButtonSize.toolbar,
                      shape: DButtonShape.pill,
                      onPressed: state.back
                          ? () =>
                                controller.handleBack(canReturnToSidebar: false)
                          : null,
                    ),
                    DButton.iconOnly(
                      key: forwardKey,
                      icon: const RotatedBox(
                        quarterTurns: 2,
                        child: DIcon(DIcons.arrowLeft),
                      ),
                      tooltip: context.l10n.forwardMouseForwardButton,
                      semanticLabel: context.l10n.forward,
                      shortcut: DShortcut(
                        contentForwardShortcutForPlatform(
                          defaultTargetPlatform,
                        ),
                      ),
                      variant: DButtonVariant.ghost,
                      size: DButtonSize.toolbar,
                      shape: DButtonShape.pill,
                      onPressed: state.forward
                          ? controller.handleForward
                          : null,
                    ),
                    DSeparator(
                      orientation: Axis.vertical,
                      length: DControlStyle.scaledHeight(
                        DControlSize.toolbar,
                        MediaQuery.textScalerOf(context),
                        context: context,
                      ),
                      indent: DSpacing.sm,
                      endIndent: DSpacing.sm,
                      color: tokens.mutedForeground.withValues(alpha: .35),
                    ),
                    DButton.iconOnly(
                      key: refreshKey,
                      icon: const DIcon(DIcons.arrowsRotate),
                      tooltip: context.l10n.refreshCurrentTab,
                      shortcut: DShortcut(
                        refreshTabShortcutForPlatform(defaultTargetPlatform),
                      ),
                      variant: DButtonVariant.ghost,
                      size: DButtonSize.toolbar,
                      shape: DButtonShape.pill,
                      foregroundColor: tokens.foreground,
                      onPressed: state.refresh && !state.refreshing
                          ? () => unawaited(controller.refreshCurrentTab())
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}
