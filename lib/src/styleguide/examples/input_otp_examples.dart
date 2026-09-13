import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/discourse_typography.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final inputOTPExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'An accessible one-time-code editor projected into composable visual slots.',
  notes:
      'One native TextField owns typing, selection, paste, IME and one-time-code '
      'autofill. Groups, slots and separators only project its state. The API '
      'supports local, controlled or borrowed-controller ownership, character '
      'patterns, paste transforms, completion, Form validation/save/reset, '
      'disabled and invalid states. The independent review measured the live '
      'Base UI render and verified the isolated macOS fixture.',
  examples: [
    StyleguideExample(
      title: 'Default',
      description: 'Six joined 32px slots with an initial value.',
      states: const ['Default', 'Caret', 'Keyboard'],
      code:
          "DInputOTP(maxLength: 6, initialValue: '123456', semanticLabel: 'One-time password')",
      builder: (_) => DInputOTP(
        maxLength: 6,
        initialValue: '123456',
        semanticLabel: 'One-time password',
      ),
    ),
    StyleguideExample(
      title: 'Pattern',
      description:
          'Non-digits are removed from typing and paste before the six-character limit.',
      states: const ['Digits only', 'Paste', 'Field'],
      code: '''DInputOTP(maxLength: 6, pattern: dInputOTPDigits,
  semanticLabel: 'Digits Only')''',
      builder: (_) => const _PatternExample(),
    ),
    StyleguideExample(
      title: 'Separator',
      description: 'Three two-slot groups separated by the 16px minus artwork.',
      states: const ['Groups', 'Separator'],
      code: '''DInputOTP(maxLength: 6, children: [
  DInputOTPGroup(children: [DInputOTPSlot(index: 0), DInputOTPSlot(index: 1)]),
  DInputOTPSeparator(),
  DInputOTPGroup(children: [DInputOTPSlot(index: 2), DInputOTPSlot(index: 3)]),
  DInputOTPSeparator(),
  DInputOTPGroup(children: [DInputOTPSlot(index: 4), DInputOTPSlot(index: 5)]),
])''',
      builder: (_) => const _SeparatedOTP(),
    ),
    StyleguideExample(
      title: 'Disabled',
      description:
          'The complete editor and separator composition fades to 50%.',
      states: const ['Disabled', 'Complete'],
      code:
          "DInputOTP(maxLength: 6, value: '123456', enabled: false, children: separatedSlots)",
      builder: (_) => const _SeparatedOTP(value: '123456', enabled: false),
    ),
    StyleguideExample(
      title: 'Controlled',
      description: 'The message reflects the parent-owned value immediately.',
      states: const ['Controlled', 'Live value'],
      code: '''DInputOTP(maxLength: 6, value: value,
  onChanged: (next) => setState(() => value = next));''',
      builder: (_) => const _ControlledExample(),
    ),
    StyleguideExample(
      title: 'Invalid',
      description:
          'Destructive slot borders and exterior group rings accompany an explicit error.',
      states: const ['Invalid', 'Error', 'Field'],
      code: '''DField(invalid: true, children: [
  DFieldControl(label: 'Verification code', errors: ['Invalid code'],
    child: DInputOTP(maxLength: 6, value: '000000', invalid: true)),
  DFieldError(errors: ['Invalid code']),
])''',
      builder: (_) => const _InvalidExample(),
    ),
    StyleguideExample(
      title: 'Four Digits',
      description: 'A compact digits-only PIN pattern.',
      states: const ['Four digits', 'PIN'],
      code:
          'DInputOTP(maxLength: 4, pattern: dInputOTPDigits, semanticLabel: \'PIN\')',
      builder: (_) => DInputOTP(
        maxLength: 4,
        pattern: dInputOTPDigits,
        semanticLabel: 'PIN',
      ),
    ),
    StyleguideExample(
      title: 'Alphanumeric',
      description:
          'Letters and digits are accepted; pasted input is normalized to upper case.',
      states: const ['Alphanumeric', 'Paste transform'],
      code: '''DInputOTP(maxLength: 6, pattern: dInputOTPAlphanumeric,
  keyboardType: TextInputType.text,
  inputTransformer: (value) => value.toUpperCase(), children: separatedSlots)''',
      builder: (_) => _SeparatedOTP(
        pattern: dInputOTPAlphanumeric,
        keyboardType: TextInputType.text,
        transformer: (value) => value.toUpperCase(),
        semanticLabel: 'Alphanumeric code',
      ),
    ),
    StyleguideExample(
      title: 'Form',
      description:
          'The reference verification card uses final Card, Field and Button owners.',
      states: const ['Form', 'Required', 'Save', 'Reset', 'Large slots'],
      code: '''Form(key: formKey, child: DCard(children: [
  DCardHeader(title: DCardTitle(child: Text('Verify your login'))),
  DCardContent(child: DField(children: [
    DFieldLabel(focusNode: focus, child: Text('Verification code')),
    DFieldControl(label: 'Verification code', required: true,
      child: DInputOTP(maxLength: 6, focusNode: focus,
        validator: (value) => value?.length == 6 ? null : 'Enter all six digits')),
  ])),
]));''',
      builder: (_) => const _OTPFormExample(),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'Logical group order, corners, focus and Arabic field metadata follow RTL.',
      states: const ['RTL', 'Arabic', '200% text'],
      code: '''Directionality(textDirection: TextDirection.rtl,
  child: DInputOTP(maxLength: 6, initialValue: '123456',
    semanticLabel: 'رمز التحقق'))''',
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: _PatternExample(arabic: true),
      ),
    ),
  ],
);

