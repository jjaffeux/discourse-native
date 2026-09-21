import 'package:discourse_native/discourse_ui.dart';
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
