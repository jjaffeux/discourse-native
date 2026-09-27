import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show AppExitType;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_shortcuts.dart';
import '../data/diagnostics_panel_width_store.dart';
import '../data/sidebar_width_store.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../diagnostics/diagnostics_scope.dart';
import '../models/bookmark.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'aggregate_view.dart';
import 'bookmark_ui.dart';
import 'composer_panel.dart';
import 'composer_presentation.dart';
import 'desktop_navigation.dart';
import 'desktop_panels.dart';
import 'diagnostics_panel.dart';
import 'empty_state.dart';
import 'forum_theme_surfaces.dart';
import 'instance_actions.dart';
import 'instance_rail.dart';
import 'instance_sidebar.dart';
import 'keyboard_navigation.dart';
import 'keyboard_shortcuts_help.dart';
import 'main_content.dart';
import 'mobile_shell.dart';
import 'platform.dart';
import 'resizable_pane.dart';
import 'shell_controller.dart';
import 'shell_metrics.dart';
import 'shell_panel.dart';
import 'shell_scope.dart';
import 'shell_search_controller.dart';
import 'title_bar.dart';
import 'topic_presentation.dart';

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
});

class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({super.key});

  static const double railWidth = 48;
  static const double compactRailWidth = 48;
  static const double sidebarWidth = 208 + workspacePanelGap;
  // ResizablePane includes the gutter in its width.
  static const double sidebarMinWidth = 200 + workspacePanelGap;
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
  // Aggregate and a forum's gate replace the forum shell while they are
  // shown. The sidebar and panel layouts belong to the window, so they are
  // held here to be found as they were when a forum comes back. Unlike the
  // widths above, they are not persisted.
  final _sidebarExpanded = ValueNotifier<bool?>(null);
  final _panelsLayout = DesktopPanelsLayout();
  VoidCallback? _cancelPendingReply;

  @override
  void initState() {
    super.initState();
    _diagnosticsWidth = PanelWidthController(
      initialWidth: diagnosticsPanelWidth,
      minimumWidth: diagnosticsPanelMinWidth,
      readWidth: _diagnosticsWidthStore.read,
      writeWidth: _diagnosticsWidthStore.write,
    );
    _sidebarWidth = PanelWidthController(
      initialWidth: AdaptiveShell.sidebarWidth,
      minimumWidth: AdaptiveShell.sidebarMinWidth,
      readWidth: _sidebarWidthStore.read,
      writeWidth: _sidebarWidthStore.write,
    );
    HardwareKeyboard.instance.addHandler(_handleShortcut);
  }

  @override
  void dispose() {
    _cancelPendingReply?.call();
    HardwareKeyboard.instance.removeHandler(_handleShortcut);
    _diagnosticsWidth.dispose();
    _sidebarWidth.dispose();
    _sidebarExpanded.dispose();
    _panelsLayout.dispose();
    super.dispose();
  }

  bool _handleShortcut(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    // A dialog, sheet or picker above the shell owns the keyboard: a shortcut
    // must neither act on the shell underneath it nor be swallowed on its way
    // to the modal. Focus alone cannot tell, because a modal whose content
    // takes no focus leaves primary focus on a scope node.
    if (Navigator.of(context).canPop()) return false;
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    final focusedRoute = focusedContext == null
        ? null
        : ModalRoute.of(focusedContext);
    if (focusedRoute is PopupRoute &&
        focusedRoute.settings is! ReadingRouteSettings) {
      return false;
    }

    final keyboard = HardwareKeyboard.instance;
    final controller = ShellScope.read(context);
    if (refreshTabShortcutForPlatform(
      defaultTargetPlatform,
    ).accepts(event, keyboard)) {
      if (!controller.canRefreshCurrentTab) return false;
      unawaited(controller.refreshCurrentTab());
      return true;
    }
    final backShortcut = contentBackShortcutForPlatform(defaultTargetPlatform);
    if (backShortcut.accepts(event, keyboard)) {
      if (_focusOwnsHistoryShortcut(backShortcut)) return false;
      return controller.rootMode == ShellRootMode.forum &&
          controller.canPopContent &&
          controller.handleBack(canReturnToSidebar: false);
    }
    final forwardShortcut = contentForwardShortcutForPlatform(
      defaultTargetPlatform,
    );
    if (forwardShortcut.accepts(event, keyboard)) {
      if (_focusOwnsHistoryShortcut(forwardShortcut)) return false;
      return controller.handleForward();
    }
    if (newTopicShortcut.accepts(event, keyboard)) {
      if (controller.rootMode != ShellRootMode.forum ||
          !controller.canCreateTopicFromSidebar ||
          _formControlHasFocus) {
        return false;
      }
      unawaited(controller.openNewTopicFromSidebar());
      return true;
    }

    if (topicReplyShortcut.accepts(event, keyboard)) {
      if (controller.rootMode != ShellRootMode.forum ||
          controller.currentContent?.isTopic != true ||
          _formControlHasFocus) {
        return false;
      }
      if (controller.canReplyHere) {
        controller.openReply();
        return true;
      }
      if (controller.currentTopic == null && controller.currentTopicLoading) {
        _replyWhenLoaded(controller);
        return true;
      }
      return false;
    }

    if (topicBookmarkShortcut.accepts(event, keyboard)) {
      final instance = controller.currentInstance;
      final topic = controller.currentTopic;
      if (controller.rootMode != ShellRootMode.forum ||
          controller.currentContent?.isTopic != true ||
          instance == null ||
          instance.user == null ||
          topic == null ||
          _formControlHasFocus ||
          controller.bookmarkWriteInFlight(
            siteUrl: instance.url,
            topicId: topic.id,
            targetType: BookmarkTargetType.topic,
            targetId: topic.id,
          )) {
        return false;
      }
      unawaited(
        showTopicBookmarkMenu(
          context: context,
          controller: controller,
          siteUrl: instance.url,
          topic: topic,
        ),
      );
      return true;
    }

    if (const CharacterActivator('/').accepts(event, keyboard) &&
        controller.rootMode == ShellRootMode.forum &&
        (controller.currentContent?.isTopic == true ||
            controller.currentContent?.isTopicList == true) &&
        !_formControlHasFocus) {
      controller.search.requestFocus(mode: SearchFocusMode.contextual);
      return true;
    }

    for (final mode in SearchFocusMode.values) {
      if (searchShortcutForPlatform(
        defaultTargetPlatform,
        contextual: mode == SearchFocusMode.contextual,
      ).accepts(event, keyboard)) {
        if (controller.rootMode != ShellRootMode.forum) return false;
        controller.search.requestFocus(mode: mode);
        return true;
      }
    }

    final usesMetaModifier = defaultTargetPlatform == TargetPlatform.macOS;
    final modifierPressed = usesMetaModifier
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    if (!modifierPressed) return false;

    final secondaryModifierPressed = usesMetaModifier
        ? keyboard.isControlPressed
        : keyboard.isMetaPressed;
    if (keyboard.isAltPressed || secondaryModifierPressed) return false;

    if (keyboard.isShiftPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyT) {
        return _reopenClosedTab(controller);
      }
      return false;
    }

    if (_handleSidebarActionShortcut(event, keyboard, controller)) return true;

    if (event.logicalKey == LogicalKeyboardKey.keyT) {
      return _openTab(controller);
    }
    if (event.logicalKey == LogicalKeyboardKey.keyW) {
      if (_focusOwnsCloseShortcut) return false;
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

  void _replyWhenLoaded(ShellController controller) {
    _cancelPendingReply?.call();
    final route = controller.currentContent;
    final site = controller.currentInstance?.url;
    final tab = controller.activeTabId;
    final composer = controller.visibleComposer;
    late final VoidCallback listener;
    void cancel() {
      controller.removeListener(listener);
      _cancelPendingReply = null;
    }

    bool stillCurrent() =>
        mounted &&
        controller.rootMode == ShellRootMode.forum &&
        controller.currentContent?.id == route?.id &&
        controller.currentInstance?.url == site &&
        controller.activeTabId == tab &&
        identical(controller.visibleComposer, composer);

    listener = () {
      if (!stillCurrent()) {
        cancel();
        return;
      }
      if (controller.currentTopicLoading) return;
      cancel();
      // Loading notifies listeners while the reader is rebuilding. Open the
      // editor after that frame, only if the original topic still owns input.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!stillCurrent() ||
            !controller.canReplyHere ||
            Navigator.of(context).canPop() ||
            _formControlHasFocus) {
          return;
        }
        final focusedContext = FocusManager.instance.primaryFocus?.context;
        final focusedRoute = focusedContext == null
            ? null
            : ModalRoute.of(focusedContext);
        if (focusedRoute is PopupRoute &&
            focusedRoute.settings is! ReadingRouteSettings) {
          return;
        }
        controller.openReply();
      });
    };
    _cancelPendingReply = cancel;
    controller.addListener(listener);
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
    }
    return true;
  }

  bool _closeCurrentTab(ShellController controller) {
    if (controller.rootMode == ShellRootMode.aggregate &&
        controller.aggregateSettingsOpen) {
      controller.closeAggregateSettings();
      return true;
    }
    if (!controller.forumTabsEnabled) return false;
    final tabCount = switch (controller.rootMode) {
      ShellRootMode.aggregate => controller.aggregateTabs.length,
      ShellRootMode.forum => controller.tabsForCurrentForum.length,
    };
    if (tabCount == 1) {
      unawaited(
        ServicesBinding.instance.exitApplication(AppExitType.cancelable),
      );
      return true;
    }

    switch (controller.rootMode) {
      case ShellRootMode.aggregate:
        controller.closeAggregateTab(controller.activeAggregateTabId);
      case ShellRootMode.forum:
        final activeTabId = controller.activeTabId;
        if (activeTabId == null) return false;
        controller.closeTab(activeTabId);
    }
    return true;
  }

  bool _handleSidebarActionShortcut(
    KeyEvent event,
    HardwareKeyboard keyboard,
    ShellController controller,
  ) {
    if (controller.rootMode != ShellRootMode.forum) return false;

    for (final section in PluginScope.of(
      context,
    ).registry.sidebarSections(context)) {
      final shortcut = section.actionShortcut;
      final action = section.onAction;
      if (shortcut?.accepts(event, keyboard) == true && action != null) {
        action();
        return true;
      }
    }
    return false;
  }

  bool _reopenClosedTab(ShellController controller) {
    if (!controller.forumTabsEnabled) return false;
    return switch (controller.rootMode) {
      ShellRootMode.aggregate => controller.reopenClosedAggregateTab(),
      ShellRootMode.forum => controller.reopenClosedTab(),
    };
  }

  bool _selectAdjacentTab(ShellController controller, int offset) {
    if (!controller.forumTabsEnabled || _formControlHasFocus) return false;

    final (tabs, activeTabId) = switch (controller.rootMode) {
      ShellRootMode.aggregate => (
        controller.aggregateTabs.map((tab) => tab.id).toList(),
        controller.activeAggregateTabId,
      ),
      ShellRootMode.forum => (
        controller.tabsForCurrentForum
            .where((tab) => tab.panel == controller.activeTab?.panel)
            .map((tab) => tab.id)
            .toList(),
        controller.activeTabId,
      ),
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
    }
    return true;
  }

  // App commands follow the active topic, including when focus is on a nested
  // Navigator's scope. Editable controls still own their keyboard input.
  bool get _formControlHasFocus =>
      !navigationShortcutsAllowed(context, matchFocusRoute: false);

  // Off macOS the history chords are Alt+Arrow, which text fields also bind
  // to caret movement. Handlers here run before the focus tree, not instead
  // of it, so claiming the chord would move the caret and leave the page in
  // one keystroke.
  bool _focusOwnsHistoryShortcut(SingleActivator shortcut) =>
      shortcut.alt && _formControlHasFocus;

  // The composer binds the close chord to closing itself. Handlers here run
  // before the focus tree, not instead of it, so claiming the chord as well
  // would also close the tab under the composer, or quit the app when that
  // tab is the last one.
  bool get _focusOwnsCloseShortcut {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    // A detached focus cannot be searched (see navigationShortcutsAllowed),
    // and closing the tab, or the app, on a guess is the worse failure.
    if (!focusContext.mounted ||
        (focusContext is Element &&
            focusContext.renderObject?.attached != true)) {
      return true;
    }
    return focusContext.findAncestorWidgetOfExactType<ComposerPanel>() != null;
  }

  @override
  Widget build(BuildContext context) {
    return ReadingShortcuts(
      commands: {
        ReadingCommand.back: () {
          final controller = ShellScope.read(context);
          if (controller.rootMode != ShellRootMode.forum) return false;
          final handled = controller.handleBack(
            canReturnToSidebar: ShellLayout.forWidth(
              MediaQuery.sizeOf(context).width,
            ).isCompact,
          );
          if (handled) FocusManager.instance.primaryFocus?.unfocus();
          return handled;
        },
        ReadingCommand.help: () {
          unawaited(showKeyboardShortcuts(context));
          return true;
        },
      },
      child: TopicPresentationPreferences(
        child: ComposerPresentationHost(child: _buildShell(context)),
      ),
    );
  }

  Widget _buildShell(BuildContext context) {
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
        if (diagnostics == null) {
          return _buildScaffold(null, false);
        }

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
    final mobile = ShellScope.read(context).mobileNavigationEnabled;
    return Scaffold(
      // iOS exposes this surface around the keyboard's rounded upper corners.
      backgroundColor: mobile
          ? Theme.of(context).shell.content
          : Colors.transparent,
      body: ForumWindowBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final layout = ShellLayout.forWidth(constraints.maxWidth);
            final shell = mobile
                ? const _MobileShell()
                : _WideShell(
                    layout: layout,
                    sidebarWidth: _sidebarWidth,
                    sidebarExpanded: _sidebarExpanded,
                    panelsLayout: _panelsLayout,
                    atWindowEdge:
                        !diagnosticsOpen || layout != ShellLayout.expanded,
                  );

            Widget framedShell(Widget body) => Stack(
              children: [
                Positioned.fill(
                  child: Column(
                    children: [
                      if (!mobile) const ShellTitleBar(),
                      Expanded(child: body),
                    ],
                  ),
                ),
                ...PluginScope.of(context).registry.shellOverlays(context),
              ],
            );

            if (diagnostics == null) return framedShell(shell);
            final showDiagnostics = diagnosticsOpen;
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

            final dockDiagnostics = layout == ShellLayout.expanded;
            final reader = framedShell(
              Row(
                children: [
                  Expanded(child: shell),
                  if (showDiagnostics && dockDiagnostics)
                    resizablePanel(const ValueKey('diagnostics-docked-slot')),
                ],
              ),
            );
            final phoneWidth = constraints.maxWidth < 600;
            final overlay = Stack(
              children: [
                Positioned.fill(child: reader),
                if (showDiagnostics && !dockDiagnostics)
                  Positioned.fill(
                    child: ModalBarrier(
                      key: const ValueKey('diagnostics-modal-barrier'),
                      dismissible: true,
                      onDismiss: diagnostics.closePanel,
                      color: Colors.black.withValues(alpha: 0.32),
                    ),
                  ),
                if (showDiagnostics && !dockDiagnostics)
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
              open: showDiagnostics,
              diagnostics: diagnostics,
              child: overlay,
            );
          },
        ),
      ),
    );
  }

  Widget _withDiagnosticsBackHandling({
    required bool open,
    required DiagnosticsController diagnostics,
    required Widget child,
  }) {
    // Keep this wrapper stable when docking a composer changes the layout.
    // Recreating the reader also reopens its sheet and takes focus from the
    // composer. The mobile shell owns back handling at every viewport width.
    return PopScope(
      canPop: ShellScope.read(context).mobileNavigationEnabled || !open,
      onPopInvokedWithResult: (didPop, result) {
        if (!ShellScope.read(context).mobileNavigationEnabled &&
            !didPop &&
            diagnostics.isPanelOpen) {
          diagnostics.closePanel();
        }
      },
      child: child,
    );
  }
}

