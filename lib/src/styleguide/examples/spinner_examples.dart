import 'package:flutter/material.dart';

import '../../../discourse_ui.dart';
import '../styleguide_example.dart';

final spinnerExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  notes:
      'Import package:discourse_native/discourse_ui.dart; no extra dependency. '
      'DSpinner uses native Apple artwork on macOS/iOS and a Material ring '
      'elsewhere. A child supplies custom rotating artwork. Size is in logical '
      'pixels and color inherits IconTheme; explicit colors override it. '
      'strokeWidth applies to the Material ring. semanticLabel defaults to '
      'Loading; localize it, or set null when the surrounding control owns the '
      'status. Stationary spinners still mean busy. Remove them on completion. '
      'Motion pauses for Reduce motion, inactive apps and disabled ticker '
      'subtrees. The spinner takes no input or focus. Host controls own actions, '
      'errors and async completion. Badge, input and empty surfaces here are '
      'local Flutter compositions; their catalogue APIs belong to separate tasks.',
  examples: [
    StyleguideExample(
      title: 'Size and customization',
      description:
          'Compare the four reference sizes, then change the sample artwork, '
          'size, color and motion. Preview themes update inherited colors live. '
          'Reduce motion freezes both the native and custom artwork.',
      states: const ['12', '16', '24', '32', 'Custom icon', 'Stationary'],
      code: '''const Wrap(
  spacing: DSpacing.xl,
  children: [
    DSpinner(size: 12), DSpinner(),
    DSpinner(size: 24), DSpinner(size: 32),
  ],
)
// Custom artwork inherits size and color. The caller owns these values.
DSpinner(
  size: size,
  color: useAccent ? DTokens.of(context).primary : null,
  animating: animate,
  semanticLabel: 'Processing sample',
  child: custom ? const Icon(Icons.autorenew) : null,
)''',
      builder: (_) => const _SpinnerAppearance(),
    ),
    StyleguideExample(
      title: 'Button loading and completion',
      description:
          'Start any operation. Its button disables while busy and retains its '
          'accessible name. Complete or fail the operation, then start again. '
          'The trailing example composes a spinner after its label. Use Tab and '
          'Enter or Space; loading buttons cannot submit twice.',
      states: const ['Primary', 'Standard', 'Transparent', 'Disabled', 'Error'],
      code: '''DButton(
  label: const Text('Save changes'),
  loadingLabel: const Text('Saving…'),
  variant: DButtonVariant.primary,
  loading: busy,
  onPressed: startSave,
)
// DButton owns the busy semantics and uses DSpinner internally.
// Ordinary label composition also supports an inline-end spinner:
const DButton(
  onPressed: null,
  semanticLabel: 'Processing',
  label: Row(mainAxisSize: MainAxisSize.min, children: [
    Flexible(child: Text('Processing')),
    SizedBox(width: DSpacing.sm),
    DSpinner(semanticLabel: null),
  ]),
)''',
      builder: (_) => const _SpinnerButtons(),
    ),
    StyleguideExample(
      title: 'Badge and inline placement',
      description:
          'Toggle activity and inline-end placement. These local badge '
          'compositions demonstrate default, secondary and outline surfaces. '
          'Their text and indicator follow preview direction together; the '
          'status remains understandable without animation or color.',
      states: const ['Default surface', 'Secondary surface', 'Outline', 'RTL'],
      code: '''Semantics(
  label: syncing ? 'Syncing' : 'Synced',
  liveRegion: true,
  excludeSemantics: true,
  child: Container(
    padding: const EdgeInsetsDirectional.all(DSpacing.sm),
    decoration: BoxDecoration(
      color: DTokens.of(context).muted,
      borderRadius: DTokens.of(context).borderRadius,
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (syncing) const DSpinner(semanticLabel: null),
      if (syncing) const SizedBox(width: DSpacing.sm),
      Flexible(child: Text(syncing ? 'Syncing' : 'Synced')),
    ]),
  ),
)''',
      builder: (_) => const _SpinnerBadges(),
    ),
    StyleguideExample(
      title: 'Input group validation',
      description:
          'Edit both fields and start validation. The disabled single-line '
          'input shows an inline-end spinner; the textarea uses a block-end '
          'status and send action. Accept or reject the sample to restore '
          'editing without losing text. No requests are made.',
      states: const ['Inline end', 'Block end', 'Disabled', 'Error', 'Success'],
      code: '''TextField(
  enabled: !validating,
  decoration: InputDecoration(
    labelText: 'Subject',
    suffixIcon: validating ? const Center(
      widthFactor: 1, heightFactor: 1,
      child: DSpinner(semanticLabel: 'Validating subject'),
    ) : null,
  ),
)
// Below a multiline TextField:
Row(children: [
  if (validating) const DSpinner(semanticLabel: null),
  const SizedBox(width: DSpacing.sm),
  Expanded(child: Text(validating ? 'Validating…' : 'Ready')),
  IconButton(
    tooltip: 'Send message',
    onPressed: validating ? null : send,
    icon: const Icon(Icons.arrow_upward),
  ),
])''',
      builder: (_) => const _SpinnerInputs(),
    ),
    StyleguideExample(
      title: 'Empty state with cancellation',
      description:
          'Start a request, then cancel, complete or fail it. Retry after '
          'failure. The local state owner replaces the spinner with a readable '
          'result. Longer text wraps at narrow widths and large text scales.',
      states: const ['Empty', 'Busy', 'Canceled', 'Success', 'Error', 'Retry'],
      code: '''Column(children: [
  if (busy) const DSpinner(
    size: 32,
    semanticLabel: 'Processing your request',
  ),
  const SizedBox(height: DSpacing.md),
  Text(busy ? 'Processing your request' : status),
  const Text('You can cancel while this operation is pending.'),
  const SizedBox(height: DSpacing.md),
  DButton(
    label: Text(busy ? 'Cancel request' : 'Start request'),
    onPressed: busy ? cancel : start,
  ),
])''',
      builder: (_) => const _SpinnerEmpty(),
    ),
    StyleguideExample(
      title: 'RTL payment status',
      description:
          'The row inherits the preview direction. Switch Right to left and '
          '200% text. The leading spinner and amount change logical positions '
          'and the long label wraps. Rotation remains clockwise in both '
          'directions, as on native platforms.',
      states: const ['RTL', 'Narrow', 'Large text', 'Inherited color'],
      code: '''Row(children: [
  const DSpinner(semanticLabel: null),
  const SizedBox(width: DSpacing.md),
  const Expanded(child: Text('جاري معالجة الدفع…')),
  const SizedBox(width: DSpacing.sm),
  Flexible(child: Text('١٠٠٫٠٠ دولار', textAlign: TextAlign.end)),
])''',
      builder: (context) => _SpinnerSurface(
        child: Semantics(
          label: 'جاري معالجة الدفع، ١٠٠٫٠٠ دولار',
          liveRegion: true,
          excludeSemantics: true,
          child: const Row(
            children: [
              DSpinner(semanticLabel: null),
              SizedBox(width: DSpacing.md),
              Expanded(child: Text('جاري معالجة الدفع…')),
              SizedBox(width: DSpacing.sm),
              Flexible(child: Text('١٠٠٫٠٠ دولار', textAlign: TextAlign.end)),
            ],
          ),
        ),
      ),
    ),
  ],
);

