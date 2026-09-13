import 'package:discourse_native/discourse_ui.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final inputExamples = ComponentExamples(
  topLevelExampleIndex: 8,
  status: ComponentStatus.implemented,
  description: 'A text input for forms and everyday data entry.',
  notes:
      'DInput is single-line. Use a controller for selection and IME state, '
      'value for parent updates, or initialValue for local editing. Form owns '
      'validation, save and reset. Labels stay above the input. Read-only fields '
      'remain selectable; disabled fields do not accept interaction. '
      'Field, Badge, Input Group and Button Group compositions remain owned by '
      'their catalogue tasks; the inline slots here support simple app search '
      'and status controls. File selection uses the native host picker and '
      'returns display names; it never uploads data. Reference base-nova: '
      '32px minimum height, 14/20px desktop type, 10px horizontal inset and '
      '3px focus/invalid ring. The full box takes the text cursor and focuses '
      'from its inset; the ring appears immediately while colors ease. Large '
      'text grows naturally.',
  examples: [
    StyleguideExample(
      title: 'Borderless editing',
      description: 'Edit text in place without a field border or inset.',
      code:
          "DInput(borderless: true, initialValue: 'Editable title', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))",
      builder: (_) => DInput(
        borderless: true,
        initialValue: 'Editable title',
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      states: const ['Default', 'Focus', 'Selection'],
    ),
    StyleguideExample(
      title: 'Basic',
      description:
          'Click anywhere in the box to enter text, select it, and use native copy and paste.',
      code: "DInput(hintText: 'Enter text')",
      builder: (_) => DInput(hintText: 'Enter text'),
      states: const ['Default', 'Focus', 'Selection', 'IME'],
    ),
    StyleguideExample(
      title: 'Field and states',
      description:
          'Static labels and descriptions accompany enabled, disabled, invalid and read-only inputs.',
      code: """Column(children: [
  DInput(labelText: 'Username', hintText: 'Enter your username',
    helperText: 'Choose a unique username for your account.'),
  const SizedBox(height: 20),
  DInput(labelText: 'Email', hintText: 'Email', enabled: false),
  const SizedBox(height: 20),
  DInput(labelText: 'Invalid Input', initialValue: 'Error',
    errorText: 'This field contains validation errors.'),
  const SizedBox(height: 20),
  DInput(labelText: 'Read-only', initialValue: 'Select and copy me', readOnly: true),
])""",
      builder: (_) => Column(
        children: [
          DInput(
            labelText: 'Username',
            hintText: 'Enter your username',
            helperText: 'Choose a unique username for your account.',
          ),
          const SizedBox(height: 20),
          DInput(labelText: 'Email', hintText: 'Email', enabled: false),
          const SizedBox(height: 20),
          DInput(
            labelText: 'Invalid Input',
            initialValue: 'Error',
            errorText: 'This field contains validation errors.',
          ),
          const SizedBox(height: 20),
          DInput(
            labelText: 'Read-only',
            initialValue: 'Select and copy me',
            readOnly: true,
          ),
        ],
      ),
      states: const ['Disabled', 'Invalid', 'Read-only'],
    ),
    StyleguideExample(
      title: 'Form, required and grid',
      description:
          'Submit to validate required fields, save locally, or reset. Fields stack at narrow widths.',
      code: _formCode,
      builder: (_) => const InputFormExample(),
      states: const ['Required', 'Validation', 'Save', 'Reset', 'Grid'],
    ),
    StyleguideExample(
      title: 'Secure and controlled editing',
      description:
          'Reveal the password or replace the controlled value. Selection survives unrelated rebuilds.',
      code: _editingCode,
      builder: (_) => const _EditingExample(),
      states: const ['Password', 'Controlled', 'Controller'],
    ),
    StyleguideExample(
      title: 'Inline search and composition',
      description:
          'Submit a search with Return or the adjacent button. Clear keeps editing focus.',
      code: _searchCode,
      builder: (_) => const _SearchExample(),
      states: const ['Inline', 'Prefix', 'Suffix', 'Keyboard'],
    ),
    StyleguideExample(
      title: 'File',
      description:
          'Choose a file with the native picker. Only its name is displayed; nothing is uploaded.',
      code: """DFileInput(onPick: () async {
  final file = await openFile();
  return file == null ? null : [file.name];
})""",
      builder: (_) => DFileInput(
        onPick: () async {
          final file = await openFile();
          return file == null ? null : [file.name];
        },
      ),
      states: const ['File', 'Cancel', 'Native picker'],
    ),
    StyleguideExample(
      title: 'RTL and long text',
      description:
          'Edit mixed Arabic and Latin text. Try 200% text and the narrow viewport controls.',
      code: """Directionality(textDirection: TextDirection.rtl, child: DInput(
  labelText: 'مفتاح API',
  initialValue: 'sk-example-هذا-نص-طويل-1234567890-abcdefghijklmnopqrstuvwxyz',
  helperText: 'مفتاح API الخاص بك مشفر ومخزن بأمان.',
))""",
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: DInput(
          labelText: 'مفتاح API',
          initialValue:
              'sk-example-هذا-نص-طويل-1234567890-abcdefghijklmnopqrstuvwxyz',
          helperText: 'مفتاح API الخاص بك مشفر ومخزن بأمان.',
        ),
      ),
      states: const ['RTL', 'Long text', 'Text scaling', 'Narrow'],
    ),
    StyleguideExample(
      title: 'Reference demo',
      description:
          'The canonical API-key field combines a label, secure input, and supporting description.',
      states: const ['Password', 'Placeholder', 'Field composition'],
      code: '''DField(children: [
  DFieldLabel(focusNode: focusNode, child: const Text('API Key')),
  DFieldControl(
    label: 'API Key',
    description: 'Your API key is encrypted and stored securely.',
    child: DInput(
      focusNode: focusNode,
      obscureText: true,
      hintText: 'sk-...',
    ),
  ),
  const DFieldDescription(
    child: Text('Your API key is encrypted and stored securely.'),
  ),
])''',
      builder: (_) => const _InputReferenceDemo(),
    ),
  ],
);

