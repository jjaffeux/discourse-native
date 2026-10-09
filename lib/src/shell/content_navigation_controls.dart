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
              variant: DCardVariant.capsule,
              size: DCardSize.small,
              border: false,
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                label: context.l10n.navigation,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: DSpacing.xxs,
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
                      density: DButtonDensity.chrome,
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
                      density: DButtonDensity.chrome,
                      onPressed: state.forward
                          ? controller.handleForward
                          : null,
                    ),
                    DSeparator(
                      orientation: Axis.vertical,
                      space: 11,
                      length: DControlStyle.scaledHeight(
                        DControlSize.segment,
                        MediaQuery.textScalerOf(context),
                        context: context,
                      ),
                      indent: DSpacing.controlGap,
                      endIndent: DSpacing.controlGap,
                      color: tokens.border,
                    ),
                    DButton.iconOnly(
                      key: refreshKey,
                      icon: const DIcon(DIcons.arrowRotateRight),
                      tooltip: context.l10n.refreshCurrentTab,
                      shortcut: DShortcut(
                        refreshTabShortcutForPlatform(defaultTargetPlatform),
                      ),
                      variant: DButtonVariant.ghost,
                      density: DButtonDensity.chrome,
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