class _ForumBoundaryShell extends StatelessWidget {
  const _ForumBoundaryShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (ShellScope.read(context).mobileNavigationEnabled) {
      return ForumWindowBackground(
        child: SafeArea(child: MobileForumRoot(content: child, boundary: true)),
      );
    }
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
      color: ForumWindowBackground.surfaceColor(context, theme.shell.content),
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
                    icon: const DIcon(DIcons.upRightFromSquare),
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
      color: ForumWindowBackground.surfaceColor(context, theme.shell.content),
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
                      spacing: DSpacing.controlGap,
                      runSpacing: 12,
                      children: [
                        DButton(
                          key: const ValueKey('unavailable-forum-retry'),
                          label: const Text('Try again'),
                          onPressed: () =>
                              unawaited(controller.retryCurrentForum()),
                          icon: const DIcon(DIcons.arrowsRotate),
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
                          icon: const DIcon(DIcons.trashCan),
                          variant: DButtonVariant.destructive,
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

class _MobileShell extends StatelessWidget {
  const _MobileShell();

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) return;
      final diagnostics = DiagnosticsScope.maybeRead(context);
      if (diagnostics?.isPanelOpen ?? false) {
        diagnostics!.closePanel();
      } else if (!ShellScope.read(context).handleBack()) {
        unawaited(SystemNavigator.pop());
      }
    },
    child: ForumWindowBackground(
      child: SafeArea(
        child:
            ShellSelector<
              ({
                InstanceLoadStatus loadStatus,
                bool hasInstances,
                bool aggregateSettingsOpen,
                ShellRootMode rootMode,
              })
            >(
              select: (shell) => (
                loadStatus: shell.loadStatus,
                hasInstances: shell.hasInstances,
                aggregateSettingsOpen: shell.aggregateSettingsOpen,
                rootMode: shell.rootMode,
              ),
              builder: (context, state, _) {
                Widget homeStatus(Widget child) => Row(
                  children: [
                    const SizedBox(width: 48, child: InstanceRail()),
                    Expanded(child: child),
                  ],
                );
                if (state.loadStatus == InstanceLoadStatus.loading) {
                  return homeStatus(const _ShellLoadProgress());
                }
                if (state.loadStatus == InstanceLoadStatus.failed) {
                  return homeStatus(const _ShellLoadFailure());
                }
                if (!state.hasInstances && !state.aggregateSettingsOpen) {
                  return homeStatus(const EmptyState());
                }
                return _PageComposerDock(
                  child: MobileForumRoot(
                    content: state.rootMode == ShellRootMode.aggregate
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: DButton.iconOnly(
                                  icon: const DIcon(DIcons.arrowLeft),
                                  tooltip: 'Back',
                                  variant: DButtonVariant.ghost,
                                  onPressed: () =>
                                      ShellScope.read(context).handleBack(),
                                ),
                              ),
                              const Expanded(child: AggregateView()),
                            ],
                          )
                        : MainContent(
                            key: ComposerPresentationHost.contentKeyOf(context),
                            layout: ShellLayout.compact,
                          ),
                  ),
                );
              },
            ),
      ),
    ),
  );
}

