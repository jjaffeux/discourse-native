import 'package:flutter/widgets.dart';

import '../foundation/app_text_scaler.dart';
import 'd_mobile_dock.dart';
import 'd_scroll_chrome.dart';

/// Places a phone composer above the open navigation dock and beside its
/// collapsed destination. Only the composer rebuilds as chrome folds away.
class DComposerDock extends StatefulWidget {
  const DComposerDock({super.key, required this.builder});

  final Widget Function(BuildContext context, bool compact) builder;

  /// Gap above the visible composer inside the measured dock.
  static const topInset = 6.0;

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
  Widget build(BuildContext context) =>
      DReferenceTextScale(child: Builder(builder: _buildComposer));

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
          compact ? 6 + DMobileDock.collapsedExtentOf(context) + 8 : 6,
          DComposerDock.topInset,
          6,
          keyboard
              ? 6
              : compact || _focus.hasFocus
              ? safeBottom + 6
              // The shell's measured footer includes its 6px upper inset.
              // The visible capsule and composer are separated by 8px.
              : (room > 0 ? room : safeBottom + 74) + 2,
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
