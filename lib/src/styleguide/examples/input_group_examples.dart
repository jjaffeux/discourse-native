import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../styleguide_example.dart';

final inputGroupExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Add addons, buttons, and helper content to inputs.',
  notes:
      'DInputGroup owns the joined shadcn surface, border, fill and exterior '
      'focus/invalid ring. DInputGroupInput, DInputGroupTextarea and '
      'DInputGroupButton keep independent focus, Form state, semantics, keyboard '
      'editing and actions. Addons can align inline-start, inline-end, '
      'block-start or block-end; place controls before addons in the child list '
      'and use align for visual order. Button Group composes this public API '
      'for joined input/action geometry with separate editor '
      'and button semantics, RTL and scaling. Field owns labels and supporting '
      'content outside the shared surface; Dropdown Menu and Popover own overlay '
      'lifecycle. Empty uses the same accepted composition. Button Group remains '
      'a downstream consumer of this public API.',
  examples: [
    StyleguideExample(
      title: 'Default search',
      description:
          'The icon is visually inline-start while the editor remains the only text field.',
      states: const ['Inline start', 'Icon', 'Focus'],
      code: '''DInputGroup(children: [
  DInputGroupInput(hintText: 'Search...', semanticLabel: 'Search'),
  DInputGroupAddon(child: Icon(Icons.search)),
  DInputGroupAddon(
    alignment: DInputGroupAddonAlignment.inlineEnd,
    child: DInputGroupText(Text('12 results')),
  ),
])''',
      builder: (_) => DInputGroup(
        children: [
          DInputGroupInput(hintText: 'Search...', semanticLabel: 'Search'),
          const DInputGroupAddon(child: Icon(Icons.search)),
          const DInputGroupAddon(
            alignment: DInputGroupAddonAlignment.inlineEnd,
            child: DInputGroupText(Text('12 results')),
          ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'Alignments',
      description:
          'Inline and block addons use the same control while changing only visual placement.',
      states: const ['inline-start', 'inline-end', 'block-start', 'block-end'],
      code: '''Column(children: [
  DInputGroup(children: [
    DInputGroupInput(hintText: 'Enter password'),
    DInputGroupAddon(alignment: DInputGroupAddonAlignment.inlineEnd,
      child: Icon(Icons.visibility_off)),
  ]),
  DInputGroup(children: [
    DInputGroupTextarea(hintText: 'console.log("hello")'),
    DInputGroupAddon(alignment: DInputGroupAddonAlignment.blockStart,
      child: DInputGroupText(Text('script.js'))),
  ]),
])''',
      builder: (_) => const _AlignmentExample(),
    ),
    StyleguideExample(
      title: 'Text addons',
      description:
          'Prefix, suffix and helper text share the grouped surface without merging editor semantics.',
      states: const ['Prefix', 'Suffix', 'Helper text', 'RTL'],
      code: '''DInputGroup(children: [
  DInputGroupInput(hintText: 'example.com', semanticLabel: 'Domain'),
  DInputGroupAddon(child: DInputGroupText(Text('https://'))),
  DInputGroupAddon(alignment: DInputGroupAddonAlignment.inlineEnd,
    child: DInputGroupText(Text('.com'))),
])''',
      builder: (_) => const _TextAddonExample(),
    ),
    StyleguideExample(
      title: 'Button actions',
      description:
          'The joined input/action geometry required by Button Group keeps separate input and button focus/actions.',
      states: const ['Joined action', 'Icon button', 'Loading', 'Disabled'],
      code: '''DInputGroup(children: [
  DInputGroupInput(controller: controller,
    hintText: 'Type to search...', semanticLabel: 'Search query'),
  DInputGroupAddon(alignment: DInputGroupAddonAlignment.inlineEnd, child:
    DInputGroupButton(label: Text('Search'), onPressed: search)),
])''',
      builder: (_) => const InputGroupButtonActionsExample(),
    ),
    StyleguideExample(
      title: 'Kbd, dropdown, and spinner',
      description:
          'Keycaps and busy status stay decorative; the accepted Dropdown Menu adds an independent popup trigger without taking editor ownership.',
      states: const [
        'Kbd',
        'Dropdown Menu',
        'Spinner',
        'Reduced motion',
        'Multiple addons',
      ],
      code: '''DInputGroup(children: [
  DInputGroupInput(hintText: 'Search...', semanticLabel: 'Search workspace'),
  DInputGroupAddon(alignment: DInputGroupAddonAlignment.inlineEnd, child:
    DDropdownMenu(
      content: DDropdownMenuContent(children: [
        DDropdownMenuItem(onPressed: searchAll, child: Text('All content')),
        DDropdownMenuItem(onPressed: searchUsers, child: Text('Users')),
      ]),
      child: DDropdownMenuTrigger(builder: (context, menu) =>
        Semantics(expanded: menu.open, child: DInputGroupButton(
          label: Text('Search in'), hasPopup: true,
          focusNode: menu.focusNode, onPressed: menu.toggle))),
    )),
])''',
      builder: (_) => const _KbdSpinnerExample(),
    ),
    StyleguideExample(
      title: 'Textarea footer',
      description:
          'A block-end addon can hold counters and buttons below a multiline editor.',
      states: const ['Textarea', 'Counter', 'Block end', 'Submit'],
      code: '''DInputGroup(children: [
  DInputGroupTextarea(controller: controller, maxLength: 280,
    hintText: 'Write a message...', semanticLabel: 'Message'),
  DInputGroupAddon(alignment: DInputGroupAddonAlignment.blockEnd, child:
    Row(children: [
      Expanded(child: Text('\${controller.text.length}/280')),
      DInputGroupButton(label: Text('Post'), onPressed: post),
    ])),
])''',
      builder: (_) => const _TextareaFooterExample(),
    ),
    StyleguideExample(
      title: 'Custom input',
      description:
          'A custom content-growing editor attaches the focus node supplied by the group adapter.',
      states: const ['Custom editor', 'Content growth', 'Focus', 'Submit'],
      code: '''DInputGroup(children: [
  DInputGroupControl(multiline: true,
    builder: (context, focusNode) => TextField(
      controller: controller, focusNode: focusNode,
      minLines: 1, maxLines: 5,
      decoration: const InputDecoration.collapsed(
        hintText: 'Custom resizable textarea'))),
  DInputGroupAddon(alignment: DInputGroupAddonAlignment.blockEnd,
    child: DInputGroupButton(label: Text('Submit'), onPressed: submit)),
])''',
      builder: (_) => const _CustomInputExample(),
    ),
    StyleguideExample(
      title: 'Form validation',
      description:
          'Field owns the external label, description and error while the grouped editor retains Form, focus, save and reset ownership.',
      states: const ['Field', 'Form', 'Invalid', 'Reset', 'Read-only'],
      code: '''Form(key: form, child: DField(invalid: invalid, children: [
  DFieldLabel(focusNode: focusNode, excludeSemantics: true,
    child: Text('Username')),
  DInputGroup(invalid: invalid, children: [
    DInputGroupInput(focusNode: focusNode, initialValue: 'shadcn',
      semanticLabel: 'Username', validator: validate, onSaved: save),
    DInputGroupAddon(alignment: DInputGroupAddonAlignment.inlineEnd,
      child: DInputGroupText(Text('@company.com'))),
  ]),
  DFieldDescription(child: Text('Choose your workspace username.')),
  if (invalid) DFieldError(errors: ['Required']),
]))''',
      builder: (_) => const _FormExample(),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'Logical alignments, counters and actions mirror under an inherited RTL direction.',
      states: const ['RTL', 'Arabic', 'Inline end', 'Block end'],
      code: '''Directionality(textDirection: TextDirection.rtl,
  child: DInputGroup(children: [
    DInputGroupInput(hintText: 'بحث...', semanticLabel: 'بحث'),
    DInputGroupAddon(child: Icon(Icons.search)),
    DInputGroupAddon(alignment: DInputGroupAddonAlignment.inlineEnd,
      child: DInputGroupText(Text('١٢ نتيجة'))),
  ]))''',
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DInputGroup(
              children: [
                DInputGroupInput(hintText: 'بحث...', semanticLabel: 'بحث'),
                const DInputGroupAddon(child: Icon(Icons.search)),
                const DInputGroupAddon(
                  alignment: DInputGroupAddonAlignment.inlineEnd,
                  child: DInputGroupText(Text('١٢ نتيجة')),
                ),
              ],
            ),
            const SizedBox(height: DSpacing.md),
            DInputGroup(
              children: [
                DInputGroupTextarea(
                  hintText: 'اكتب رسالة...',
                  semanticLabel: 'منطقة النص',
                ),
                DInputGroupAddon(
                  alignment: DInputGroupAddonAlignment.blockEnd,
                  child: Row(
                    children: [
                      const Expanded(child: Text('٠/٢٨٠')),
                      DInputGroupButton(
                        label: const Text('نشر'),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  ],
);

class _AlignmentExample extends StatelessWidget {
  const _AlignmentExample();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DInputGroup(
        children: [
          DInputGroupInput(hintText: 'Enter password'),
          const DInputGroupAddon(
            alignment: DInputGroupAddonAlignment.inlineEnd,
            child: Icon(Icons.visibility_off),
          ),
        ],
      ),
      const SizedBox(height: DSpacing.md),
      DInputGroup(
        children: [
          DInputGroupInput(hintText: 'Enter your name'),
          const DInputGroupAddon(
            alignment: DInputGroupAddonAlignment.blockStart,
            child: DInputGroupText(Text('Full Name')),
          ),
        ],
      ),
      const SizedBox(height: DSpacing.md),
      DInputGroup(
        children: [
          DInputGroupInput(hintText: 'Enter amount'),
          const DInputGroupAddon(
            alignment: DInputGroupAddonAlignment.blockEnd,
            child: DInputGroupText(Text('USD')),
          ),
        ],
      ),
      const SizedBox(height: DSpacing.md),
      DInputGroup(
        children: [
          DInputGroupTextarea(
            hintText: 'console.log("hello")',
            semanticLabel: 'Script',
          ),
          const DInputGroupAddon(
            alignment: DInputGroupAddonAlignment.blockStart,
            child: Row(
              children: [
                Icon(Icons.code, size: 16),
                SizedBox(width: DSpacing.sm),
                Text('script.js'),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}

class _TextAddonExample extends StatelessWidget {
  const _TextAddonExample();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DInputGroup(
        children: [
          DInputGroupInput(hintText: '0.00', semanticLabel: 'Amount'),
          const DInputGroupAddon(child: DInputGroupText(Text(r'$'))),
          const DInputGroupAddon(
            alignment: DInputGroupAddonAlignment.inlineEnd,
            child: DInputGroupText(Text('USD')),
          ),
        ],
      ),
      const SizedBox(height: DSpacing.md),
      DInputGroup(
        children: [
          DInputGroupInput(hintText: 'example.com', semanticLabel: 'Domain'),
          const DInputGroupAddon(child: DInputGroupText(Text('https://'))),
          const DInputGroupAddon(
            alignment: DInputGroupAddonAlignment.inlineEnd,
            child: DInputGroupText(Text('.com')),
          ),
        ],
      ),
      const SizedBox(height: DSpacing.md),
      DInputGroup(
        children: [
          DInputGroupInput(
            hintText: 'Enter your username',
            semanticLabel: 'Username',
          ),
          const DInputGroupAddon(
            alignment: DInputGroupAddonAlignment.inlineEnd,
            child: DInputGroupText(Text('@company.com')),
          ),
        ],
      ),
    ],
  );
}

class InputGroupButtonActionsExample extends StatefulWidget {
  const InputGroupButtonActionsExample({super.key});

  @override
  State<InputGroupButtonActionsExample> createState() =>
      _InputGroupButtonActionsExampleState();
}

class _InputGroupButtonActionsExampleState
    extends State<InputGroupButtonActionsExample> {
  final _controller = TextEditingController(text: 'https://x.com/shadcn');
  String _status = 'Ready';
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search() => setState(() => _status = 'Searched ${_controller.text}');

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DInputGroup(
        children: [
          DInputGroupInput(
            controller: _controller,
            hintText: 'Type to search...',
            semanticLabel: 'Search query',
          ),
          DInputGroupAddon(
            alignment: DInputGroupAddonAlignment.inlineEnd,
            child: DInputGroupButton(
              label: const Text('Search'),
              onPressed: _busy ? null : _search,
              loading: _busy,
            ),
          ),
        ],
      ),
      const SizedBox(height: DSpacing.md),
      DInputGroup(
        children: [
          DInputGroupInput(hintText: 'https://', semanticLabel: 'URL scheme'),
          DInputGroupAddon(
            alignment: DInputGroupAddonAlignment.inlineEnd,
            child: DInputGroupButton.icon(
              icon: const Icon(Icons.copy, size: 14),
              tooltip: 'Copy URL',
              onPressed: () => setState(() => _status = 'Copied URL'),
            ),
          ),
        ],
      ),
      const SizedBox(height: DSpacing.md),
      Wrap(
        spacing: DSpacing.sm,
        runSpacing: DSpacing.sm,
        children: [
          DButton(
            label: Text(_busy ? 'Finish loading' : 'Show loading'),
            onPressed: () => setState(() => _busy = !_busy),
          ),
          DButton(
            label: const Text('Clear'),
            onPressed: () => setState(() {
              _controller.clear();
              _status = 'Cleared';
            }),
          ),
        ],
      ),
      const SizedBox(height: DSpacing.sm),
      Semantics(liveRegion: true, child: Text(_status)),
    ],
  );
}

class _KbdSpinnerExample extends StatelessWidget {
  const _KbdSpinnerExample();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DInputGroup(
        children: [
          DInputGroupInput(
            hintText: 'Search...',
            semanticLabel: 'Command search',
          ),
          const DInputGroupAddon(child: DKbd('⌘K')),
        ],
      ),
      const SizedBox(height: DSpacing.md),
      DInputGroup(
        children: [
          DInputGroupInput(
            hintText: 'Search workspace...',
            semanticLabel: 'Search workspace',
          ),
          DInputGroupAddon(
            alignment: DInputGroupAddonAlignment.inlineEnd,
            child: DDropdownMenu(
              content: DDropdownMenuContent(
                semanticLabel: 'Search scope menu',
                children: [
                  DDropdownMenuItem(
                    onPressed: () {},
                    child: const Text('All content'),
                  ),
                  DDropdownMenuItem(
                    onPressed: () {},
                    child: const Text('Users'),
                  ),
                ],
              ),
              child: DDropdownMenuTrigger(
                builder: (context, menu) => Semantics(
                  expanded: menu.open,
                  child: DInputGroupButton(
                    label: const Text('Search in'),
                    icon: const Icon(Icons.arrow_drop_down, size: 16),
                    iconPosition: DButtonIconPosition.end,
                    hasPopup: true,
                    focusNode: menu.focusNode,
                    onPressed: menu.toggle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: DSpacing.md),
      DInputGroup(
        children: [
          DInputGroupInput(
            enabled: false,
            initialValue: 'Saving changes...',
            semanticLabel: 'Saving changes',
          ),
          const DInputGroupAddon(
            alignment: DInputGroupAddonAlignment.inlineEnd,
            child: DSpinner(size: 16, semanticLabel: null),
          ),
        ],
      ),
      const SizedBox(height: DSpacing.md),
      DInputGroup(
        children: [
          DInputGroupInput(
            hintText: 'Type to search...',
            semanticLabel: 'AI search',
          ),
          const DInputGroupAddon(
            alignment: DInputGroupAddonAlignment.inlineEnd,
            child: DInputGroupText(Text('Ask AI')),
          ),
          const DInputGroupAddon(
            alignment: DInputGroupAddonAlignment.inlineEnd,
            child: DKbd('Tab'),
          ),
        ],
      ),
    ],
  );
}

class _TextareaFooterExample extends StatefulWidget {
  const _TextareaFooterExample();

  @override
  State<_TextareaFooterExample> createState() => _TextareaFooterExampleState();
}

class _TextareaFooterExampleState extends State<_TextareaFooterExample> {
  final _controller = TextEditingController();
  String _status = 'Draft';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DInputGroup(
        children: [
          DInputGroupTextarea(
            controller: _controller,
            hintText: 'Write a message...',
            semanticLabel: 'Message',
            maxLength: 280,
            inputFormatters: [LengthLimitingTextInputFormatter(280)],
          ),
          DInputGroupAddon(
            alignment: DInputGroupAddonAlignment.blockEnd,
            child: Row(
              children: [
                Expanded(child: Text('${_controller.text.length}/280')),
                DInputGroupButton(
                  label: const Text('Post'),
                  onPressed: _controller.text.trim().isEmpty
                      ? null
                      : () => setState(() => _status = 'Posted locally'),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: DSpacing.sm),
      Text(_status),
    ],
  );
}

class _FormExample extends StatefulWidget {
  const _FormExample();

  @override
  State<_FormExample> createState() => _FormExampleState();
}

class _CustomInputExample extends StatefulWidget {
  const _CustomInputExample();

  @override
  State<_CustomInputExample> createState() => _CustomInputExampleState();
}

class _CustomInputExampleState extends State<_CustomInputExample> {
  final _controller = TextEditingController();
  String _status = 'Ready';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DInputGroup(
        children: [
          DInputGroupControl(
            multiline: true,
            builder: (context, focusNode) => TextField(
              controller: _controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 5,
              decoration: const InputDecoration.collapsed(
                hintText: 'Custom resizable textarea',
              ),
            ),
          ),
          DInputGroupAddon(
            alignment: DInputGroupAddonAlignment.blockEnd,
            child: DInputGroupButton(
              label: const Text('Submit'),
              onPressed: () => setState(
                () => _status = _controller.text.trim().isEmpty
                    ? 'Nothing to submit'
                    : 'Submitted locally',
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: DSpacing.sm),
      Semantics(liveRegion: true, child: Text(_status)),
    ],
  );
}

class _FormExampleState extends State<_FormExample> {
  final _form = GlobalKey<FormState>();
  final _focus = FocusNode();
  bool _invalid = false;
  String _status = 'Not saved';

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Form(
        key: _form,
        child: DField(
          invalid: _invalid,
          children: [
            DFieldLabel(
              focusNode: _focus,
              excludeSemantics: true,
              child: const Text('Username'),
            ),
            DInputGroup(
              invalid: _invalid,
              children: [
                DInputGroupInput(
                  focusNode: _focus,
                  initialValue: 'shadcn',
                  semanticLabel: 'Username',
                  isRequired: true,
                  validator: (value) =>
                      value!.trim().isEmpty ? 'Required' : null,
                  onSaved: (value) => _status = 'Saved $value',
                ),
                const DInputGroupAddon(
                  alignment: DInputGroupAddonAlignment.inlineEnd,
                  child: DInputGroupText(Text('@company.com')),
                ),
              ],
            ),
            const DFieldDescription(
              child: Text('Choose your workspace username.'),
            ),
            if (_invalid) const DFieldError(errors: ['Required']),
          ],
        ),
      ),
      const SizedBox(height: DSpacing.md),
      Wrap(
        spacing: DSpacing.sm,
        runSpacing: DSpacing.sm,
        children: [
          DButton(
            label: const Text('Save'),
            onPressed: () => setState(() {
              _invalid = !_form.currentState!.validate();
              if (!_invalid) _form.currentState!.save();
            }),
          ),
          DButton(
            label: const Text('Reset'),
            variant: DButtonVariant.outline,
            onPressed: () => setState(() {
              _invalid = false;
              _form.currentState!.reset();
              _status = 'Reset';
            }),
          ),
        ],
      ),
      const SizedBox(height: DSpacing.sm),
      Semantics(liveRegion: true, child: Text(_status)),
    ],
  );
}