class _SpinnerAppearance extends StatefulWidget {
  const _SpinnerAppearance();

  @override
  State<_SpinnerAppearance> createState() => _SpinnerAppearanceState();
}

class _SpinnerAppearanceState extends State<_SpinnerAppearance> {
  double _size = 24;
  bool _custom = false;
  bool _accent = false;
  bool _animate = true;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: DSpacing.xl,
        runSpacing: DSpacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final size in [12.0, 16.0, 24.0, 32.0])
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DSpinner(size: size, semanticLabel: null),
                const SizedBox(height: DSpacing.sm),
                Text('${size.toInt()} px'),
              ],
            ),
        ],
      ),
      const SizedBox(height: DSpacing.xl),
      _SpinnerSurface(
        child: Row(
          children: [
            DSpinner(
              key: const ValueKey('spinner-custom-sample'),
              size: _size,
              color: _accent ? DTokens.of(context).primary : null,
              animating: _animate,
              semanticLabel: 'Processing sample',
              child: _custom ? const Icon(Icons.autorenew) : null,
            ),
            const SizedBox(width: DSpacing.md),
            const Expanded(child: Text('Processing sample')),
          ],
        ),
      ),
      const SizedBox(height: DSpacing.md),
      Wrap(
        spacing: DSpacing.sm,
        runSpacing: DSpacing.xs,
        children: [
          for (final size in [12.0, 16.0, 24.0, 32.0])
            ChoiceChip(
              label: Text('Size ${size.toInt()}'),
              selected: _size == size,
              onSelected: (_) => setState(() => _size = size),
            ),
        ],
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Custom artwork'),
        value: _custom,
        onChanged: (value) => setState(() => _custom = value),
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Accent color'),
        value: _accent,
        onChanged: (value) => setState(() => _accent = value),
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Animate sample'),
        value: _animate,
        onChanged: (value) => setState(() => _animate = value),
      ),
    ],
  );
}

