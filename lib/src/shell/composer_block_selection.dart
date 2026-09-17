import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

/// Keeps a block's selection visible above its embedded controls and surfaces.
class ComposerBlockSelection extends StatelessWidget {
  const ComposerBlockSelection({
    super.key,
    required this.selected,
    required this.child,
  });

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) => DItem(
    selected: selected,
    selectionStyle: DItemSelectionStyle.outline,
    shape: DItemShape.card,
    showSelectionIndicator: false,
    padding: EdgeInsets.zero,
    children: [
      DItemContent(spacing: 0, children: [child]),
    ],
  );
}