class _InputReferenceDemo extends StatefulWidget {
  const _InputReferenceDemo();

  @override
  State<_InputReferenceDemo> createState() => _InputReferenceDemoState();
}

class _InputReferenceDemoState extends State<_InputReferenceDemo> {
  final _focusNode = FocusNode(debugLabel: 'API key');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 384),
    child: DField(
      children: [
        DFieldLabel(focusNode: _focusNode, child: const Text('API Key')),
        DFieldControl(
          label: 'API Key',
          description: 'Your API key is encrypted and stored securely.',
          child: DInput(
            focusNode: _focusNode,
            obscureText: true,
            hintText: 'sk-...',
          ),
        ),
        const DFieldDescription(
          child: Text('Your API key is encrypted and stored securely.'),
        ),
      ],
    ),
  );
}

class InputFormExample extends StatefulWidget {
  const InputFormExample({super.key});
  @override
  State<InputFormExample> createState() => _InputFormExampleState();
}

class _InputFormExampleState extends State<InputFormExample> {
  final _form = GlobalKey<FormState>();
  final _nameField = GlobalKey<FormFieldState<String>>();
  final _emailField = GlobalKey<FormFieldState<String>>();
  String _name = '', _email = '', _result = '';
  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final fields = [
              DInput(
                key: _nameField,
                labelText: 'Name *',
                isRequired: true,
                hintText: 'Jordan Lee',
                textInputAction: TextInputAction.next,
                validator: (v) => v!.trim().isEmpty ? 'Enter your name.' : null,
                onSaved: (v) => _name = v!,
              ),
              DInput(
                key: _emailField,
                labelText: 'Email *',
                isRequired: true,
                hintText: 'name@example.com',
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                validator: (v) =>
                    v!.contains('@') ? null : 'Enter a valid email.',
                onSaved: (v) => _email = v!,
              ),
            ];
            return constraints.maxWidth < 480
                ? Column(
                    children: [
                      fields[0],
                      const SizedBox(height: 20),
                      fields[1],
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: fields[0]),
                      const SizedBox(width: 16),
                      Expanded(child: fields[1]),
                    ],
                  );
          },
        ),
        const SizedBox(height: 20),
        DInput(
          labelText: 'Phone',
          keyboardType: TextInputType.phone,
          hintText: '+1 (555) 123-4567',
        ),
        const SizedBox(height: 20),
        DInput(
          labelText: 'Address',
          autofillHints: const [AutofillHints.fullStreetAddress],
          hintText: '123 Main St',
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DButton(
              label: const Text('Reset'),
              onPressed: () {
                _form.currentState!.reset();
                setState(() => _result = 'Form reset');
              },
            ),
            DButton(
              label: const Text('Submit'),
              onPressed: () {
                if (_form.currentState!.validate()) {
                  _form.currentState!.save();
                  setState(() => _result = 'Saved $_name · $_email');
                }
              },
            ),
          ],
        ),
        if (_result.isNotEmpty) ...[const SizedBox(height: 12), Text(_result)],
      ],
    ),
  );
}

