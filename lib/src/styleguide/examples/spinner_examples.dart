import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../discourse_ui.dart';
import '../styleguide_example.dart';
import 'button_reference_icons.dart';

final spinnerExamples = ComponentExamples(
  description: 'A compact indicator for work in progress.',
  status: ComponentStatus.implemented,
  notes:
      'Import package:discourse_native/discourse_ui.dart; no extra dependency. '
      'DSpinner uses the Lucide Loader2 arc on every platform: '
      'a 24-unit view box, round 2-unit stroke, 16px default box and linear '
      'clockwise rotation once per second. A child supplies custom artwork. '
      'Size is in logical pixels; strokeWidth scales with the view box. '
      'Color inherits IconTheme, so Button, Badge, Item media, Input Group '
      'addons and Empty media tint it like the reference; explicit colors '
      'override it. semanticLabel defaults to Loading; localize it, or set null '
      'when the surrounding control owns the status, as DButton and DBadge do. '
      'Stationary spinners still mean busy. Remove them on completion. Motion '
      'pauses for Reduce motion and disabled ticker subtrees, and keeps '
      'turning in an unfocused window like the reference. The spinner takes '
      'no input or focus. Host controls own actions, errors and async '
      'completion. The compositions below use the public DItem, DButton, '
      'DBadge, DInputGroup and DEmpty components.',
  examples: [
    StyleguideExample(
      title: 'Processing payment',
      description:
          'The reference demo: a muted Item with a leading spinner, a '
          'one-line title and a tabular amount at the inline end. The spinner '
          'announces Loading; the row inherits the preview direction and '
          'reflows for large text.',
      states: const ['Muted item', 'Inherited color', 'Large text'],
      code: '''ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: 320),
  child: DItem(
    variant: DItemVariant.muted,
    children: [
      const DItemMedia(child: DSpinner()),
      const DItemContent(
        children: [DItemTitle(child: Text('Processing payment...'))],
      ),
      DItemContent(
        children: [
          Text(
            r'\$100.00',
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    ],
  ),
)''',
      builder: (_) => const _SpinnerPayment(title: 'Processing payment...'),
    ),
    StyleguideExample(
      title: 'Size',
      description:
          'The four reference sizes with 24px gaps: 12, 16 (default), 24 and '
          '32 logical pixels. The stroke scales with the view box.',
      states: const ['12', '16', '24', '32'],
      code: '''const Row(
  mainAxisSize: MainAxisSize.min,
  spacing: DSpacing.xl,
  children: [
    DSpinner(size: 12),
    DSpinner(),
    DSpinner(size: 24),
    DSpinner(size: 32),
  ],
)''',
      builder: (_) => const Wrap(
        spacing: DSpacing.xl,
        runSpacing: DSpacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DSpinner(size: 12),
          DSpinner(),
          DSpinner(size: 24),
          DSpinner(size: 32),
        ],
      ),
    ),
    StyleguideExample(
      title: 'Customization',
      description:
          'The reference replaces the arc with Lucide LoaderIcon. Toggle the '
          'custom artwork, accent color, size and motion; preview themes '
          'update inherited colors live. Reduce motion freezes both artworks.',
      states: const ['Loader icon', 'Accent color', 'Stationary'],
      code:
          '''// Custom artwork inherits size and color. The caller owns these values.
DSpinner(
  size: size,
  color: useAccent ? DTokens.of(context).primary : null,
  animating: animate,
  semanticLabel: 'Processing sample',
  child: custom ? const LoaderIcon() : null, // Any child, e.g. an SVG icon.
)''',
      builder: (_) => const _SpinnerAppearance(),
    ),
    StyleguideExample(
      title: 'Button',
      description:
          'The reference: three disabled small buttons with an inline-start '
          'spinner in the default, outline and secondary variants. Below, '
          'start any operation: its button disables while busy and retains '
          'its accessible name; complete or fail it, then start again. The '
          'last button places the spinner at the inline end. Use Tab and '
          'Enter or Space; loading buttons cannot submit twice.',
      states: const ['Default', 'Outline', 'Secondary', 'Inline end', 'Busy'],
      code: '''const Column(
  spacing: DSpacing.lg,
  children: [
    DButton(
      size: DButtonSize.small,
      icon: DSpinner(semanticLabel: null),
      label: Text('Loading...'),
      onPressed: null,
    ),
    DButton(
      variant: DButtonVariant.outline,
      size: DButtonSize.small,
      icon: DSpinner(semanticLabel: null),
      label: Text('Please wait'),
      onPressed: null,
    ),
    DButton(
      variant: DButtonVariant.secondary,
      size: DButtonSize.small,
      icon: DSpinner(semanticLabel: null),
      label: Text('Processing'),
      onPressed: null,
    ),
  ],
)
// DButton owns the busy semantics and composes DSpinner internally.
DButton(
  label: const Text('Save changes'),
  loadingLabel: const Text('Saving…'),
  loading: busy,
  onPressed: startSave,
)
// An inline-end spinner uses the icon slot after the label.
const DButton(
  icon: DSpinner(semanticLabel: null),
  iconPosition: DButtonIconPosition.end,
  label: Text('Processing'),
  onPressed: null,
)''',
      builder: (_) => const _SpinnerButtons(),
    ),
    StyleguideExample(
      title: 'Badge',
      description:
          'Toggle activity and inline-end placement. These DBadge '
          'compositions demonstrate default, secondary and outline surfaces '
          'with the 12px badge artwork. Their text and indicator follow the '
          'preview direction together; the status remains understandable '
          'without animation or color.',
      states: const ['Default', 'Secondary', 'Outline', 'Inline end', 'RTL'],
      code: """DBadge(
  variant: DBadgeVariant.secondary,
  leading: syncing ? const DSpinner(size: 12, semanticLabel: null) : null,
  liveRegion: true,
  child: Text(syncing ? 'Syncing' : 'Synced'),
)""",
      builder: (_) => const _SpinnerBadges(),
    ),
    StyleguideExample(
      title: 'Input Group',
      description:
          'The reference: a disabled input with an inline-end spinner, and a '
          'disabled textarea whose block-end addon shows a spinner, status '
          'text and a send action. Addons tint the spinner muted. Accept or '
          'reject the sample to restore editing without losing text, then '
          'validate again. No requests are made.',
      states: const ['Inline end', 'Block end', 'Disabled', 'Error', 'Success'],
      code: '''DInputGroup(children: [
  DInputGroupInput(enabled: !validating, hintText: 'Send a message...',
    semanticLabel: 'Subject'),
  if (validating) const DInputGroupAddon(
    alignment: DInputGroupAddonAlignment.inlineEnd,
    child: DSpinner(semanticLabel: 'Validating subject')),
])
DInputGroup(invalid: error != null, children: [
  DInputGroupTextarea(enabled: !validating, minLines: 3, maxLines: 4,
    hintText: 'Send a message...', semanticLabel: 'Message'),
  DInputGroupAddon(alignment: DInputGroupAddonAlignment.blockEnd,
    child: Row(children: [
      if (validating) ...[
        const DSpinner(semanticLabel: null),
        const SizedBox(width: DSpacing.sm),
      ],
      Expanded(child: Text(status)),
      const SizedBox(width: DSpacing.sm),
      DInputGroupButton.icon(
        icon: const ButtonReferenceIcon(ButtonReferenceIcon.arrowUp),
        tooltip: 'Send', variant: DButtonVariant.primary,
        onPressed: validating ? null : send),
    ])),
])''',
      builder: (_) => const _SpinnerInputs(),
    ),
    StyleguideExample(
      title: 'Empty',
      description:
          'The reference: icon media holding the spinner, a title, a '
          'description and a small outline Cancel action. Cancel, complete or '
          'fail the request, then start again; the local state owner replaces '
          'the spinner with a readable result. Text wraps at narrow widths.',
      states: const ['Busy', 'Canceled', 'Success', 'Error', 'Retry'],
      code: '''DEmpty(children: [
  DEmptyHeader(children: [
    if (busy) const DEmptyMedia(
      variant: DEmptyMediaVariant.icon, child: DSpinner()),
    DEmptyTitle(busy ? 'Processing your request' : status),
    DEmptyDescription(busy
        ? 'Please wait while we process your request. Do not refresh the page.'
        : 'Your sample data is unchanged. Start a request to try again.'),
  ]),
  DEmptyContent(children: [
    DButton(
      variant: DButtonVariant.outline,
      size: DButtonSize.small,
      label: Text(busy ? 'Cancel' : 'Start request'),
      onPressed: busy ? cancel : start,
    ),
  ]),
])''',
      builder: (_) => const _SpinnerEmpty(),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'The reference language selector switches the payment Item between '
          'English, Arabic and Hebrew. Direction follows the language: the '
          'spinner keeps the logical start, the amount the inline end, and '
          'rotation stays clockwise.',
      states: const ['Arabic', 'Hebrew', 'English'],
      code: '''DDirection(
  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
  child: DItem(
    variant: DItemVariant.muted,
    children: [
      const DItemMedia(child: DSpinner()),
      DItemContent(children: [DItemTitle(child: Text(title))]),
      DItemContent(children: [Text(amount, style: tabular)]),
    ],
  ),
)''',
      builder: (_) => const _SpinnerRtl(),
    ),
  ],
);

