import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final labelExamples = ComponentExamples(
  description: 'An accessible label for a form control.',
  status: ComponentStatus.implemented,
  notes:
      'Import package:discourse_native/discourse_ui.dart. DLabel accepts child, '
      'style and enabled. Registry metrics: 14px, weight 500, line height 1, '
      '8px composition gap, no padding/border/radius, and disabled opacity 0.5. '
      'The host supplies the font family, text scaler and live foreground tokens. '
      'Native control slots own association, activation, focus and combined '
      'semantics; a standalone DLabel is ordinary text. Keep interactive links '
      'outside a list tile. The form example composes the accepted DField and '
      'DInput owners. '
      'The larger reference FieldDemo belongs to Field; its neighboring '
      'outline, horizontal and submit props are not Label variants.',
  examples: [
    StyleguideExample(
      title: 'Control association and disabled state',
      description:
          'Tap the label or its row to toggle the checkbox. Tab reaches the '
          'native control once; Space toggles it. Disable the control to keep '
          'its value while removing activation. The control and label receive '
          'the same enabled state. Sample state is local to this preview.',
      states: const ['Default', 'Checked', 'Disabled', 'Keyboard', 'Touch'],
      code: '''// Inside a State with bool accepted = false and enabled = true.
DCheckbox(
  contentPadding: EdgeInsets.zero,
  value: accepted,
  onChanged: enabled
      ? (value) => setState(() => accepted = value ?? false)
      : null,
  title: const DLabel(
    child: Text('Accept terms and conditions'),
  ),
)''',
      builder: (_) => const _ControlPreview(),
    ),
    StyleguideExample(
      title: 'Rich labels and wrapping',
      description:
          'A decorative icon and emphasized spans share the label style. '
          'The label wraps at narrow widths and large text sizes. The separate '
          'terms action retains its own focus and semantics; the label does '
          'not contain a second interactive control.',
      states: const ['Rich content', 'Wrapping', 'Text scaling', 'Composition'],
      code: '''// Inside a State with bool updates = false.
DCheckbox(
  contentPadding: EdgeInsets.zero,
  value: updates,
  onChanged: (value) => setState(() => updates = value ?? false),
  title: const DLabel(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ExcludeSemantics(child: Icon(Icons.mail_outline, size: 20)),
        SizedBox(width: DSpacing.sm),
        Expanded(child: Text.rich(TextSpan(children: [
          TextSpan(text: 'Send me '),
          TextSpan(
            text: 'community updates',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: ' with highlights from discussions I follow.'),
        ]))),
      ],
    ),
  ),
)''',
      builder: (_) => const _RichPreview(),
    ),
    StyleguideExample(
      title: 'Label in a form',
      description:
          'This demonstrates Label with the accepted Field and Input owners. '
          'Tap the email label to focus its DInput. Submit an empty or invalid '
          'address to see the shared error and accessible required state. '
          'Submit a valid address, then reset. Form and DInput own validation, '
          'save/reset and editing; DLabel remains presentational.',
      states: const ['Field composition', 'Required', 'Error', 'Save', 'Reset'],
      code: '''// Inside a State:
final formKey = GlobalKey<FormState>();
final emailFocus = FocusNode();
bool updates = false;
String? savedEmail;

@override
void dispose() {
  emailFocus.dispose();
  super.dispose();
}

Form(
  key: formKey,
  child: Column(children: [
    DField(children: [
      DFieldLabel(focusNode: emailFocus, excludeSemantics: true,
        child: const Text('Your email address')),
      const DFieldDescription(
        child: Text('Required. Used only in this local example.')),
      DFieldControl(label: 'Your email address',
        description: 'Required. Used only in this local example.',
        required: true,
        child: DInput(focusNode: emailFocus,
          keyboardType: TextInputType.emailAddress, isRequired: true,
        validator: (value) => (value ?? '').contains('@')
            ? null : 'Enter an email address containing @.',
        onSaved: (value) => savedEmail = value?.trim(),
      )),
    ]),
    DCheckbox(
      value: updates,
      onChanged: (value) => setState(() => updates = value ?? false),
      title: const DLabel(child: Text('Send me product updates')),
    ),
    DButton(
      label: const Text('Submit example'),
      onPressed: () {
        if (formKey.currentState!.validate()) {
          setState(() => formKey.currentState!.save());
        }
      },
    ),
    DButton(
      label: const Text('Reset form'),
      onPressed: () {
        formKey.currentState!.reset();
        setState(() { updates = false; savedEmail = null; });
      },
    ),
  ]),
)''',
      builder: (_) => const _FormPreview(),
    ),
    StyleguideExample(
      title: 'RTL labels',
      description:
          'Arabic and Hebrew labels inherit DDirection. Leading controls, '
          'wrapping and text alignment follow the reading direction. Both '
          'checkboxes remain interactive and keep their state when the '
          'styleguide theme, width or text scale changes.',
      states: const ['RTL', 'Arabic', 'Hebrew', 'Wrapping'],
      code: '''// Inside a State with bool accepted = false.
DDirection(
  textDirection: TextDirection.rtl,
  child: DCheckbox(
    contentPadding: EdgeInsets.zero,

    value: accepted,
    onChanged: (value) => setState(() => accepted = value ?? false),
    title: const DLabel(child: Text('قبول الشروط والأحكام')),
  ),
)''',
      builder: (_) => const _RtlPreview(),
    ),
  ],
);

