import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/content_route.dart';
import '../../models/sidebar.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../shell/adaptive_shell.dart';
import '../../shell/emoji.dart';
import '../../shell/platform.dart';
import '../../shell/relative_time.dart';
import '../../shell/shell_scope.dart';
import '../../shell/title_bar.dart';
import '../../shell/user_status.dart';
import '../../theme/d_button.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'chat_channel.dart';
import 'chat_channel_actions.dart';
import 'chat_controller.dart';
import 'chat_drawer_preferences_store.dart';
import 'chat_new_direct_message.dart';
import 'chat_plugin_data.dart';
import 'chat_route.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';
import 'chat_thread.dart';
import 'chat_user_avatar.dart';

typedef ChatDrawerContentBuilder =
    Widget Function(BuildContext context, ContentRoute route);
typedef ChatDrawerHeaderActionsBuilder =
    List<Widget> Function(BuildContext context, ContentRoute route);
typedef ChatDrawerHeaderWidgetBuilder =
    Widget? Function(BuildContext context, ContentRoute route);
typedef ChatDrawerHeaderActionBuilder =
    VoidCallback? Function(BuildContext context, ContentRoute route);
typedef ChatDrawerFooterVisibility = bool Function(ContentRoute route);

enum ChatDrawerChannelListKind { channels, starred, directMessages }

/// Marks an action whose own popover must outlive the drawer overflow menu
/// button press. Closing the outer menu immediately would dispose that action
/// before its nested route can report the selected value.
abstract interface class ChatDrawerNestedMenuAction {}

class ChatDrawerOverflowActionScope extends InheritedWidget {
  const ChatDrawerOverflowActionScope({
    super.key,
    required this.closeOverflow,
    required super.child,
  });

  final VoidCallback closeOverflow;

  static VoidCallback? maybeCloseOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ChatDrawerOverflowActionScope>()
      ?.closeOverflow;

  @override
  bool updateShouldNotify(ChatDrawerOverflowActionScope oldWidget) => false;
}

class ChatDrawerScope extends InheritedWidget {
  const ChatDrawerScope({super.key, required super.child});

  static bool isDrawer(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatDrawerScope>() != null;

  @override
  bool updateShouldNotify(ChatDrawerScope oldWidget) => false;
}

/// A modeless, bottom-end Chat surface. Its route stack belongs to the Chat
/// session rather than the shell, so the forum beneath it remains mounted and
/// keeps its exact navigation state.
class ChatDrawerOverlay extends StatefulWidget {
  const ChatDrawerOverlay({
    super.key,
    required this.contentBuilder,
    required this.headerActionsBuilder,
    required this.headerLeadingBuilder,
    required this.headerTitleTrailingBuilder,
    required this.headerTitleActionBuilder,
    required this.showFooterForRoute,
    this.preferencesStore = const ChatDrawerPreferencesStore(),
  });

  final ChatDrawerContentBuilder contentBuilder;
  final ChatDrawerHeaderActionsBuilder headerActionsBuilder;
  final ChatDrawerHeaderWidgetBuilder headerLeadingBuilder;
  final ChatDrawerHeaderWidgetBuilder headerTitleTrailingBuilder;
  final ChatDrawerHeaderActionBuilder headerTitleActionBuilder;
  final ChatDrawerFooterVisibility showFooterForRoute;
  final ChatDrawerPreferencesStore preferencesStore;

  static const Key drawerKey = ValueKey('chat-drawer');
  static const Key expandedKey = ValueKey('chat-drawer-expanded');
  static const Key collapsedKey = ValueKey('chat-drawer-collapsed');
  static const Key headerKey = ValueKey('chat-drawer-header');
  static const Key resizeHandleKey = ValueKey('chat-drawer-resize-handle');
  static const Key collapseButtonKey = ValueKey('chat-drawer-collapse');
  static const Key fullPageButtonKey = ValueKey('chat-drawer-full-page');
  static const Key overflowButtonKey = ValueKey('chat-drawer-overflow');
  static const Key closeButtonKey = ValueKey('chat-drawer-close');
  static const double headerHeight = 45;
  static const double endMargin = 15;
  static const double topMargin = 15;

