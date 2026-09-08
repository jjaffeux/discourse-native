import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final labelExamples = ComponentExamples(
  status: ComponentStatus.baseline,
  notes:
      'Import package:discourse_native/discourse_ui.dart. DLabel has one style, '
      'with child composition, optional TextStyle emphasis, and enabled state. '
      'There are no outline, orientation, or submit variants: those props in '
      'the reference belong to neighboring Field and Button controls. The '
      'registry text-sm / font-medium / leading-none maps to 14 logical pixels, '
      'weight 500 and line height 1; gap-2 maps to 8 pixels in composed rows. '
      'Disabled content uses opacity 0.5 and rejects interaction. There is no '
      'label padding, border or radius. Live site tokens supply foreground '
      'color, and the host supplies the font family and text scaler. Native '
      'list tiles associate the label and control, combine their semantics, '
      'and own the hit target, Tab focus, Space activation and focus indication. '
      'A standalone DLabel is ordinary text, not an HTML htmlFor association. '
      'Keep InputDecoration.labelText and Form for floating field labels, '
      'descriptions, validation and errors. Label itself creates no focus target, '
      'gesture, animation or selection owner. Put interactive links outside a '
      'list tile so they can retain independent keyboard and semantic actions.',
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
CheckboxListTile.adaptive(
  controlAffinity: ListTileControlAffinity.leading,
  contentPadding: EdgeInsets.zero,
  value: accepted,
  onChanged: enabled
      ? (value) => setState(() => accepted = value ?? false)
      : null,
  title: DLabel(
    enabled: enabled,
    child: const Text('Accept terms and conditions'),
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
CheckboxListTile.adaptive(
  controlAffinity: ListTileControlAffinity.leading,
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
      title: 'Label in a native form',
      description:
          'This is the native adaptation of Label in Field. Tap the email '
          'label to focus its TextFormField. Submit an empty or invalid address '
          'to see the native error and accessible required state. Submit a '
          'valid address, then reset. The form, not DLabel, owns validation, '
          'save/reset, descriptions, editing and floating-label colors.',
      states: const ['Field composition', 'Required', 'Error', 'Save', 'Reset'],
      code: '''// Inside a State with a GlobalKey<FormState> formKey,
// bool updates = false, and String? savedEmail.
Form(
  key: formKey,
  child: Column(children: [
    Semantics(
      isRequired: true,
      child: TextFormField(
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(
          labelText: 'Your email address',
          helperText: 'Required. Used only in this local example.',
          helperMaxLines: 3,
          errorMaxLines: 3,
        ),
        validator: (value) => (value ?? '').contains('@')
            ? null : 'Enter an email address containing @.',
        onSaved: (value) => savedEmail = value?.trim(),
      ),
    ),
    CheckboxListTile.adaptive(
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
  child: CheckboxListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
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
      CheckboxListTile.adaptive(
        key: const ValueKey('label-terms'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _accepted,
        onChanged: _enabled
            ? (value) => setState(() => _accepted = value ?? false)
            : null,
        title: DLabel(
          enabled: _enabled,
          child: const Text('Accept terms and conditions'),
        ),
      ),
      SwitchListTile.adaptive(
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
      CheckboxListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
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
  bool _updates = false;
  String? _savedEmail;

  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          isRequired: true,
          child: TextFormField(
            key: const ValueKey('label-email'),
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Your email address',
              helperText: 'Required. Used only in this local example.',
              helperMaxLines: 3,
              errorMaxLines: 3,
            ),
            validator: (value) => (value ?? '').contains('@')
                ? null
                : 'Enter an email address containing @.',
            onChanged: (_) => setState(() => _savedEmail = null),
            onSaved: (value) => _savedEmail = value?.trim(),
          ),
        ),
        const SizedBox(height: DSpacing.md),
        CheckboxListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
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
        CheckboxListTile.adaptive(
          key: const ValueKey('label-arabic'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _arabic,
          onChanged: (value) => setState(() => _arabic = value ?? false),
          title: const DLabel(child: Text('قبول الشروط والأحكام')),
        ),
        CheckboxListTile.adaptive(
          key: const ValueKey('label-hebrew'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _hebrew,
          onChanged: (value) => setState(() => _hebrew = value ?? false),
          title: const DLabel(child: Text('קבל תנאים והגבלות')),
        ),
      ],
    ),
  );
}
