import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final switchExamples = ComponentExamples(
  description: 'A control that toggles a setting on or off.',
  status: ComponentStatus.baseline,
  notes:
      'Source implementation complete; native comparison pending. '
      'DSwitch accepts controlled value/onChanged or uncontrolled initialValue. '
      'DSwitchTile associates wrapping title/subtitle with a single row action. '
      'DSwitchFormField supports validation/save/reset. Read-only retains focus; '
      'disabled prevents activation. Space and Enter toggle; Tab moves focus. '
      'Default artwork is 32×18.4 with a 16px thumb; small is 24×14 with a 12px '
      'thumb. Desktop rows are intrinsic; touch rows retain 48px targets. '
      'Choice cards compose local switch rows; the general Field API is pending.',
  examples: [
    StyleguideExample(
      title: 'Airplane Mode',
      description: 'The reference default: a switch and an associated label.',
      states: const ['Default', 'Keyboard', 'Touch'],
      code: '''DSwitchTile(leading: true, value: airplane, onChanged: (value) =>
  setState(() => airplane = value), title: const Text('Airplane Mode'))''',
      builder: (_) => const _SwitchDemo(kind: 'default'),
    ),
    StyleguideExample(
      title: 'Description',
      description:
          'The description wraps with the inherited text scale. Activate anywhere in the row.',
      states: const ['Description', 'Wrapping'],
      code:
          '''DSwitchTile(value: share, onChanged: (value) => setState(() => share = value),
  title: const Text('Share across devices'),
  subtitle: const Text('Focus is shared across devices, and turns off when you leave the app.'))''',
      builder: (_) => const _SwitchDemo(kind: 'description'),
    ),
    StyleguideExample(
      title: 'Choice Card',
      description: 'Two independent settings with clickable card bounds.',
      states: const ['Choice Card', 'Checked', 'Unchecked'],
      code: '''DSwitchTile(choiceCard: true, value: share,
  onChanged: (value) => setState(() => share = value),
  title: const Text('Share across devices'),
  subtitle: const Text('Focus is shared across devices, and turns off when you leave the app.'))''',
      builder: (_) => const _SwitchDemo(kind: 'card'),
    ),
    StyleguideExample(
      title: 'Disabled and read-only',
      description:
          'Disabled switches leave traversal. Read-only switches retain focus without edits.',
      states: const ['Disabled', 'Read-only'],
      code: '''const DSwitch(value: false, semanticLabel: 'Disabled');
const DSwitch(initialValue: true, enabled: false, semanticLabel: 'Disabled checked');
const DSwitch(initialValue: true, readOnly: true, semanticLabel: 'Read-only');''',
      builder: (_) => const Column(
        children: [
          DSwitchTile(value: false, onChanged: null, title: Text('Disabled')),
          DSwitchTile(
            value: true,
            onChanged: null,
            title: Text('Disabled checked'),
          ),
          Row(
            children: [
              DSwitch(
                initialValue: true,
                readOnly: true,
                semanticLabel: 'Read-only',
              ),
              Flexible(child: DLabel(child: Text('Read-only'))),
            ],
          ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'Invalid',
      description:
          'The reference invalid state keeps the description muted and marks the switch and title.',
      states: const ['Invalid', 'Description'],
      code:
          "DSwitchTile(invalid: true, value: accepted, onChanged: (value) => setState(() => accepted = value), title: const Text('Accept terms and conditions'), subtitle: const Text('You must accept the terms and conditions to continue.'))",
      builder: (_) => const _SwitchDemo(kind: 'invalid'),
    ),
    StyleguideExample(
      title: 'Invalid and Form',
      description:
          'Submit without accepting, then accept and save. Reset restores the original value.',
      states: const ['Invalid', 'Form', 'Save', 'Reset'],
      code: '''DSwitchFormField(initialValue: false,
  title: const Text('Accept terms and conditions'),
  validator: (value) => value == true ? null : 'You must accept the terms and conditions to continue.',
  onSaved: (value) => saved = value);
// Form.of(context).validate(), .save(), and .reset() use ordinary Flutter Form.''',
      builder: (_) =>
          const Align(child: SizedBox(width: 384, child: _SwitchForm())),
    ),
    StyleguideExample(
      title: 'Size',
      description:
          'Small and default keep their exact artwork inside accessible targets.',
      states: const ['Small', 'Default', 'Associated label'],
      code: '''DSwitchTile(leading: true, size: DSwitchSize.small, value: small,
  onChanged: (value) => setState(() => small = value),
  title: const DLabel(style: TextStyle(height: 1.375), child: Text('Small')));
DSwitchTile(leading: true, value: standard,
  onChanged: (value) => setState(() => standard = value),
  title: const DLabel(style: TextStyle(height: 1.375), child: Text('Default')));''',
      builder: (_) => const _SwitchSizes(),
    ),
    StyleguideExample(
      title: 'RTL',
      description: 'Thumb travel and label placement follow logical direction.',
      states: const ['RTL', 'Description'],
      code: '''Directionality(textDirection: TextDirection.rtl,
  child: DSwitchTile(value: share, onChanged: (value) => setState(() => share = value),
    title: const Text('المشاركة عبر الأجهزة'),
    subtitle: const Text('يتم مشاركة التركيز عبر الأجهزة، ويتم إيقاف تشغيله عند مغادرة التطبيق.')))''',
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: _SwitchDemo(kind: 'rtl'),
      ),
    ),
    StyleguideExample(
      title: 'Controlled updates',
      description:
          'An external action updates the same setting; rebuilding preserves local example state.',
      states: const ['Controlled', 'External update'],
      code:
          '''DSwitchTile(value: enabled, onChanged: (value) => setState(() => enabled = value),
  title: const Text('Enable notifications'));
DButton(label: const Text('Change externally'), onPressed: () => setState(() => enabled = !enabled));''',
      builder: (_) => const _SwitchDemo(kind: 'controlled'),
    ),
  ],
);

class _SwitchDemo extends StatefulWidget {
  const _SwitchDemo({required this.kind});
  final String kind;
  @override
  State<_SwitchDemo> createState() => _SwitchDemoState();
}

class _SwitchDemoState extends State<_SwitchDemo> {
  bool _value = false;
  bool _notifications = true;
  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DSwitchTile(
          value: _value,
          onChanged: (value) => setState(() => _value = value),
          choiceCard: kind == 'card',
          invalid: kind == 'invalid',
          leading: kind == 'default',
          title: Text(
            kind == 'invalid'
                ? 'Accept terms and conditions'
                : kind == 'default'
                ? 'Airplane Mode'
                : kind == 'rtl'
                ? 'المشاركة عبر الأجهزة'
                : kind == 'controlled'
                ? 'Enable notifications'
                : 'Share across devices',
          ),
          subtitle: kind == 'default' || kind == 'controlled'
              ? null
              : Text(
                  kind == 'invalid'
                      ? 'You must accept the terms and conditions to continue.'
                      : kind == 'rtl'
                      ? 'يتم مشاركة التركيز عبر الأجهزة، ويتم إيقاف تشغيله عند مغادرة التطبيق.'
                      : 'Focus is shared across devices, and turns off when you leave the app.',
                ),
        ),
        if (kind == 'card') ...[
          const SizedBox(height: 20),
          DSwitchTile(
            choiceCard: true,
            value: _notifications,
            onChanged: (value) => setState(() => _notifications = value),
            title: const Text('Enable notifications'),
            subtitle: const Text(
              'Receive notifications when focus mode is enabled or disabled.',
            ),
          ),
        ],
        if (kind == 'controlled')
          DButton(
            label: const Text('Change externally'),
            onPressed: () => setState(() => _value = !_value),
          ),
      ],
    );
    return Align(
      child: kind == 'default'
          ? IntrinsicWidth(child: content)
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 384),
              child: content,
            ),
    );
  }
}

