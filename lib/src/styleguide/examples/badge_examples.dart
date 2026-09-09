import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../discourse_ui.dart';
import '../styleguide_example.dart';

final badgeExamples = ComponentExamples(
  description: 'Compact labels for status, counts, and short links.',
  status: ComponentStatus.implemented,
  notes:
      'Import package:discourse_native/discourse_ui.dart. DBadge is static; '
      'DBadge.action and DBadge.link own a single focus and activation target. '
      'A null callback disables an interactive badge. Links activate with Enter; '
      'actions also accept Space. The caller owns navigation and async work. '
      'Use leading/trailing for decorative 12px artwork or DSpinner. '
      'Variants use live theme tokens; custom colors resolve in the caller build. '
      'The reference uses 20px height, 12/16px medium type, 4px gaps and pill corners. '
      'Labels grow and wrap for accessibility; native touch actions reserve 48px '
      'around their compact visual. No selected/toggle behavior is implied. '
      'Use semanticValue and liveRegion for changes, invalid for validation, '
      'and a descriptive label so status remains clear without color or motion.',
  examples: [
    StyleguideExample(
      title: 'Variants',
      description:
          'All six reference treatments. A link treatment alone is still static text.',
      states: const [
        'Default',
        'Secondary',
        'Destructive',
        'Outline',
        'Ghost',
        'Link',
      ],
      code: r'''const Wrap(spacing: 8, runSpacing: 8, children: [
  DBadge(child: Text('Default')),
  DBadge(variant: DBadgeVariant.secondary, child: Text('Secondary')),
  DBadge(variant: DBadgeVariant.destructive, child: Text('Destructive')),
  DBadge(variant: DBadgeVariant.outline, child: Text('Outline')),
  DBadge(variant: DBadgeVariant.ghost, child: Text('Ghost')),
  DBadge(variant: DBadgeVariant.link, child: Text('Link')),
])''',
      builder: (_) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final variant in DBadgeVariant.values)
            DBadge(variant: variant, child: Text(_label(variant))),
        ],
      ),
    ),
    StyleguideExample(
      title: 'With icon',
      description:
          'Verified and Bookmark use the reference Lucide artwork. Inline start and end follow preview direction.',
      states: const ['Leading', 'Trailing', 'RTL'],
      code: r'''DBadge(
  variant: DBadgeVariant.secondary,
  leading: verifiedIcon, // Any widget; fitted into a decorative 12px slot.
  child: const Text('Verified'),
)
DBadge(
  variant: DBadgeVariant.outline,
  trailing: bookmarkIcon,
  child: const Text('Bookmark'),
)''',
      builder: (_) => const Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          DBadge(
            variant: DBadgeVariant.secondary,
            leading: _BadgeIcon('badge-check'),
            child: Text('Verified'),
          ),
          DBadge(
            variant: DBadgeVariant.outline,
            trailing: _BadgeIcon('bookmark'),
            child: Text('Bookmark'),
          ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'With spinner',
      description:
          'Complete or restart the local operation. Status text and busy semantics change together; reduced motion keeps the status visible.',
      states: const ['Deleting', 'Generating', 'Complete', 'Reduced motion'],
      code: r'''DBadge(
  variant: DBadgeVariant.destructive,
  leading: busy ? const DSpinner(size: 12, semanticLabel: null) : null,
  semanticValue: busy ? 'Loading' : null,
  liveRegion: true,
  child: Text(busy ? 'Deleting' : 'Deleted'),
)
// Use trailing for inline-end placement. The caller owns busy and completion.''',
      builder: (_) => const _BadgeLoading(),
    ),
    StyleguideExample(
      title: 'Links and actions',
      description:
          'Open the local detail route, return, then activate an action with Tab and Enter or Space. Disable actions without losing sample state.',
      states: const [
        'Link',
        'Action',
        'Hover',
        'Pressed',
        'Focus',
        'Disabled',
        'Invalid',
      ],
      code: r'''DBadge.link(
  onPressed: () => Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => const DetailPage()),
  ),
  trailing: externalLinkIcon,
  child: const Text('Open Link'),
)
DBadge.action(
  onPressed: enabled ? () => setState(() => count++) : null,
  child: Text('Count $count'),
)
const DBadge(invalid: true, child: Text('Invalid status'))''',
      builder: (_) => const _BadgeActions(),
    ),
    StyleguideExample(
      title: 'Custom colors',
      description:
          'The five documented color pairs switch with light and dark mode. A host-palette badge demonstrates live site colors.',
      states: const ['Blue', 'Green', 'Sky', 'Purple', 'Red', 'Site palette'],
      code: r'''final colors = Theme.of(context).colorScheme;
DBadge(
  backgroundColor: colors.tertiaryContainer,
  foregroundColor: colors.onTertiaryContainer,
  child: const Text('Site palette'),
) // Resolve colors during build so live changes reach existing badges.''',
      builder: (context) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        final colors = Theme.of(context).colorScheme;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, lightBg, lightFg, darkBg, darkFg) in const [
              ('Blue', 0xffeff6ff, 0xff1447e6, 0xff162456, 0xff8ec5ff),
              ('Green', 0xfff0fdf4, 0xff008236, 0xff032e15, 0xff7bf1a8),
              ('Sky', 0xfff0f9ff, 0xff0069a8, 0xff052f4a, 0xff74d4ff),
              ('Purple', 0xfffaf5ff, 0xff8200db, 0xff3c0366, 0xffdab2ff),
              ('Red', 0xfffef2f2, 0xffc10007, 0xff460809, 0xffffa2a2),
            ])
              DBadge(
                backgroundColor: Color(dark ? darkBg : lightBg),
                foregroundColor: Color(dark ? darkFg : lightFg),
                child: Text(label),
              ),
            DBadge(
              backgroundColor: colors.tertiaryContainer,
              foregroundColor: colors.onTertiaryContainer,
              child: const Text('Site palette'),
            ),
          ],
        );
      },
    ),
    StyleguideExample(
      title: 'Long labels and RTL',
      description:
          'Switch between English and Arabic. Try 360px, 200% text, and a custom palette; labels wrap and artwork keeps its logical position.',
      states: const ['Long label', 'RTL', 'Large text', 'Narrow'],
      code: r'''Directionality(
  textDirection: TextDirection.rtl,
  child: DBadge(
    variant: DBadgeVariant.secondary,
    leading: verifiedIcon,
    child: const Text('تم التحقق من حالة الحساب وجميع المعلومات المطلوبة'),
  ),
)''',
      builder: (_) => const _BadgeDirection(),
    ),
  ],
);