class _SpinnerPayment extends StatelessWidget {
  const _SpinnerPayment({required this.title, this.amount = '\$100.00'});

  final String title;
  final String amount;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: DItem(
        variant: DItemVariant.muted,
        children: [
          const DItemMedia(child: DSpinner()),
          DItemContent(children: [DItemTitle(child: Text(title))]),
          DItemContent(
            children: [
              Text(
                amount,
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _SpinnerRtl extends StatefulWidget {
  const _SpinnerRtl();

  @override
  State<_SpinnerRtl> createState() => _SpinnerRtlState();
}

class _SpinnerRtlState extends State<_SpinnerRtl> {
  String _language = 'ar';

  @override
  Widget build(BuildContext context) {
    final (title, amount) = switch (_language) {
      'ar' => ('جاري معالجة الدفع...', '١٠٠.٠٠ دولار'),
      'he' => ('מעבד תשלום...', '\$100.00'),
      _ => ('Processing payment...', '\$100.00'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DSelect<String>.controlled(
          value: _language,
          semanticLabel: 'Language',
          entries: const [
            DSelectOption(
              value: 'en',
              label: 'English',
              child: Text('English'),
            ),
            DSelectOption(
              value: 'ar',
              label: 'العربية',
              child: Text('العربية'),
            ),
            DSelectOption(value: 'he', label: 'עברית', child: Text('עברית')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _language = value);
          },
        ),
        const SizedBox(height: DSpacing.lg),
        DDirection(
          textDirection: _language == 'en'
              ? TextDirection.ltr
              : TextDirection.rtl,
          child: _SpinnerPayment(title: title, amount: amount),
        ),
      ],
    );
  }
}

class _SpinnerAppearance extends StatefulWidget {
  const _SpinnerAppearance();

  @override
  State<_SpinnerAppearance> createState() => _SpinnerAppearanceState();
}

class _SpinnerAppearanceState extends State<_SpinnerAppearance> {
  double _size = 16;
  bool _custom = true;
  bool _accent = false;
  bool _animate = true;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          DSpinner(
            key: const ValueKey('spinner-custom-sample'),
            size: _size,
            color: _accent ? DTokens.of(context).primary : null,
            animating: _animate,
            semanticLabel: 'Processing sample',
            child: _custom ? const _ReferenceLoader() : null,
          ),
          const SizedBox(width: DSpacing.lg),
          const Expanded(child: Text('Processing sample')),
        ],
      ),
      const SizedBox(height: DSpacing.lg),
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
      DSwitchTile(
        title: const Text('Custom artwork'),
        value: _custom,
        onChanged: (value) => setState(() => _custom = value),
      ),
      DSwitchTile(
        title: const Text('Accent color'),
        value: _accent,
        onChanged: (value) => setState(() => _accent = value),
      ),
      DSwitchTile(
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
            DButton(
              size: DButtonSize.small,
              icon: DSpinner(semanticLabel: null),
              label: Text('Loading...'),
              onPressed: null,
            ),
            DButton(
              variant: DButtonVariant.outline,
              size: DButtonSize.small,
              icon: DSpinner(semanticLabel: null),
              label: Text('Please wait'),
              onPressed: null,
            ),
            DButton(
              variant: DButtonVariant.secondary,
              size: DButtonSize.small,
              icon: DSpinner(semanticLabel: null),
              label: Text('Processing'),
              onPressed: null,
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
            (1, 'Sync locally', DButtonVariant.outline),
            (2, 'Process sample', DButtonVariant.secondary),
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
            icon: DSpinner(semanticLabel: null),
            iconPosition: DButtonIconPosition.end,
            label: Text('Processing'),
            onPressed: null,
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: DSpacing.lg,
        runSpacing: DSpacing.lg,
        children: [
          for (final (label, variant) in [
            (_busy ? 'Syncing' : 'Synced', DBadgeVariant.primary),
            (_busy ? 'Updating' : 'Updated', DBadgeVariant.secondary),
            (_busy ? 'Processing' : 'Processed', DBadgeVariant.outline),
          ])
            DBadge(
              variant: variant,
              liveRegion: true,
              leading: _busy && !_trailing
                  ? const DSpinner(size: 12, semanticLabel: null)
                  : null,
              trailing: _busy && _trailing
                  ? const DSpinner(size: 12, semanticLabel: null)
                  : null,
              child: Text(label),
            ),
        ],
      ),
      const SizedBox(height: DSpacing.md),
      DSwitchTile(
        title: const Text('Activity in progress'),
        value: _busy,
        onChanged: (value) => setState(() => _busy = value),
      ),
      DSwitchTile(
        title: const Text('Spinner at inline end'),
        value: _trailing,
        onChanged: (value) => setState(() => _trailing = value),
      ),
    ],
  );
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
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 448),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DInputGroup(
              children: [
                DInputGroupInput(
                  key: const ValueKey('spinner-subject'),
                  enabled: !_validating,
                  hintText: 'Send a message...',
                  semanticLabel: 'Subject',
                ),
                if (_validating)
                  const DInputGroupAddon(
                    alignment: DInputGroupAddonAlignment.inlineEnd,
                    child: DSpinner(semanticLabel: 'Validating subject'),
                  ),
              ],
            ),
            const SizedBox(height: DSpacing.lg),
            DInputGroup(
              invalid: _error != null,
              children: [
                DInputGroupTextarea(
                  key: const ValueKey('spinner-message'),
                  enabled: !_validating,
                  minLines: 3,
                  maxLines: 4,
                  hintText: 'Send a message...',
                  semanticLabel: 'Message',
                ),
                DInputGroupAddon(
                  alignment: DInputGroupAddonAlignment.blockEnd,
                  child: Row(
                    children: [
                      if (_validating) ...[
                        const DSpinner(semanticLabel: null),
                        const SizedBox(width: DSpacing.sm),
                      ],
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(_status),
                        ),
                      ),
                      const SizedBox(width: DSpacing.sm),
                      DInputGroupButton.icon(
                        key: const ValueKey('spinner-send'),
                        icon: IconTheme.merge(
                          data: const IconThemeData(size: 14),
                          child: const ButtonReferenceIcon(
                            ButtonReferenceIcon.arrowUp,
                          ),
                        ),
                        tooltip: 'Send',
                        variant: DButtonVariant.primary,
                        onPressed: _validating
                            ? null
                            : () => setState(
                                () => _status = 'Message sent locally',
                              ),
                      ),
                    ],
                  ),
                ),
              ],
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
  Widget build(BuildContext context) => DEmpty(
    children: [
      DEmptyHeader(
        children: [
          if (_busy)
            const DEmptyMedia(
              variant: DEmptyMediaVariant.icon,
              child: DSpinner(),
            ),
          DEmptyTitle.child(
            child: Semantics(liveRegion: true, child: Text(_status)),
          ),
          DEmptyDescription(
            _busy
                ? 'Please wait while we process your request. Do not refresh the page.'
                : 'Your sample data is unchanged. Start a request to try again.',
          ),
        ],
      ),
      DEmptyContent(
        children: [
          DButton(
            variant: DButtonVariant.outline,
            size: DButtonSize.small,
            label: Text(_busy ? 'Cancel' : 'Start request'),
            onPressed: _busy
                ? () => _finish('Request canceled')
                : () => setState(() {
                    _busy = true;
                    _status = 'Processing your request';
                  }),
          ),
          if (_busy)
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
      ),
    ],
  );
}

/// Lucide LoaderIcon, the reference customization artwork; attribution in
/// licenses/lucide.txt. It inherits the spinner's size and color.
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