  @override
  State<ChatDrawerOverlay> createState() => _ChatDrawerOverlayState();
}

class _ChatDrawerOverlayState extends State<ChatDrawerOverlay> {
  final GlobalKey _overlayBoundsKey = GlobalKey();
  double _preferredWidth = ChatDrawerPreferencesStore.defaultWidth;
  double _preferredHeight = ChatDrawerPreferencesStore.defaultHeight;
  int _sizeGeneration = 0;
  bool _headerMenuOpen = false;
  bool _drawerWasVisible = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyboard);
    unawaited(_restoreSize());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyboard);
    super.dispose();
  }

  Future<void> _restoreSize() async {
    final generation = _sizeGeneration;
    final size = await widget.preferencesStore.readDrawerSize();
    if (!mounted || generation != _sizeGeneration) return;
    setState(() {
      _preferredWidth = size.width;
      _preferredHeight = size.height;
    });
  }

  bool _handleKeyboard(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final shell = PluginUiScope.maybe(context, chatShellService);
    if (shell == null) return false;
    final modalRoute = ModalRoute.of(context);
    if (modalRoute != null && !modalRoute.isCurrent) return false;
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    final editingText =
        focusedContext?.widget is EditableText ||
        focusedContext?.findAncestorWidgetOfExactType<EditableText>() != null;
    final interactiveFocus = _isInteractiveFocus(focusedContext);
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (!shell.drawerActive) return false;
      if (_headerMenuOpen) return false;
      if (editingText || _drawerContains(focusedContext)) return false;
      shell.closeDrawer();
      return true;
    }
    final isChannelCycleKey =
        event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown;
    if (shell.chatActive &&
        isChannelCycleKey &&
        HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed) {
      return shell.cycleDrawerChannel(
        forward: event.logicalKey == LogicalKeyboardKey.arrowDown,
        unreadOnly: HardwareKeyboard.instance.isShiftPressed,
      );
    }
    if (event.logicalKey != LogicalKeyboardKey.minus ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isShiftPressed ||
        editingText ||
        interactiveFocus) {
      return false;
    }
    if (shell.drawerActive) {
      shell.closeDrawer();
    } else if (shell.drawerAvailable &&
        (shell.showHeaderShortcut || shell.chatActive)) {
      unawaited(shell.openDrawerShortcut());
    } else {
      return false;
    }
    return true;
  }

  bool _drawerContains(BuildContext? child) {
    final drawer = _overlayBoundsKey.currentContext;
    if (child == null || drawer == null) return false;
    if (identical(child, drawer)) return true;
    var contains = false;
    child.visitAncestorElements((element) {
      contains = identical(element, drawer);
      return !contains;
    });
    return contains;
  }

  bool _isInteractiveFocus(BuildContext? focused) {
    if (focused == null) return false;
    bool capturesTyping(Widget widget) =>
        widget is EditableText ||
        widget is ButtonStyleButton ||
        widget is IconButton ||
        widget is Checkbox ||
        widget is Radio ||
        widget is Switch ||
        widget is Slider ||
        widget is DropdownButton ||
        widget is DropdownMenu ||
        widget is PopupMenuButton ||
        widget is MenuAnchor;
    if (capturesTyping(focused.widget)) return true;
    var interactive = false;
    focused.visitAncestorElements((element) {
      interactive = capturesTyping(element.widget);
      return !interactive;
    });
    return interactive;
  }

  void _handleDrawerEscape(ChatShellService shell) {
    if (!shell.drawerActive) return;
    final modalRoute = ModalRoute.of(context);
    if (modalRoute != null && !modalRoute.isCurrent) return;
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    final editingText =
        focusedContext?.widget is EditableText ||
        focusedContext?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (editingText) {
      FocusManager.instance.primaryFocus?.unfocus();
    } else {
      shell.closeDrawer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = PluginUiScope.require(context, chatShellService);
    return Positioned.fill(
      child: SizedBox.expand(
        key: _overlayBoundsKey,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                _handleDrawerEscape(shell),
          },
          child: ListenableBuilder(
            listenable: shell,
            builder: (context, _) => LayoutBuilder(
              builder: (context, constraints) {
                final available =
                    ShellLayout.forWidth(constraints.maxWidth) !=
                    ShellLayout.compact;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) shell.updateDrawerAvailability(available);
                });
                if (shell.drawerCurrentContent == null) {
                  return const SizedBox.shrink();
                }
                final visible = available && shell.drawerActive;
                if (_drawerWasVisible && !visible) {
                  final focused = FocusManager.instance.primaryFocus;
                  if (_drawerContains(focused?.context)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted &&
                          identical(
                            focused,
                            FocusManager.instance.primaryFocus,
                          )) {
                        focused?.unfocus();
                      }
                    });
                  }
                }
                _drawerWasVisible = visible;
                return TickerMode(
                  enabled: visible,
                  child: Offstage(
                    offstage: !visible,
                    child: _buildDrawer(context, shell, constraints),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer(
    BuildContext context,
    ChatShellService shell,
    BoxConstraints constraints,
  ) {
    final route = shell.drawerCurrentContent;
    if (route == null) return const SizedBox.shrink();

    final titleBarOffset = ShellTitleBar.isSupported
        ? ShellTitleBar.height
        : 0.0;
    final maximumWidth = math.max(
      ChatDrawerPreferencesStore.minimumWidth,
      constraints.maxWidth - ChatDrawerOverlay.endMargin * 2,
    );
    final unobstructedMaximumHeight = math.max(
      ChatDrawerPreferencesStore.minimumHeight,
      constraints.maxHeight - titleBarOffset - ChatDrawerOverlay.topMargin,
    );
    final expandedWidth = _preferredWidth
        .clamp(ChatDrawerPreferencesStore.minimumWidth, maximumWidth)
        .toDouble();
    final unobstructedExpandedHeight = _preferredHeight
        .clamp(
          ChatDrawerPreferencesStore.minimumHeight,
          unobstructedMaximumHeight,
        )
        .toDouble();
    final collapsedWidth = math.max(
      ChatDrawerPreferencesStore.minimumWidth,
      math.min(expandedWidth, constraints.maxWidth * 0.25),
    );
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    // Closing resets the retained drawer to expanded. Keeping its last content
    // mounted offstage lets active edits and uploads survive close/reopen just
    // as they do while the web drawer is hidden.
    final expanded = shell.drawerActive ? shell.drawerExpanded : true;
    final drawerWidth = expanded ? expandedWidth : collapsedWidth;
    final candidateHeight = expanded
        ? unobstructedExpandedHeight
        : ChatDrawerOverlay.headerHeight;
    final bottomOffset = _composerBottomOffset(
      shell: shell,
      constraints: constraints,
      drawerWidth: drawerWidth,
      drawerHeight: candidateHeight,
      titleBarOffset: titleBarOffset,
      minimumBottomOffset: safeBottom,
    );
    final maximumHeight = math.max(
      ChatDrawerPreferencesStore.minimumHeight,
      constraints.maxHeight -
          titleBarOffset -
          ChatDrawerOverlay.topMargin -
          bottomOffset,
    );
    final expandedHeight = _preferredHeight
        .clamp(ChatDrawerPreferencesStore.minimumHeight, maximumHeight)
        .toDouble();
    final frameHeight = expanded
        ? expandedHeight
        : ChatDrawerOverlay.headerHeight;

    return Stack(
      key: ChatDrawerOverlay.drawerKey,
      children: [
        PositionedDirectional(
          end: ChatDrawerOverlay.endMargin,
          bottom: bottomOffset,
          width: drawerWidth,
          height: frameHeight,
          child: IgnorePointer(
            child: SizedBox.expand(
              key: expanded
                  ? ChatDrawerOverlay.expandedKey
                  : ChatDrawerOverlay.collapsedKey,
            ),
          ),
        ),
        PositionedDirectional(
          end: ChatDrawerOverlay.endMargin,
          bottom: bottomOffset,
          width: drawerWidth,
          height: frameHeight,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: expandedHeight,
              maxHeight: expandedHeight,
              child: SizedBox(
                width: expanded ? expandedWidth : collapsedWidth,
                height: expandedHeight,
                child: _DrawerFrame(
                  expanded: expanded,
                  header: _DrawerHeader(
                    route: route,
                    expanded: expanded,
                    canGoBack: shell.drawerCanGoBack,
                    onBack: shell.drawerBack,
                    onToggle: shell.toggleDrawerExpanded,
                    onFullPage: () => unawaited(shell.openFullPageFromDrawer()),
                    onClose: shell.closeDrawer,
                    leading: widget.headerLeadingBuilder(context, route),
                    titleTrailing: widget.headerTitleTrailingBuilder(
                      context,
                      route,
                    ),
                    titleAction: widget.headerTitleActionBuilder(
                      context,
                      route,
                    ),
                    routeActions: widget.headerActionsBuilder(context, route),
                    onOverflowOpenChanged: (open) => _headerMenuOpen = open,
                  ),
                  content: ChatDrawerScope(
                    child: Builder(
                      builder: (drawerContext) =>
                          widget.contentBuilder(drawerContext, route),
                    ),
                  ),
                  footer: widget.showFooterForRoute(route)
                      ? const ChatDrawerFooter()
                      : null,
                ),
              ),
            ),
          ),
        ),
        if (expanded)
          PositionedDirectional(
            end:
                ChatDrawerOverlay.endMargin +
                expandedWidth -
                _DrawerResizeHandle.extent,
            bottom: bottomOffset + expandedHeight - _DrawerResizeHandle.extent,
            child: _DrawerResizeHandle(
              onUpdate: (details) => _resize(
                details.delta,
                constraints: constraints,
                titleBarOffset: titleBarOffset,
                bottomOffset: bottomOffset,
              ),
              onEnd: _persistSize,
            ),
          ),
      ],
    );
  }

  double _composerBottomOffset({
    required ChatShellService shell,
    required BoxConstraints constraints,
    required double drawerWidth,
    required double drawerHeight,
    required double titleBarOffset,
    required double minimumBottomOffset,
  }) {
    final composerBounds = shell.floatingComposerBounds;
    if (composerBounds == null) return minimumBottomOffset;

    final overlayBounds = _globalOverlayBounds(constraints);
    final left = Directionality.of(context) == TextDirection.ltr
        ? overlayBounds.right - ChatDrawerOverlay.endMargin - drawerWidth
        : overlayBounds.left + ChatDrawerOverlay.endMargin;
    final candidate = Rect.fromLTWH(
      left,
      overlayBounds.bottom - minimumBottomOffset - drawerHeight,
      drawerWidth,
      drawerHeight,
    );
    if (!candidate.overlaps(composerBounds)) return minimumBottomOffset;

    final availableOffset = math.max(
      minimumBottomOffset,
      constraints.maxHeight -
          titleBarOffset -
          ChatDrawerOverlay.topMargin -
          ChatDrawerPreferencesStore.minimumHeight,
    );
    return (overlayBounds.bottom - composerBounds.top)
        .clamp(minimumBottomOffset, availableOffset)
        .toDouble();
  }

  Rect _globalOverlayBounds(BoxConstraints constraints) {
    final renderObject = _overlayBoundsKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox &&
        renderObject.attached &&
        renderObject.hasSize) {
      return renderObject.localToGlobal(Offset.zero) & renderObject.size;
    }
    return Offset.zero & Size(constraints.maxWidth, constraints.maxHeight);
  }

  void _resize(
    Offset delta, {
    required BoxConstraints constraints,
    required double titleBarOffset,
    required double bottomOffset,
  }) {
    final direction = Directionality.of(context);
    final widthDelta = direction == TextDirection.ltr ? -delta.dx : delta.dx;
    final maximumWidth = math.max(
      ChatDrawerPreferencesStore.minimumWidth,
      constraints.maxWidth - ChatDrawerOverlay.endMargin * 2,
    );
    final maximumHeight = math.max(
      ChatDrawerPreferencesStore.minimumHeight,
      constraints.maxHeight -
          titleBarOffset -
          ChatDrawerOverlay.topMargin -
          bottomOffset,
    );
    _sizeGeneration++;
    setState(() {
      _preferredWidth = (_preferredWidth + widthDelta)
          .clamp(ChatDrawerPreferencesStore.minimumWidth, maximumWidth)
          .toDouble();
      _preferredHeight = (_preferredHeight - delta.dy)
          .clamp(ChatDrawerPreferencesStore.minimumHeight, maximumHeight)
          .toDouble();
    });
  }

  void _persistSize(DragEndDetails _) => unawaited(
    widget.preferencesStore.writeDrawerSize(
      width: _preferredWidth,
      height: _preferredHeight,
    ),
  );
}