String _label(DBadgeVariant variant) => switch (variant) {
  DBadgeVariant.primary => 'Default',
  DBadgeVariant.secondary => 'Secondary',
  DBadgeVariant.destructive => 'Destructive',
  DBadgeVariant.outline => 'Outline',
  DBadgeVariant.ghost => 'Ghost',
  DBadgeVariant.link => 'Link',
};

class _BadgeLoading extends StatefulWidget {
  const _BadgeLoading();
  @override
  State<_BadgeLoading> createState() => _BadgeLoadingState();
}

class _BadgeLoadingState extends State<_BadgeLoading> {
  bool _busy = true;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          DBadge(
            variant: DBadgeVariant.destructive,
            leading: _busy
                ? const DSpinner(size: 12, semanticLabel: null)
                : null,
            semanticValue: _busy ? 'Loading' : null,
            liveRegion: true,
            child: Text(_busy ? 'Deleting' : 'Deleted'),
          ),
          DBadge(
            variant: DBadgeVariant.secondary,
            trailing: _busy
                ? const DSpinner(size: 12, semanticLabel: null)
                : null,
            semanticValue: _busy ? 'Loading' : null,
            liveRegion: true,
            child: Text(_busy ? 'Generating' : 'Generated'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      DButton(
        onPressed: () => setState(() => _busy = !_busy),
        label: Text(_busy ? 'Complete operation' : 'Restart operation'),
      ),
    ],
  );
}

class _BadgeActions extends StatefulWidget {
  const _BadgeActions();
  @override
  State<_BadgeActions> createState() => _BadgeActionsState();
}