class _PatternExample extends StatefulWidget {
  const _PatternExample({this.arabic = false});
  final bool arabic;
  @override
  State<_PatternExample> createState() => _PatternExampleState();
}

class _PatternExampleState extends State<_PatternExample> {
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.arabic ? 'رمز التحقق' : 'Digits Only';
    return DField(
      children: [
        DFieldLabel(
          focusNode: _focus,
          excludeSemantics: true,
          child: Text(label),
        ),
        DFieldControl(
          label: label,
          child: DInputOTP(
            maxLength: 6,
            initialValue: widget.arabic ? '123456' : null,
            pattern: dInputOTPDigits,
            focusNode: _focus,
          ),
        ),
      ],
    );
  }
}

class _SeparatedOTP extends StatelessWidget {
  const _SeparatedOTP({
    this.value,
    this.enabled = true,
    this.pattern,
    this.keyboardType,
    this.transformer,
    this.semanticLabel = 'One-time password',
  });
  final String? value;
  final bool enabled;
  final RegExp? pattern;
  final TextInputType? keyboardType;
  final DInputOTPTransformer? transformer;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => DInputOTP(
    maxLength: 6,
    value: value,
    enabled: enabled,
    pattern: pattern,
    keyboardType: keyboardType,
    inputTransformer: transformer,
    semanticLabel: semanticLabel,
    children: const [
      DInputOTPGroup(
        children: [DInputOTPSlot(index: 0), DInputOTPSlot(index: 1)],
      ),
      DInputOTPSeparator(),
      DInputOTPGroup(
        children: [DInputOTPSlot(index: 2), DInputOTPSlot(index: 3)],
      ),
      DInputOTPSeparator(),
      DInputOTPGroup(
        children: [DInputOTPSlot(index: 4), DInputOTPSlot(index: 5)],
      ),
    ],
  );
}

class _ControlledExample extends StatefulWidget {
  const _ControlledExample();
  @override
  State<_ControlledExample> createState() => _ControlledExampleState();
}

class _ControlledExampleState extends State<_ControlledExample> {
  String _value = '';
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DInputOTP(
        maxLength: 6,
        value: _value,
        semanticLabel: 'One-time password',
        onChanged: (value) => setState(() => _value = value),
      ),
      const SizedBox(height: 8),
      Text(
        _value.isEmpty
            ? 'Enter your one-time password.'
            : 'You entered: $_value',
        textAlign: TextAlign.center,
      ),
    ],
  );
}

class _InvalidExample extends StatelessWidget {
  const _InvalidExample();
  @override
  Widget build(BuildContext context) => DField(
    invalid: true,
    children: [
      DFieldControl(
        label: 'Verification code',
        errors: const ['Invalid code'],
        child: DInputOTP(
          maxLength: 6,
          value: '000000',
          invalid: true,
          children: const [
            DInputOTPGroup(
              children: [
                DInputOTPSlot(index: 0, invalid: true),
                DInputOTPSlot(index: 1, invalid: true),
              ],
            ),
            DInputOTPSeparator(),
            DInputOTPGroup(
              children: [
                DInputOTPSlot(index: 2, invalid: true),
                DInputOTPSlot(index: 3, invalid: true),
              ],
            ),
            DInputOTPSeparator(),
            DInputOTPGroup(
              children: [
                DInputOTPSlot(index: 4, invalid: true),
                DInputOTPSlot(index: 5, invalid: true),
              ],
            ),
          ],
        ),
      ),
      const DFieldError(errors: ['Invalid code']),
    ],
  );
}

