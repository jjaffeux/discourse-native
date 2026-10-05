import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

import '../styleguide_example.dart';

final alphabetIndexExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'Jump through a list by pressing or dragging its alphabet index.',
  notes:
      'The index owns its visible bounds, drag feedback, keyboard and semantics. '
      'The caller scrolls its list and suspends row interaction while scrubbing. '
      'Arrow keys, Home and End navigate; Enter and Space activate the current entry.',
  examples: [
    StyleguideExample(
      title: 'Press, drag and keyboard',
      description:
          'Drag along the letters, or focus the index and use arrow keys.',
      states: const ['Press', 'Drag', 'Keyboard', 'Text scaling', 'RTL'],
      code: '''DAlphabetIndex<String>(
  entries: [
    DAlphabetIndexEntry(value: 'bookmarks', label: 'B'),
    DAlphabetIndexEntry(value: 'categories', label: 'C'),
  ],
  onSelected: jumpToSection,
)''',
      builder: (_) => const _Example(),
    ),
  ],
);

class _Example extends StatefulWidget {
  const _Example();
  @override
  State<_Example> createState() => _ExampleState();
}

class _ExampleState extends State<_Example> {
  String _selected = 'Bookmarks';
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(_selected),
      DAlphabetIndex<String>(
        entries: const [
          DAlphabetIndexEntry(value: 'Bookmarks', label: 'B'),
          DAlphabetIndexEntry(value: 'Categories', label: 'C'),
          DAlphabetIndexEntry(value: 'Groups', label: 'G'),
          DAlphabetIndexEntry(value: 'Messages', label: 'M'),
          DAlphabetIndexEntry(value: 'Users', label: 'U'),
        ],
        onSelected: (value) => setState(() => _selected = value),
      ),
    ],
  );
}