class _DrawerFrame extends StatelessWidget {
  const _DrawerFrame({
    required this.expanded,
    required this.header,
    required this.content,
    required this.footer,
  });

  final bool expanded;
  final Widget header;
  final Widget content;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      elevation: 12,
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          header,
          Offstage(
            offstage: !expanded,
            child: Divider(height: 1, color: colors.outlineVariant),
          ),
          Expanded(
            child: Offstage(offstage: !expanded, child: content),
          ),
          if (footer case final footer?)
            Offstage(offstage: !expanded, child: footer),
        ],
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({
    required this.route,
    required this.expanded,
    required this.canGoBack,
    required this.onBack,
    required this.onToggle,
    required this.onFullPage,
    required this.onClose,
    required this.leading,
    required this.titleTrailing,
    required this.titleAction,
    required this.routeActions,
    required this.onOverflowOpenChanged,
  });

  final ContentRoute route;
  final bool expanded;
  final bool canGoBack;
  final VoidCallback onBack;
  final VoidCallback onToggle;
  final VoidCallback onFullPage;
  final VoidCallback onClose;
  final Widget? leading;
  final Widget? titleTrailing;
  final VoidCallback? titleAction;
  final List<Widget> routeActions;
  final ValueChanged<bool> onOverflowOpenChanged;

  static const double _narrowActionsWidth =
      ChatDrawerPreferencesStore.defaultWidth;

  @override
  Widget build(BuildContext context) {
    Widget fullPageButton() => DButton.iconOnly(
      key: ChatDrawerOverlay.fullPageButtonKey,
      tooltip: 'Open full-screen chat',
      onPressed: onFullPage,
      variant: DButtonVariant.flat,
      icon: const DIcon(DIcons.discourseExpand, size: 18),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final overflowActions =
            expanded && constraints.maxWidth < _narrowActionsWidth;
        return GestureDetector(
          key: ChatDrawerOverlay.headerKey,
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: SizedBox(
            height: ChatDrawerOverlay.headerHeight,
            child: Row(
              children: [
                if (expanded && canGoBack)
                  DButton.iconOnly(
                    tooltip: 'Back',
                    onPressed: onBack,
                    variant: DButtonVariant.flat,
                    icon: const DIcon(DIcons.chevronLeft, size: 18),
                  )
                else
                  const SizedBox(width: 10),
                if (leading != null) ...[
                  SizedBox(width: 24, height: 24, child: leading),
                  const SizedBox(width: 6),
                ] else ...[
                  const DIcon(DIcons.comment, size: 18),
                  const SizedBox(width: 7),
                ],
                Expanded(
                  child: InkWell(
                    onTap: expanded ? (titleAction ?? onToggle) : onToggle,
                    child: Row(
                      children: [
                        Flexible(child: _DrawerRouteTitle(route: route)),
                        if (titleTrailing != null) ...[
                          const SizedBox(width: 5),
                          titleTrailing!,
                        ],
                      ],
                    ),
                  ),
                ),
                if (overflowActions)
                  _DrawerHeaderOverflowMenu(
                    actions: [...routeActions, fullPageButton()],
                    onOpenChanged: onOverflowOpenChanged,
                  )
                else if (expanded)
                  ...routeActions,
                if (expanded)
                  DButton.iconOnly(
                    key: ChatDrawerOverlay.collapseButtonKey,
                    tooltip: 'Collapse Chat Drawer',
                    onPressed: onToggle,
                    variant: DButtonVariant.flat,
                    icon: const DIcon(DIcons.minus, size: 18),
                  )
                else
                  _CollapsedDrawerToggleButton(onPressed: onToggle),
                if (expanded && !overflowActions) fullPageButton(),
                DButton.iconOnly(
                  key: ChatDrawerOverlay.closeButtonKey,
                  tooltip: 'Close',
                  onPressed: onClose,
                  variant: DButtonVariant.flatClose,
                  icon: const DIcon(DIcons.xmark, size: 18),
                ),
                const SizedBox(width: 2),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DrawerRouteTitle extends StatelessWidget {
  const _DrawerRouteTitle({required this.route});

  final ContentRoute route;

  @override
  Widget build(BuildContext context) {
    final parsed = ChatRoute.parse(route.id);
    final shell = PluginUiScope.require(context, chatShellService);
    final siteUrl = shell.currentSiteUrl;
    final style = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);
    if (siteUrl == null || parsed?.isThread != true) {
      return Text(
        route.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final chat = PluginUiScope.require(context, chatControllerService);
    return ValueListenableBuilder<ChatThread?>(
      valueListenable: chat.threadRef(siteUrl, parsed!.threadId!),
      builder: (context, thread, _) => Text(
        thread?.title?.trim().isNotEmpty == true ? thread!.title! : route.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

class _CollapsedDrawerToggleButton extends StatefulWidget {
  const _CollapsedDrawerToggleButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_CollapsedDrawerToggleButton> createState() =>
      _CollapsedDrawerToggleButtonState();
}

class _CollapsedDrawerToggleButtonState
    extends State<_CollapsedDrawerToggleButton> {
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (_focused != _focus.hasFocus) {
      setState(() => _focused = _focus.hasFocus);
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_handleFocus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    key: ChatDrawerOverlay.collapseButtonKey,
    width: _focused ? DButton.minimumDimension : 1,
    height: _focused ? ChatDrawerOverlay.headerHeight : 1,
    child: ClipRect(
      child: OverflowBox(
        minWidth: DButton.minimumDimension,
        maxWidth: DButton.minimumDimension,
        minHeight: DButton.minimumDimension,
        maxHeight: DButton.minimumDimension,
        child: DButton.iconOnly(
          tooltip: 'Expand Chat Drawer',
          onPressed: widget.onPressed,
          focusNode: _focus,
          variant: DButtonVariant.flat,
          icon: const DIcon(DIcons.arrowUp, size: 18),
        ),
      ),
    ),
  );
}

class _DrawerHeaderOverflowMenu extends StatefulWidget {
  const _DrawerHeaderOverflowMenu({
    required this.actions,
    required this.onOpenChanged,
  });

  final List<Widget> actions;
  final ValueChanged<bool> onOpenChanged;

  @override
  State<_DrawerHeaderOverflowMenu> createState() =>
      _DrawerHeaderOverflowMenuState();
}

class _DrawerHeaderOverflowMenuState extends State<_DrawerHeaderOverflowMenu> {
  final MenuController _controller = MenuController();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyboard);
  }

  bool _handleKeyboard(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !_controller.isOpen) {
      return false;
    }
    _controller.close();
    return true;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyboard);
    super.dispose();
  }

  void _closeAfterActivation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.isOpen) _controller.close();
    });
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
    controller: _controller,
    menuChildren: [
      for (final action in widget.actions)
        Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              _controller.close();
              return KeyEventResult.handled;
            }
            if (action is! ChatDrawerNestedMenuAction &&
                event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space)) {
              _closeAfterActivation();
            }
            return KeyEventResult.ignored;
          },
          child: Listener(
            onPointerUp: action is ChatDrawerNestedMenuAction
                ? null
                : (_) => _closeAfterActivation(),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: ChatDrawerOverflowActionScope(
                closeOverflow: _controller.close,
                child: action,
              ),
            ),
          ),
        ),
    ],
    onOpen: () => widget.onOpenChanged(true),
    onClose: () => widget.onOpenChanged(false),
    builder: (context, _, _) => DButton.iconOnly(
      key: ChatDrawerOverlay.overflowButtonKey,
      tooltip: 'More Chat actions',
      semanticLabel: 'More Chat actions',
      onPressed: _controller.isOpen ? _controller.close : _controller.open,
      variant: DButtonVariant.flat,
      icon: const DIcon(DIcons.ellipsis, size: 18),
    ),
  );
}

