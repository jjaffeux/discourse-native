import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'empty_state.dart';
import 'instance_rail.dart';
import 'instance_sidebar.dart';
import 'main_content.dart';
import 'right_sidebar.dart';
import 'shell_controller.dart';
import 'shell_panel.dart';
import 'shell_scope.dart';
import 'user_bar.dart';

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

/// Grows the bottom padding the columns see, so their contents end above the
/// user bar drawn on top of them. Their backgrounds still run to the bottom
/// edge, which is what makes the bar read as floating rather than as a row.
Widget reserveForUserBar(BuildContext context, {required Widget child}) {
  final media = MediaQuery.of(context);
  return MediaQuery(
    data: media.copyWith(
      padding: media.padding.copyWith(bottom: UserBar.reservedHeight(context)),
    ),
    child: child,
  );
}

/// The application frame. The rail is present at every size; everything to the
/// right of it is what changes.
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({super.key});

  static const double railWidth = 72;
  static const double compactRailWidth = 64;
  static const double sidebarWidth = 240;
  static const double rightSidebarWidth = 280;

  /// Clearance for the traffic lights, which float over the top of the rail
  /// now that the macOS window has no title bar of its own.
  static double windowControlsInset(BuildContext context) =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS ? 28 : 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final layout = ShellLayout.forWidth(constraints.maxWidth);
          return layout.isCompact
              ? const _CompactShell()
              : _WideShell(layout: layout);
        },
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

    // The bar belongs to the navigation side, so when the main content takes
    // over the pane it gets the full height instead.
    final showUserBar = controller.mobilePane == MobilePane.sidebar;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        controller.handleBack();
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: _maybeReserve(
              context,
              reserve: showUserBar,
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
                          (true, MobilePane.sidebar) => const InstanceSidebar(
                            key: ValueKey(MobilePane.sidebar),
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
            ),
          ),
          if (showUserBar)
            const Positioned(left: 0, right: 0, bottom: 0, child: UserBar()),
        ],
      ),
    );
  }

  static Widget _maybeReserve(
    BuildContext context, {
    required bool reserve,
    required Widget child,
  }) => reserve ? reserveForUserBar(context, child: child) : child;

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
    final showRightSidebar =
        layout == ShellLayout.expanded && controller.rightSidebarVisible;

    return Stack(
      children: [
        Positioned.fill(
          child: Row(
            children: [
              // The rail sits directly on the backdrop, with no panel of its own.
              SizedBox(
                width: AdaptiveShell.railWidth,
                child: reserveForUserBar(context, child: const InstanceRail()),
              ),
              Expanded(
                child: ShellPanel(
                  child: controller.hasInstances
                      ? Row(
                          children: [
                            SizedBox(
                              width: AdaptiveShell.sidebarWidth,
                              child: reserveForUserBar(
                                context,
                                child: const InstanceSidebar(),
                              ),
                            ),
                            Expanded(child: MainContent(layout: layout)),
                            if (showRightSidebar)
                              const SizedBox(
                                width: AdaptiveShell.rightSidebarWidth,
                                child: RightSidebar(),
                              ),
                          ],
                        )
                      : const EmptyState(),
                ),
              ),
            ],
          ),
        ),
        // Floats over the rail and the sidebar, but not the main content.
        const Positioned(
          left: 0,
          bottom: 0,
          width: AdaptiveShell.railWidth + AdaptiveShell.sidebarWidth,
          child: UserBar(),
        ),
      ],
    );
  }
}
