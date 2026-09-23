import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

import '../../theme/d_icons.dart';
import '../styleguide_example.dart';

final dragExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'Typed drag handles and insertion boundaries for movable content.',
  notes:
      'Keep text outside the handle. Always provide a tap or keyboard action. '
      'Handles show an open hand on hover and a fist while pressed or dragging. '
      'DDragHighlight tints the source while DDropIndicator marks its destination. '
      'The application validates the snapshot and commits the move once on drop.',
  examples: [
    StyleguideExample(
      title: 'Drag and tap',
      description:
          'Drag the handle into the target, or activate it to place the block.',
      states: const ['Light', 'Dark', 'Touch', 'Keyboard', 'RTL'],
      code:
          'DDragHandle<int>(data: 1, label: "Move paragraph", onPressed: place)',
      builder: (_) => const _DragExample(),
    ),
    StyleguideExample(
      title: 'Compact composer actions',
      description:
          'Desktop-only narrow hit zones retain regular icons and height. '
          'Touch platforms retain the normal accessible targets.',
      states: const ['Light', 'Dark', 'Keyboard', 'Touch'],
      code:
          'DDragHandle<int>(density: DButtonDensity.composerBlock, '
          'data: 1, label: "Move paragraph", onPressed: place)',
      builder: (_) => const _DragExample(compact: true),
    ),
    StyleguideExample(
      title: 'Disabled',
      description: 'Unavailable handles cannot start a drag or action.',
      states: const ['Disabled'],
      code:
          'DDragHandle<int>(data: 1, label: "Move paragraph", enabled: false, onPressed: null)',
      builder: (_) => const DDragHandle<int>(
        data: 1,
        label: 'Move paragraph',
        enabled: false,
        onPressed: null,
      ),
    ),
  ],
);

class _DragExample extends StatefulWidget {
  const _DragExample({this.compact = false});

  final bool compact;
  @override
  State<_DragExample> createState() => _DragExampleState();
}

class _DragExampleState extends State<_DragExample> {
  bool _over = false;
  bool _placed = false;
  bool _dragging = false;
  void _place() => setState(() {
    _placed = true;
    _over = false;
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Stack(
        children: [
          if (_dragging) const Positioned.fill(child: DDragHighlight()),
          Row(
            children: [
              if (widget.compact)
                DButton.iconOnly(
                  density: DButtonDensity.composerBlock,
                  variant: DButtonVariant.transparentBackground,
                  backgroundColor: const Color(0x00000000),
                  icon: const DIcon(DIcons.plus),
                  tooltip: 'Add block',
                  onPressed: _place,
                ),
              _handle(),
              const SizedBox(width: DSpacing.controlGap),
              const Expanded(
                child: Text(
                  'A paragraph remains selectable while its handle moves.',
                ),
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: DSpacing.md),
      DDragRegion<int>(
        accepts: (data) => data == 1,
        onMove: (_, _) => setState(() => _over = true),
        onLeave: () => setState(() => _over = false),
        onDrop: (_, _) => _place(),
        child: DCard(
          child: Column(
            children: [
              if (_over) const DDropIndicator(),
              Text(_placed ? 'Paragraph placed' : 'Drop here'),
            ],
          ),
        ),
      ),
      if (_placed)
        DButton(
          label: const Text('Reset'),
          onPressed: () => setState(() => _placed = false),
        ),
    ],
  );

  Widget _handle() => DDragHandle<int>(
    density: widget.compact
        ? DButtonDensity.composerBlock
        : DButtonDensity.standard,
    data: 1,
    label: 'Move paragraph',
    onPressed: _place,
    onDragStarted: () => setState(() => _dragging = true),
    onDragEnd: () {
      if (mounted) setState(() => _dragging = false);
    },
  );
}