class _SwitchForm extends StatefulWidget {
  const _SwitchForm();
  @override
  State<_SwitchForm> createState() => _SwitchFormState();
}

class _SwitchFormState extends State<_SwitchForm> {
  final _form = GlobalKey<FormState>();
  String _result = 'Not saved';
  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DSwitchFormField(
          title: const Text('Accept terms and conditions'),
          subtitle: const Text(
            'You must accept the terms and conditions to continue.',
          ),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (value) =>
              value == true ? null : 'Accept terms to continue.',
          onSaved: (value) => setState(() => _result = 'Saved: $value'),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DButton(
              label: const Text('Submit'),
              onPressed: () {
                if (_form.currentState!.validate()) _form.currentState!.save();
              },
            ),
            DButton(
              label: const Text('Reset'),
              onPressed: () {
                _form.currentState!.reset();
                setState(() => _result = 'Not saved');
              },
            ),
          ],
        ),
        Text(_result),
      ],
    ),
  );
}

class _SwitchSizes extends StatefulWidget {
  const _SwitchSizes();
  @override
  State<_SwitchSizes> createState() => _SwitchSizesState();
}

class _SwitchSizesState extends State<_SwitchSizes> {
  bool _small = false;
  bool _standard = false;
  @override
  Widget build(BuildContext context) => Align(
    child: IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DSwitchTile(
            leading: true,
            size: DSwitchSize.small,
            value: _small,
            onChanged: (value) => setState(() => _small = value),
            title: const DLabel(
              style: TextStyle(height: 1.375),
              child: Text('Small'),
            ),
          ),
          const SizedBox(height: 20),
          DSwitchTile(
            leading: true,
            value: _standard,
            onChanged: (value) => setState(() => _standard = value),
            title: const DLabel(
              style: TextStyle(height: 1.375),
              child: Text('Default'),
            ),
          ),
        ],
      ),
    ),
  );
}