class _SpinnerButtons extends StatefulWidget {
  const _SpinnerButtons();

  @override
  State<_SpinnerButtons> createState() => _SpinnerButtonsState();
}

class _SpinnerButtonsState extends State<_SpinnerButtons> {
  int? _busy;
  String _status = 'No operation started';

  void _finish(String status) => setState(() {
    _busy = null;
    _status = status;
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: DSpacing.sm,
        runSpacing: DSpacing.sm,
        children: [
          for (final (index, label, variant) in [
            (0, 'Save changes', DButtonVariant.primary),
            (1, 'Sync locally', DButtonVariant.standard),
            (2, 'Process sample', DButtonVariant.transparent),
          ])
            DButton(
              label: Text(label),
              loadingLabel: Text(
                ['Loading…', 'Please wait', 'Processing'][index],
              ),
              loading: _busy == index,
              variant: variant,
              onPressed: _busy != null
                  ? null
                  : () => setState(() {
                      _busy = index;
                      _status = '$label in progress';
                    }),
            ),
          const DButton(
            onPressed: null,
            semanticLabel: 'Processing',
            label: _SpinnerStatus(label: 'Processing', trailing: true),
          ),
        ],
      ),
      const SizedBox(height: DSpacing.md),
      Wrap(
        spacing: DSpacing.sm,
        runSpacing: DSpacing.sm,
        children: [
          DButton(
            label: const Text('Complete operation'),
            onPressed: _busy == null
                ? null
                : () => _finish('Operation complete'),
          ),
          DButton(
            label: const Text('Fail operation'),
            onPressed: _busy == null
                ? null
                : () => _finish('Operation failed. Try again.'),
          ),
        ],
      ),
      const SizedBox(height: DSpacing.md),
      Semantics(liveRegion: true, child: Text(_status)),
    ],
  );
}

class _SpinnerBadges extends StatefulWidget {
  const _SpinnerBadges();

  @override
  State<_SpinnerBadges> createState() => _SpinnerBadgesState();
}

class _SpinnerBadgesState extends State<_SpinnerBadges> {
  bool _busy = true;
  bool _trailing = false;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: DSpacing.md,
          runSpacing: DSpacing.md,
          children: [
            for (final (label, background, foreground, outlined) in [
              (
                _busy ? 'Syncing' : 'Synced',
                tokens.primary,
                tokens.primaryForeground,
                false,
              ),
              (
                _busy ? 'Updating' : 'Updated',
                tokens.muted,
                tokens.foreground,
                false,
              ),
              (
                _busy ? 'Processing' : 'Processed',
                tokens.background,
                tokens.foreground,
                true,
              ),
            ])
              Semantics(
                label: label,
                liveRegion: true,
                excludeSemantics: true,
                child: Container(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: DSpacing.md,
                    vertical: DSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: background,
                    border: outlined ? Border.all(color: tokens.border) : null,
                    borderRadius: tokens.borderRadius,
                  ),
                  child: IconTheme.merge(
                    data: IconThemeData(color: foreground),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: foreground),
                      child: _SpinnerStatus(
                        label: label,
                        trailing: _trailing,
                        busy: _busy,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Activity in progress'),
          value: _busy,
          onChanged: (value) => setState(() => _busy = value),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Spinner at inline end'),
          value: _trailing,
          onChanged: (value) => setState(() => _trailing = value),
        ),
      ],
    );
  }
}

class _SpinnerInputs extends StatefulWidget {
  const _SpinnerInputs();

  @override
  State<_SpinnerInputs> createState() => _SpinnerInputsState();
}

