import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../discourse_ui.dart';
import '../styleguide_example.dart';

final badgeExamples = ComponentExamples(
  topLevelExampleIndex: 6,
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
          'Verified and Bookmark preserve the documented composition; the variant rows mirror the linked registry coverage for both inline slots. Start and end follow preview direction.',
      states: const ['Leading', 'Trailing', 'All variants', 'RTL'],
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
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Wrap(
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
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final variant in DBadgeVariant.values)
                DBadge(
                  variant: variant,
                  leading: const _BadgeIcon('badge-check'),
                  child: Text(_label(variant)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final variant in DBadgeVariant.values)
                DBadge(
                  variant: variant,
                  trailing: const _BadgeIcon('arrow-right'),
                  child: Text(_label(variant)),
                ),
            ],
          ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'With spinner',
      description:
          'Every treatment accepts a real spinner. Complete or restart the local operation; status text and busy semantics change together.',
      states: const [
        'All variants',
        'Deleting',
        'Generating',
        'Complete',
        'Reduced motion',
      ],
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
          'The linked registry\'s solid and adaptive color pairs are reproduced alongside a badge driven by the live host palette.',
      states: const [
        'Solid',
        'Adaptive',
        'Blue',
        'Green',
        'Sky',
        'Purple',
        'Red',
        'Site palette',
      ],
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
            for (final (label, background, foreground) in const [
              ('Blue', 0xff2563eb, 0xffeff6ff),
              ('Green', 0xff16a34a, 0xfff0fdf4),
              ('Sky', 0xff0284c7, 0xfff0f9ff),
              ('Purple', 0xff9333ea, 0xfffaf5ff),
            ])
              DBadge(
                backgroundColor: Color(background),
                foregroundColor: Color(foreground),
                child: Text(label),
              ),
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
          'Cycle through the documented Arabic, English and Hebrew translations. Try 360px, 200% text, and a custom palette; labels wrap and artwork keeps its logical position.',
      states: const [
        'Arabic',
        'English',
        'Hebrew',
        'Long label',
        'Large text',
        'Narrow',
      ],
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
    StyleguideExample(
      title: 'Reference demo',
      description:
          'The canonical default, secondary, destructive, and outline badges.',
      states: const ['Default', 'Secondary', 'Destructive', 'Outline'],
      code: '''const Wrap(
  spacing: DSpacing.sm,
  children: [
    DBadge(child: Text('Badge')),
    DBadge(variant: DBadgeVariant.secondary, child: Text('Secondary')),
    DBadge(variant: DBadgeVariant.destructive, child: Text('Destructive')),
    DBadge(variant: DBadgeVariant.outline, child: Text('Outline')),
  ],
)''',
      builder: (_) => const Wrap(
        spacing: DSpacing.sm,
        runSpacing: DSpacing.sm,
        alignment: WrapAlignment.center,
        children: [
          DBadge(child: Text('Badge')),
          DBadge(variant: DBadgeVariant.secondary, child: Text('Secondary')),
          DBadge(
            variant: DBadgeVariant.destructive,
            child: Text('Destructive'),
          ),
          DBadge(variant: DBadgeVariant.outline, child: Text('Outline')),
        ],
      ),
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
          for (final variant in DBadgeVariant.values)
            DBadge(
              variant: variant,
              leading: _busy && variant != DBadgeVariant.secondary
                  ? const DSpinner(size: 12, semanticLabel: null)
                  : null,
              trailing: _busy && variant == DBadgeVariant.secondary
                  ? const DSpinner(size: 12, semanticLabel: null)
                  : null,
              semanticValue: _busy ? 'Loading' : null,
              liveRegion: true,
              child: Text(switch ((variant, _busy)) {
                (DBadgeVariant.primary, true) => 'Deleting',
                (DBadgeVariant.primary, false) => 'Deleted',
                (DBadgeVariant.secondary, true) => 'Generating',
                (DBadgeVariant.secondary, false) => 'Generated',
                (_, true) => _label(variant),
                (_, false) => '${_label(variant)} ready',
              }),
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

enum _Language { arabic, english, hebrew }

typedef _Translation = ({
  bool rtl,
  String badge,
  String secondary,
  String destructive,
  String outline,
  String verified,
  String bookmark,
  String long,
});

// The reference language selector's ar, en and he values, in its default
// order, plus the registry's long label in each script.
const _translations = <_Language, _Translation>{
  _Language.arabic: (
    rtl: true,
    badge: 'شارة',
    secondary: 'ثانوي',
    destructive: 'مدمر',
    outline: 'مخطط',
    verified: 'متحقق',
    bookmark: 'إشارة مرجعية',
    long: 'تم التحقق من حالة الحساب وجميع المعلومات المطلوبة',
  ),
  _Language.english: (
    rtl: false,
    badge: 'Badge',
    secondary: 'Secondary',
    destructive: 'Destructive',
    outline: 'Outline',
    verified: 'Verified',
    bookmark: 'Bookmark',
    long: 'A badge with a lot of text to see how it wraps',
  ),
  _Language.hebrew: (
    rtl: true,
    badge: 'תג',
    secondary: 'משני',
    destructive: 'הרסני',
    outline: 'קווי מתאר',
    verified: 'מאומת',
    bookmark: 'סימנייה',
    long: 'תג עם הרבה טקסט כדי לראות איך הוא נשבר לשורות',
  ),
};

String _languageName(_Language language) => switch (language) {
  _Language.arabic => 'Arabic',
  _Language.english => 'English',
  _Language.hebrew => 'Hebrew',
};

class _BadgeDirectionState extends State<_BadgeDirection> {
  _Language _language = _Language.arabic;
  @override
  Widget build(BuildContext context) {
    final t = _translations[_language]!;
    final next =
        _Language.values[(_language.index + 1) % _Language.values.length];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Directionality(
          textDirection: t.rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DBadge(child: Text(t.badge)),
              DBadge(
                variant: DBadgeVariant.secondary,
                child: Text(t.secondary),
              ),
              DBadge(
                variant: DBadgeVariant.destructive,
                child: Text(t.destructive),
              ),
              DBadge(variant: DBadgeVariant.outline, child: Text(t.outline)),
              DBadge(
                variant: DBadgeVariant.secondary,
                leading: const _BadgeIcon('badge-check'),
                child: Text(t.verified),
              ),
              DBadge(
                variant: DBadgeVariant.outline,
                trailing: const _BadgeIcon('bookmark'),
                child: Text(t.bookmark),
              ),
              DBadge(
                variant: DBadgeVariant.secondary,
                leading: const _BadgeIcon('badge-check'),
                child: Text(t.long),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DButton(
          onPressed: () => setState(() => _language = next),
          label: Text('Use ${_languageName(next)}'),
        ),
      ],
    );
  }
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
        '<path d="M3.85 8.62a4 4 0 0 1 4.78-4.77 4 4 0 0 1 6.74 0 4 4 0 0 1 4.78 4.78 4 4 0 0 1 0 6.74 4 4 0 0 1-4.77 4.78 4 4 0 0 1-6.75 0 4 4 0 0 1-4.78-4.77 4 4 0 0 1 0-6.76Z"/><path d="m9 12 2 2 4-4"/>',
    'bookmark':
        '<path d="m19 21-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v16z"/>',
    'arrow-right': '<path d="M5 12h14"/><path d="m12 5 7 7-7 7"/>',
    'arrow-up-right': '<path d="M7 7h10v10"/><path d="M7 17 17 7"/>',
  };
}
