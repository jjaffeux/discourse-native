import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/diagnostics_panel_width_store.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../diagnostics/diagnostics_scope.dart';
import '../plugins/resenha/resenha_call_widget.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'diagnostics_panel.dart';
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
class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({super.key});

  static const double railWidth = 72;
  static const double compactRailWidth = 64;
  static const double sidebarWidth = 240;

  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  final DiagnosticsPanelWidthStore _diagnosticsWidthStore =
      DiagnosticsPanelWidthStore();
  double _diagnosticsWidth = diagnosticsPanelWidth;
  bool _diagnosticsWidthChanged = false;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreDiagnosticsWidth());
  }

  Future<void> _restoreDiagnosticsWidth() async {
    final stored = await _diagnosticsWidthStore.read();
    if (!mounted ||
        _diagnosticsWidthChanged ||
        stored == null ||
        !stored.isFinite) {
      return;
    }
    setState(() {
      _diagnosticsWidth = stored.clamp(
        diagnosticsPanelMinWidth,
        diagnosticsPanelMaxWidth,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final diagnostics = DiagnosticsScope.maybeRead(context);
    if (diagnostics == null) return _buildScaffold(null, false);

    // Panel visibility is the only diagnostics-controller state that rebuilds
    // this frame. HTTP traffic is listened to by DiagnosticsPanel itself,
    // below the shell chrome, so it cannot rebuild the rail, sidebar, topic
    // list, or chat stream.
    return ValueListenableBuilder<bool>(
      valueListenable: diagnostics.panelListenable,
      builder: (context, open, _) => _buildScaffold(diagnostics, open),
    );
  }

  Widget _buildScaffold(
    DiagnosticsController? diagnostics,
    bool diagnosticsOpen,
  ) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final layout = ShellLayout.forWidth(constraints.maxWidth);
          final shell = layout.isCompact
              ? const _CompactShell()
              : _WideShell(layout: layout);

          Widget framedShell(Widget body) => Stack(
            children: [
              Positioned.fill(
                child: Column(
                  children: [
                    // Spans every shell column. On compact and medium layouts this
                    // frame sits under the app-wide diagnostics modal layer.
                    const ShellTitleBar(),
                    Expanded(child: body),
                  ],
                ),
              ),
              const Positioned.fill(
                child: IgnorePointer(
                  ignoring: false,
                  child: ResenhaCallWidget(),
                ),
              ),
            ],
          );

          if (diagnostics == null) return framedShell(shell);
          final panel = DiagnosticsPanel(
            controller: diagnostics,
            onClose: diagnostics.closePanel,
          );

          final panelWidth = _effectiveDiagnosticsWidth(constraints.maxWidth);
          final resizablePanel = _ResizableDiagnosticsPanel(
            width: panelWidth,
            onResize: (delta) => _resizeDiagnosticsPanel(
              fromWidth: panelWidth,
              delta: delta,
              availableWidth: constraints.maxWidth,
            ),
            onResizeEnd: _persistDiagnosticsWidth,
            child: panel,
          );

          if (layout == ShellLayout.expanded) {
            final docked = framedShell(
              Row(
                children: [
                  Expanded(child: shell),
                  if (diagnosticsOpen)
                    SizedBox(
                      key: const ValueKey('diagnostics-docked-slot'),
                      width: panelWidth,
                      child: resizablePanel,
                    ),
                ],
              ),
            );
            return _withDiagnosticsBackHandling(
              layout: layout,
              open: diagnosticsOpen,
              diagnostics: diagnostics,
              child: docked,
            );
          }

          final phoneWidth = constraints.maxWidth < 600;
          final overlay = Stack(
            children: [
              Positioned.fill(child: framedShell(shell)),
              if (diagnosticsOpen)
                Positioned.fill(
                  child: ModalBarrier(
                    key: const ValueKey('diagnostics-modal-barrier'),
                    dismissible: true,
                    onDismiss: diagnostics.closePanel,
                    color: Colors.black.withValues(alpha: 0.32),
                  ),
                ),
              if (diagnosticsOpen)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      key: const ValueKey('diagnostics-overlay-slot'),
                      width: phoneWidth ? constraints.maxWidth : panelWidth,
                      child: phoneWidth ? panel : resizablePanel,
                    ),
                  ),
                ),
            ],
          );
          return _withDiagnosticsBackHandling(
            layout: layout,
            open: diagnosticsOpen,
            diagnostics: diagnostics,
            child: overlay,
          );
        },
      ),
    );
  }

  double _effectiveDiagnosticsWidth(double availableWidth) {
    final windowMaximum = math.max(
      diagnosticsPanelMinWidth,
      availableWidth - AdaptiveShell.compactRailWidth,
    );
    return _diagnosticsWidth.clamp(
      diagnosticsPanelMinWidth,
      math.min(diagnosticsPanelMaxWidth, windowMaximum),
    );
  }

  void _resizeDiagnosticsPanel({
    required double fromWidth,
    required double delta,
    required double availableWidth,
  }) {
    final windowMaximum = math.max(
      diagnosticsPanelMinWidth,
      availableWidth - AdaptiveShell.compactRailWidth,
    );
    setState(() {
      _diagnosticsWidthChanged = true;
      _diagnosticsWidth = (fromWidth - delta).clamp(
        diagnosticsPanelMinWidth,
        math.min(diagnosticsPanelMaxWidth, windowMaximum),
      );
    });
  }

  void _persistDiagnosticsWidth() {
    unawaited(_diagnosticsWidthStore.write(_diagnosticsWidth));
  }

  Widget _withDiagnosticsBackHandling({
    required ShellLayout layout,
    required bool open,
    required DiagnosticsController diagnostics,
    required Widget child,
  }) {
    // Compact already owns a PopScope for its sidebar/content hierarchy. It
    // gives diagnostics first refusal itself so one Back event cannot both
    // close the panel and navigate the underlying shell.
    if (!open || layout.isCompact) return child;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && diagnostics.isPanelOpen) diagnostics.closePanel();
      },
      child: child,
    );
  }
}