class _DrawerResizeHandle extends StatelessWidget {
  const _DrawerResizeHandle({required this.onUpdate, required this.onEnd});

  static const double extent = 15;
  final GestureDragUpdateCallback onUpdate;
  final GestureDragEndCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    return Semantics(
      label: 'Resize Chat Drawer',
      child: MouseRegion(
        cursor: direction == TextDirection.ltr
            ? SystemMouseCursors.resizeUpLeftDownRight
            : SystemMouseCursors.resizeUpRightDownLeft,
        child: GestureDetector(
          key: ChatDrawerOverlay.resizeHandleKey,
          behavior: HitTestBehavior.opaque,
          onPanUpdate: onUpdate,
          onPanEnd: onEnd,
          child: SizedBox(
            width: extent,
            height: extent,
            child: CustomPaint(
              painter: _ResizeGripPainter(
                color: Theme.of(context).colorScheme.outline,
                direction: direction,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResizeGripPainter extends CustomPainter {
  const _ResizeGripPainter({required this.color, required this.direction});

  final Color color;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var inset = 4.0; inset <= 10; inset += 3) {
      final start = direction == TextDirection.ltr
          ? Offset(0, inset)
          : Offset(size.width, inset);
      final end = direction == TextDirection.ltr
          ? Offset(inset, 0)
          : Offset(size.width - inset, 0);
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(_ResizeGripPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.direction != direction;
}

class ChatDrawerChannelsView extends StatelessWidget {
  const ChatDrawerChannelsView({
    super.key,
    required this.siteUrl,
    required this.kind,
  });

  final String siteUrl;
  final ChatDrawerChannelListKind kind;

  @override
  Widget build(BuildContext context) {
    final chat = PluginUiScope.require(context, chatControllerService);
    final shell = PluginUiScope.require(context, chatShellService);
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        final channels = switch (kind) {
          ChatDrawerChannelListKind.channels =>
            chat.activitySortedPublicChannels(siteUrl),
          ChatDrawerChannelListKind.starred =>
            chat.activitySortedStarredChannels(siteUrl),
          ChatDrawerChannelListKind.directMessages =>
            chat
                .activitySortedDirectChannels(siteUrl)
                .take(50)
                .toList(growable: false),
        };
        final action = switch (kind) {
          ChatDrawerChannelListKind.channels
              when chat
                  .siteConfigFor(siteUrl)
                  .chatSettings
                  .publicChannelsEnabled =>
            _DrawerListAction(
              key: const ValueKey('chat-drawer-browse-action'),
              label: 'Browse channels',
              icon: DIcons.list,
              onPressed: shell.openBrowseChannels,
            ),
          ChatDrawerChannelListKind.directMessages
              when shell.currentUser?.staff == true ||
                  shell.currentUser?.canDirectMessage == true =>
            _DrawerListAction(
              key: const ValueKey('chat-drawer-new-message-action'),
              label: 'New message',
              icon: DIcons.plus,
              onPressed: () => unawaited(
                showChatNewDirectMessageDialog(
                  context: context,
                  siteUrl: siteUrl,
                  chat: chat,
                  shell: shell,
                ),
              ),
            ),
          _ => null,
        };
        if (channels.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(switch (kind) {
                    ChatDrawerChannelListKind.channels =>
                      'You have not joined any channels yet.',
                    ChatDrawerChannelListKind.starred =>
                      'You have no starred channels.',
                    ChatDrawerChannelListKind.directMessages =>
                      'You have no direct messages yet.',
                  }, textAlign: TextAlign.center),
                  if (action != null) ...[const SizedBox(height: 12), action],
                ],
              ),
            ),
          );
        }
        return ListView(
          key: PageStorageKey<ChatDrawerChannelListKind>(kind),
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            if (action != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: action,
              ),
            for (final channel in channels)
              _DrawerChannelRow(
                siteUrl: siteUrl,
                channel: channel,
                onTap: () => shell.openChannel(channel.id),
              ),
          ],
        );
      },
    );
  }
}

class _DrawerListAction extends StatelessWidget {
  const _DrawerListAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final DIconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DButton(
    label: Text(label),
    icon: DIcon(icon, size: 16),
    onPressed: onPressed,
    variant: DButtonVariant.flat,
    size: DButtonSize.small,
  );
}

class _DrawerChannelRow extends StatelessWidget {
  const _DrawerChannelRow({
    required this.siteUrl,
    required this.channel,
    required this.onTap,
  });

