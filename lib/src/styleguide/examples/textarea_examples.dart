import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final textareaExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'A multiline field that grows with its content.',
  notes:
      'Source, rendered reference, native macOS review and a 2026-09-09 '
      'reference audit are complete. Base-nova uses a 64px minimum, 10px '
      'horizontal/8px vertical padding plus 1px border, rounded-lg (host '
      'radius), 14/20px desktop and 16/24px touch text. Focus and invalid rings '
      'extend 3px outside and appear at once; border and fill colors ease over '
      '150ms. The box is editable edge to edge. Native TextField owns '
      'selection, IME, scrolling and keyboard behavior. Content grows by '
      'default; the reference rows attribute is inert under field-sizing: '
      'content, so minLines/maxLines are native extensions that reserve and '
      'bound lines. Native layouts omit the browser resize grip. '
      'Controller/value/initialValue are exclusive. Form reset restores the '
      'mount snapshot and emits onChanged; equal parent strings preserve '
      'composition. Borrowed editing/focus/scroll/undo owners are never '
      'disposed. Field composes DField, DFieldLabel, DFieldDescription and '
      'DFieldControl; DButton supplies the Button composition.',
  examples: [
    StyleguideExample(
      title: 'Default',
      description:
          'Type multiple lines or paste a long message. The field grows '
          'with content. Tab moves focus and Enter adds a newline.',
      states: const ['Empty', 'Placeholder', 'Focus', 'Content growth'],
      code: "DTextarea(hintText: 'Type your message here.')",
      builder: (_) => DTextarea(hintText: 'Type your message here.'),
    ),
    StyleguideExample(
      title: 'Field',
      description:
          'The reference Field places the label and description above the '
          'textarea with the Field gaps. Tap Message to focus; the editor '
          'announces the label and description as one control.',
      states: const ['Label', 'Description', 'Focus association'],
      code: '''// State owns and disposes final focus = FocusNode().
DField(children: [
  DFieldLabel(focusNode: focus, excludeSemantics: true,
    child: const Text('Message')),
  const DFieldDescription(child: Text('Enter your message below.')),
  DFieldControl(label: 'Message', description: 'Enter your message below.',
    child: DTextarea(focusNode: focus, hintText: 'Type your message here.')),
])''',
      builder: (_) => const _FieldExample(),
    ),
    StyleguideExample(
      title: 'Disabled',
      description:
          'A disabled Message label and textarea retain their contents '
          'and cannot be edited or focused.',
      states: const ['Disabled'],
      code:
          "DTextarea(labelText: 'Message', hintText: 'Type your message here.', enabled: false)",
      builder: (_) => DTextarea(
        labelText: 'Message',
        hintText: 'Type your message here.',
        enabled: false,
      ),
    ),
    StyleguideExample(
      title: 'Invalid',
      description:
          'Invalid semantics and an exterior destructive ring accompany '
          'a visible error. The error stays present when focused.',
      states: const ['Invalid', 'Error', 'Focus'],
      code:
          "DTextarea(labelText: 'Message', hintText: 'Type your message here.', invalid: true, helperText: 'Please enter a valid message.')",
      builder: (_) => DTextarea(
        labelText: 'Message',
        hintText: 'Type your message here.',
        invalid: true,
        helperText: 'Please enter a valid message.',
      ),
    ),
    StyleguideExample(
      title: 'Button',
      description:
          'The reference grid stretches Send message under the field with '
          'an 8px gap. Sending shows the text locally and clears the field.',
      states: const ['Composition', 'Send'],
      code: '''// State owns/disposes controller; String? sent.
Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
  DTextarea(controller: controller, hintText: 'Type your message here.'),
  DButton(label: const Text('Send message'),
    onPressed: () => setState(() {
      sent = controller.text;
      controller.clear();
    })),
  if (sent case final sent?) Text('Sent: \$sent'),
])''',
      builder: (_) => const _ButtonExample(),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'Arabic feedback with a label and description inside the '
          'reference 320px maximum. The reference rows attribute is inert under '
          'field-sizing: content, so the field keeps the 64px minimum. Native '
          'directional text editing follows the inherited direction.',
      states: const ['RTL', 'Description', 'Max width'],
      code: '''Align(alignment: AlignmentDirectional.centerStart,
  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 320),
    child: Directionality(textDirection: TextDirection.rtl,
      child: DTextarea(labelText: 'التعليقات',
        hintText: 'تعليقاتك تساعدنا على التحسين...',
        helperText: 'شاركنا أفكارك حول خدمتنا.'))))''',
      builder: (_) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: DTextarea(
              labelText: 'التعليقات',
              hintText: 'تعليقاتك تساعدنا على التحسين...',
              helperText: 'شاركنا أفكارك حول خدمتنا.',
            ),
          ),
        ),
      ),
    ),
    StyleguideExample(
      title: 'Form',
      description:
          'Send an empty message to validate, then enter a message and '
          'send again to save locally. Reset restores the original empty text. '
          'Native Form owns validation, save and reset.',
      states: const ['Submit', 'Validation', 'Save', 'Reset'],
      code: '''// State owns form = GlobalKey<FormState>() and String? saved.
Form(key: form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
  spacing: 8, children: [
    DTextarea(hintText: 'Type your message here.', isRequired: true,
      validator: (text) => text!.trim().isEmpty ? 'Enter a message.' : null,
      onSaved: (text) => saved = text),
    DButton(label: const Text('Send message'), onPressed: () {
      if (form.currentState!.validate()) {
        form.currentState!.save();
        setState(() {});
      }
    }),
    DButton(label: const Text('Reset'), onPressed: () {
      form.currentState!.reset();
      setState(() => saved = null);
    }),
    if (saved != null) Text('Saved: \$saved'),
  ]))''',
      builder: (_) => const _FormExample(),
    ),
    StyleguideExample(
      title: 'Bounded editing and read-only',
      description:
          'A borrowed controller keeps selection/composition. This '
          'field grows to four lines then scrolls; the counter counts graphemes. '
          'Toggle read-only to keep selection/copy while preventing edits.',
      states: const ['Controller', 'Max length', 'Scrolling', 'Read-only'],
      code: '''// State owns/disposes controller; bool readOnly = false.
Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
  DTextarea(controller: controller, labelText: 'Notes',
    minLines: 2, maxLines: 4, maxLength: 280, showCounter: true,
    readOnly: readOnly),
  DButton(label: Text(readOnly ? 'Enable editing' : 'Make read-only'),
    onPressed: () => setState(() => readOnly = !readOnly)),
])''',
      builder: (_) => const _BoundedExample(),
    ),
  ],
);

