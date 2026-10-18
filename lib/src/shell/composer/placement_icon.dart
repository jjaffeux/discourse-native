import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

import '../../models/composer_placement.dart';
import '../../models/forum_workspace.dart';
import '../shell_scope.dart';
import 'presentation.dart';

/// Shares the desktop panel glyph and its live window visibility.
class ComposerPlacementIcon extends StatelessWidget {
  const ComposerPlacementIcon({
    super.key,
    required this.placement,
    this.minimized = false,
  });
  final ComposerPlacement placement;
  final bool minimized;
  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    final layout = ComposerPresentationHost.panelsLayoutOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([shell, ?layout]),
      builder: (context, _) {
        final active = shell.activeTab?.panel ?? ForumPanel.main;
        final split = layout?.splitVisible ?? shell.topicPanelsVisible;
        return DLayoutGlyph(
          mainVisible: split || active == ForumPanel.main,
          secondaryVisible: split || active == ForumPanel.secondary,
          changingPanel: active.index,
          dock: minimized
              ? DLayoutGlyphDock.bottom
              : switch (placement) {
                  ComposerPlacement.left => DLayoutGlyphDock.left,
                  ComposerPlacement.right => DLayoutGlyphDock.right,
                  ComposerPlacement.bottom => DLayoutGlyphDock.bottom,
                  ComposerPlacement.fullScreen => DLayoutGlyphDock.full,
                },
        );
      },
    );
  }
}
