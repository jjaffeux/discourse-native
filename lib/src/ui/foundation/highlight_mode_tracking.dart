import 'package:flutter/widgets.dart';

/// Decides, as [FocusableActionDetector] does, whether a hovered or focused
/// control may show its highlight: only while the focus highlight mode is
/// traditional. The detector listens to that mode from mount to dispose and
/// registers a global key and a post-frame callback per mount, which a list
/// pays for every link and row it scrolls in. This listens only while the
/// control is hovered or focused, when a change of mode can change what it
/// shows.
mixin DHighlightModeTracking<T extends StatefulWidget> on State<T> {
  bool _listening = false;

  /// Whether the current focus highlight mode lets a highlight show.
  bool get highlightModeShowsHighlight =>
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  /// Call whenever the control becomes or stops being hovered or focused.
  void trackHighlightMode({required bool engaged}) {
    if (engaged == _listening) return;
    _listening = engaged;
    if (engaged) {
      FocusManager.instance.addHighlightModeListener(_highlightModeChanged);
    } else {
      FocusManager.instance.removeHighlightModeListener(_highlightModeChanged);
    }
  }

  void _highlightModeChanged(FocusHighlightMode mode) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_listening) {
      FocusManager.instance.removeHighlightModeListener(_highlightModeChanged);
    }
    super.dispose();
  }
}
