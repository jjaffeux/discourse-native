import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final progressExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Completion and ongoing work, with optional labels and values.',
  notes:
      'Default range is 0–100; use max: 1 for fractional '
      'application values. Null/non-finite values are unknown; finite values clamp '
      'to min/max. Progress is read-only and does not take keyboard focus. '
      'DProgressLabel provides its accessible name; provide semanticsLabel when '
      'no visible label exists. DProgressValue supports localized builders. '
      'A 150ms fill transition respects reduced motion. Unknown work uses a '
      'one-third moving segment (static with reduced motion), a documented native '
      'adaptation for existing async strips. DButton controls temporarily replace '
      'the upstream demonstrative Slider; Slider remains its own catalogue task.',
  examples: [
    StyleguideExample(
      title: 'Basic',
      description:
          'The reference 60% width example advances from 13 to 66 after 500ms. Replay it locally.',
      states: const ['Determinate', 'Controlled'],
      code: "DProgress(value: 13, semanticsLabel: 'Loading content')",
      builder: (_) => const _Basic(),
    ),
    StyleguideExample(
      title: 'With label and value',
      description:
          'Source composition at 56%, with a full-width track below the header.',
      states: const ['Label', 'Value', 'Composition'],
      code: "const DProgress(value: 56,\n  \n  \n)",
      builder: (_) => const _ReferenceFrame(child: DProgress(value: 56)),
    ),
    StyleguideExample(
      title: 'Controlled',
      description:
          'Change local progress with pointer, touch, Tab and Return. '
          'The value survives live theme, direction and text-size changes.',
      states: const ['Controlled', 'Keyboard', 'Clamping'],
      code:
          "DProgress(value: value,\n  \n  )\n// Caller owns value; DButton updates it with setState.\n// Later compose the independently implemented Slider here.",
      builder: (_) => const _ReferenceFrame(child: _Controlled()),
    ),
    StyleguideExample(
      title: 'RTL',
      description: 'Logical-start fill and localized Arabic percentage.',
      states: const ['RTL', 'Localized'],
      code:
          "Directionality(textDirection: TextDirection.rtl,\n  child: DProgress(value: 56,\n    \n    ))",
      builder: (_) => const _ReferenceFrame(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: DProgress(value: 56),
        ),
      ),
    ),
    StyleguideExample(
      title: 'Async and range edges',
      description:
          'Unknown, zero, complete and out-of-range data. Reduced motion '
          'stops unknown-work animation. Long labels wrap at narrow widths.',
      states: const ['Indeterminate', 'Reduced motion', 'Min/max', 'Narrow'],
      code:
          "const DProgress(value: null,\n  \n  )\nconst DProgress(value: 150,  max: 200,\n  \n  )",
      builder: (_) => const Column(
        children: [
          DProgress(),
          SizedBox(height: 24),
          DProgress(value: 150, max: 200),
          SizedBox(height: 24),
          DProgress(value: -10),
          SizedBox(height: 24),
          DProgress(value: 120),
        ],
      ),
    ),
    StyleguideExample(
      title: 'Explicit parts',
      description:
          'The root can supply state and semantics to a caller-owned '
          'layout. Track and indicator colors remain live tokens by default.',
      states: const ['Track', 'Indicator', 'Custom composition'],
      code: "const DProgress(value: 40, )",
      builder: (_) => const DProgress(value: 40),
    ),
  ],
);

class _Basic extends StatefulWidget {
  const _Basic();
  @override
  State<_Basic> createState() => _BasicState();
}

class _BasicState extends State<_Basic> {
  double value = 13;
  Timer? timer;
  void advance() {
    timer?.cancel();
    timer = Timer(
      const Duration(milliseconds: 500),
      () => setState(() => value = 66),
    );
  }

  @override
  void initState() {
    super.initState();
    advance();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      FractionallySizedBox(
        widthFactor: .6,
        child: DProgress(value: value, semanticsLabel: 'Loading content'),
      ),
      const SizedBox(height: 24),
      DButton(
        onPressed: () {
          setState(() => value = 13);
          advance();
        },
        label: const Text('Replay'),
      ),
    ],
  );
}

class _Controlled extends StatefulWidget {
  const _Controlled();
  @override
  State<_Controlled> createState() => _ControlledState();
}

class _ControlledState extends State<_Controlled> {
  double? value = 50;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      DProgress(
        value: value,
        track: const Column(children: [DProgressTrack(), DProgressValue()]),
      ),
      const SizedBox(height: 24),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          DButton(
            onPressed: () => setState(() => value = (value ?? 0) - 10),
            label: const Text('Decrease'),
          ),
          DButton(
            onPressed: () => setState(() => value = (value ?? 0) + 10),
            label: const Text('Increase'),
          ),
          DButton(
            onPressed: () => setState(() => value = value == null ? 50 : null),
            label: const Text('Unknown / resume'),
          ),
        ],
      ),
    ],
  );
}

class _ReferenceFrame extends StatelessWidget {
  const _ReferenceFrame({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 384),
      child: child,
    ),
  );
}