class _FieldExample extends StatefulWidget {
  const _FieldExample();
  @override
  State<_FieldExample> createState() => _FieldExampleState();
}

class _FieldExampleState extends State<_FieldExample> {
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DField(
    children: [
      DFieldLabel(
        focusNode: _focus,
        excludeSemantics: true,
        child: const Text('Message'),
      ),
      const DFieldDescription(child: Text('Enter your message below.')),
      DFieldControl(
        label: 'Message',
        description: 'Enter your message below.',
        child: DTextarea(
          focusNode: _focus,
          hintText: 'Type your message here.',
        ),
      ),
    ],
  );
}

class _ButtonExample extends StatefulWidget {
  const _ButtonExample();
  @override
  State<_ButtonExample> createState() => _ButtonExampleState();
}

class _ButtonExampleState extends State<_ButtonExample> {
  final _controller = TextEditingController();
  String? _sent;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 8,
    children: [
      DTextarea(controller: _controller, hintText: 'Type your message here.'),
      DButton(
        label: const Text('Send message'),
        onPressed: () => setState(() {
          _sent = _controller.text;
          _controller.clear();
        }),
      ),
      if (_sent case final sent?) Text('Sent: $sent'),
    ],
  );
}

class _FormExample extends StatefulWidget {
  const _FormExample();
  @override
  State<_FormExample> createState() => _FormExampleState();
}

class _FormExampleState extends State<_FormExample> {
  final _form = GlobalKey<FormState>();
  String? _saved;
  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        DTextarea(
          hintText: 'Type your message here.',
          isRequired: true,
          validator: (text) => text!.trim().isEmpty ? 'Enter a message.' : null,
          onSaved: (text) => _saved = text,
        ),
        DButton(
          label: const Text('Send message'),
          onPressed: () {
            if (_form.currentState!.validate()) {
              _form.currentState!.save();
              setState(() {});
            }
          },
        ),
        DButton(
          label: const Text('Reset'),
          onPressed: () {
            _form.currentState!.reset();
            setState(() => _saved = null);
          },
        ),
        if (_saved != null) Text('Saved: $_saved'),
      ],
    ),
  );
}

class _BoundedExample extends StatefulWidget {
  const _BoundedExample();
  @override
  State<_BoundedExample> createState() => _BoundedExampleState();
}

class _BoundedExampleState extends State<_BoundedExample> {
  final _controller = TextEditingController(text: 'First line\nSecond line');
  bool _readOnly = false;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DTextarea(
        controller: _controller,
        labelText: 'Notes',
        minLines: 2,
        maxLines: 4,
        maxLength: 280,
        showCounter: true,
        readOnly: _readOnly,
      ),
      DButton(
        label: Text(_readOnly ? 'Enable editing' : 'Make read-only'),
        onPressed: () => setState(() => _readOnly = !_readOnly),
      ),
    ],
  );
}
