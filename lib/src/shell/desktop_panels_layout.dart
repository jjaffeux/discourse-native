import 'package:flutter/foundation.dart';

import '../foundation/frame_safe_notifier.dart';
import '../models/forum_workspace.dart';
import 'resizable_pane.dart';
import 'shell_metrics.dart';

/// The split between the desktop panels and which of them is minimized.
///
/// Both belong to the window rather than to the panels showing them, so they
/// outlive views that replace the panels for a while, such as a forum's sign-in
/// gate. Neither is persisted. The panels that show this layout are its only
/// writer; every other reader takes the split and its toggle.
final class DesktopPanelsLayout extends FrameSafeNotifier {
  final mainWidth = PanelWidthController(
    initialWidth: 400 + workspacePanelGap,
    minimumWidth: 320 + workspacePanelGap,
  );

  // Only one panel stands down at a time, or there would be nothing left to
  // read.
  ForumPanel leading = ForumPanel.main;
  ForumPanel? minimized;
  VoidCallback? toggle;
  bool _splitVisible = false;
  bool _canToggleSplit = false;

  bool get splitVisible => _splitVisible;
  bool get canToggleSplit => _canToggleSplit && toggle != null;

  void toggleSplit() {
    if (canToggleSplit) toggle!();
  }

  void present({required bool visible, required bool enabled}) {
    if (_splitVisible == visible && _canToggleSplit == enabled) return;
    _splitVisible = visible;
    _canToggleSplit = enabled;
    notifySafely();
  }

  @override
  void dispose() {
    mainWidth.dispose();
    super.dispose();
  }
}
