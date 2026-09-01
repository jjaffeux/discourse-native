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
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'aggregate_view.dart';
import 'app_settings_page.dart';
import 'composer_controller.dart';
import 'composer_panel.dart';
import 'diagnostics_panel.dart';
import 'empty_state.dart';
import 'instance_actions.dart';
import 'instance_rail.dart';
import 'instance_sidebar.dart';
import 'main_content.dart';
import 'resizable_pane.dart';
import 'shell_controller.dart';
import 'shell_panel.dart';
import 'shell_scope.dart';
import 'title_bar.dart';

enum ShellLayout {
  compact,

  medium,

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
  bool settings,
});

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
  static const DiagnosticsPanelWidthStore _diagnosticsWidthStore =
      DiagnosticsPanelWidthStore();
  static const SidebarWidthStore _sidebarWidthStore = SidebarWidthStore();
  late final PanelWidthController _diagnosticsWidth;
  late final PanelWidthController _sidebarWidth;

  @override
  void initState() {
    super.initState();
    _diagnosticsWidth = PanelWidthController(
      initialWidth: diagnosticsPanelWidth,
      minimumWidth: diagnosticsPanelMinWidth,
      maximumWidth: diagnosticsPanelMaxWidth,
      readWidth: _diagnosticsWidthStore.read,
      writeWidth: _diagnosticsWidthStore.write,
    );
    _sidebarWidth = PanelWidthController(
      initialWidth: AdaptiveShell.sidebarWidth,
      minimumWidth: AdaptiveShell.sidebarMinWidth,
      maximumWidth: AdaptiveShell.sidebarMaxWidth,
      readWidth: _sidebarWidthStore.read,
      writeWidth: _sidebarWidthStore.write,
    );
    HardwareKeyboard.instance.addHandler(_handleShortcut);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleShortcut);
    _diagnosticsWidth.dispose();
    _sidebarWidth.dispose();
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
    final extraModifierPressed =
        keyboard.isShiftPressed ||
        keyboard.isAltPressed ||
        (usesMetaModifier ? keyboard.isControlPressed : keyboard.isMetaPressed);
    if (extraModifierPressed) return false;

    if (event.logicalKey == LogicalKeyboardKey.keyF) {
      if (controller.rootMode != ShellRootMode.forum) return false;

      final route = controller.currentContent;
      final pluginSearch = route == null
          ? (owned: false, action: null)
          : PluginScope.of(context).registry.contentSearch(context, route);
      if (pluginSearch.owned) {
        pluginSearch.action?.call();
        return pluginSearch.action != null;
      }
      if (route?.topicId case final topicId?) {
        controller.search.requestTopicFocus(topicId);
      } else {
        controller.search.requestFocus();
      }
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyT) {
      return _openTab(controller);
    }
    if (event.logicalKey == LogicalKeyboardKey.keyW) {
      return _closeCurrentTab(controller);
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      return _selectAdjacentTab(controller, -1);
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      return _selectAdjacentTab(controller, 1);
    }

    final shortcutIndex = forumSwitchShortcutKeys.indexOf(event.logicalKey);
    if (shortcutIndex < 0 || !controller.forumTabsEnabled) return false;

    if (shortcutIndex == 0) {
      if (controller.instances.isEmpty) return false;
      controller.selectAggregate();
      return true;
    }

    final forumIndex = shortcutIndex - 1;
    if (forumIndex >= controller.instances.length) {
      return false;
    }
    controller.selectInstance(forumIndex);
    return true;
  }

  bool _openTab(ShellController controller) {
    if (!controller.forumTabsEnabled) return false;
    switch (controller.rootMode) {
      case ShellRootMode.aggregate:
        if (!controller.canCreateAggregateTab) return false;
        controller.createAggregateTab();
      case ShellRootMode.forum:
        if (!controller.canCreateTab) return false;
        controller.createTab();
      case ShellRootMode.settings:
        return false;
    }
    return true;
  }

  bool _closeCurrentTab(ShellController controller) {
    if (!controller.forumTabsEnabled) return false;
    switch (controller.rootMode) {
      case ShellRootMode.aggregate:
        controller.closeAggregateTab(controller.activeAggregateTabId);
      case ShellRootMode.forum:
        final activeTabId = controller.activeTabId;
        if (activeTabId == null) return false;
        controller.closeTab(activeTabId);
      case ShellRootMode.settings:
        return false;
    }
    return true;
  }

  bool _selectAdjacentTab(ShellController controller, int offset) {
    if (!controller.forumTabsEnabled || _formControlHasFocus) return false;

    final (tabs, activeTabId) = switch (controller.rootMode) {
      ShellRootMode.aggregate => (
        controller.aggregateTabs.map((tab) => tab.id).toList(),
        controller.activeAggregateTabId,
      ),
      ShellRootMode.forum => (
        controller.tabsForCurrentForum.map((tab) => tab.id).toList(),
        controller.activeTabId,
      ),
      ShellRootMode.settings => (const <String>[], null),
    };
    if (tabs.length < 2 || activeTabId == null) return false;

    final activeIndex = tabs.indexOf(activeTabId);
    if (activeIndex < 0) return false;
    final targetId = tabs[(activeIndex + offset) % tabs.length];
    switch (controller.rootMode) {
      case ShellRootMode.aggregate:
        controller.selectAggregateTab(targetId);
      case ShellRootMode.forum:
        controller.selectTab(targetId);
      case ShellRootMode.settings:
        return false;
    }
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
          settings: controller.rootMode == ShellRootMode.settings,
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
        if (diagnostics == null) {
          return _buildScaffold(null, false, settings: boundary.settings);
        }

        // Panel visibility is the only diagnostics-controller state that
        // rebuilds this frame. HTTP traffic is listened to by DiagnosticsPanel
        // itself, below the shell chrome, so it cannot rebuild the rail,
        // sidebar, topic list, or chat stream.
        return ValueListenableBuilder<bool>(
          valueListenable: diagnostics.panelListenable,
          builder: (context, open, _) =>
              _buildScaffold(diagnostics, open, settings: boundary.settings),
        );
      },
    );
  }

  Widget _buildScaffold(
    DiagnosticsController? diagnostics,
    bool diagnosticsOpen, {
    required bool settings,
  }) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final layout = ShellLayout.forWidth(constraints.maxWidth);
          final shell = layout.isCompact
              ? const _CompactShell()
              : _WideShell(layout: layout, sidebarWidth: _sidebarWidth);

          Widget framedShell(Widget body) => Stack(
            children: [
              Positioned.fill(
                child: Column(
                  children: [
                    const ShellTitleBar(),
                    Expanded(child: body),
                  ],
                ),
              ),
              ...PluginScope.of(context).registry.shellOverlays(context),
              const Positioned.fill(child: _ComposerViewportOverlay()),
            ],
          );

          if (diagnostics == null) return framedShell(shell);
          final showDiagnostics = diagnosticsOpen && !settings;
          final panel = DiagnosticsPanel(
            controller: diagnostics,
            plugins: DiagnosticsScope.pluginsOf(context),
            onClose: diagnostics.closePanel,
          );

          final panelMaximumWidth = math.max(
            diagnosticsPanelMinWidth,
            constraints.maxWidth - AdaptiveShell.compactRailWidth,
          );

          Widget resizablePanel(Key key) => ResizablePane(
            key: key,
            controller: _diagnosticsWidth,
            edge: ResizablePaneEdge.leading,
            resizeKey: 'diagnostics',
            semanticsLabel: 'Resize diagnostics panel',
            maximumWidth: panelMaximumWidth,
            handleWidth: diagnosticsPanelResizeHandleWidth,
            dividerWidth: 1,
            child: panel,
          );

          if (layout == ShellLayout.expanded) {
            final docked = framedShell(
              Row(
                children: [
                  Expanded(child: shell),
                  if (showDiagnostics)
                    resizablePanel(const ValueKey('diagnostics-docked-slot')),
                ],
              ),
            );
            return _withDiagnosticsBackHandling(
              layout: layout,
              open: showDiagnostics,
              diagnostics: diagnostics,
              child: docked,
            );
          }

          final phoneWidth = constraints.maxWidth < 600;
          final overlay = Stack(
            children: [
              Positioned.fill(child: framedShell(shell)),
              if (showDiagnostics)
                Positioned.fill(
                  child: ModalBarrier(
                    key: const ValueKey('diagnostics-modal-barrier'),
                    dismissible: true,
                    onDismiss: diagnostics.closePanel,
                    color: Colors.black.withValues(alpha: 0.32),
                  ),
                ),
              if (showDiagnostics)
                Positioned.fill(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: phoneWidth
                        ? SizedBox(
                            key: const ValueKey('diagnostics-overlay-slot'),
                            width: constraints.maxWidth,
                            child: panel,
                          )
                        : resizablePanel(
                            const ValueKey('diagnostics-overlay-slot'),
                          ),
                  ),
                ),
            ],
          );
          return _withDiagnosticsBackHandling(
            layout: layout,
            open: showDiagnostics,
            diagnostics: diagnostics,
            child: overlay,
          );
        },
      ),
    );
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