class _BadgeActionsState extends State<_BadgeActions> {
  int _count = 0;
  bool _enabled = true;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final variant in DBadgeVariant.values)
            DBadge.link(
              variant: variant,
              onPressed: _enabled
                  ? () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (context) => Scaffold(
                          body: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Badge link detail'),
                                const SizedBox(height: 16),
                                DButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  label: const Text('Return to badges'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  : null,
              trailing: const _BadgeIcon('arrow-up-right'),
              child: Text(
                variant == DBadgeVariant.primary
                    ? 'Open Link'
                    : '${_label(variant)} link',
              ),
            ),
          DBadge.action(
            key: const ValueKey('badge-counter'),
            onPressed: _enabled ? () => setState(() => _count++) : null,
            child: Text('Count $_count'),
          ),
          const DBadge.action(onPressed: null, child: Text('Unavailable')),
          const DBadge(invalid: true, child: Text('Invalid status')),
        ],
      ),
      const SizedBox(height: 16),
      DButton(
        onPressed: () => setState(() => _enabled = !_enabled),
        label: Text(_enabled ? 'Disable actions' : 'Enable actions'),
      ),
    ],
  );
}

class _BadgeDirection extends StatefulWidget {
  const _BadgeDirection();
  @override
  State<_BadgeDirection> createState() => _BadgeDirectionState();
}

class _BadgeDirectionState extends State<_BadgeDirection> {
  bool _arabic = true;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Directionality(
        textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (variant, ar) in const [
              (DBadgeVariant.primary, 'شارة'),
              (DBadgeVariant.secondary, 'ثانوي'),
              (DBadgeVariant.destructive, 'مدمر'),
              (DBadgeVariant.outline, 'مخطط'),
            ])
              DBadge(
                variant: variant,
                child: Text(_arabic ? ar : _label(variant)),
              ),
            DBadge(
              variant: DBadgeVariant.secondary,
              leading: const _BadgeIcon('badge-check'),
              child: Text(_arabic ? 'متحقق' : 'Verified'),
            ),
            DBadge(
              variant: DBadgeVariant.outline,
              trailing: const _BadgeIcon('bookmark'),
              child: Text(_arabic ? 'إشارة مرجعية' : 'Bookmark'),
            ),
            DBadge(
              variant: DBadgeVariant.secondary,
              leading: const _BadgeIcon('badge-check'),
              child: Text(
                _arabic
                    ? 'تم التحقق من حالة الحساب وجميع المعلومات المطلوبة'
                    : 'A badge with a lot of text to see how it wraps',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      DButton(
        onPressed: () => setState(() => _arabic = !_arabic),
        label: Text(_arabic ? 'Use English' : 'Use Arabic'),
      ),
    ],
  );
}

// Exact Lucide source is preserved under reference/badge-icons with MIT attribution.
class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon(this.name);
  final String name;
  @override
  Widget build(BuildContext context) => SvgPicture.string(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${_paths[name]}</svg>',
    width: 12,
    height: 12,
    colorFilter: ColorFilter.mode(
      IconTheme.of(context).color!,
      BlendMode.srcIn,
    ),
  );
  static const _paths = {
    'badge-check':
        '<path d="M3.85 8.62a4 4 0 0 1 4.78-4.77 4 4 0 0 1 6.74 0 4 4 0 0 1 4.78 4.78 4 4 0 0 1 0 6.74 4 4 0 0 1-4.77 4.78 4 4 0 0 1-6.75 0 4 4 0 0 1-4.78-4.77 4 4 0 0 1 0-6.76Z"/><path d="m16 9-5.5 5.5L8 12"/>',
    'bookmark':
        '<path d="M17 3a2 2 0 0 1 2 2v15a1 1 0 0 1-1.496.868l-4.512-2.578a2 2 0 0 0-1.984 0l-4.512 2.578A1 1 0 0 1 5 20V5a2 2 0 0 1 2-2z"/>',
    'arrow-up-right': '<path d="M7 7h10v10"/><path d="M7 17 17 7"/>',
  };
}
