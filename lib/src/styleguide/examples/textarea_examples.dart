import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_chrome.dart';
import '../styleguide_example.dart';

final textareaExamples = ComponentExamples(
  status: ComponentStatus.baseline,
  description: 'A multiline field that grows with its content.',
  notes:
      'Source implementation is complete; rendered/native review is pending. '
      'Base-nova uses a 64px minimum, 10px horizontal/8px vertical padding plus '
      '1px border, rounded-lg (host radius), 14/20px desktop and 16/24px touch '
      'text. Focus and invalid rings extend 3px outside. Native TextField owns '
      'selection, IME, scrolling and keyboard behavior. Content grows by default; '
      'minLines/maxLines reserve and bound lines. Native layouts omit the browser '
      'resize grip. Controller/value/initialValue are exclusive. Form reset '
      'restores the mount snapshot and emits onChanged; equal parent strings '
      'preserve composition. Borrowed editing/focus/scroll/undo owners are never '
      'disposed. DLabel and native Form supply field composition while Field is '
      'pending; StyleguideAction is a temporary submit action while Button is '
      'pending. Neither is an invented Field/Button API.',
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
          'The reference label and description sit above the field. '
          'Tap Message to focus. This uses DLabel and native composition.',
      states: const ['Label', 'Description', 'Focus association'],
      code: '''// State owns and disposes final focus = FocusNode().
Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
  GestureDetector(onTap: focus.requestFocus,
    child: const ExcludeSemantics(child: DLabel(style: TextStyle(height: 1.375), child: Text('Message')))),
  const SizedBox(height: 8),
  const Text('Enter your message below.'),
  const SizedBox(height: 8),
  Semantics(label: 'Message', hint: 'Enter your message below.',
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
      title: 'Button and native Form',
      description:
          'Send an empty message to validate, then enter a message and '
          'send again to save locally. Reset restores the original empty text. '
          'StyleguideAction supplies the temporary submit action.',
      states: const ['Submit', 'Validation', 'Save', 'Reset'],
      code: '''// State owns form = GlobalKey<FormState>() and String? saved.
Form(key: form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    DTextarea(hintText: 'Type your message here.', isRequired: true,
      validator: (text) => text!.trim().isEmpty ? 'Enter a message.' : null,
      onSaved: (text) => saved = text),
    const SizedBox(height: 8),
    StyleguideAction(label: 'Send message', onPressed: () {
      if (form.currentState!.validate()) {
        form.currentState!.save();
        setState(() {});
      }
    }),
    StyleguideAction(label: 'Reset', onPressed: () {
      form.currentState!.reset();
      setState(() => saved = null);
    }),
    if (saved != null) Text('Saved: \$saved'),
  ]))''',
      builder: (_) => const _FormExample(),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'Arabic feedback, four reserved lines and a description. '
          'Native directional text editing follows the inherited direction.',
      states: const ['RTL', 'Rows', 'Description'],
      code: '''Directionality(textDirection: TextDirection.rtl,
  child: DTextarea(labelText: 'التعليقات',
    hintText: 'تعليقاتك تساعدنا على التحسين...', minLines: 4,
    helperText: 'شاركنا أفكارك حول خدمتنا.'))''',
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: DTextarea(
          labelText: 'التعليقات',
          hintText: 'تعليقاتك تساعدنا على التحسين...',
          minLines: 4,
          helperText: 'شاركنا أفكارك حول خدمتنا.',
        ),
      ),
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
  StyleguideAction(label: readOnly ? 'Enable editing' : 'Make read-only',
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GestureDetector(
        onTap: _focus.requestFocus,
        child: const ExcludeSemantics(
          child: DLabel(
            style: TextStyle(height: 1.375),
            child: Text('Message'),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Enter your message below.',
        style: styleguideText(context, height: 21, muted: true),
      ),
      const SizedBox(height: 8),
      Semantics(
        label: 'Message',
        hint: 'Enter your message below.',
        child: DTextarea(
          focusNode: _focus,
          hintText: 'Type your message here.',
        ),
      ),
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
      children: [
        DTextarea(
          hintText: 'Type your message here.',
          isRequired: true,
          validator: (text) => text!.trim().isEmpty ? 'Enter a message.' : null,
          onSaved: (text) => _saved = text,
        ),
        const SizedBox(height: 8),
        StyleguideAction(
          label: 'Send message',
          onPressed: () {
            if (_form.currentState!.validate()) {
              _form.currentState!.save();
              setState(() {});
            }
          },
        ),
        StyleguideAction(
          label: 'Reset',
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
      StyleguideAction(
        label: _readOnly ? 'Enable editing' : 'Make read-only',
        onPressed: () => setState(() => _readOnly = !_readOnly),
      ),
    ],
  );
}