class _WideShell extends StatefulWidget {
  const _WideShell({
    required this.layout,
    required this.sidebarWidth,
    required this.sidebarExpanded,
    required this.panelsLayout,
    required this.atWindowEdge,
  });

  final ShellLayout layout;
  final PanelWidthController sidebarWidth;

  /// What the rail's toggle last chose for the sidebar, or null while the
  /// sidebar follows the window's width.
  final ValueNotifier<bool?> sidebarExpanded;
  final DesktopPanelsLayout panelsLayout;
  final bool atWindowEdge;

  @override
  State<_WideShell> createState() => _WideShellState();
}

class _WideShellState extends State<_WideShell> {
  // Window constraints change on every resize tick, but the fixed-width rail
  // only needs new configuration when the sidebar opens or closes. Its own
  // selectors and inherited dependencies still update it normally.
  late final _expandedRail = _buildRail(true);
  late final _collapsedRail = _buildRail(false);
  // The panels take no configuration from this shell either, so its rebuilds
  // leave them to their own dependencies and constraints.
  late final _desktopPanels = DesktopPanels(layout: widget.panelsLayout);

  @override
  void initState() {
    super.initState();
    widget.sidebarExpanded.addListener(_sidebarChoiceChanged);
  }

  @override
  void didUpdateWidget(_WideShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sidebarExpanded == widget.sidebarExpanded) return;
    oldWidget.sidebarExpanded.removeListener(_sidebarChoiceChanged);
    widget.sidebarExpanded.addListener(_sidebarChoiceChanged);
  }

  @override
  void dispose() {
    widget.sidebarExpanded.removeListener(_sidebarChoiceChanged);
    super.dispose();
  }

  void _sidebarChoiceChanged() => setState(() {});

  Widget _buildRail(bool sidebarExpanded) => ShellSelector<bool>(
    select: (controller) =>
        controller.hasInstances && controller.rootMode == ShellRootMode.forum,
    builder: (context, available, _) => InstanceRail(
      showSidebarToggle: true,
      sidebarExpanded: available && sidebarExpanded,
      onToggleSidebar: available
          ? () => widget.sidebarExpanded.value = !sidebarExpanded
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final sidebarChoice = widget.sidebarExpanded.value;
    return LayoutBuilder(
      builder: (context, constraints) {
        final windowMaximum = math.max(
          AdaptiveShell.sidebarMinWidth,
          constraints.maxWidth -
              AdaptiveShell.railWidth -
              AdaptiveShell.mainContentMinWidth,
        );
        final sidebarExpanded =
            sidebarChoice ?? (context.isTouch || constraints.maxWidth >= 1100);
        return Row(
          children: [
            SizedBox(
              width: AdaptiveShell.railWidth,
              child: sidebarExpanded ? _expandedRail : _collapsedRail,
            ),
            Expanded(
              child: ShellWorkspace(
                atWindowEdge: widget.atWindowEdge,
                child:
                    ShellSelector<
                      ({
                        InstanceLoadStatus loadStatus,
                        bool hasInstances,
                        bool aggregateSettingsOpen,
                        ShellRootMode rootMode,
                      })
                    >(
                      select: (controller) => (
                        loadStatus: controller.loadStatus,
                        hasInstances: controller.hasInstances,
                        aggregateSettingsOpen: controller.aggregateSettingsOpen,
                        rootMode: controller.rootMode,
                      ),
                      builder: (context, state, _) => switch (state
                          .loadStatus) {
                        InstanceLoadStatus.loading =>
                          const _ShellLoadProgress(),
                        InstanceLoadStatus.failed => const _ShellLoadFailure(),
                        InstanceLoadStatus.ready
                            when (state.hasInstances ||
                                    state.aggregateSettingsOpen) &&
                                state.rootMode == ShellRootMode.aggregate =>
                          const AggregateView(),
                        InstanceLoadStatus.ready when state.hasInstances =>
                          DesktopNavigation(
                            compact: !sidebarExpanded,
                            showTrigger: sidebarChoice == null,
                            sidebar: ResizablePane(
                              controller: widget.sidebarWidth,
                              edge: ResizablePaneEdge.trailing,
                              resizeKey: 'sidebar',
                              semanticsLabel: 'Resize sidebar',
                              maximumWidth: windowMaximum,
                              dividerWidth: 1,
                              gap: context.isTouch ? 0 : workspacePanelGap,
                              handleWidth: context.isTouch
                                  ? 2
                                  : workspacePanelGap,
                              child: const WorkspacePanel(
                                atRightEdge: false,
                                child: InstanceSidebar(),
                              ),
                            ),
                            child: _PageComposerDock(
                              child:
                                  !context.isTouch &&
                                      ShellScope.read(context).forumTabsEnabled
                                  ? _desktopPanels
                                  : MainContent(
                                      key:
                                          ComposerPresentationHost.contentKeyOf(
                                            context,
                                          ),
                                      layout: context.isTouch
                                          ? widget.layout
                                          : ShellLayout.expanded,
                                    ),
                            ),
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

/// Dock inside the content workspace so community navigation keeps its space.
class _PageComposerDock extends StatelessWidget {
  const _PageComposerDock({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => context.isTouch
      ? ComposerDock(
          key: ComposerPresentationHost.dockKeyOf(context),
          child: child,
        )
      : TopicWorkspace(child: child);
}

class _ShellLoadProgress extends StatelessWidget {
  const _ShellLoadProgress();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: ForumWindowBackground.surfaceColor(
      context,
      Theme.of(context).shell.content,
    ),
    child: const Center(child: DSpinner(size: DSpacing.xl)),
  );
}

class _ShellLoadFailure extends StatelessWidget {
  const _ShellLoadFailure();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredBox(
      color: ForumWindowBackground.surfaceColor(context, theme.shell.content),
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
                    icon: const DIcon(DIcons.arrowsRotate),
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
