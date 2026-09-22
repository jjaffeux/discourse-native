import 'package:discourse_native/src/theme/discourse_typography.dart';

import 'package:flutter/material.dart';

import '../../../discourse_ui.dart';
import '../styleguide_example.dart';

final foundationExamples = ComponentExamples(
  description: 'Colors, typography, and spacing for the component library.',
  status: ComponentStatus.implemented,
  notes:
      'Colors follow the host palette. Text uses the app typography. '
      'Preview controls affect examples only and never save app settings.',
  examples: [
    StyleguideExample(
      title: 'Application design scale',
      description:
          'One type scale for desktop and mobile. Page titles are 22/27.5, '
          'list titles 14.5/19.575 and reading text 14/23.1 logical pixels. '
          'Zoom changes text; touch platforms retain larger hit targets.',
      states: const ['Typography', 'Radii', 'Spacing', 'Text scaling'],
      code:
          '''Text('Page title', style: Theme.of(context).textTheme.headlineSmall)
Text('List title', style: Theme.of(context).textTheme.titleSmall)
DItem(padding: DInsets.listRow, children: [
  DItemContent(children: [
    DItemTitle(child: Text('A conversation worth joining')),
    DItemDescription(child: Text('A short preview of the discussion.')),
  ]),
])''',
      builder: (_) => const _DesignScalePreview(),
    ),
    StyleguideExample(
      title: 'Theme tokens',
      description:
          'Switch theme and text size to inspect semantic colors '
          'and existing app controls together.',
      states: const ['Live theme', 'Text scaling', 'Reduced motion', 'RTL'],
      code: '''final tokens = DTokens.of(context);
Container(
  padding: const EdgeInsets.all(DSpacing.lg),
  decoration: BoxDecoration(
    color: tokens.surface,
    border: Border.all(color: tokens.border),
    borderRadius: tokens.borderRadius,
  ),
  child: Text('A themed surface',
    style: Theme.of(context).textTheme.bodyMedium),
)''',
      builder: (_) => const _TokenPreview(),
    ),
  ],
);

class _DesignScalePreview extends StatelessWidget {
  const _DesignScalePreview();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tokens = DTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DSpacing.lg,
      children: [
        for (final (label, style) in [
          ('Page title · 22 / 27.5', text.headlineSmall!),
          ('Dialog title · 18 / 25.2', text.titleLarge!),
          ('Section title · 17 / 25.5', text.titleMedium!),
          ('Topic title · 14.5 / 19.575', text.titleSmall!),
          ('Reading text · 14 / 23.1', text.bodyLarge!),
          ('Interface text · 14 / 21', text.bodyMedium!),
          ('Control label · 13 / 19.5', text.labelLarge!),
          ('Metadata · 12 / 18', text.bodySmall!),
        ])
          Text(label, style: style),
        Wrap(
          spacing: DSpacing.md,
          runSpacing: DSpacing.md,
          children: [
            for (final (name, radius) in [
              ('Code · 4', DRadius.code),
              ('Control · 8', DRadius.control),
              ('Popup · 10', DRadius.popover),
              ('Bubble · 12', DRadius.bubble),
              ('Panel · 14', DRadius.panel),
            ])
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.surface,
                  border: Border.all(color: tokens.border),
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: Padding(
                  padding: DInsets.page,
                  child: Text(name, style: text.bodySmall),
                ),
              ),
          ],
        ),
        const DItem(
          padding: DInsets.listRow,
          variant: DItemVariant.outline,
          children: [
            DItemContent(
              children: [
                DItemTitle(child: Text('A conversation worth joining')),
                DItemDescription(
                  child: Text('A short preview of the discussion.'),
                ),
              ],
            ),
          ],
        ),
        const _ButtonPreview(compact: true),
      ],
    );
  }
}

class _TokenPreview extends StatelessWidget {
  const _TokenPreview();

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: DSpacing.lg,
            runSpacing: DSpacing.lg,
            children: [
              for (final (label, color) in [
                ('Surface', tokens.surface),
                ('Muted', tokens.muted),
                ('Primary', tokens.primary),
                ('Selected', tokens.selected),
                ('Destructive', tokens.destructive),
              ])
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 76,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        border: Border.all(color: tokens.border),
                        borderRadius: tokens.borderRadius,
                      ),
                    ),
                    const SizedBox(height: DSpacing.sm),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: DiscourseTypography.xs,
                        height: DiscourseTypography.lineHeightCaption,
                        color: tokens.mutedForeground,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: DSpacing.xl),
          const DCard(
            children: [
              DCardHeader(
                title: DCardTitle(child: Text('Your community')),
                description: DCardDescription(
                  child: Text('Shared components, shaped by your theme.'),
                ),
              ),
              DCardContent(child: _ButtonPreview(compact: true)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ButtonPreview extends StatefulWidget {
  const _ButtonPreview({this.compact = false});
  final bool compact;

  @override
  State<_ButtonPreview> createState() => _ButtonPreviewState();
}

class _ButtonPreviewState extends State<_ButtonPreview> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: DSpacing.sm,
        runSpacing: DSpacing.sm,
        children: [
          for (final variant
              in widget.compact
                  ? [DButtonVariant.primary, DButtonVariant.outline]
                  : DButtonVariant.values)
            DButton(
              label: Text(variant.name),
              variant: variant,
              onPressed: () => setState(() => _count++),
            ),
          if (!widget.compact) ...[
            const DButton(label: Text('Disabled'), onPressed: null),
            DButton(
              label: const Text('Loading'),
              loading: true,
              onPressed: () {},
            ),
          ],
        ],
      ),
      const SizedBox(height: DSpacing.md),
      Semantics(liveRegion: true, child: Text('Actions: $_count')),
    ],
  );
}