  final String siteUrl;
  final ChatChannel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final badge = _drawerChannelBadge(channel);
    final muted = channel.membership.muted;
    final theme = Theme.of(context);
    final foreground = muted
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55)
        : theme.colorScheme.onSurface;
    final directUser = channel.isDirectMessage && channel.users.length == 1
        ? channel.users.first
        : null;
    final status = directUser?.status;
    return ListTile(
      key: ValueKey('chat-drawer-channel-${channel.id}'),
      dense: true,
      leading: _DrawerChannelPrefix(
        siteUrl: siteUrl,
        channel: channel,
        foreground: foreground,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              channel.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: foreground),
            ),
          ),
          if (status != null)
            UserStatusMessage(
              siteUrl: siteUrl,
              userId: directUser!.id,
              status: status,
              size: 14,
              leadingGap: 4,
            ),
        ],
      ),
      subtitle: switch (_drawerChannelActivityAt(channel)) {
        final at? => Text(
          relativeTime(at),
          maxLines: 1,
          style: theme.textTheme.labelSmall?.copyWith(color: foreground),
        ),
        null => null,
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge.isVisible)
            _DrawerBadge(badge: badge)
          else if (channel.membership.starred)
            DIcon(DIcons.star, size: 14, color: foreground),
          ChatChannelMenuButton(siteUrl: siteUrl, channelId: channel.id),
        ],
      ),
      onTap: onTap,
      onLongPress: context.isTouch
          ? () => unawaited(
              ChatChannelMenuButton.showSheet(
                context: context,
                siteUrl: siteUrl,
                channelId: channel.id,
              ),
            )
          : null,
    );
  }
}