class _ComposerViewportOverlay extends StatelessWidget {
  const _ComposerViewportOverlay();

  @override
  Widget build(BuildContext context) => ShellSelector<ComposerController?>(
    select: (controller) => controller.visibleComposer,
    builder: (context, composer, _) => composer == null
        ? const SizedBox.shrink()
        : FloatingComposerPanel(key: ObjectKey(composer), composer: composer),
  );
}

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
                  DButton(
                    key: const ValueKey('private-forum-sign-in'),
                    label: const Text('Sign in'),
                    onPressed: () =>
                        unawaited(controller.connectCurrentInstance()),
                    icon: const DIcon(DIcons.upRightFromSquare, size: 18),
                    variant: DButtonVariant.primary,
                    loading: connecting,
                    loadingLabel: const Text('Signing in…'),
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

class _UnavailableForum extends StatelessWidget {
  const _UnavailableForum({required this.siteTitle, required this.retrying});

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
                        DButton(
                          key: const ValueKey('unavailable-forum-retry'),
                          label: const Text('Try again'),
                          onPressed: () =>
                              unawaited(controller.retryCurrentForum()),
                          icon: const DIcon(DIcons.arrowsRotate, size: 18),
                          variant: DButtonVariant.primary,
                          loading: retrying,
                          loadingLabel: const Text('Trying again…'),
                        ),
                        DButton(
                          key: const ValueKey('unavailable-forum-remove'),
                          label: const Text('Remove forum'),
                          onPressed: () {
                            final instance = controller.currentInstance;
                            if (instance != null) {
                              unawaited(
                                confirmInstanceRemoval(context, instance),
                              );
                            }
                          },
                          icon: const DIcon(DIcons.trashCan, size: 18),
                          variant: DButtonVariant.danger,
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
                      bool settings,
                    })
                  >(
                    select: (controller) => (
                      loadStatus: controller.loadStatus,
                      hasInstances: controller.hasInstances,
                      pane: controller.settingsUnderlayMobilePane,
                      rootMode: controller.settingsUnderlayRootMode,
                      settings: controller.rootMode == ShellRootMode.settings,
                    ),
                    builder: (context, state, _) => _SettingsStack(
                      settings: state.settings,
                      underlay: AnimatedSwitcher(
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
                          (_, _, _, ShellRootMode.settings) =>
                            const SizedBox.shrink(),
                        },
                      ),
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _slide(Widget child, Animation<double> animation) {
    final fromRight =
        child.key == const ValueKey(MobilePane.content) ||
        child.key == const ValueKey(ShellRootMode.aggregate) ||
        child.key == const ValueKey(ShellRootMode.settings);
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

class _SettingsStack extends StatelessWidget {
  const _SettingsStack({required this.settings, required this.underlay});

  final bool settings;
  final Widget underlay;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Visibility(visible: !settings, maintainState: true, child: underlay),
      Visibility(
        visible: settings,
        maintainState: true,
        child: const AppSettingsPage(key: ValueKey(ShellRootMode.settings)),
      ),
    ],
  );
}

class _WideShell extends StatelessWidget {
  const _WideShell({required this.layout, required this.sidebarWidth});

  final ShellLayout layout;
  final PanelWidthController sidebarWidth;

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
        return Row(
          children: [
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
                        bool settings,
                      })
                    >(
                      select: (controller) => (
                        loadStatus: controller.loadStatus,
                        hasInstances: controller.hasInstances,
                        rootMode: controller.settingsUnderlayRootMode,
                        settings: controller.rootMode == ShellRootMode.settings,
                      ),
                      builder: (context, state, _) => _SettingsStack(
                        settings: state.settings,
                        underlay: switch (state.loadStatus) {
                          InstanceLoadStatus.loading =>
                            const _ShellLoadProgress(),
                          InstanceLoadStatus.failed =>
                            const _ShellLoadFailure(),
                          InstanceLoadStatus.ready
                              when state.hasInstances &&
                                  state.rootMode == ShellRootMode.aggregate =>
                            const AggregateView(),
                          InstanceLoadStatus.ready when state.hasInstances =>
                            Row(
                              children: [
                                ResizablePane(
                                  controller: sidebarWidth,
                                  edge: ResizablePaneEdge.trailing,
                                  resizeKey: 'sidebar',
                                  semanticsLabel: 'Resize sidebar',
                                  maximumWidth: windowMaximum,
                                  dividerWidth: 1,
                                  child: const InstanceSidebar(),
                                ),
                                Expanded(child: MainContent(layout: layout)),
                              ],
                            ),
                          InstanceLoadStatus.ready => const EmptyState(),
                        },
                      ),
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
                  DButton(
                    key: const ValueKey('instance-load-retry-panel'),
                    label: const Text('Retry'),
                    onPressed: ShellScope.read(context).load,
                    icon: const DIcon(DIcons.arrowsRotate, size: 18),
                    variant: DButtonVariant.primary,
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
