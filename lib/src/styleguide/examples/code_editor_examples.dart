import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter/widgets.dart';

import '../styleguide_example.dart';

final codeEditorExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'Native code editing with highlighting, line numbers and indentation.',
  notes:
      'Wraps the existing post code editor engine. Own and dispose the controller. '
      'Use a bounded height. Long lines scroll horizontally; source always reads left to right.',
  examples: [
    StyleguideExample(
      title: 'Editable code',
      description: 'Edit code, select text, indent with Tab and undo changes.',
      states: const ['Light', 'Dark', 'Narrow', 'Keyboard'],
      code: "DCodeEditor(controller: controller)",
      builder: (_) => const _CodeExample(),
    ),
    StyleguideExample(
      title: 'Read-only code',
      description:
          'The same editor is used by the fullscreen post code viewer.',
      states: const ['Read-only'],
      code: "DCodeEditor(controller: controller, readOnly: true)",
      builder: (_) => const _CodeExample(readOnly: true),
    ),
    StyleguideExample(
      title: 'Long code viewer',
      description:
          'Scroll through a complete numbered source with visible-line layout.',
      states: const ['Read-only', 'Selection', 'Large text'],
      code:
          'SelectionArea(child: DScrollArea(child: DCodeViewer(source: source)))',
      builder: (_) => SizedBox(
        height: 280,
        child: SelectionArea(
          contextMenuBuilder: (context, region) => const SizedBox.shrink(),
          child: DScrollArea(
            child: DCodeViewer(
              source: List.generate(
                500,
                (index) => 'final value$index = $index;',
              ).join('\n'),
              lineNumbers: List.generate(500, (index) => index + 78),
              highlightedLines: const {2, 499},
            ),
          ),
        ),
      ),
    ),
  ],
);

class _CodeExample extends StatefulWidget {
  const _CodeExample({this.readOnly = false});
  final bool readOnly;
  @override
  State<_CodeExample> createState() => _CodeExampleState();
}

class _CodeExampleState extends State<_CodeExample> {
  late final _controller = DCodeEditingController(
    text: "void main() {\n  print('Hello, Discourse!');\n}",
    language: 'dart',
    readOnly: widget.readOnly,
  );
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 280,
    child: DCodeEditor(controller: _controller, readOnly: widget.readOnly),
  );
}