class _DrawerChannelPrefix extends StatelessWidget {
  const _DrawerChannelPrefix({
    required this.siteUrl,
    required this.channel,
    required this.foreground,
  });

  final String siteUrl;
  final ChatChannel channel;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    Widget art;
    if (channel.isDirectMessage && channel.users.length == 1) {
      final user = channel.users.first;
      art = ChatUserAvatar(
        siteUrl: siteUrl,
        userId: user.id,
        url: channel.avatarUrl,
        size: 24,
        fallback: DIcon(DIcons.user, size: 18, color: foreground),
      );
    } else if (channel.isDirectMessage) {
      art = DIcon(DIcons.users, size: 18, color: foreground);
    } else if (channel.emoji case final emoji?) {
      final shell = ShellScope.read(context);
      art = EmojiImage(
        url: shell.emojiUrlFor(siteUrl, emoji),
        size: 18,
        alt: ':$emoji:',
      );
    } else {
      art = DIcon(
        DIcons.comment,
        size: 18,
        color: channel.categoryColor ?? foreground,
      );
    }
    if (!channel.isCategoryChannel || !channel.readRestricted) return art;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        art,
        Positioned(
          right: -4,
          bottom: -4,
          child: DIcon(DIcons.lock, size: 10, color: foreground),
        ),
      ],
    );
  }
}

