import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_shortcuts.dart';
import '../data/diagnostics_panel_width_store.dart';
import '../data/sidebar_width_store.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../diagnostics/diagnostics_scope.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'aggregate_view.dart';
import 'diagnostics_panel.dart';
import 'empty_state.dart';
import 'instance_actions.dart';
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

typedef _ForumBoundarySnapshot = ({
  String? privateForumTitle,
  String? unavailableForumTitle,
  bool connecting,
  bool retrying,
  String? error,
});

/// The application frame. A signed-out private forum replaces it with one
/// account boundary; once a forum is readable, the rail is present at every
/// size and everything to its right adapts to the available width.
class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({super.key});

  static const double railWidth = 72;
  static const double compactRailWidth = 64;
  static const double sidebarWidth = 240;
  static const double sidebarMinWidth = 200;
  static const double sidebarMaxWidth = 480;
  static const double mainContentMinWidth = 320;

  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  static const _tabShortcutKeys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  static const DiagnosticsPanelWidthStore _diagnosticsWidthStore =
      DiagnosticsPanelWidthStore();
  static const SidebarWidthStore _sidebarWidthStore = SidebarWidthStore();
  double _diagnosticsWidth = diagnosticsPanelWidth;
  double _sidebarWidth = AdaptiveShell.sidebarWidth;
  bool _diagnosticsWidthChanged = false;
  bool _sidebarWidthChanged = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleShortcut);
    unawaited(_restoreDiagnosticsWidth());
    unawaited(_restoreSidebarWidth());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleShortcut);
    super.dispose();
  }

  bool _handleShortcut(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final keyboard = HardwareKeyboard.instance;
    if (newTopicShortcut.accepts(event, keyboard)) {
      final controller = ShellScope.read(context);
      if (controller.rootMode != ShellRootMode.forum ||
          !controller.canCreateTopicFromSidebar ||
          _formControlHasFocus) {
        return false;
      }
      unawaited(controller.openNewTopicFromSidebar());
      return true;
    }

    if (topicReplyShortcut.accepts(event, keyboard)) {
      final controller = ShellScope.read(context);
      if (controller.rootMode != ShellRootMode.forum ||
          controller.currentContent?.isTopic != true ||
          !controller.canReplyHere ||
          _formControlHasFocus) {
        return false;
      }
      controller.openReply();
      return true;
    }

    final usesMetaModifier = defaultTargetPlatform == TargetPlatform.macOS;
    final modifierPressed = usesMetaModifier
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    if (!modifierPressed) return false;

    final controller = ShellScope.read(context);
    if (event.logicalKey == LogicalKeyboardKey.keyK) {
      if (controller.rootMode != ShellRootMode.forum) return false;
      controller.search.requestFocus();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyF) {
      if (controller.rootMode != ShellRootMode.forum) return false;
      final extraModifierPressed =
          keyboard.isShiftPressed ||
          keyboard.isAltPressed ||
          (usesMetaModifier
              ? keyboard.isControlPressed
              : keyboard.isMetaPressed);
      if (extraModifierPressed) return false;
      final topicId = controller.currentContent?.topicId;
      if (topicId == null) return false;
      controller.search.requestTopicFocus(topicId);
      return true;
    }

    final tabIndex = _tabShortcutKeys.indexOf(event.logicalKey);
    if (tabIndex < 0) return false;
    final extraModifierPressed =
        keyboard.isShiftPressed ||
        keyboard.isAltPressed ||
        (usesMetaModifier ? keyboard.isControlPressed : keyboard.isMetaPressed);
    if (extraModifierPressed) return false;

    if (controller.rootMode == ShellRootMode.aggregate) {
      final tabs = controller.aggregateTabs;
      if (!controller.forumTabsEnabled || tabIndex >= tabs.length) {
        return false;
      }
      controller.selectAggregateTab(tabs[tabIndex].id);
      return true;
    }
    final tabs = controller.tabsForCurrentForum;
    if (!controller.forumTabsEnabled || tabIndex >= tabs.length) {
      return false;
    }

    controller.selectTab(tabs[tabIndex].id);
    return true;
  }

  bool get _formControlHasFocus {
    final primaryFocus = FocusManager.instance.primaryFocus;
    final focusContext = primaryFocus?.context;
    if (primaryFocus == null ||
        primaryFocus is FocusScopeNode ||
        focusContext == null) {
      return false;
    }
    // A select moves primary focus into its popup route while the originating
    // form control remains open underneath it.
    if (ModalRoute.of(focusContext) is PopupRoute<Object?>) return true;

    bool isFormControl(Widget widget) =>
        widget is EditableText ||
        widget is FormField<Object?> ||
        widget is DropdownButton<Object?> ||
        widget is DropdownMenu<Object?> ||
        widget is Checkbox ||
        widget is CheckboxListTile ||
        widget is Radio<Object?> ||
        widget is RadioListTile<Object?> ||
        widget is Switch ||
        widget is SwitchListTile ||
        widget is Slider ||
        widget is RangeSlider ||
        widget is SegmentedButton<Object?> ||
        widget is ToggleButtons;

    if (isFormControl(focusContext.widget)) return true;
    var found = false;
    focusContext.visitAncestorElements((element) {
      found = isFormControl(element.widget);
      return !found;
    });
    if (found || focusContext is! Element) return found;

    // Some controls attach their FocusNode to a wrapper above the actual
    // control, so inspect that focused wrapper's subtree as well as its path.
    void visitFocusedSubtree(Element element) {
      if (found) return;
      found = isFormControl(element.widget);
      if (!found) element.visitChildElements(visitFocusedSubtree);
    }

    focusContext.visitChildElements(visitFocusedSubtree);
    return found;
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

  Future<void> _restoreSidebarWidth() async {
    final stored = await _sidebarWidthStore.read();
    if (!mounted ||
        _sidebarWidthChanged ||
        stored == null ||
        !stored.isFinite) {
      return;
    }
    setState(() {
      _sidebarWidth = stored.clamp(
        AdaptiveShell.sidebarMinWidth,
        AdaptiveShell.sidebarMaxWidth,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ShellSelector<_ForumBoundarySnapshot>(
      select: (controller) {
        final instance = controller.currentInstance;
        final forumMode = controller.rootMode == ShellRootMode.forum;
        final privateForum =
            forumMode &&
            controller.loadStatus == InstanceLoadStatus.ready &&
            instance?.loginRequired == true &&
            instance?.isConnected == false;
        final unavailableForum =
            forumMode &&
            controller.loadStatus == InstanceLoadStatus.ready &&
            instance != null &&
            controller.currentForumUnavailable;
        return (
          privateForumTitle: privateForum ? instance!.title : null,
          unavailableForumTitle: unavailableForum ? instance.title : null,
          connecting: privateForum && controller.connecting,
          retrying: unavailableForum && controller.retryingCurrentForum,
          error: privateForum ? controller.connectError : null,
        );
      },
      builder: (context, boundary, _) {
        if (boundary.unavailableForumTitle case final siteTitle?) {
          return Scaffold(
            body: _ForumBoundaryShell(
              child: _UnavailableForum(
                siteTitle: siteTitle,
                retrying: boundary.retrying,
              ),
            ),
          );
        }
        if (boundary.privateForumTitle case final siteTitle?) {
          return Scaffold(
            body: _ForumBoundaryShell(
              child: _PrivateForumSignIn(
                siteTitle: siteTitle,
                connecting: boundary.connecting,
                error: boundary.error,
              ),
            ),
          );
        }

        final diagnostics = DiagnosticsScope.maybeRead(context);
        if (diagnostics == null) return _buildScaffold(null, false);

        // Panel visibility is the only diagnostics-controller state that
        // rebuilds this frame. HTTP traffic is listened to by DiagnosticsPanel
        // itself, below the shell chrome, so it cannot rebuild the rail,
        // sidebar, topic list, or chat stream.
        return ValueListenableBuilder<bool>(
          valueListenable: diagnostics.panelListenable,
          builder: (context, open, _) => _buildScaffold(diagnostics, open),
        );
      },
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
              : _WideShell(
                  layout: layout,
                  sidebarWidth: _sidebarWidth,
                  onResizeSidebar: _resizeSidebar,
                  onResizeSidebarEnd: _persistSidebarWidth,
                );

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
              ...PluginScope.of(context).registry.shellOverlays(context),
            ],
          );

          if (diagnostics == null) return framedShell(shell);
          final panel = DiagnosticsPanel(
            controller: diagnostics,
            plugins: DiagnosticsScope.pluginsOf(context),
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

  void _resizeSidebar(double width) {
    setState(() {
      _sidebarWidthChanged = true;
      _sidebarWidth = width.clamp(
        AdaptiveShell.sidebarMinWidth,
        AdaptiveShell.sidebarMaxWidth,
      );
    });
  }

  void _persistSidebarWidth() {
    unawaited(_sidebarWidthStore.write(_sidebarWidth));
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

/// Keeps app-level forum switching available while one forum is unavailable.
class _ForumBoundaryShell extends StatelessWidget {
  const _ForumBoundaryShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const ShellTitleBar(showControls: false),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = ShellLayout.forWidth(constraints.maxWidth);
              final railWidth = layout.isCompact
                  ? AdaptiveShell.compactRailWidth
                  : AdaptiveShell.railWidth;
              return Row(
                children: [
                  SizedBox(width: railWidth, child: const InstanceRail()),
                  Expanded(child: ShellPanel(child: child)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The full-shell account boundary for a forum whose content is private.
///
/// Lookup has already established that anonymous requests cannot read this
/// forum. Keep its forum-specific chrome out of view until authentication
/// succeeds, while [_ForumBoundaryShell] preserves app-level forum switching.
class _PrivateForumSignIn extends StatelessWidget {
  const _PrivateForumSignIn({
    required this.siteTitle,
    required this.connecting,
    required this.error,
  });

  final String siteTitle;
  final bool connecting;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.read(context);

    return ColoredBox(
      key: const ValueKey('private-forum-gate'),
      color: theme.shell.content,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DIcon(
                    DIcons.lock,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Sign in to continue',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$siteTitle is a private forum. Sign in to view its topics '
                    'and conversations.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (error case final message?) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DIcon(
                              DIcons.triangleExclamation,
                              size: 18,
                              color: theme.colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                message,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const ValueKey('private-forum-sign-in'),
                    onPressed: connecting
                        ? null
                        : () => unawaited(controller.connectCurrentInstance()),
                    icon: connecting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                            ),
                          )
                        : const DIcon(DIcons.upRightFromSquare, size: 18),
                    label: Text(connecting ? 'Signing in…' : 'Sign in'),
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

/// The full-shell recovery boundary for a forum that did not answer.
///
/// The community title is the only route identity retained here: a connection
/// failure belongs to the forum, so channel names, tabs, sidebar destinations,
/// and composers would all imply that part of it remained usable.
class _UnavailableForum extends StatelessWidget {
  const _UnavailableForum({required this.siteTitle, required this.retrying});

  // The app's button padding matches Discourse's web controls. Flutter's
  // compact desktop density subtracts 8px from each vertical inset, which
  // reduces that padding to zero, so keep these prominent recovery actions at
  // the geometry the theme actually specifies.
  static const _actionStyle = ButtonStyle(
    visualDensity: VisualDensity.standard,
  );

  final String siteTitle;
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.read(context);

    return ColoredBox(
      key: const ValueKey('unavailable-forum-gate'),
      color: theme.shell.content,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Semantics(
                liveRegion: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        shape: BoxShape.circle,
                      ),
                      child: DIcon(
                        DIcons.triangleExclamation,
                        size: 32,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      siteTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "We couldn't reach this community. Check its address "
                      'or your internet connection, then try again.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('unavailable-forum-retry'),
                          style: _actionStyle,
                          onPressed: retrying
                              ? null
                              : () => unawaited(controller.retryCurrentForum()),
                          icon: retrying
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator.adaptive(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const DIcon(DIcons.arrowsRotate, size: 18),
                          label: Text(retrying ? 'Trying again…' : 'Try again'),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('unavailable-forum-remove'),
                          onPressed: () {
                            final instance = controller.currentInstance;
                            if (instance != null) {
                              unawaited(
                                confirmInstanceRemoval(context, instance),
                              );
                            }
                          },
                          style: _actionStyle.copyWith(
                            foregroundColor: WidgetStatePropertyAll(
                              theme.colorScheme.error,
                            ),
                          ),
                          icon: const DIcon(DIcons.trashCan, size: 18),
                          label: const Text('Remove forum'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResizableDiagnosticsPanel extends StatefulWidget {
  const _ResizableDiagnosticsPanel({
    required this.width,
    required this.onResize,
    required this.onResizeEnd,
    required this.child,
  });

  final double width;
  final ValueChanged<double> onResize;
  final VoidCallback onResizeEnd;
  final Widget child;

  @override
  State<_ResizableDiagnosticsPanel> createState() =>
      _ResizableDiagnosticsPanelState();
}

class _ResizableDiagnosticsPanelState
    extends State<_ResizableDiagnosticsPanel> {
  static const double _handleWidth = diagnosticsPanelResizeHandleWidth;
  static const double _keyboardStep = 16;

  final FocusNode _focus = FocusNode(debugLabel: 'diagnostics panel resize');
  bool _focused = false;
  bool _keyboardResizePending = false;

  @override
  void dispose() {
    if (_keyboardResizePending) widget.onResizeEnd();
    _focus.dispose();
    super.dispose();
  }

  void _resizeOnce(double delta) {
    widget.onResize(delta);
    widget.onResizeEnd();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => -_keyboardStep,
      LogicalKeyboardKey.arrowRight => _keyboardStep,
      _ => null,
    };
    if (delta == null) return KeyEventResult.ignored;

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      widget.onResize(delta);
      _keyboardResizePending = true;
    } else if (event is KeyUpEvent && _keyboardResizePending) {
      _keyboardResizePending = false;
      widget.onResizeEnd();
    }
    return KeyEventResult.handled;
  }

  void _focusChanged(bool focused) {
    if (_focused == focused) return;
    if (!focused && _keyboardResizePending) {
      _keyboardResizePending = false;
      widget.onResizeEnd();
    }
    setState(() => _focused = focused);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final divider = _focused ? theme.colorScheme.primary : theme.shell.divider;
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: _handleWidth,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: Focus(
              key: const ValueKey('diagnostics-resize-focus'),
              focusNode: _focus,
              onFocusChange: _focusChanged,
              onKeyEvent: _handleKey,
              child: Semantics(
                key: const ValueKey('diagnostics-resize-semantics'),
                container: true,
                focusable: true,
                focused: _focused,
                label: 'Resize diagnostics panel',
                value: '${widget.width.round()} pixels wide',
                increasedValue:
                    '${(widget.width + _keyboardStep).round()} pixels wide',
                decreasedValue:
                    '${(widget.width - _keyboardStep).round()} pixels wide',
                onIncrease: () => _resizeOnce(-_keyboardStep),
                onDecrease: () => _resizeOnce(_keyboardStep),
                child: GestureDetector(
                  key: const ValueKey('diagnostics-resize-handle'),
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: (_) => _focus.requestFocus(),
                  onHorizontalDragUpdate: (details) =>
                      widget.onResize(details.delta.dx),
                  onHorizontalDragEnd: (_) => widget.onResizeEnd(),
                  onHorizontalDragCancel: widget.onResizeEnd,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ColoredBox(
                      color: divider,
                      child: SizedBox(
                        width: _focused ? 3 : 1,
                        height: double.infinity,
                      ),
                    ),
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
        // canPop: false claims every back event before the platform sees it,
        // so once the shell has nothing left to unwind, leaving the app has
        // to be an explicit request rather than a fall-through.
        if (!ShellScope.read(context).handleBack()) {
          unawaited(SystemNavigator.pop());
        }
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
                      ShellRootMode rootMode,
                    })
                  >(
                    select: (controller) => (
                      loadStatus: controller.loadStatus,
                      hasInstances: controller.hasInstances,
                      pane: controller.mobilePane,
                      rootMode: controller.rootMode,
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
                        state.rootMode,
                      )) {
                        (InstanceLoadStatus.loading, _, _, _) =>
                          const _ShellLoadProgress(),
                        (InstanceLoadStatus.failed, _, _, _) =>
                          const _ShellLoadFailure(),
                        (InstanceLoadStatus.ready, false, _, _) =>
                          const EmptyState(key: ValueKey(MobilePane.sidebar)),
                        (
                          InstanceLoadStatus.ready,
                          true,
                          _,
                          ShellRootMode.aggregate,
                        ) =>
                          const AggregateView(
                            key: ValueKey(ShellRootMode.aggregate),
                          ),
                        // Only one pane is on screen at a time here, so whichever
                        // one it is carries the avatar — unless the title bar has it.
                        (
                          InstanceLoadStatus.ready,
                          true,
                          MobilePane.sidebar,
                          ShellRootMode.forum,
                        ) =>
                          InstanceSidebar(
                            key: const ValueKey(MobilePane.sidebar),
                            showUserMenu: ShellTitleBar.columnsCarryUserMenu,
                          ),
                        (
                          InstanceLoadStatus.ready,
                          true,
                          MobilePane.content,
                          ShellRootMode.forum,
                        ) =>
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
    final fromRight =
        child.key == const ValueKey(MobilePane.content) ||
        child.key == const ValueKey(ShellRootMode.aggregate);
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

class _ResizableSidebar extends StatefulWidget {
  const _ResizableSidebar({
    required this.width,
    required this.onResize,
    required this.onResizeEnd,
    required this.child,
  });

  final double width;
  final ValueChanged<double> onResize;
  final VoidCallback onResizeEnd;
  final Widget child;

  @override
  State<_ResizableSidebar> createState() => _ResizableSidebarState();
}

class _ResizableSidebarState extends State<_ResizableSidebar> {
  static const double _handleWidth = 16;
  static const double _keyboardStep = 16;

  final FocusNode _focus = FocusNode(debugLabel: 'sidebar resize');
  bool _focused = false;
  bool _keyboardResizePending = false;

  @override
  void dispose() {
    if (_keyboardResizePending) widget.onResizeEnd();
    _focus.dispose();
    super.dispose();
  }

  void _resizeOnce(double delta) {
    widget.onResize(widget.width + delta);
    widget.onResizeEnd();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => -_keyboardStep,
      LogicalKeyboardKey.arrowRight => _keyboardStep,
      _ => null,
    };
    if (delta == null) return KeyEventResult.ignored;

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      widget.onResize(widget.width + delta);
      _keyboardResizePending = true;
    } else if (event is KeyUpEvent && _keyboardResizePending) {
      _keyboardResizePending = false;
      widget.onResizeEnd();
    }
    return KeyEventResult.handled;
  }

  void _focusChanged(bool focused) {
    if (_focused == focused) return;
    if (!focused && _keyboardResizePending) {
      _keyboardResizePending = false;
      widget.onResizeEnd();
    }
    setState(() => _focused = focused);
  }

  @override
  Widget build(BuildContext context) {
    final increasedWidth = (widget.width + _keyboardStep).clamp(
      AdaptiveShell.sidebarMinWidth,
      AdaptiveShell.sidebarMaxWidth,
    );
    final decreasedWidth = (widget.width - _keyboardStep).clamp(
      AdaptiveShell.sidebarMinWidth,
      AdaptiveShell.sidebarMaxWidth,
    );

    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: _handleWidth,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: Focus(
              key: const ValueKey('sidebar-resize-focus'),
              focusNode: _focus,
              onFocusChange: _focusChanged,
              onKeyEvent: _handleKey,
              child: Semantics(
                key: const ValueKey('sidebar-resize-semantics'),
                container: true,
                focusable: true,
                focused: _focused,
                label: 'Resize sidebar',
                value: '${widget.width.round()} pixels wide',
                increasedValue: '${increasedWidth.round()} pixels wide',
                decreasedValue: '${decreasedWidth.round()} pixels wide',
                onIncrease: () => _resizeOnce(_keyboardStep),
                onDecrease: () => _resizeOnce(-_keyboardStep),
                child: GestureDetector(
                  key: const ValueKey('sidebar-resize-handle'),
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: (_) => _focus.requestFocus(),
                  onHorizontalDragUpdate: (details) =>
                      widget.onResize(widget.width + details.delta.dx),
                  onHorizontalDragEnd: (_) => widget.onResizeEnd(),
                  onHorizontalDragCancel: widget.onResizeEnd,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Rail + resizable sidebar + content, optionally with the right sidebar.
class _WideShell extends StatelessWidget {
  const _WideShell({
    required this.layout,
    required this.sidebarWidth,
    required this.onResizeSidebar,
    required this.onResizeSidebarEnd,
  });

  final ShellLayout layout;
  final double sidebarWidth;
  final ValueChanged<double> onResizeSidebar;
  final VoidCallback onResizeSidebarEnd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final windowMaximum = math.max(
          AdaptiveShell.sidebarMinWidth,
          constraints.maxWidth -
              AdaptiveShell.railWidth -
              AdaptiveShell.mainContentMinWidth,
        );
        final effectiveSidebarWidth = sidebarWidth
            .clamp(
              AdaptiveShell.sidebarMinWidth,
              math.min(AdaptiveShell.sidebarMaxWidth, windowMaximum),
            )
            .toDouble();

        return Row(
          children: [
            // The rail sits directly on the backdrop, with no panel of its own.
            const SizedBox(
              width: AdaptiveShell.railWidth,
              child: InstanceRail(),
            ),
            Expanded(
              child: ShellPanel(
                child:
                    ShellSelector<
                      ({
                        InstanceLoadStatus loadStatus,
                        bool hasInstances,
                        ShellRootMode rootMode,
                      })
                    >(
                      select: (controller) => (
                        loadStatus: controller.loadStatus,
                        hasInstances: controller.hasInstances,
                        rootMode: controller.rootMode,
                      ),
                      builder: (context, state, _) => switch (state
                          .loadStatus) {
                        InstanceLoadStatus.loading =>
                          const _ShellLoadProgress(),
                        InstanceLoadStatus.failed => const _ShellLoadFailure(),
                        InstanceLoadStatus.ready
                            when state.hasInstances &&
                                state.rootMode == ShellRootMode.aggregate =>
                          const AggregateView(),
                        InstanceLoadStatus.ready when state.hasInstances => Row(
                          children: [
                            SizedBox(
                              width: effectiveSidebarWidth,
                              child: _ResizableSidebar(
                                width: effectiveSidebarWidth,
                                onResize: onResizeSidebar,
                                onResizeEnd: onResizeSidebarEnd,
                                child: const InstanceSidebar(),
                              ),
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
      },
    );
  }
}

class _ShellLoadProgress extends StatelessWidget {
  const _ShellLoadProgress();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).shell.content,
    child: const Center(child: CircularProgressIndicator.adaptive()),
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