class _ResizableDiagnosticsPanel extends StatelessWidget {
  const _ResizableDiagnosticsPanel({
    required this.width,
    required this.onResize,
    required this.onResizeEnd,
    required this.child,
  });

  static const double _handleWidth = 12;

  final double width;
  final ValueChanged<double> onResize;
  final VoidCallback onResizeEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).shell.divider;
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: _handleWidth,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: Semantics(
              label: 'Resize diagnostics panel',
              value: '${width.round()} pixels wide',
              child: GestureDetector(
                key: const ValueKey('diagnostics-resize-handle'),
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) => onResize(details.delta.dx),
                onHorizontalDragEnd: (_) => onResizeEnd(),
                onHorizontalDragCancel: onResizeEnd,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ColoredBox(
                    color: divider,
                    child: const SizedBox(width: 1, height: double.infinity),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Rail + one pane, swapping between the sidebar and the main content.
class _CompactShell extends StatelessWidget {
  const _CompactShell();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final diagnostics = DiagnosticsScope.maybeRead(context);
        if (diagnostics?.isPanelOpen ?? false) {
          diagnostics!.closePanel();
          return;
        }
        ShellScope.read(context).handleBack();
      },
      child: Row(
        children: [
          const SizedBox(
            width: AdaptiveShell.compactRailWidth,
            child: InstanceRail(),
          ),
          Expanded(
            child: ShellPanel(
              child:
                  ShellSelector<
                    ({
                      InstanceLoadStatus loadStatus,
                      bool hasInstances,
                      MobilePane pane,
                    })
                  >(
                    select: (controller) => (
                      loadStatus: controller.loadStatus,
                      hasInstances: controller.hasInstances,
                      pane: controller.mobilePane,
                    ),
                    builder: (context, state, _) => AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: _slide,
                      child: switch ((
                        state.loadStatus,
                        state.hasInstances,
                        state.pane,
                      )) {
                        (InstanceLoadStatus.loading, _, _) =>
                          const _ShellLoadProgress(),
                        (InstanceLoadStatus.failed, _, _) =>
                          const _ShellLoadFailure(),
                        (InstanceLoadStatus.ready, false, _) =>
                          const EmptyState(key: ValueKey(MobilePane.sidebar)),
                        // Only one pane is on screen at a time here, so whichever
                        // one it is carries the avatar — unless the title bar has it.
                        (InstanceLoadStatus.ready, true, MobilePane.sidebar) =>
                          InstanceSidebar(
                            key: const ValueKey(MobilePane.sidebar),
                            showUserMenu: ShellTitleBar.columnsCarryUserMenu,
                          ),
                        (InstanceLoadStatus.ready, true, MobilePane.content) =>
                          const MainContent(
                            key: ValueKey(MobilePane.content),
                            layout: ShellLayout.compact,
                          ),
                      },
                    ),
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
    return Row(
      children: [
        // The rail sits directly on the backdrop, with no panel of its own.
        const SizedBox(width: AdaptiveShell.railWidth, child: InstanceRail()),
        Expanded(
          child: ShellPanel(
            child:
                ShellSelector<
                  ({InstanceLoadStatus loadStatus, bool hasInstances})
                >(
                  select: (controller) => (
                    loadStatus: controller.loadStatus,
                    hasInstances: controller.hasInstances,
                  ),
                  builder: (context, state, _) => switch (state.loadStatus) {
                    InstanceLoadStatus.loading => const _ShellLoadProgress(),
                    InstanceLoadStatus.failed => const _ShellLoadFailure(),
                    InstanceLoadStatus.ready when state.hasInstances => Row(
                      children: [
                        const SizedBox(
                          width: AdaptiveShell.sidebarWidth,
                          child: InstanceSidebar(),
                        ),
                        Expanded(child: MainContent(layout: layout)),
                      ],
                    ),
                    InstanceLoadStatus.ready => const EmptyState(),
                  },
                ),
          ),
        ),
      ],
    );
  }
}

class _ShellLoadProgress extends StatelessWidget {
  const _ShellLoadProgress();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).shell.content,
    child: const Center(child: CircularProgressIndicator()),
  );
}

class _ShellLoadFailure extends StatelessWidget {
  const _ShellLoadFailure();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredBox(
      color: theme.shell.content,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DIcon(
                    DIcons.triangleExclamation,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Couldn't load your sites",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your saved sites have not been changed. Try loading them again.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const ValueKey('instance-load-retry-panel'),
                    onPressed: ShellScope.read(context).load,
                    icon: const DIcon(DIcons.arrowsRotate, size: 18),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
