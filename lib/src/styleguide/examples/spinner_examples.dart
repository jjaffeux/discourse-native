import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../discourse_ui.dart';
import '../styleguide_example.dart';

final spinnerExamples = ComponentExamples(
  description: 'A compact indicator for work in progress.',
  status: ComponentStatus.implemented,
  notes:
      'Import package:discourse_native/discourse_ui.dart; no extra dependency. '
      'DSpinner reproduces shadcn’s Lucide Loader2 arc on every platform: '
      'a 24-unit view box, round 2-unit stroke, 16px default box and linear '
      'clockwise rotation once per second. A child supplies custom artwork. '
      'Size is in logical pixels; strokeWidth scales with the view box. '
      'Color inherits IconTheme; explicit colors override it. semanticLabel defaults to '
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
          'Reduce motion freezes both the default and custom artwork.',
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
  child: customArtwork, // Any child, e.g. a different loader icon.
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
      states: const ['Default', 'Outline', 'Secondary', 'Disabled', 'Error'],
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
    padding: const EdgeInsetsDirectional.fromSTEB(5, 1, 7, 1),
    decoration: BoxDecoration(
      color: DTokens.of(context).muted,
      border: Border.all(color: Colors.transparent),
      borderRadius: BorderRadius.circular(32),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (syncing) const DSpinner(size: 12, semanticLabel: null),
      if (syncing) const SizedBox(width: DSpacing.xs),
      Flexible(child: Text(syncing ? 'Syncing' : 'Synced')),
    ]),
  ),
)''',
      builder: (_) => const _SpinnerBadges(),
    ),
    StyleguideExample(
      title: 'Input group validation',
      description:
          'Accept the initial validation, edit both fields and validate again. The disabled single-line '
          'input shows an inline-end spinner; the textarea uses a block-end '
          'status and send action. Accept or reject the sample to restore '
          'editing without losing text. No requests are made.',
      states: const ['Inline end', 'Block end', 'Disabled', 'Error', 'Success'],
      code: '''TextField(
  enabled: !validating,
  decoration: InputDecoration(
    hintText: 'Send a message...',
    isCollapsed: true,
    border: InputBorder.none,
    // The surrounding group supplies the border and padding.
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
          'Cancel, complete or fail the initial request, then start again. Retry after '
          'failure. The local state owner replaces the spinner with a readable '
          'result. Longer text wraps at narrow widths and large text scales.',
      states: const ['Empty', 'Busy', 'Canceled', 'Success', 'Error', 'Retry'],
      code: '''Column(children: [
  if (busy) Container(
    width: 32, height: 32,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: DTokens.of(context).muted,
      borderRadius: DTokens.of(context).borderRadius),
    child: const DSpinner(semanticLabel: 'Processing your request'),
  ),
  const SizedBox(height: DSpacing.md),
  Text(busy ? 'Processing your request' : status),
  const Text('Please wait while we process your request. Do not refresh the page.'),
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
          'directions, as in the reference.',
      states: const ['RTL', 'Narrow', 'Large text', 'Inherited color'],
      code: '''Row(children: [
  const DSpinner(semanticLabel: null),
  const SizedBox(width: 10),
  const Expanded(child: Text('جاري معالجة الدفع...')),
  const SizedBox(width: 10),
  Text('١٠٠٫٠٠ دولار', textAlign: TextAlign.end),
])''',
      builder: (_) => const _SpinnerPayment(),
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
              child: _custom ? const _ReferenceLoader() : null,
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
      const Align(
        alignment: AlignmentDirectional.center,
        child: Column(
          spacing: DSpacing.lg,
          children: [
            _ReferenceButton(
              variant: DButtonVariant.primary,
              inlineIcon: true,
              child: _SpinnerStatus(label: 'Loading...'),
            ),
            _ReferenceButton(
              inlineIcon: true,
              child: _SpinnerStatus(label: 'Please wait'),
            ),
            _ReferenceButton(
              variant: DButtonVariant.flat,
              inlineIcon: true,
              child: _SpinnerStatus(label: 'Processing'),
            ),
          ],
        ),
      ),
      const SizedBox(height: DSpacing.xl),

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
          spacing: DSpacing.lg,
          runSpacing: DSpacing.lg,
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
                  padding: EdgeInsetsDirectional.fromSTEB(
                    _trailing ? 7 : 5,
                    1,
                    _trailing ? 5 : 7,
                    1,
                  ),
                  decoration: BoxDecoration(
                    color: background,
                    border: Border.all(
                      color: outlined ? tokens.border : Colors.transparent,
                    ),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: IconTheme.merge(
                    data: IconThemeData(color: foreground),
                    child: DefaultTextStyle.merge(
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall!.copyWith(color: foreground),
                      child: _SpinnerStatus(
                        label: label,
                        trailing: _trailing,
                        busy: _busy,
                        size: 12,
                        gap: DSpacing.xs,
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
  bool _validating = true;
  String? _error;
  String _status = 'Validating...';

  void _finish({required bool accepted}) => setState(() {
    _validating = false;
    _error = accepted ? null : 'Sample rejected. Edit your message and retry.';
    _status = accepted ? 'Validation complete' : 'Validation failed';
  });

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final textStyle = Theme.of(context).textTheme.bodySmall;
    const bareInput = InputDecoration(
      hintText: 'Send a message...',
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      filled: false,
      isCollapsed: true,
      contentPadding: EdgeInsets.zero,
    );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 448),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SpinnerInputSurface(
              disabled: _validating,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(10, 5, 8, 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        label: 'Subject',
                        child: TextField(
                          key: const ValueKey('spinner-subject'),
                          enabled: !_validating,
                          style: textStyle,
                          decoration: bareInput,
                        ),
                      ),
                    ),
                    if (_validating) ...[
                      const SizedBox(width: 6),
                      DSpinner(
                        color: tokens.mutedForeground,
                        semanticLabel: 'Validating subject',
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: DSpacing.lg),
            _SpinnerInputSurface(
              disabled: _validating,
              invalid: _error != null,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Semantics(
                      label: 'Message',
                      child: TextField(
                        key: const ValueKey('spinner-message'),
                        enabled: !_validating,
                        minLines: 3,
                        maxLines: 4,
                        style: textStyle,
                        decoration: bareInput,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 10, 8),
                    child: IconTheme.merge(
                      data: IconThemeData(color: tokens.mutedForeground),
                      child: Row(
                        children: [
                          if (_validating) ...[
                            const DSpinner(semanticLabel: null),
                            const SizedBox(width: DSpacing.sm),
                          ],
                          Expanded(
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                _status,
                                style: Theme.of(context).textTheme.labelLarge!
                                    .copyWith(color: tokens.mutedForeground),
                              ),
                            ),
                          ),
                          const SizedBox(width: DSpacing.sm),
                          DButton(
                            key: const ValueKey('spinner-send'),
                            semanticLabel: 'Send message',
                            tooltip: 'Send message',
                            padding: const EdgeInsets.all(5),
                            variant: DButtonVariant.primary,
                            onPressed: _validating
                                ? null
                                : () => setState(
                                    () => _status = 'Message sent locally',
                                  ),
                            label: const Icon(Icons.arrow_upward, size: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: DSpacing.sm),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: textStyle!.copyWith(color: tokens.destructive),
                ),
              ),
            ],
            const SizedBox(height: DSpacing.lg),
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
                          _status = 'Validating...';
                        }),
                ),
                DButton(
                  label: const Text('Accept sample'),
                  onPressed: _validating ? () => _finish(accepted: true) : null,
                ),
                DButton(
                  label: const Text('Reject sample'),
                  onPressed: _validating
                      ? () => _finish(accepted: false)
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpinnerInputSurface extends StatefulWidget {
  const _SpinnerInputSurface({
    required this.child,
    required this.disabled,
    this.invalid = false,
  });
  final Widget child;
  final bool disabled;
  final bool invalid;

  @override
  State<_SpinnerInputSurface> createState() => _SpinnerInputSurfaceState();
}

class _SpinnerInputSurfaceState extends State<_SpinnerInputSurface> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final ring = widget.invalid ? tokens.destructive : tokens.focusRing;
    return Focus(
      onFocusChange: (value) => setState(() => _focused = value),
      child: Opacity(
        opacity: widget.disabled ? 0.5 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: widget.disabled
                ? tokens.border.withValues(alpha: 0.5)
                : tokens.background,
            border: Border.all(
              color: widget.invalid || _focused ? ring : tokens.border,
            ),
            borderRadius: tokens.borderRadius,
            boxShadow: widget.invalid || _focused
                ? [
                    BoxShadow(
                      color: ring.withValues(alpha: widget.invalid ? 0.2 : 0.5),
                      spreadRadius: 3,
                    ),
                  ]
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _SpinnerEmpty extends StatefulWidget {
  const _SpinnerEmpty();

  @override
  State<_SpinnerEmpty> createState() => _SpinnerEmptyState();
}

class _SpinnerEmptyState extends State<_SpinnerEmpty> {
  bool _busy = true;
  String _status = 'Processing your request';

  void _finish(String status) => setState(() {
    _busy = false;
    _status = status;
  });

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(DSpacing.xl),
      child: Column(
        children: [
          if (_busy) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: tokens.muted,
                borderRadius: tokens.borderRadius,
              ),
              alignment: Alignment.center,
              child: const DSpinner(semanticLabel: null),
            ),
            const SizedBox(height: DSpacing.lg),
          ],
          Semantics(
            liveRegion: true,
            child: Text(
              _status,
              textAlign: TextAlign.center,
              style: text.labelLarge!.copyWith(letterSpacing: -0.35),
            ),
          ),
          const SizedBox(height: DSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 384),
            child: Text(
              _busy
                  ? 'Please wait while we process your request. Do not refresh the page.'
                  : 'Your sample data is unchanged. Start a request to try again.',
              textAlign: TextAlign.center,
              style: text.bodySmall!.copyWith(
                height: 1.625,
                color: tokens.mutedForeground,
              ),
            ),
          ),
          const SizedBox(height: DSpacing.lg),
          _ReferenceButton(
            onPressed: _busy
                ? () => _finish('Request canceled')
                : () => setState(() {
                    _busy = true;
                    _status = 'Processing your request';
                  }),
            child: Text(_busy ? 'Cancel request' : 'Start request'),
          ),
          if (_busy) ...[
            const SizedBox(height: DSpacing.lg),
            Wrap(
              spacing: DSpacing.sm,
              runSpacing: DSpacing.sm,
              alignment: WrapAlignment.center,
              children: [
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
            ),
          ],
        ],
      ),
    );
  }
}

class _SpinnerStatus extends StatelessWidget {
  const _SpinnerStatus({
    required this.label,
    this.trailing = false,
    this.busy = true,
    this.size = 16,
    this.gap = DSpacing.xs,
  });

  final double size;
  final double gap;
  final String label;
  final bool trailing;
  final bool busy;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (busy && !trailing) ...[
        DSpinner(size: size, semanticLabel: null),
        SizedBox(width: gap),
      ],
      Flexible(child: Text(label)),
      if (busy && trailing) ...[
        SizedBox(width: gap),
        DSpinner(size: size, semanticLabel: null),
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

// The companion catalogue components are separate tasks. These local
// compositions use their reference dimensions without introducing public APIs.
class _ReferenceButton extends StatelessWidget {
  const _ReferenceButton({
    required this.child,
    this.variant = DButtonVariant.standard,
    this.onPressed,
    this.inlineIcon = false,
  });

  final Widget child;
  final DButtonVariant variant;
  final VoidCallback? onPressed;
  final bool inlineIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = DTokens.of(context);
    DButtonStateStyle state(
      Color background, {
      BorderSide border = BorderSide.none,
    }) => DButtonStateStyle(
      foregroundColor: tokens.foreground,
      backgroundColor: background,
      iconColor: tokens.foreground,
      border: border,
    );
    final buttons = theme.discourseButtons.copyWith(
      disabledOpacity: 0.5,
      standard: DButtonVariantStyle(
        enabled: state(
          tokens.background,
          border: BorderSide(color: tokens.border),
        ),
        interactive: state(
          tokens.muted,
          border: BorderSide(color: tokens.border),
        ),
      ),
      flat: DButtonVariantStyle(
        enabled: state(tokens.muted),
        interactive: state(tokens.hover),
      ),
    );
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          labelLarge: theme.textTheme.labelLarge!.copyWith(
            fontSize: 12.8,
            height: 20 / 12.8,
          ),
        ),
        extensions: [
          for (final extension in theme.extensions.values)
            if (extension is! DiscourseButtonTheme) extension,
          buttons,
        ],
      ),
      child: DButton(
        label: child,
        variant: variant,
        size: DButtonSize.small,
        padding: EdgeInsetsDirectional.fromSTEB(inlineIcon ? 6 : 10, 4, 10, 4),
        onPressed: onPressed,
      ),
    );
  }
}

class _SpinnerPayment extends StatelessWidget {
  const _SpinnerPayment();

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final title = rtl ? 'جاري معالجة الدفع...' : 'Processing payment...';
    final amount = rtl ? '١٠٠.٠٠ دولار' : '\$100.00';
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: tokens.muted.withValues(alpha: 0.5),
            border: Border.all(color: Colors.transparent),
            borderRadius: tokens.borderRadius,
          ),
          child: Semantics(
            label: '$title, $amount',
            liveRegion: true,
            excludeSemantics: true,
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  const DSpinner(semanticLabel: null),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: MediaQuery.textScalerOf(context).scale(14) <= 14
                          ? 1
                          : null,
                      overflow: MediaQuery.textScalerOf(context).scale(14) <= 14
                          ? TextOverflow.ellipsis
                          : null,
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge!.copyWith(height: 1.375),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth / 2,
                    ),
                    child: Text(
                      amount,
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReferenceLoader extends StatelessWidget {
  const _ReferenceLoader();

  @override
  Widget build(BuildContext context) {
    final icons = IconTheme.of(context);
    return SvgPicture.string(
      '''<svg
  xmlns="http://www.w3.org/2000/svg"
  width="24"
  height="24"
  viewBox="0 0 24 24"
  fill="none"
  stroke="currentColor"
  stroke-width="2"
  stroke-linecap="round"
  stroke-linejoin="round"
>
  <path d="M12 2v4" />
  <path d="m16.2 7.8 2.9-2.9" />
  <path d="M18 12h4" />
  <path d="m16.2 16.2 2.9 2.9" />
  <path d="M12 18v4" />
  <path d="m4.9 19.1 2.9-2.9" />
  <path d="M2 12h4" />
  <path d="m4.9 4.9 2.9 2.9" />
</svg>''',
      width: icons.size ?? 16,
      height: icons.size ?? 16,
      theme: SvgTheme(
        currentColor: icons.color ?? DTokens.of(context).foreground,
      ),
    );
  }
}
