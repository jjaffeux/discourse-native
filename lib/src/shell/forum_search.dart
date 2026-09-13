import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_shortcuts.dart';
import '../models/search_results.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'content_navigation_controls.dart';
import 'global_search_controller.dart';
import 'global_search_models.dart';
import 'global_search_panel.dart';
import 'open_link.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'shell_search_controller.dart';

/// Global search with one editor shared by the navbar and its open surface.
class ForumSearch extends StatefulWidget {
  const ForumSearch({super.key, this.dense = false});

  final bool dense;
  static const Key inputKey = ValueKey('forum-search-input');
  static const Key panelKey = ValueKey('forum-search-panel');
  static const Key anchorKey = ValueKey('forum-search-anchor');

  @override
  State<ForumSearch> createState() => _ForumSearchState();
}

class _ForumSearchState extends State<ForumSearch> {
  final Object _field = Object();
  final _editorKey = GlobalKey(debugLabel: 'global-search-shared-editor');
  final _anchorKey = GlobalKey(debugLabel: 'global-search-anchor-footprint');
  final _text = TextEditingController();
  final _focus = FocusNode(debugLabel: 'forum search');
  final _popover = DPopoverController();
  ShellController? _shell;
  late ShellSearchController _search;
  late GlobalSearchController _global;
  VoidCallback? _unregisterFocus;
  bool _open = false;
  bool _suppressFocus = false;
  bool _syncScheduled = false;
  bool _geometryScheduled = false;
  double _anchorHeight = 32;
  double _anchorLeft = 8;
  double _anchorTop = 6;
  double? _layoutWidth;
  Size? _layoutViewport;
  String? _lastExternalQuery;
  int? _lastTopicId;
  String? _selectedResultId;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = ShellScope.read(context);
    if (identical(shell, _shell)) return;
    _detach();
    _shell = shell;
    _search = shell.search;
    _global = shell.globalSearch;
    _lastExternalQuery = _search.query;
    _lastTopicId = _search.topicId;
    _search.addListener(_searchChanged);
    _global.addListener(_globalChanged);
    shell.addListener(_siteChanged);
    _unregisterFocus = _search.registerFocus(_field, _requestFocus);
    _syncSite();
    _syncText();
  }

  void _detach() {
    if (_shell == null) return;
    _search.removeListener(_searchChanged);
    _global.removeListener(_globalChanged);
    _shell!.removeListener(_siteChanged);
    _unregisterFocus?.call();
    _unregisterFocus = null;
  }

  void _syncSite() {
    final shell = _shell!;
    final site = _search.siteUrl;
    final instance = site == null ? null : shell.instanceFor(site);
    final chatInstalled = shell.plugins.registry.plugins.any(
      (plugin) => plugin.name == 'chat',
    );
    _global.configure(
      siteUrl: site,
      capabilities: site == null
          ? const GlobalSearchCapabilities()
          : GlobalSearchCapabilities.fromSite(
              shell.siteConfigFor(site),
              instance?.user,
              chat: chatInstalled && instance?.isConnected == true,
            ),
    );
  }

  void _siteChanged() {
    if (!mounted) return;
    _syncSite();
  }

  void _searchChanged() {
    if (!mounted) return;
    _syncSite();
    if (_lastExternalQuery != _search.query) {
      _lastExternalQuery = _search.query;
      _global.setQuery(_search.query);
    }
    if (_lastTopicId != _search.topicId) {
      _lastTopicId = _search.topicId;
      _global.setTopicContext(_search.topicId);
    }
    _syncText();
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      final active = _search.panelOpen && _search.ownsPanel(_field);
      if (active) {
        _openSearch();
      } else if (_popover.isOpen) {
        _popover.close();
      }
      setState(() {});
    });
  }

  void _globalChanged() {
    if (!mounted) return;
    _syncText();
    if (!_global.results.any((row) => row.id == _selectedResultId)) {
      _selectedResultId = null;
    }
    setState(() {});
  }

  void _syncText() {
    if (_text.text == _global.query) return;
    _text.value = TextEditingValue(
      text: _global.query,
      selection: TextSelection.collapsed(offset: _global.query.length),
    );
  }

  void _requestFocus() {
    if (!mounted) return;
    _search.activateField(_field);
    _openSearch();
  }

  void _focusChanged() {
    if (_focus.hasFocus && !_suppressFocus && !_open) _requestFocus();
  }

  void _openSearch() {
    if (_search.siteUrl == null) return;
    _measureAnchor();
    if (!_popover.isOpen) _popover.open(DPopoverInteraction.keyboard);
  }

  void _measureAnchor() {
    final box = _anchorKey.currentContext?.findRenderObject();
    final overlay = Overlay.of(context).context.findRenderObject();
    if (box is RenderBox && box.hasSize && overlay is RenderBox) {
      final rect = MatrixUtils.transformRect(
        box.getTransformTo(overlay),
        Offset.zero & box.size,
      );
      _anchorHeight = box.size.height;
      _anchorLeft = rect.left;
      _anchorTop = rect.top;
    }
  }

  void _scheduleGeometry() {
    if (_geometryScheduled) return;
    _geometryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _geometryScheduled = false;
      if (!mounted || !_open) return;
      setState(_measureAnchor);
    });
  }

  void _openChanged(bool open, DPopoverChangeReason reason) {
    if (!mounted) return;
    final editingValue = _text.value;
    _suppressFocus = true;
    setState(() => _open = open);
    if (!open) _search.closePanel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_text.text == editingValue.text) _text.value = editingValue;
      if (open || reason == DPopoverChangeReason.escape) {
        _focus.requestFocus();
      } else {
        _focus.unfocus();
      }
      _suppressFocus = false;
    });
  }

  void _clear() {
    _selectedResultId = null;
    _global.setQuery('');
    _focus.requestFocus();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_focus.hasFocus || !_open) return KeyEventResult.ignored;
    final composing = _text.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      final rows = _global.results;
      if (rows.isEmpty) return KeyEventResult.ignored;
      final current = rows.indexWhere((row) => row.id == _selectedResultId);
      final down = key == LogicalKeyboardKey.arrowDown;
      final next = current < 0
          ? (down ? 0 : rows.length - 1)
          : (current + (down ? 1 : -1) + rows.length) % rows.length;
      setState(() => _selectedResultId = rows[next].id);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final selected = _global.results
          .where((row) => row.id == _selectedResultId)
          .firstOrNull;
      if (selected != null) {
        _openResult(selected);
      } else {
        _global.submit();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _openResult(GlobalSearchResult result) {
    final site = _global.siteUrl;
    if (site == null) return;
    unawaited(_global.recordSelection(result));
    _popover.close();
    if (result.source case final SearchPostHit hit) {
      _shell!.openSearchResult(hit);
    } else {
      unawaited(
        openLink(context, result.path, title: result.title, siteUrl: site),
      );
    }
  }

  Widget _editor(double width, {required bool expanded}) {
    return Focus(
      key: _editorKey,
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleKey,
      child: DInputGroup(
        borderless: expanded,
        children: [
          DInputGroupInput(
            key: ForumSearch.inputKey,
            controller: _text,
            focusNode: _focus,
            semanticLabel: 'Search this forum',
            hintText: 'Search everywhere',
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            onTap: _requestFocus,
            onChanged: (value) {
              _selectedResultId = null;
              _global.setQuery(value);
            },
            onSubmitted: (_) => _global.submit(),
          ),
          if (width >= 140)
            const DInputGroupAddon(
              alignment: DInputGroupAddonAlignment.inlineStart,
              child: DIcon(DIcons.magnifyingGlass, size: 16),
            ),
          DInputGroupAddon(
            alignment: DInputGroupAddonAlignment.inlineEnd,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_global.query.isNotEmpty)
                  DInputGroupButton.icon(
                    key: const ValueKey('forum-search-clear'),
                    icon: const DIcon(DIcons.xmark, size: 16),
                    tooltip: 'Clear search',
                    onPressed: _clear,
                  )
                else if (width >=
                    280 * MediaQuery.textScalerOf(context).scale(14) / 14)
                  DShortcutKeycaps(
                    shortcut: DShortcut(
                      primaryShortcutForPlatform(
                        defaultTargetPlatform,
                        LogicalKeyboardKey.keyF,
                      ),
                    ),
                    listenToKeyboard: false,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_search.siteUrl == null) return const SizedBox.shrink();
    final platform = Theme.of(context).platform;
    final mobile =
        (platform == TargetPlatform.iOS ||
            platform == TargetPlatform.android) &&
        MediaQuery.sizeOf(context).width < 768;
    final field = LayoutBuilder(
      builder: (context, constraints) {
        final anchorWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 420.0;
        final viewport = MediaQuery.sizeOf(context);
        final safe = MediaQuery.paddingOf(context);
        if (_open &&
            (_layoutWidth != anchorWidth || _layoutViewport != viewport)) {
          _scheduleGeometry();
        }
        _layoutWidth = anchorWidth;
        _layoutViewport = viewport;
        final inset = mobile ? 0.0 : 8.0;
        final width = mobile
            ? viewport.width
            : math.min(
                math.max(640.0, anchorWidth + inset * 2),
                viewport.width - safe.horizontal - 8,
              );
        final surfaceLeft = (_anchorLeft - inset)
            .clamp(
              safe.left + 4,
              math.max(safe.left + 4, viewport.width - safe.right - width - 4),
            )
            .toDouble();
        final editorLeft = math.max(0.0, _anchorLeft - surfaceLeft);
        final height = mobile
            ? math.max(
                160.0,
                viewport.height -
                    MediaQuery.viewInsetsOf(context).bottom -
                    MediaQuery.paddingOf(context).vertical -
                    8,
              )
            : math.min(
                654.0,
                math.max(
                  100.0,
                  viewport.height -
                      MediaQuery.viewInsetsOf(context).bottom -
                      MediaQuery.paddingOf(context).bottom -
                      math.max(_anchorTop - 6, 0) -
                      8,
                ),
              );
        return DPopover(
          controller: _popover,
          restoreFocus: false,
          focusContentOnOpen: false,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          onOpenChange: _openChanged,
          content: DPopoverContent(
            key: ForumSearch.panelKey,
            semanticLabel: 'Global search',
            width: width,
            constraints: BoxConstraints(maxHeight: height),
            padding: EdgeInsets.zero,
            scrollable: false,
            shadow: DPopoverShadow.large,
            collisionPadding: mobile ? 4 : 0,
            sideCollision: DPopoverCollision.shift,
            alignCollision: DPopoverCollision.shift,
            placementResolver: (placement) => mobile
                ? placement.boundary.topLeft
                : Offset(surfaceLeft, placement.target.top - 6),
            child: SizedBox(
              height: height,
              child: Column(
                children: [
                  Padding(
                    padding: mobile
                        ? const EdgeInsets.symmetric(vertical: 8)
                        : EdgeInsets.fromLTRB(
                            editorLeft,
                            6,
                            math.max(0.0, width - editorLeft - anchorWidth),
                            6,
                          ),
                    child: Row(
                      children: [
                        if (mobile)
                          DButton.iconOnly(
                            key: const ValueKey('global-search-back'),
                            icon: const DIcon(DIcons.arrowLeft),
                            tooltip: 'Back',
                            variant: DButtonVariant.ghost,
                            onPressed: _popover.close,
                          ),
                        Expanded(
                          child: _open
                              ? _editor(
                                  mobile ? width - 32 : anchorWidth,
                                  expanded: true,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                  const DSeparator(),
                  Expanded(
                    child: GlobalSearchPanel(
                      controller: _global,
                      selectedResultId: _selectedResultId,
                      onSelect: (id) => setState(() => _selectedResultId = id),
                      onOpen: _openResult,
                    ),
                  ),
                ],
              ),
            ),
          ),
          child: DPopoverAnchor(
            child: SizedBox(
              key: _anchorKey,
              width: anchorWidth,
              child: _open
                  ? SizedBox(key: ForumSearch.anchorKey, height: _anchorHeight)
                  : _editor(anchorWidth, expanded: false),
            ),
          ),
        );
      },
    );
    if (mobile) {
      return PopScope(
        canPop: !_open,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _open) _popover.close();
        },
        child: field,
      );
    }
    if (!ContentNavigationControls.isSupported) return field;
    return Row(
      children: [
        const ContentNavigationControls(),
        const SizedBox(width: 4),
        Expanded(child: field),
      ],
    );
  }

  @override
  void dispose() {
    _detach();
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _text.dispose();
    _popover.dispose();
    super.dispose();
  }
}