class _EditingExample extends StatefulWidget {
  const _EditingExample();
  @override
  State<_EditingExample> createState() => _EditingExampleState();
}

class _EditingExampleState extends State<_EditingExample> {
  final _password = TextEditingController(text: 'correct horse battery staple');
  bool _hidden = true;
  String _value = 'Parent-owned value';
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      DInput(
        controller: _password,
        labelText: 'Password',
        obscureText: _hidden,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const [AutofillHints.password],
      ),
      const SizedBox(height: 8),
      DButton(
        label: Text(_hidden ? 'Show password' : 'Hide password'),
        onPressed: () => setState(() => _hidden = !_hidden),
      ),
      const SizedBox(height: 20),
      DInput(
        labelText: 'Controlled value',
        value: _value,
        onChanged: (v) => setState(() => _value = v),
      ),
      const SizedBox(height: 8),
      DButton(
        label: const Text('Replace value'),
        onPressed: () => setState(() => _value = 'Updated by parent'),
      ),
    ],
  );
}

class _SearchExample extends StatefulWidget {
  const _SearchExample();
  @override
  State<_SearchExample> createState() => _SearchExampleState();
}

class _SearchExampleState extends State<_SearchExample> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _result = '';
  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _search() => setState(() => _result = 'Search: ${_controller.text}');
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: DInput(
              controller: _controller,
              focusNode: _focus,
              hintText: 'Search...',
              textInputAction: TextInputAction.search,
              prefix: const Icon(Icons.search, size: 16),
              onSubmitted: (_) => _search(),
            ),
          ),
          const SizedBox(width: 8),
          DButton(label: const Text('Search'), onPressed: _search),
        ],
      ),
      const SizedBox(height: 12),
      DButton(
        label: const Text('Clear'),
        onPressed: () {
          _controller.clear();
          _focus.requestFocus();
        },
      ),
      if (_result.isNotEmpty) Text(_result),
    ],
  );
}

const _formCode = '''// Inside a State with a GlobalKey<FormState> formKey.
Form(key: formKey, child: Column(children: [
  DInput(labelText: 'Name *',
            isRequired: true, textInputAction: TextInputAction.next,
    validator: (value) => value!.trim().isEmpty ? 'Enter your name.' : null,
    onSaved: (value) => name = value!),
  DInput(labelText: 'Email *',
            isRequired: true, keyboardType: TextInputType.emailAddress,
    validator: (value) => value!.contains('@') ? null : 'Enter a valid email.',
    onSaved: (value) => email = value!),
  DButton(label: const Text('Submit'), onPressed: () {
    if (formKey.currentState!.validate()) formKey.currentState!.save();
  }),
  DButton(label: const Text('Reset'), onPressed: () => formKey.currentState!.reset()),
]))''';
const _editingCode = '''// Dispose the controller in State.dispose.
DInput(controller: passwordController, labelText: 'Password',
  obscureText: hidden, autocorrect: false, enableSuggestions: false);
DInput(value: value, onChanged: (text) => setState(() => value = text));''';
const _searchCode = '''// Dispose controller and focusNode in State.dispose.
Row(children: [
  Expanded(child: DInput(controller: controller, focusNode: focusNode,
    hintText: 'Search...', textInputAction: TextInputAction.search,
    prefix: const Icon(Icons.search, size: 16), onSubmitted: (_) => search())),
  const SizedBox(width: 8),
  DButton(label: const Text('Search'), onPressed: search),
])''';
