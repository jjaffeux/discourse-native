import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'anchored_layout.dart';

class HoverPanel extends StatefulWidget {
  const HoverPanel({
    super.key,
    required this.child,
    required this.panelBuilder,
    this.maxWidth = 260,
    this.onOpen,
    this.enabled = true,
    this.preferAbove = false,
  });

  static const Duration openDelay = Duration(milliseconds: 250);

  static const Duration closeDelay = Duration(milliseconds: 500);

  final Widget child;

  final WidgetBuilder panelBuilder;

  final double maxWidth;

  final VoidCallback? onOpen;

  final bool enabled;

  final bool preferAbove;

  @override
  State<HoverPanel> createState() => HoverPanelState();
}

class HoverPanelState extends State<HoverPanel> {
  final OverlayPortalController _portal = OverlayPortalController();
  final GlobalKey _anchorKey = GlobalKey();

  final ValueNotifier<Rect?> _anchor = ValueNotifier(null);

  Timer? _opening;
  Timer? _closing;
  ScrollPosition? _scroll;
  Object? _anchorSyncToken;
  bool _suppressFocusOpen = false;

  bool get isShowing => _portal.isShowing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (identical(position, _scroll)) return;
    _scroll?.removeListener(_onScroll);
    _scroll = position?..addListener(_onScroll);
    _refreshAnchorAfterLayout();
  }

  @override
  void didUpdateWidget(HoverPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _cancelOpen();
    _refreshAnchorAfterLayout();
  }

  void _refreshAnchorAfterLayout() {
    if (!_portal.isShowing) return;
    final token = Object();
    _anchorSyncToken = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!identical(_anchorSyncToken, token)) return;
      _anchorSyncToken = null;
      if (!mounted || !_portal.isShowing) return;
      final anchor = _anchorRect();
      if (anchor == null || !widget.enabled) {
        close();
      } else {
        _anchor.value = anchor;
      }
    });
  }

  void _onScroll() {
    _cancelOpen();
    close();
  }

  void _cancelOpen() {
    _opening?.cancel();
    _opening = null;
  }

  void _scheduleOpen() {
    if (!widget.enabled) return;
    _closing?.cancel();
    _closing = null;
    if (_portal.isShowing || _opening != null) return;
    _opening = Timer(HoverPanel.openDelay, _open);
  }

  void open() {
    _cancelOpen();
    _closing?.cancel();
    _closing = null;
    if (!_portal.isShowing) _open();
  }

  void _open() {
    _opening = null;
    if (!widget.enabled) return;
    final anchor = _anchorRect();
    if (anchor == null) return;

    _anchor.value = anchor;
    if (!_portal.isShowing) _portal.show();
    widget.onOpen?.call();
  }

  void _scheduleClose() {
    _cancelOpen();
    if (!_portal.isShowing) return;
    _closing?.cancel();
    _closing = Timer(HoverPanel.closeDelay, close);
  }

  void close() {
    _cancelOpen();
    _closing?.cancel();
    _closing = null;
    if (!_portal.isShowing) return;
    // Dismissing a focused panel returns focus to its anchor. That return
    // must not immediately reopen the panel the user just dismissed.
    _suppressFocusOpen = true;
    _portal.hide();
  }

  void _anchorFocusChanged(bool focused) {
    if (focused) {
      if (!_suppressFocusOpen) open();
    } else {
      _suppressFocusOpen = false;
      _scheduleClose();
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _portal.isShowing) {
      close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Rect? _anchorRect() => anchorRect(
    anchor: _anchorKey.currentContext?.findRenderObject() as RenderBox?,
    overlay: Overlay.of(context).context.findRenderObject() as RenderBox?,
  );

  @override
  void dispose() {
    _anchorSyncToken = null;
    _opening?.cancel();
    _closing?.cancel();
    _scroll?.removeListener(_onScroll);
    _anchor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: _portal,
      onTapOutside: (_) => close(),
      child: Focus(
        canRequestFocus: false,
        onFocusChange: _anchorFocusChanged,
        onKeyEvent: _handleKey,
        child: MouseRegion(
          onEnter: (_) => _scheduleOpen(),
          onExit: (_) => _scheduleClose(),
          child: OverlayPortal(
            controller: _portal,
            overlayChildBuilder: (context) => ValueListenableBuilder<Rect?>(
              valueListenable: _anchor,
              builder: (context, anchor, child) => CustomSingleChildLayout(
                delegate: AnchoredLayout(
                  anchor: anchor,
                  maxWidth: widget.maxWidth,
                  preferAbove: widget.preferAbove,
                ),
                child: child!,
              ),
              child: TapRegion(
                groupId: _portal,
                child: Focus(
                  canRequestFocus: false,
                  onFocusChange: (focused) {
                    if (focused) {
                      _closing?.cancel();
                      _closing = null;
                    } else {
                      _scheduleClose();
                    }
                  },
                  onKeyEvent: _handleKey,
                  child: MouseRegion(
                    onEnter: (_) {
                      _closing?.cancel();
                      _closing = null;
                    },
                    onExit: (_) => _scheduleClose(),
                    child: Builder(builder: widget.panelBuilder),
                  ),
                ),
              ),
            ),
            child: KeyedSubtree(key: _anchorKey, child: widget.child),
          ),
        ),
      ),
    );
  }
}
