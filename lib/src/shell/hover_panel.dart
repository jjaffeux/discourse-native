import 'dart:async';

import 'package:flutter/material.dart';

import 'anchored_layout.dart';

/// Something small that opens a panel when the pointer rests on it.
///
/// Extracted from the likes count so the reactions row, its reactor list and
/// the picker are not each carrying their own copy of the timers — there is one
/// answer to how long a hover has to last, and it is here.
///
/// Touch is not handled: a pointer is the only thing that can hover, and the
/// touch equivalent is a sheet, which is a different surface with a different
/// shape. Callers wrap this in their own long-press detector.
class HoverPanel extends StatefulWidget {
  const HoverPanel({
    super.key,
    required this.child,
    required this.panelBuilder,
    this.maxWidth = 260,
    this.onOpen,
  });

  /// How long the pointer has to rest before the panel opens.
  ///
  /// Long enough that crossing on the way somewhere else does not open it, and
  /// does not spend a request finding out. Discourse's reactions plugin waits
  /// the same 250ms.
  static const Duration openDelay = Duration(milliseconds: 250);

  /// And how long it stays open after the pointer leaves.
  ///
  /// The panel is separated from its anchor by a gap, so moving onto it means
  /// leaving both for a moment. This is what bridges that; entering the panel
  /// cancels it.
  static const Duration closeDelay = Duration(milliseconds: 500);

  /// What is hovered.
  final Widget child;

  /// What floats above it.
  final WidgetBuilder panelBuilder;

  final double maxWidth;

  /// Called every time the panel opens — which is where a caller refetches
  /// whatever it is about to show.
  final VoidCallback? onOpen;

  @override
  State<HoverPanel> createState() => HoverPanelState();
}

class HoverPanelState extends State<HoverPanel> {
  final OverlayPortalController _portal = OverlayPortalController();
  final GlobalKey _anchorKey = GlobalKey();

  /// Where the panel should sit, in the overlay's coordinates.
  final ValueNotifier<Rect?> _anchor = ValueNotifier(null);

  Timer? _opening;
  Timer? _closing;
  ScrollPosition? _scroll;
  Object? _anchorSyncToken;

  /// Whether the panel is up, for a caller deciding whether what it is showing
  /// is worth refreshing.
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
      if (anchor == null) {
        close();
      } else {
        _anchor.value = anchor;
      }
    });
  }

  /// A panel pinned to a row that is moving reads as broken. Discourse's own
  /// closes on scroll for the same reason.
  void _onScroll() {
    _cancelOpen();
    close();
  }

  /// Cancelling and forgetting go together everywhere: a cancelled timer left
  /// in [_opening] reads as one still counting down, and [_scheduleOpen]
  /// declines to arm another while it is there.
  void _cancelOpen() {
    _opening?.cancel();
    _opening = null;
  }

  void _scheduleOpen() {
    _closing?.cancel();
    _closing = null;
    if (_portal.isShowing || _opening != null) return;
    _opening = Timer(HoverPanel.openDelay, _open);
  }

  void _open() {
    _opening = null;
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

  /// Cancels the pending close as well as closing, since this is also reached
  /// from a scroll rather than only from the timer itself — an orphaned one
  /// would come back later and shut a panel reopened in the meantime.
  void close() {
    _closing?.cancel();
    _closing = null;
    if (!_portal.isShowing) return;
    _portal.hide();
  }

  /// The anchor's rectangle, in the coordinates the overlay lays its children
  /// out in. Null before it has been laid out, or once it no longer is.
  Rect? _anchorRect() {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || !box.hasSize || !box.attached) {
      return null;
    }
    return Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
  }

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
    return MouseRegion(
      onEnter: (_) => _scheduleOpen(),
      onExit: (_) => _scheduleClose(),
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => ValueListenableBuilder<Rect?>(
          valueListenable: _anchor,
          builder: (context, anchor, child) => CustomSingleChildLayout(
            delegate: AnchoredLayout(anchor: anchor, maxWidth: widget.maxWidth),
            child: child!,
          ),
          child: MouseRegion(
            onEnter: (_) => _closing?.cancel(),
            onExit: (_) => _scheduleClose(),
            child: Builder(builder: widget.panelBuilder),
          ),
        ),
        child: KeyedSubtree(key: _anchorKey, child: widget.child),
      ),
    );
  }
}
