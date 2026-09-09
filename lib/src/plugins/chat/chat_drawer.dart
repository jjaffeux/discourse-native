import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/content_route.dart';
import '../../models/sidebar.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../shell/adaptive_shell.dart';
import '../../shell/emoji.dart';
import '../../shell/platform.dart';
import '../../shell/relative_time.dart';
import '../../shell/site_emoji_text.dart';
import '../../shell/title_bar.dart';
import '../../shell/user_status.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../../theme/discourse_typography.dart';
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
typedef ChatDrawerNavigationVisibility = bool Function(ContentRoute route);

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
    required this.showNavigationForRoute,
    this.preferencesStore = const ChatDrawerPreferencesStore(),
  });

  final ChatDrawerContentBuilder contentBuilder;
  final ChatDrawerHeaderActionsBuilder headerActionsBuilder;
  final ChatDrawerHeaderWidgetBuilder headerLeadingBuilder;
  final ChatDrawerHeaderWidgetBuilder headerTitleTrailingBuilder;
  final ChatDrawerHeaderActionBuilder headerTitleActionBuilder;
  final ChatDrawerNavigationVisibility showNavigationForRoute;
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
  static const Key searchButtonKey = ValueKey('chat-drawer-search');
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
  ChatShellService? _shell;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyboard);
    unawaited(_restoreSize());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyboard);
    _shell?.updateDrawerContentVisibility(false);
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
        widget is DCheckbox ||
        widget is Checkbox ||
        widget is RawRadio ||
        widget is Radio ||
        widget is Switch ||
        widget is DMultiSlider ||
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
    if (!identical(_shell, shell)) {
      _shell?.updateDrawerContentVisibility(false);
      _shell = shell;
    }
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
                final contentVisible =
                    available &&
                    shell.drawerExpanded &&
                    TickerMode.valuesOf(context).enabled;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || !identical(_shell, shell)) return;
                  shell.updateDrawerAvailability(available);
                  shell.updateDrawerContentVisibility(contentVisible);
                });
                if (shell.drawerCurrentContent == null) {
                  return const SizedBox.shrink();
                }
                final visible = available && shell.drawerActive;
                if (_drawerWasVisible && !visible) {
                  final focused = FocusManager.instance.primaryFocus;
                  // Primary focus can still belong to a deactivated element
                  // during layout. Check its ancestry after tree finalization.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final focusedContext = focused?.context;
                    if (mounted &&
                        identical(
                          focused,
                          FocusManager.instance.primaryFocus,
                        ) &&
                        focusedContext != null &&
                        focusedContext.mounted &&
                        _drawerContains(focusedContext)) {
                      focused?.unfocus();
                    }
                  });
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
    final showNavigation = widget.showNavigationForRoute(route);
    final siteUrl = shell.currentSiteUrl;
    final isChannelList = const {
      'chat-channels',
      'chat-starred',
      'chat-direct-messages',
    }.contains(route.id);

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
                    canGoBack: !isChannelList && shell.drawerCanGoBack,
                    isChannelList: isChannelList,
                    onBack: shell.drawerBack,
                    onToggle: shell.toggleDrawerExpanded,
                    onFullPage: () => unawaited(shell.openFullPageFromDrawer()),
                    onClose: shell.closeDrawer,
                    onSearch:
                        showNavigation &&
                            shell.currentUser != null &&
                            siteUrl != null &&
                            shell.chat
                                .siteConfigFor(siteUrl)
                                .chatSettings
                                .searchEnabled
                        ? shell.openSearch
                        : null,
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
                  navigation: showNavigation
                      ? const ChatDrawerNavigation()
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
                _DrawerResizeHandle.extent +
                _DrawerResizeHandle.overhang,
            bottom:
                bottomOffset +
                expandedHeight -
                _DrawerResizeHandle.extent +
                _DrawerResizeHandle.overhang,
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
    final left = DDirection.of(context) == TextDirection.ltr
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
    final direction = DDirection.of(context);
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
    required this.navigation,
  });

  final bool expanded;
  final Widget header;
  final Widget content;
  final Widget? navigation;

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
          if (navigation case final navigation?)
            TickerMode(
              enabled: expanded,
              child: Offstage(offstage: !expanded, child: navigation),
            )
          else
            Offstage(
              offstage: !expanded,
              child: DSeparator(space: 1, color: colors.outlineVariant),
            ),
          Expanded(
            child: TickerMode(
              enabled: expanded,
              child: Offstage(offstage: !expanded, child: content),
            ),
          ),
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
    required this.isChannelList,
    required this.onBack,
    required this.onToggle,
    required this.onFullPage,
    required this.onClose,
    required this.onSearch,
    required this.leading,
    required this.titleTrailing,
    required this.titleAction,
    required this.routeActions,
    required this.onOverflowOpenChanged,
  });

  final ContentRoute route;
  final bool expanded;
  final bool canGoBack;
  final bool isChannelList;
  final VoidCallback onBack;
  final VoidCallback onToggle;
  final VoidCallback onFullPage;
  final VoidCallback onClose;
  final VoidCallback? onSearch;
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
        final showLeading = !overflowActions || titleTrailing == null;
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
                if (showLeading)
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
                        Flexible(
                          child: isChannelList
                              ? Text(
                                  'Chat',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                )
                              : _DrawerRouteTitle(route: route),
                        ),
                        if (titleTrailing != null) ...[
                          const SizedBox(width: 5),
                          titleTrailing!,
                        ],
                      ],
                    ),
                  ),
                ),
                if (expanded && onSearch != null)
                  DButton.iconOnly(
                    key: ChatDrawerOverlay.searchButtonKey,
                    tooltip: 'Search chat',
                    onPressed: onSearch,
                    variant: route.id == 'chat-search'
                        ? DButtonVariant.transparentPrimary
                        : DButtonVariant.flat,
                    icon: const DIcon(DIcons.magnifyingGlass, size: 16),
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
  static const double overhang = 5;
  final GestureDragUpdateCallback onUpdate;
  final GestureDragEndCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final direction = DDirection.of(context);
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
          child: const SizedBox(width: extent, height: extent),
        ),
      ),
    );
  }
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
              label: 'Browse',
              tooltip: 'Browse channels',
              icon: DIcons.plus,
              onPressed: shell.openBrowseChannels,
            ),
          ChatDrawerChannelListKind.directMessages
              when shell.currentUser?.staff == true ||
                  shell.currentUser?.canDirectMessage == true =>
            _DrawerListAction(
              key: const ValueKey('chat-drawer-new-message-action'),
              label: 'New',
              tooltip: 'New message',
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
        final colors = Theme.of(context).colorScheme;
        return Column(
          children: [
            Padding(
              key: const ValueKey('chat-drawer-list-heading'),
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.textScalerOf(context).scale(36),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              switch (kind) {
                                ChatDrawerChannelListKind.channels =>
                                  'Channels',
                                ChatDrawerChannelListKind.starred => 'Starred',
                                ChatDrawerChannelListKind.directMessages =>
                                  'Direct messages',
                              },
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${channels.length}',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (action != null) ...[const SizedBox(width: 8), action],
                  ],
                ),
              ),
            ),
            Expanded(
              child: channels.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(switch (kind) {
                          ChatDrawerChannelListKind.channels =>
                            'You have not joined any channels yet.',
                          ChatDrawerChannelListKind.starred =>
                            'You have no starred channels.',
                          ChatDrawerChannelListKind.directMessages =>
                            'You have no direct messages yet.',
                        }, textAlign: TextAlign.center),
                      ),
                    )
                  : ListView.builder(
                      key: PageStorageKey<ChatDrawerChannelListKind>(kind),
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      itemCount: channels.length,
                      itemBuilder: (context, index) {
                        final channel = channels[index];
                        return ValueListenableBuilder<ChatChannel?>(
                          key: ValueKey(channel.id),
                          valueListenable: chat.channelRef(siteUrl, channel.id),
                          builder: (context, current, _) => _DrawerChannelRow(
                            siteUrl: siteUrl,
                            channel: current ?? channel,
                            onTap: () => shell.openChannel(channel.id),
                          ),
                        );
                      },
                    ),
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
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final DIconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DButton(
    label: Text(label),
    tooltip: tooltip,
    icon: DIcon(icon, size: 16),
    onPressed: onPressed,
    variant: DButtonVariant.transparentPrimary,
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
    final colors = theme.colorScheme;
    final at = _drawerChannelActivityAt(channel);
    final preview =
        channel.lastMessagePreview ??
        (channel.lastMessageId == null ? 'No messages yet' : '');
    final radius = BorderRadius.circular(8);
    return Padding(
      key: ValueKey('chat-drawer-channel-${channel.id}'),
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: badge.isVisible && !muted
            ? colors.primary.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.14 : 0.07,
              )
            : Colors.transparent,
        borderRadius: radius,
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: badge.isVisible ? 'Unread conversation' : null,
                child: InkWell(
                  borderRadius: radius,
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 11,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact =
                            constraints.maxWidth < 280 &&
                            MediaQuery.textScalerOf(context).scale(12) > 18;
                        final metadata = Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (at != null)
                              Text(
                                relativeTime(at),
                                key: ValueKey('chat-drawer-time-${channel.id}'),
                                maxLines: 1,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            if (badge.isVisible) ...[
                              const SizedBox(height: 6),
                              _DrawerBadge(badge: badge),
                            ],
                          ],
                        );
                        return Row(
                          children: [
                            _DrawerChannelPrefix(
                              siteUrl: siteUrl,
                              channel: channel,
                              foreground: foreground,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          channel.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: foreground,
                                                fontWeight: badge.isVisible
                                                    ? FontWeight.w600
                                                    : FontWeight.w500,
                                              ),
                                        ),
                                      ),
                                      if (channel.readRestricted) ...[
                                        const SizedBox(width: 5),
                                        DIcon(
                                          DIcons.lock,
                                          size: 10,
                                          color: foreground,
                                        ),
                                      ],
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
                                  const SizedBox(height: 3),
                                  SiteEmojiText.plain(
                                    preview,
                                    key: ValueKey(
                                      'chat-drawer-preview-${channel.id}',
                                    ),
                                    siteUrl: siteUrl,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: muted
                                          ? foreground
                                          : colors.onSurfaceVariant,
                                    ),
                                  ),
                                  if (compact &&
                                      (at != null || badge.isVisible)) ...[
                                    const SizedBox(height: 6),
                                    metadata,
                                  ],
                                ],
                              ),
                            ),
                            if (!compact &&
                                (at != null || badge.isVisible)) ...[
                              const SizedBox(width: 10),
                              metadata,
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: ChatChannelMenuButton(
                siteUrl: siteUrl,
                channelId: channel.id,
              ),
            ),
          ],
        ),
      ),
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
        size: 36,
        fallback: DIcon(DIcons.user, size: 18, color: foreground),
      );
    } else if (channel.isDirectMessage) {
      art = DIcon(DIcons.users, size: 18, color: foreground);
    } else if (channel.emoji case final emoji?) {
      final emojiHost = PluginUiScope.require(context, chatEmojiHostService);
      art = EmojiImage(
        url: emojiHost.resolveUrl(siteUrl, emoji),
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
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: channel.isDirectMessage && channel.users.length == 1
            ? null
            : Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(9),
      ),
      child: art,
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
  const _DrawerBadge({super.key, required this.badge});

  final SidebarBadge badge;

  @override
  Widget build(BuildContext context) {
    if (badge.dot) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
      );
    }
    return DBadge(
      semanticLabel: '${badge.count} urgent notifications',
      child: Text(badge.count > 99 ? '99+' : '${badge.count}'),
    );
  }
}

