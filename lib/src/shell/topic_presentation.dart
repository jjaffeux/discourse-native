import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../app_shortcuts.dart';
import '../models/topic_presentation.dart';
import 'composer_presentation.dart';
import 'forum_tabs_bar.dart';
import 'keyboard_navigation.dart';
import 'platform.dart';
import 'reader_content_bounds.dart';
import 'shell_scope.dart';
import 'topic_list_bottom_bar.dart';
import 'topic_presentation_controller.dart';

/// Owns the desktop preference across forums, tabs and workspace changes.
class TopicPresentationPreferences extends StatefulWidget {
  const TopicPresentationPreferences({super.key, required this.child});
  final Widget child;

  @override
  State<TopicPresentationPreferences> createState() =>
      _TopicPresentationPreferencesState();
}

class _TopicPresentationPreferencesState
    extends State<TopicPresentationPreferences> {
  final _controller = TopicPresentationController();

  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  Widget build(BuildContext context) =>
      _PreferenceScope(notifier: _controller, child: widget.child);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _PreferenceScope extends InheritedNotifier<TopicPresentationController> {
  const _PreferenceScope({required super.notifier, required super.child});

  static TopicPresentationController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PreferenceScope>()!.notifier!;
}

/// Bounds topic sheets to the workspace, leaving community navigation available.
class TopicWorkspace extends StatelessWidget {
  const TopicWorkspace({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = _PreferenceScope.of(context);
    final shell = ShellScope.of(context);
    return ListenableBuilder(
      listenable: ComposerPresentationHost.layoutChangesOf(context),
      builder: (context, _) => LayoutBuilder(
        builder: (context, bounds) {
          final sheet =
              shell.currentContent?.isTopic == true &&
              controller.preference == TopicPresentation.sheet;
          return _TopicWorkspaceScope(
            sheet: sheet,
            width: bounds.maxWidth,
            content: child,
            child: Column(
              children: [
                if (shell.forumTabsEnabled) const CurrentForumTabsBar(),
                Expanded(
                  child: Navigator(
                    onGenerateRoute: (_) => PageRouteBuilder<void>(
                      settings: const ReadingRouteSettings(
                        name: 'topic-workspace',
                      ),
                      pageBuilder: (context, _, _) =>
                          const _TopicWorkspacePage(),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TopicWorkspacePage extends StatelessWidget {
  const _TopicWorkspacePage();

  @override
  Widget build(BuildContext context) {
    final sheet = TopicReaderPresentation.isSheetOf(context);
    return ComposerDock(
      key: ComposerPresentationHost.dockKeyOf(context),
      appWorkspace: true,
      enabled: !sheet,
      child: ReaderContentBounds(
        enabled: !sheet,
        child: _TopicWorkspaceScope.of(context)!.content,
      ),
    );
  }
}

class _TopicWorkspaceScope extends InheritedWidget {
  const _TopicWorkspaceScope({
    required this.sheet,
    required this.width,
    required this.content,
    required super.child,
  });

  final bool sheet;
  final double width;
  final Widget content;

  static _TopicWorkspaceScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TopicWorkspaceScope>();

  @override
  bool updateShouldNotify(_TopicWorkspaceScope oldWidget) =>
      sheet != oldWidget.sheet ||
      width != oldWidget.width ||
      content != oldWidget.content;
}

/// Keeps one reader mounted while its sheet route is created or dismissed.
class TopicReaderPresentation extends StatefulWidget {
  const TopicReaderPresentation({super.key, required this.child});
  final Widget child;

  static bool isSheetOf(BuildContext context) =>
      _TopicWorkspaceScope.of(context)?.sheet ?? false;

  static bool hasWorkspaceOf(BuildContext context) =>
      _TopicWorkspaceScope.of(context) != null;

  @override
  State<TopicReaderPresentation> createState() =>
      _TopicReaderPresentationState();
}

class _TopicReaderPresentationState extends State<TopicReaderPresentation> {
  final _readerKey = GlobalKey();
  final _changes = ValueNotifier(0);
  bool _outletReady = false;
  bool _closing = false;
  VoidCallback? _afterDismiss;

  Widget get _reader => KeyedSubtree(key: _readerKey, child: widget.child);

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    _changes.value++;
  }

  @override
  void didUpdateWidget(TopicReaderPresentation oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _changes.value++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final workspace = _TopicWorkspaceScope.of(context);
    if (workspace == null) return widget.child;
    if (!workspace.sheet && _outletReady) _closing = true;
    final inSheet =
        workspace.sheet && _outletReady && (!_closing || _afterDismiss != null);
    final shell = ShellScope.read(context);
    return DSheet<void>(
      routeSettings: const ReadingRouteSettings(name: 'topic-sheet'),
      // A reversing route still owns its outlet. Wait for its disposal before
      // reopening if the presentation changes again during dismissal.
      open: workspace.sheet && !_closing,
      onOpenChanged: (details) {
        if (details.open || !mounted || _closing || !workspace.sheet) return;
        final route = shell.currentContent;
        final siteUrl = shell.currentInstance?.url;
        final tabId = shell.activeTabId;
        // Navigation removes this presentation owner. Keep the live reader in
        // its route until Sheet has painted the complete exit transition.
        _afterDismiss = () {
          if (TopicReaderPresentation.isSheetOf(context) &&
              shell.currentInstance?.url == siteUrl &&
              shell.activeTabId == tabId &&
              identical(shell.currentContent, route)) {
            shell.closeTopic();
          }
        };
        _closing = true;
        _refresh();
      },
      barrierLabel: 'Close topic',
      content: DSheetContent(
        key: const ValueKey('topic-sheet'),
        side: DSheetSide.center,
        inset: true,
        animateSize: true,
        sidePanelMaxWidth: workspace.width,
        sidePanelWidth:
            TopicPresentationController.minimumReaderWidth +
            DSpacing.lg * 2 +
            workspace.width -
            ComposerPresentationHost.readerWidthOf(context, workspace.width),
        showCloseButton: false,
        scrollWholeSheet: false,
        semanticLabel: 'Topic',
        children: [Expanded(child: _SheetReaderOutlet(owner: this))],
      ),
      trigger: DSheetTrigger(
        builder: (context, _) => inSheet ? const SizedBox.expand() : _reader,
      ),
    );
  }

  @override
  void dispose() {
    _changes.dispose();
    super.dispose();
  }
}

class _SheetReaderOutlet extends StatefulWidget {
  const _SheetReaderOutlet({required this.owner});
  final _TopicReaderPresentationState owner;

  @override
  State<_SheetReaderOutlet> createState() => _SheetReaderOutletState();
}

class _SheetReaderOutletState extends State<_SheetReaderOutlet> {
  Animation<double>? _animation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (identical(animation, _animation)) return;
    _animation?.removeStatusListener(_animationChanged);
    _animation = animation?..addStatusListener(_animationChanged);
  }

  void _animationChanged(AnimationStatus status) {
    if (status != AnimationStatus.dismissed) return;
    final owner = widget.owner;
    final afterDismiss = owner._afterDismiss;
    owner._afterDismiss = null;
    afterDismiss?.call();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.owner.mounted) return;
      widget.owner._outletReady = true;
      widget.owner._refresh();
    });
  }

  @override
  void dispose() {
    _animation?.removeStatusListener(_animationChanged);
    widget.owner._outletReady = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final owner = widget.owner;
      if (!owner.mounted) return;
      final afterDismiss = owner._afterDismiss;
      owner._afterDismiss = null;
      afterDismiss?.call();
      owner._closing = false;
      owner._refresh();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.owner._changes,
    builder: (context, _) {
      final active =
          TopicReaderPresentation.isSheetOf(context) &&
          (!widget.owner._closing || widget.owner._afterDismiss != null);
      return ComposerDock(
        appWorkspace: true,
        enabled: active,
        child: ReaderContentBounds(
          enabled: active,
          child: ReadingShortcuts(
            commands: {
              ReadingCommand.back: () {
                unawaited(Navigator.of(context).maybePop());
                return true;
              },
              ReadingCommand.openNextTopic: () =>
                  openAdjacentTopic(context, next: true, fromKeyboard: true),
              ReadingCommand.openPreviousTopic: () =>
                  openAdjacentTopic(context, next: false, fromKeyboard: true),
            },
            child: IgnorePointer(
              ignoring: widget.owner._closing,
              child: ExcludeFocus(
                excluding: widget.owner._closing,
                child: active && widget.owner._outletReady
                    ? widget.owner._reader
                    : const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class TopicPresentationButton extends StatelessWidget {
  const TopicPresentationButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (context.isTouch || _TopicWorkspaceScope.of(context) == null) {
      return const SizedBox.shrink();
    }
    final controller = _PreferenceScope.of(context);
    final sheet = TopicReaderPresentation.isSheetOf(context);
    return DPopover(
      reverseTransitionDuration: Duration.zero,
      content: DPopoverContent(
        semanticLabel: 'Topic view',
        align: DPopoverAlign.end,
        width: 240,
        child: DPopoverClose(
          builder: (context, close) => Row(
            children: [
              const Expanded(child: Text('Topic view')),
              DToggleGroup<TopicPresentation>(
                semanticLabel: 'Topic view',
                values: [controller.preference],
                allowEmptySelection: false,
                size: DToggleSize.small,
                spacing: 1,
                onChanged: (values) {
                  close();
                  controller.select(values.single);
                },
                items: [
                  for (final mode in TopicPresentation.values)
                    DToggleGroupItem.iconOnly(
                      value: mode,
                      semanticLabel: mode.label,
                      tooltip: mode.label,
                      icon: _viewIcon(mode == TopicPresentation.sheet),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      child: DPopoverTrigger(
        builder: (context, trigger) => DButton.iconOnly(
          key: const ValueKey('topic-view-options'),
          icon: _viewIcon(sheet),
          tooltip: 'Topic view',
          semanticLabel: 'Topic view',
          variant: DButtonVariant.transparentBackground,
          size: DButtonSize.regular,
          focusNode: trigger.focusNode,
          expanded: trigger.open,
          hasPopup: true,
          onPressed: trigger.toggle,
        ),
      ),
    );
  }

  static Widget _viewIcon(bool sheet) =>
      Icon(sheet ? Icons.web_asset_outlined : Icons.view_sidebar_outlined);
}