class _ControlPreview extends StatefulWidget {
  const _ControlPreview();

  @override
  State<_ControlPreview> createState() => _ControlPreviewState();
}

class _ControlPreviewState extends State<_ControlPreview> {
  bool _accepted = false;
  bool _enabled = true;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DCheckbox(
        key: const ValueKey('label-terms'),
        contentPadding: EdgeInsets.zero,

        value: _accepted,
        onChanged: _enabled
            ? (value) => setState(() => _accepted = value ?? false)
            : null,
        title: const DLabel(child: Text('Accept terms and conditions')),
      ),
      DSwitchTile(
        key: const ValueKey('label-enable'),
        contentPadding: EdgeInsets.zero,
        title: const DLabel(child: Text('Enable terms control')),
        value: _enabled,
        onChanged: (value) => setState(() => _enabled = value),
      ),
      Text(_accepted ? 'Terms accepted' : 'Terms not accepted'),
    ],
  );
}

class _RichPreview extends StatefulWidget {
  const _RichPreview();

  @override
  State<_RichPreview> createState() => _RichPreviewState();
}

class _RichPreviewState extends State<_RichPreview> {
  bool _updates = false;
  bool _showTerms = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DCheckbox(
        contentPadding: EdgeInsets.zero,

        value: _updates,
        onChanged: (value) => setState(() => _updates = value ?? false),
        title: const DLabel(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ExcludeSemantics(child: Icon(Icons.mail_outline, size: 20)),
              SizedBox(width: DSpacing.sm),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'Send me '),
                      TextSpan(
                        text: 'community updates',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(
                        text: ' with highlights from discussions I follow.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: DSpacing.sm),
      DButton(
        onPressed: () => setState(() => _showTerms = !_showTerms),
        label: DefaultTextStyle(
          style: DText.styleOf(context, DTextVariant.small),
          child: Text(_showTerms ? 'Hide example terms' : 'Read example terms'),
        ),
      ),
      if (_showTerms) ...[
        const SizedBox(height: DSpacing.sm),
        const DText(
          'You can change this local preference at any time. '
          'No email is sent by this example.',
          variant: DTextVariant.muted,
        ),
      ],
    ],
  );
}

class _FormPreview extends StatefulWidget {
  const _FormPreview();

  @override
  State<_FormPreview> createState() => _FormPreviewState();
}

class _FormPreviewState extends State<_FormPreview> {
  final _formKey = GlobalKey<FormState>();
  final _emailFocus = FocusNode();
  bool _updates = false;
  String? _savedEmail;

  @override
  void dispose() {
    _emailFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DField(
          children: [
            DFieldLabel(
              focusNode: _emailFocus,
              excludeSemantics: true,
              child: const Text('Your email address'),
            ),
            const DFieldDescription(
              child: Text('Required. Used only in this local example.'),
            ),
            DFieldControl(
              label: 'Your email address',
              description: 'Required. Used only in this local example.',
              required: true,
              child: DInput(
                key: const ValueKey('label-email'),
                focusNode: _emailFocus,
                keyboardType: TextInputType.emailAddress,
                isRequired: true,
                validator: (value) => (value ?? '').contains('@')
                    ? null
                    : 'Enter an email address containing @.',
                onChanged: (_) => setState(() => _savedEmail = null),
                onSaved: (value) => _savedEmail = value?.trim(),
              ),
            ),
          ],
        ),
        const SizedBox(height: DSpacing.md),
        DCheckbox(
          contentPadding: EdgeInsets.zero,

          value: _updates,
          onChanged: (value) => setState(() => _updates = value ?? false),
          title: const DLabel(child: Text('Send me product updates')),
        ),
        const SizedBox(height: DSpacing.md),
        Wrap(
          spacing: DSpacing.sm,
          runSpacing: DSpacing.sm,
          children: [
            DButton(
              key: const ValueKey('label-submit'),
              label: const Text('Submit example'),
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  setState(() => _formKey.currentState!.save());
                }
              },
            ),
            DButton(
              key: const ValueKey('label-form-reset'),
              label: const Text('Reset form'),
              onPressed: () {
                _formKey.currentState!.reset();
                setState(() {
                  _updates = false;
                  _savedEmail = null;
                });
              },
            ),
          ],
        ),
        if (_savedEmail case final email?) ...[
          const SizedBox(height: DSpacing.md),
          Semantics(liveRegion: true, child: Text('Saved locally: $email')),
        ],
      ],
    ),
  );
}

class _RtlPreview extends StatefulWidget {
  const _RtlPreview();

  @override
  State<_RtlPreview> createState() => _RtlPreviewState();
}

class _RtlPreviewState extends State<_RtlPreview> {
  bool _arabic = false;
  bool _hebrew = false;

  @override
  Widget build(BuildContext context) => DDirection(
    textDirection: TextDirection.rtl,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DCheckbox(
          key: const ValueKey('label-arabic'),
          contentPadding: EdgeInsets.zero,

          value: _arabic,
          onChanged: (value) => setState(() => _arabic = value ?? false),
          title: const DLabel(child: Text('قبول الشروط والأحكام')),
        ),
        DCheckbox(
          key: const ValueKey('label-hebrew'),
          contentPadding: EdgeInsets.zero,

          value: _hebrew,
          onChanged: (value) => setState(() => _hebrew = value ?? false),
          title: const DLabel(child: Text('קבל תנאים והגבלות')),
        ),
      ],
    ),
  );
}