DateTime? _drawerChannelActivityAt(ChatChannel channel) {
  var latest = channel.lastMessageAt;
  for (final threadAt in channel.unreadThreadOverview.values) {
    if (latest == null || threadAt.isAfter(latest)) latest = threadAt;
  }
  return latest;
}

SidebarBadge _drawerChannelBadge(ChatChannel channel) {
  final urgent =
      channel.tracking.mentionCount +
      channel.tracking.watchedThreadsUnreadCount +
      (channel.isDirectMessage ? channel.tracking.unreadCount : 0);
  if (urgent > 0) return SidebarBadge.urgentCount(urgent);
  if (channel.tracking.unreadCount > 0 ||
      channel.unreadThreadsCountSinceLastViewed > 0) {
    return const SidebarBadge.dot();
  }
  return SidebarBadge.none;
}

class _DrawerBadge extends StatelessWidget {
  const _DrawerBadge({required this.badge});

  final SidebarBadge badge;

  @override
  Widget build(BuildContext context) {
    final color = badge.urgent
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    if (badge.dot) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }
    return Text(
      badge.count > 99 ? '99+' : '${badge.count}',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class ChatDrawerFooter extends StatelessWidget {
  const ChatDrawerFooter({super.key});

  static const Key footerKey = ValueKey('chat-drawer-footer');

  @override
  Widget build(BuildContext context) {
    final shell = PluginUiScope.require(context, chatShellService);
    final chat = PluginUiScope.require(context, chatControllerService);
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) => _buildFooter(context, shell, chat),
    );
  }

