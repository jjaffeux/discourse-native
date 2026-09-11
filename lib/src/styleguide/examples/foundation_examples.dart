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
                        height: 16 / 12,
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
