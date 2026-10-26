import 'package:flutter/widgets.dart';

import '../foundation/app_text_scaler.dart';
import 'd_mobile_dock_geometry.dart';
import 'd_scroll_chrome.dart';

/// Places a phone composer above the open navigation bar and, folded, beside
/// its circle in the screen's corner. Only the composer rebuilds as chrome
/// folds away.
class DComposerDock extends StatefulWidget {
  const DComposerDock({super.key, required this.builder});

  final Widget Function(BuildContext context, bool compact) builder;

  /// Gap above the visible composer inside the measured dock.
  static const topInset = 6.0;

  /// The bar beside and above the composer. The dock keeps the shell's text
  /// scale while the composer uses its reference scale, so the bar is
  /// measured outside the composer's scale.
  static DMobileDockGeometry geometryOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DockGeometry>()?.geometry ??
      DMobileDockGeometry.of(context);

  /// Height of the folded dock beside a compact composer.
  static double foldedDockExtentOf(BuildContext context) =>
      geometryOf(context).circle;

  @override
  State<DComposerDock> createState() => _DComposerDockState();
}

class _DComposerDockState extends State<DComposerDock> {
  DScrollChromeController? _chrome;
  final _focus = FocusNode(canRequestFocus: false);
  final _contentKey = GlobalKey();
  bool _compact = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    _syncFooterVisibility();
    setState(() => _compact = _shouldCompact);
  }

  void _syncFooterVisibility() => _chrome?.setFooterHidden(
    this,
    hidden:
        TickerMode.valuesOf(context).enabled &&
        (_focus.hasFocus || MediaQuery.viewInsetsOf(context).bottom > 0),
  );

  bool get _shouldCompact =>
      !_focus.hasFocus &&
      MediaQuery.viewInsetsOf(context).bottom == 0 &&
      (_chrome?.hiddenFraction ?? 0) >= .5;

  void _changed() {
    final compact = _shouldCompact;
    if (_compact != compact) setState(() => _compact = compact);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chrome = DScrollChrome.maybeOf(context);
    if (!identical(chrome, _chrome)) {
      _chrome?.setFooterHidden(this, hidden: false);
      _chrome?.removeListener(_changed);
      _chrome = chrome?..addListener(_changed);
    }
    _syncFooterVisibility();
    _compact = _shouldCompact;
  }

  @override
  void dispose() {
    _chrome?.setFooterHidden(this, hidden: false);
    _chrome?.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _DockGeometry(
    geometry: DMobileDockGeometry.of(context),
    child: DReferenceTextScale(child: Builder(builder: _buildComposer)),
  );

  Widget _buildComposer(BuildContext context) {
    final chrome = _chrome;
    final room = DScrollChrome.bottomInsetOf(context);
    if (chrome == null) {
      return SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, DComposerDock.topInset, 12, 12),
        child: widget.builder(context, false),
      );
    }
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final geometry = DComposerDock.geometryOf(context);
    // Beside the folded circle, level with it: past its width and a gap, and
    // as far in from the other side as the circle is from its own.
    final corner = geometry.cornerAt(geometry.circle);
    final compact = _compact;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final duration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 420);
    const curve = Cubic(.32, .72, 0, 1);
    final content = KeyedSubtree(
      key: _contentKey,
      child: widget.builder(context, compact),
    );
    return Focus(
      focusNode: _focus,
      child: AnimatedPadding(
        duration: duration,
        curve: curve,
        padding: EdgeInsetsDirectional.fromSTEB(
          compact ? corner + geometry.circle + 8 : 6,
          DComposerDock.topInset,
          compact ? corner : 6,
          keyboard
              ? 6
              : compact
              ? corner
              : _focus.hasFocus
              ? safeBottom + 6
              // The shell's measured footer includes the bar's upper margin.
              // The visible bar and composer are separated by 8px.
              : (room > 0 ? room : geometry.footerExtent) +
                    8 -
                    geometry.margin.top,
        ),
        child: reduced
            ? content
            : AnimatedSize(
                duration: duration,
                curve: curve,
                alignment: Alignment.bottomCenter,
                child: content,
              ),
      ),
    );
  }
}

class _DockGeometry extends InheritedWidget {
  const _DockGeometry({required this.geometry, required super.child});

  final DMobileDockGeometry geometry;

  @override
  bool updateShouldNotify(_DockGeometry oldWidget) =>
      geometry != oldWidget.geometry;
}