class _SpinnerInputsState extends State<_SpinnerInputs> {
  bool _validating = false;
  String? _error;
  String _status = 'Ready to validate';

  void _finish({required bool accepted}) => setState(() {
    _validating = false;
    _error = accepted ? null : 'Sample rejected. Edit your message and retry.';
    _status = accepted ? 'Validation complete' : 'Validation failed';
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        enabled: !_validating,
        decoration: InputDecoration(
          labelText: 'Subject',
          border: const OutlineInputBorder(),
          suffixIcon: _validating
              ? const Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: DSpinner(semanticLabel: 'Validating subject'),
                )
              : null,
        ),
      ),
      const SizedBox(height: DSpacing.md),
      _SpinnerSurface(
        child: Column(
          children: [
            TextField(
              enabled: !_validating,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Message',
                errorText: _error,
                errorMaxLines: 4,
              ),
            ),
            const SizedBox(height: DSpacing.sm),
            Row(
              children: [
                if (_validating) ...[
                  const DSpinner(semanticLabel: null),
                  const SizedBox(width: DSpacing.sm),
                ],
                Expanded(
                  child: Semantics(liveRegion: true, child: Text(_status)),
                ),
                IconButton(
                  tooltip: 'Send message',
                  onPressed: _validating
                      ? null
                      : () => setState(() => _status = 'Message sent locally'),
                  icon: const Icon(Icons.arrow_upward),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: DSpacing.md),
      Wrap(
        spacing: DSpacing.sm,
        runSpacing: DSpacing.sm,
        children: [
          DButton(
            label: const Text('Validate sample'),
            onPressed: _validating
                ? null
                : () => setState(() {
                    _validating = true;
                    _error = null;
                    _status = 'Validating…';
                  }),
          ),
          DButton(
            label: const Text('Accept sample'),
            onPressed: _validating ? () => _finish(accepted: true) : null,
          ),
          DButton(
            label: const Text('Reject sample'),
            onPressed: _validating ? () => _finish(accepted: false) : null,
          ),
        ],
      ),
    ],
  );
}

class _SpinnerEmpty extends StatefulWidget {
  const _SpinnerEmpty();

  @override
  State<_SpinnerEmpty> createState() => _SpinnerEmptyState();
}

class _SpinnerEmptyState extends State<_SpinnerEmpty> {
  bool _busy = false;
  String _status = 'No request started';

  void _finish(String status) => setState(() {
    _busy = false;
    _status = status;
  });

  @override
  Widget build(BuildContext context) => _SpinnerSurface(
    child: Column(
      children: [
        if (_busy) const DSpinner(size: 32, semanticLabel: null),
        if (_busy) const SizedBox(height: DSpacing.md),
        Semantics(
          liveRegion: true,
          child: Text(
            _status,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: DSpacing.sm),
        const Text(
          'You can cancel while this operation is pending. Your sample data '
          'stays here when you change themes, direction or text size.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: DSpacing.md),
        Wrap(
          spacing: DSpacing.sm,
          runSpacing: DSpacing.sm,
          alignment: WrapAlignment.center,
          children: [
            DButton(
              label: Text(_busy ? 'Cancel request' : 'Start request'),
              onPressed: _busy
                  ? () => _finish('Request canceled')
                  : () => setState(() {
                      _busy = true;
                      _status = 'Processing your request';
                    }),
            ),
            if (_busy) ...[
              DButton(
                label: const Text('Complete request'),
                onPressed: () => _finish('Request complete'),
              ),
              DButton(
                label: const Text('Fail request'),
                onPressed: () =>
                    _finish('Request failed. Start again to retry.'),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

class _SpinnerStatus extends StatelessWidget {
  const _SpinnerStatus({
    required this.label,
    this.trailing = false,
    this.busy = true,
  });

  final String label;
  final bool trailing;
  final bool busy;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (busy && !trailing) ...[
        const DSpinner(semanticLabel: null),
        const SizedBox(width: DSpacing.sm),
      ],
      Flexible(child: Text(label)),
      if (busy && trailing) ...[
        const SizedBox(width: DSpacing.sm),
        const DSpinner(semanticLabel: null),
      ],
    ],
  );
}

class _SpinnerSurface extends StatelessWidget {
  const _SpinnerSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(DSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: tokens.borderRadius,
      ),
      child: child,
    );
  }
}