class ChatDrawerNavigation extends StatelessWidget {
  const ChatDrawerNavigation({super.key});

  static const Key navigationKey = ValueKey('chat-drawer-navigation');

  @override
  Widget build(BuildContext context) {
    final shell = PluginUiScope.require(context, chatShellService);
    final chat = PluginUiScope.require(context, chatControllerService);
    return ListenableBuilder(
      listenable: Listenable.merge([shell, chat]),
      builder: (context, _) => _buildNavigation(context, shell, chat),
    );
  }

  Widget _buildNavigation(
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

    final items = <_NavigationItem>[
      if (includeStarred)
        _NavigationItem(
          'chat-starred',
          'Starred',
          DIcons.star,
          shell.openStarredChannels,
          _navigationBadge(
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
      _NavigationItem(
        'chat-channels',
        'Channels',
        DIcons.comments,
        shell.openChannels,
        _navigationBadge(
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
        _NavigationItem(
          'chat-direct-messages',
          'DMs',
          DIcons.users,
          shell.openDirectMessages,
          _navigationBadge(
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
        _NavigationItem(
          'chat-my-threads',
          'My threads',
          DIcons.comments,
          shell.openMyThreads,
          _navigationBadge(
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
    ];
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: navigationKey,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale =
              MediaQuery.textScalerOf(context).scale(DiscourseTypography.sm) /
              DiscourseTypography.sm;
          final showIcons = constraints.maxWidth >= 340 && textScale <= 1.25;
          Widget tab(_NavigationItem item) {
            final selected = shell.drawerCurrentContent?.id == item.routeId;
            return Semantics(
              selected: selected,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: selected ? colors.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: DButton(
                  key: ValueKey('chat-drawer-navigation-${item.routeId}'),
                  tooltip: item.label,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 10,
                  ),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.routeId == 'chat-my-threads'
                            ? 'Threads'
                            : item.label,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      if (item.badge.isVisible) ...[
                        const SizedBox(width: 4),
                        _DrawerBadge(
                          key: ValueKey(
                            'chat-drawer-navigation-badge-${item.routeId}',
                          ),
                          badge: item.badge,
                        ),
                      ],
                    ],
                  ),
                  icon: showIcons ? DIcon(item.icon, size: 16) : null,
                  onPressed: item.onPressed,
                  variant: selected
                      ? DButtonVariant.transparentPrimary
                      : DButtonVariant.flat,
                  size: DButtonSize.small,
                ),
              ),
            );
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [for (final item in items) tab(item)]),
          );
        },
      ),
    );
  }
}

SidebarBadge _navigationBadge({required int urgent, int unread = 0}) =>
    urgent > 0
    ? SidebarBadge.urgentCount(urgent)
    : unread > 0
    ? const SidebarBadge.dot()
    : SidebarBadge.none;

class _NavigationItem {
  const _NavigationItem(
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