  Widget _buildFooter(
    BuildContext context,
    ChatShellService shell,
    ChatController chat,
  ) {
    final siteUrl = shell.currentSiteUrl;
    if (siteUrl == null || !chat.channelsLoaded(siteUrl)) {
      return const SizedBox.shrink();
    }
    final settings = chat.siteConfigFor(siteUrl).chatSettings;
    final includeStarred =
        shell.currentUser != null && chat.starredChannels(siteUrl).isNotEmpty;
    final publicChannelsEnabled = settings.publicChannelsEnabled;
    final directMessagesEnabled =
        shell.currentUser != null &&
        (shell.currentUser?.staff == true ||
            shell.currentUser?.canDirectMessage == true ||
            chat.directChannels(siteUrl).isNotEmpty);
    final includeThreads = settings.threadsEnabled && chat.hasThreads(siteUrl);
    final includeSearch = shell.currentUser != null && settings.searchEnabled;
    if (!includeStarred && shell.drawerShowingStarred) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => shell.leaveEmptyStarredRoute(),
      );
    }
    final primaryCount = [
      includeStarred,
      publicChannelsEnabled,
      directMessagesEnabled,
      includeThreads,
    ].where((value) => value).length;
    if (primaryCount < 2) return const SizedBox.shrink();

    final starred = chat.starredChannels(siteUrl);
    final public = chat.unstarredPublicChannels(siteUrl);
    final direct = chat.unstarredDirectChannels(siteUrl);
    final allChannels = [
      ...chat.publicChannels(siteUrl),
      ...chat.directChannels(siteUrl),
    ];

    final items = <_FooterItem>[
      if (includeStarred)
        _FooterItem(
          'chat-starred',
          'Starred',
          DIcons.star,
          shell.openStarredChannels,
          _footerBadge(
            urgent: starred.fold(
              0,
              (count, channel) =>
                  count +
                  (channel.isDirectMessage
                      ? channel.tracking.unreadCount
                      : channel.tracking.mentionCount),
            ),
            unread: starred
                .where((channel) => channel.isCategoryChannel)
                .fold(
                  0,
                  (count, channel) => count + channel.tracking.unreadCount,
                ),
          ),
        ),
      // Web keeps the channel-list destination in every rendered footer; the
      // public-channel capability participates only in the render threshold.
      _FooterItem(
        'chat-channels',
        'Channels',
        DIcons.comments,
        shell.openChannels,
        _footerBadge(
          urgent: public.fold(
            0,
            (count, channel) => count + channel.tracking.mentionCount,
          ),
          unread: public.fold(
            0,
            (count, channel) => count + channel.tracking.unreadCount,
          ),
        ),
      ),
      if (directMessagesEnabled)
        _FooterItem(
          'chat-direct-messages',
          'DMs',
          DIcons.users,
          shell.openDirectMessages,
          _footerBadge(
            urgent: direct.fold(
              0,
              (count, channel) =>
                  count +
                  channel.tracking.unreadCount +
                  channel.tracking.mentionCount,
            ),
          ),
        ),
      if (includeThreads)
        _FooterItem(
          'chat-my-threads',
          'My threads',
          DIcons.comments,
          shell.openMyThreads,
          _footerBadge(
            urgent: allChannels.fold(
              0,
              (count, channel) =>
                  count + channel.tracking.watchedThreadsUnreadCount,
            ),
            unread: allChannels.fold(
              0,
              (count, channel) => count + channel.unreadThreadCount,
            ),
          ),
        ),
      if (includeSearch)
        _FooterItem(
          'chat-search',
          'Search',
          DIcons.magnifyingGlass,
          shell.openSearch,
          SidebarBadge.none,
        ),
    ];
    return Container(
      key: footerKey,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showLabels = constraints.maxWidth >= 375;
              return Row(
                children: [
                  for (final item in items)
                    Expanded(
                      child: Semantics(
                        selected:
                            shell.drawerCurrentContent?.id == item.routeId,
                        child: showLabels
                            ? DButton(
                                key: ValueKey(
                                  'chat-drawer-footer-${item.routeId}',
                                ),
                                tooltip: item.label,
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    item.label,
                                    maxLines: 1,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                icon: _footerIcon(item, 17),
                                onPressed: item.onPressed,
                                variant:
                                    shell.drawerCurrentContent?.id ==
                                        item.routeId
                                    ? DButtonVariant.transparentPrimary
                                    : DButtonVariant.flat,
                                size: DButtonSize.small,
                              )
                            : DButton.iconOnly(
                                key: ValueKey(
                                  'chat-drawer-footer-${item.routeId}',
                                ),
                                tooltip: item.label,
                                onPressed: item.onPressed,
                                variant:
                                    shell.drawerCurrentContent?.id ==
                                        item.routeId
                                    ? DButtonVariant.transparentPrimary
                                    : DButtonVariant.flat,
                                icon: _footerIcon(item, 18),
                              ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

Widget _footerIcon(_FooterItem item, double size) => Stack(
  clipBehavior: Clip.none,
  children: [
    DIcon(item.icon, size: size),
    if (item.badge.isVisible)
      Positioned(
        key: ValueKey('chat-drawer-footer-badge-${item.routeId}'),
        top: -7,
        right: -9,
        child: _DrawerBadge(badge: item.badge),
      ),
  ],
);

SidebarBadge _footerBadge({required int urgent, int unread = 0}) => urgent > 0
    ? SidebarBadge.urgentCount(urgent)
    : unread > 0
    ? const SidebarBadge.dot()
    : SidebarBadge.none;

class _FooterItem {
  const _FooterItem(
    this.routeId,
    this.label,
    this.icon,
    this.onPressed,
    this.badge,
  );

  final String routeId;
  final String label;
  final DIconData icon;
  final VoidCallback onPressed;
  final SidebarBadge badge;
}