class _OTPFormExample extends StatefulWidget {
  const _OTPFormExample();
  @override
  State<_OTPFormExample> createState() => _OTPFormExampleState();
}

class _OTPFormExampleState extends State<_OTPFormExample> {
  final _formKey = GlobalKey<FormState>();
  final _focus = FocusNode();
  String? _error;
  String? _saved;
  int _resends = 0;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _validateAndSave() {
    final valid = _formKey.currentState!.validate();
    setState(() => _error = valid ? null : 'Enter all six digits');
    if (valid) _formKey.currentState!.save();
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 448),
    child: Form(
      key: _formKey,
      child: DCard(
        children: [
          const DCardHeader(
            title: DCardTitle(child: Text('Verify your login')),
            description: DCardDescription(
              child: Text(
                'Enter the verification code we sent to m@example.com.',
              ),
            ),
          ),
          DCardContent(
            child: DField(
              invalid: _error != null,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DFieldLabel(
                      focusNode: _focus,
                      excludeSemantics: true,
                      child: const Text('Verification code'),
                    ),
                    DButton(
                      label: Text(
                        _resends == 0 ? 'Resend Code' : 'Resent ($_resends)',
                      ),
                      icon: const Icon(Icons.refresh, size: 16),
                      size: DButtonSize.small,
                      variant: DButtonVariant.outline,
                      onPressed: () => setState(() => _resends++),
                    ),
                  ],
                ),
                DFieldControl(
                  label: 'Verification code',
                  description: 'Enter the six-character code from your email.',
                  errors: [_error],
                  required: true,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DInputOTP(
                      maxLength: 6,
                      focusNode: _focus,
                      pattern: dInputOTPDigits,
                      validator: (value) =>
                          value?.length == 6 ? null : 'Enter all six digits',
                      onSaved: (value) => setState(() => _saved = value),
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      children: const [
                        DInputOTPGroup(
                          children: [
                            DInputOTPSlot(
                              index: 0,
                              width: 44,
                              height: 48,
                              fontSize: DiscourseTypography.xl,
                              lineHeight: 28,
                            ),
                            DInputOTPSlot(
                              index: 1,
                              width: 44,
                              height: 48,
                              fontSize: DiscourseTypography.xl,
                              lineHeight: 28,
                            ),
                            DInputOTPSlot(
                              index: 2,
                              width: 44,
                              height: 48,
                              fontSize: DiscourseTypography.xl,
                              lineHeight: 28,
                            ),
                          ],
                        ),
                        DInputOTPSeparator(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                        ),
                        DInputOTPGroup(
                          children: [
                            DInputOTPSlot(
                              index: 3,
                              width: 44,
                              height: 48,
                              fontSize: DiscourseTypography.xl,
                              lineHeight: 28,
                            ),
                            DInputOTPSlot(
                              index: 4,
                              width: 44,
                              height: 48,
                              fontSize: DiscourseTypography.xl,
                              lineHeight: 28,
                            ),
                            DInputOTPSlot(
                              index: 5,
                              width: 44,
                              height: 48,
                              fontSize: DiscourseTypography.xl,
                              lineHeight: 28,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const DFieldDescription(
                  child: Text('I no longer have access to this email address.'),
                ),
                DFieldError(errors: [_error]),
              ],
            ),
          ),
          DCardFooter(
            muted: false,
            child: DField(
              children: [
                DButton(
                  label: const Text('Verify'),
                  onPressed: _validateAndSave,
                ),
                DButton(
                  label: const Text('Reset'),
                  variant: DButtonVariant.ghost,
                  onPressed: () {
                    _formKey.currentState!.reset();
                    setState(() {
                      _error = null;
                      _saved = null;
                    });
                  },
                ),
                if (_saved != null) Text('Verified $_saved'),
                const DFieldDescription(
                  child: Text('Having trouble signing in? Contact support.'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
