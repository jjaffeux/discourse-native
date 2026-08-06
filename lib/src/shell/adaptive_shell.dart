import 'package:flutter/material.dart';

import 'empty_state.dart';
import 'instance_rail.dart';
import 'instance_sidebar.dart';
import 'main_content.dart';
import 'shell_controller.dart';
import 'shell_panel.dart';
import 'shell_scope.dart';
import 'title_bar.dart';

/// How much horizontal room the shell has to work with.
enum ShellLayout {
  /// Rail plus exactly one pane. Phones, and very narrow desktop windows.
  compact,

  /// Rail, sidebar and main content side by side.
  medium,

  /// Adds the optional right sidebar.
  expanded;

  static const double mediumMinWidth = 768;
  static const double expandedMinWidth = 1200;

  static ShellLayout forWidth(double width) {
    if (width >= expandedMinWidth) return ShellLayout.expanded;
    if (width >= mediumMinWidth) return ShellLayout.medium;
    return ShellLayout.compact;
  }

  bool get isCompact => this == ShellLayout.compact;
}

/// The application frame. The rail is present at every size; everything to the
/// right of it is what changes.
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({super.key});

  static const double railWidth = 72;
  static const double compactRailWidth = 64;
  static const double sidebarWidth = 240;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Spans every column, above the rail as well as the panel.
          const ShellTitleBar(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final layout = ShellLayout.forWidth(constraints.maxWidth);
                return layout.isCompact
                    ? const _CompactShell()
                    : _WideShell(layout: layout);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Rail + one pane, swapping between the sidebar and the main content.
class _CompactShell extends StatelessWidget {
  const _CompactShell();

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        controller.handleBack();
      },
      child: Row(
        children: [
          const SizedBox(
            width: AdaptiveShell.compactRailWidth,
            child: InstanceRail(),
          ),
          Expanded(
            child: ShellPanel(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: _slide,
                child: switch ((
                  controller.hasInstances,
                  controller.mobilePane,
                )) {
                  (false, _) => const EmptyState(
                    key: ValueKey(MobilePane.sidebar),
                  ),
                  // Only one pane is on screen at a time here, so whichever one
                  // it is carries the avatar — unless the title bar has it.
                  (true, MobilePane.sidebar) => InstanceSidebar(
                    key: const ValueKey(MobilePane.sidebar),
                    showUserMenu: ShellTitleBar.columnsCarryUserMenu,
                  ),
                  (true, MobilePane.content) => const MainContent(
                    key: ValueKey(MobilePane.content),
                    layout: ShellLayout.compact,
                  ),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Content arrives from the right, the sidebar from the left, so the swap
  /// reads as moving in and out of a hierarchy rather than a crossfade.
  static Widget _slide(Widget child, Animation<double> animation) {
    final fromRight = child.key == const ValueKey(MobilePane.content);
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(fromRight ? 0.12 : -0.12, 0),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}

/// Rail + sidebar + content, optionally with the right sidebar.
class _WideShell extends StatelessWidget {
  const _WideShell({required this.layout});

  final ShellLayout layout;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.of(context);

    return Row(
      children: [
        // The rail sits directly on the backdrop, with no panel of its own.
        const SizedBox(width: AdaptiveShell.railWidth, child: InstanceRail()),
        Expanded(
          child: ShellPanel(
            child: controller.hasInstances
                ? Row(
                    children: [
                      const SizedBox(
                        width: AdaptiveShell.sidebarWidth,
                        child: InstanceSidebar(),
                      ),
                      Expanded(child: MainContent(layout: layout)),
                    ],
                  )
                : const EmptyState(),
          ),
        ),
      ],
    );
  }
}
