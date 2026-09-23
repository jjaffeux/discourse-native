import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

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
      title: 'Long-press content',
      description:
          'On touch, hold the paragraph and move it into the destination. A quick swipe remains available for scrolling.',
      states: const ['Touch', 'Light', 'Dark'],
      code:
          'DLongPressDragRegion<int>(dataAt: dataAt, onStart: start, onMove: move, onDrop: drop, onEnd: end, child: content)',
      builder: (_) => const _LongPressExample(),
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
  const _DragExample();
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
              _handle(),
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
    data: 1,
    label: 'Move paragraph',
    onPressed: _place,
    onDragStarted: () => setState(() => _dragging = true),
    onDragEnd: () {
      if (mounted) setState(() => _dragging = false);
    },
  );
}

class _LongPressExample extends StatefulWidget {
  const _LongPressExample();

  @override
  State<_LongPressExample> createState() => _LongPressExampleState();
}

class _LongPressExampleState extends State<_LongPressExample> {
  final _source = GlobalKey();
  final _destination = GlobalKey();
  bool _dragging = false;
  bool _over = false;
  bool _placed = false;

  bool _contains(GlobalKey key, Offset position) {
    final box = key.currentContext?.findRenderObject();
    return box is RenderBox &&
        (Offset.zero & box.size).contains(box.globalToLocal(position));
  }

  void _place() => setState(() => _placed = true);

  @override
  Widget build(BuildContext context) => DLongPressDragRegion<int>(
    dataAt: (position) => _contains(_source, position) ? 1 : null,
    onStart: (_) {
      setState(() => _dragging = true);
      return true;
    },
    onMove: (_, position) =>
        setState(() => _over = _contains(_destination, position)),
    onDrop: (_, position) {
      if (_contains(_destination, position)) _place();
    },
    onEnd: () => setState(() {
      _dragging = false;
      _over = false;
    }),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          key: _source,
          children: [
            const Padding(
              padding: EdgeInsets.all(DSpacing.md),
              child: Text('Hold this paragraph, then move your finger down.'),
            ),
            if (_dragging) const Positioned.fill(child: DDragHighlight()),
          ],
        ),
        const SizedBox(height: DSpacing.md),
        DCard(
          key: _destination,
          child: Column(
            children: [
              if (_over) const DDropIndicator(),
              Text(_placed ? 'Paragraph placed' : 'Drop here'),
            ],
          ),
        ),
        DButton(
          label: Text(_placed ? 'Reset' : 'Move paragraph here'),
          onPressed: _placed ? () => setState(() => _placed = false) : _place,
        ),
      ],
    ),
  );
}
