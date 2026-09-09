import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final separatorExamples = ComponentExamples(
  description: 'Visually or semantically separates content.',
  status: ComponentStatus.implemented,
  notes:
      'Import package:discourse_native/discourse_ui.dart; no extra dependency. '
      'DSeparator is the reference one-pixel rule in the live border token: '
      'its box is exactly the line thickness, it fills its bounded length, '
      'and a vertical line fills a Row whose height is finite. Wrap a Row of '
      'unbounded height in IntrinsicHeight so the line fits its siblings, as '
      'the Menu example does. Without a length or finite constraint, the line '
      'collapses along its length. Gaps come from the parent, as in the '
      'reference; space centers the line in a larger cross-axis extent. '
      'orientation uses Axis; length includes indent and endIndent. '
      'Horizontal insets follow RTL; vertical insets mean top and bottom. '
      'thickness: 0 uses Flutter’s device-pixel hairline, which cannot be '
      'rounded; color and radius customize thicker lines. Use normal Padding '
      'and layout composition for web className/style/render equivalents. '
      'Base UI always exposes role="separator" with aria-orientation. Flutter '
      '3.47 has no separator semantics role, so decorative is the default and '
      'a meaningful boundary uses decorative: false with a localized '
      'semanticLabel: a static labeled boundary with no Tab stop or resize '
      'action. The separator has no interactive state, animation or overlay; '
      'adjacent controls own their behavior.',
  examples: [
    StyleguideExample(
      title: 'Usage',
      description:
          'The reference demo: a 384px column with 16px gaps, a 14px medium '
          'title with no extra leading, a muted subtitle 6px below it, the '
          'separator and a description. The controls below change the same '
          'separator: expose a meaningful boundary to accessibility, add '
          'asymmetric start/end insets that follow the preview direction, or '
          'thicken the line. Decorative lines stay silent and Tab skips them.',
      states: const ['Horizontal', 'Decorative', 'Meaningful', 'Live tokens'],
      code:
          '''// text-sm is 14/20 in the foreground token; muted uses mutedForeground.
ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: 384),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 16,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Text('shadcn/ui', style: text(fontWeight: FontWeight.w500, lineHeight: 14)),
          Text('The Foundation for your Design System', style: text(muted: true)),
        ],
      ),
      const DSeparator(),
      Text(
        'A set of beautifully designed components that you can customize, '
        'extend, and build on.',
        style: text(),
      ),
    ],
  ),
)

// A meaningful boundary with a localized description and native insets:
const DSeparator(
  decorative: false,
  semanticLabel: 'End of introduction',
  indent: 24,
  endIndent: 8,
  thickness: 3,
)''',
      builder: (_) => const _UsagePreview(),
    ),
    StyleguideExample(
      title: 'Vertical',
      description:
          'Blog, Docs and Source sit in a 20px row with 16px gaps; each '
          'vertical line fills the row height. The reference fixes the row at '
          '20px; here that is a minimum so larger text grows the row and the '
          'lines with it.',
      states: const ['Vertical', 'Bounded height', 'Large text'],
      code:
          '''// Flexible items shrink like flex items instead of overflowing the row.
IntrinsicHeight(
  child: ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 20),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 16,
      children: [
        Flexible(child: Text('Blog', style: text())),
        const DSeparator(orientation: Axis.vertical),
        Flexible(child: Text('Docs', style: text())),
        const DSeparator(orientation: Axis.vertical),
        Flexible(child: Text('Source', style: text())),
      ],
    ),
  ),
)''',
      builder: (_) => const _VerticalPreview(),
    ),
    StyleguideExample(
      title: 'Menu',
      description:
          'Vertical separators between menu items with descriptions. The row '
          'has no fixed height, so IntrinsicHeight lets each line fill the '
          'two-line items, the reference self-stretch. Below the 768px md '
          'breakpoint the gap is 8px and Help with its separator is hidden; '
          'from 768px the gap is 16px and all three items show. Items shrink '
          'and wrap like flex items when the preview is narrow.',
      states: const ['Vertical', 'Intrinsic height', 'Responsive'],
      code: '''// Tailwind md: applies from a 768px viewport.
final wide = MediaQuery.sizeOf(context).width >= 768;
IntrinsicHeight(
  child: Row(
    mainAxisSize: MainAxisSize.min,
    spacing: wide ? 16 : 8,
    children: [
      Flexible(child: menuItem('Settings', 'Manage preferences')),
      const DSeparator(orientation: Axis.vertical),
      Flexible(child: menuItem('Account', 'Profile & security')),
      if (wide) ...[
        const DSeparator(orientation: Axis.vertical),
        Flexible(child: menuItem('Help', 'Support & docs')),
      ],
    ],
  ),
)

// menuItem: a 4px-gap column with a 14px medium title and a 12/16 muted
// description.
Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  spacing: 4,
  children: [
    Text(title, style: text(fontWeight: FontWeight.w500)),
    Text(description, style: text(size: 12, lineHeight: 16, muted: true)),
  ],
)''',
      builder: (context) => const _MenuPreview(),
    ),
    StyleguideExample(
      title: 'List',
      description:
          'Horizontal separators between list items. Three 20px rows place '
          'the item at the start and its muted value at the end, 8px apart, '
          'inside a full-width column no wider than 384px.',
      states: const ['Horizontal', 'Between items'],
      code: '''ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: 384),
  child: SizedBox(
    width: double.infinity,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        for (final (index, item) in ['Item 1', 'Item 2', 'Item 3'].indexed) ...[
          if (index > 0) const DSeparator(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(item, style: text())),
              Flexible(child: Text('Value \${index + 1}', style: text(muted: true))),
            ],
          ),
        ],
      ],
    ),
  ),
)''',
      builder: (_) => const _ListPreview(),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'The Usage layout under a language choice. Arabic and Hebrew set '
          'an RTL direction on the demo; English restores LTR. The line has '
          'no directional treatment; the text and its alignment follow the '
          'chosen direction.',
      states: const ['RTL', 'Arabic', 'Hebrew', 'English'],
      code: '''DSelect<String>.controlled(
  value: language,
  width: 180,
  semanticLabel: 'Language',
  entries: const [
    DSelectOption(value: 'en', label: 'English', child: Text('English')),
    DSelectOption(value: 'ar', label: 'العربية', child: Text('العربية')),
    DSelectOption(value: 'he', label: 'עברית', child: Text('עברית')),
  ],
  onChanged: (value) => setState(() => language = value ?? language),
)

// The Usage column with translated strings:
DDirection(
  textDirection: language == 'en' ? TextDirection.ltr : TextDirection.rtl,
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 384),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            Text(title, style: text(fontWeight: FontWeight.w500, lineHeight: 14)),
            Text(subtitle, style: text(muted: true)),
          ],
        ),
        const DSeparator(),
        Text(description, style: text()),
      ],
    ),
  ),
)''',
      builder: (_) => const _RtlPreview(),
    ),
    StyleguideExample(
      title: 'Insets, explicit length and line style',
      description:
          'Native properties beyond the reference. The first line has a 24px '
          'start inset and an 8px end inset, mirrored by the preview '
          'direction. The scrolling row offers no finite width, so its '
          'horizontal line needs an explicit length; the vertical line beside '
          'wrapping text uses an explicit length instead of IntrinsicHeight. '
          'The last two lines are a 4px rounded primary rule and a '
          'device-pixel hairline.',
      states: const [
        'Insets',
        'Explicit length',
        'Unbounded parent',
        'Radius',
        'Hairline',
      ],
      code: '''const DSeparator(indent: 24, endIndent: 8, space: 16)

SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: Row(
    children: [
      Text('Start', style: text()),
      const DSeparator(length: 96, space: 24),
      Text('End', style: text()),
    ],
  ),
)

Row(
  children: [
    const DSeparator(orientation: Axis.vertical, length: 48, space: 24),
    Expanded(
      child: Text('A vertical line with an explicit length beside text that '
          'wraps onto more than one line.', style: text()),
    ),
  ],
)

DSeparator(
  thickness: 4,
  radius: BorderRadius.circular(2),
  color: DTokens.of(context).primary,
  space: 16,
)

const DSeparator(thickness: 0, space: 16)''',
      builder: (_) => const _StylePreview(),
    ),
  ],
);

/// The reference `text-sm` (14/20) and `text-xs` (12/16) roles in the live
/// foreground or muted-foreground token, with explicit weight and tracking.
TextStyle _text(
  BuildContext context, {
  double size = 14,
  double lineHeight = 20,
  FontWeight fontWeight = FontWeight.w400,
  bool muted = false,
}) {
  final tokens = DTokens.of(context);
  return Theme.of(context).textTheme.bodyMedium!.copyWith(
    fontSize: size,
    height: lineHeight / size,
    fontWeight: fontWeight,
    letterSpacing: 0,
    color: muted ? tokens.mutedForeground : tokens.foreground,
  );
}

/// The reference demo column: `flex max-w-sm flex-col gap-4 text-sm`.
class _ReferenceDemo extends StatelessWidget {
  const _ReferenceDemo({
    required this.title,
    required this.subtitle,
    required this.description,
    this.separator = const DSeparator(),
  });

  final String title;
  final String subtitle;
  final String description;
  final Widget separator;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 384),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            Text(
              title,
              style: _text(
                context,
                fontWeight: FontWeight.w500,
                lineHeight: 14,
              ),
            ),
            Text(subtitle, style: _text(context, muted: true)),
          ],
        ),
        separator,
        Text(description, style: _text(context)),
      ],
    ),
  );
}

class _UsagePreview extends StatefulWidget {
  const _UsagePreview();

  @override
  State<_UsagePreview> createState() => _UsagePreviewState();
}

class _UsagePreviewState extends State<_UsagePreview> {
  bool _meaningful = false;
  bool _inset = false;
  bool _emphasized = false;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 24,
    children: [
      Center(
        child: _ReferenceDemo(
          title: 'shadcn/ui',
          subtitle: 'The Foundation for your Design System',
          description:
              'A set of beautifully designed components that you can '
              'customize, extend, and build on.',
          separator: DSeparator(
            key: const ValueKey('separator-configurable'),
            decorative: !_meaningful,
            semanticLabel: _meaningful ? 'End of introduction' : null,
            indent: _inset ? 24 : 0,
            endIndent: _inset ? 8 : 0,
            thickness: _emphasized ? 3 : 1,
          ),
        ),
      ),
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DSwitchTile(
            title: const Text('Meaningful boundary'),
            subtitle: const Text('Accessibility label: End of introduction'),
            value: _meaningful,
            onChanged: (value) => setState(() => _meaningful = value),
          ),
          DSwitchTile(
            title: const Text('Asymmetric insets'),
            value: _inset,
            onChanged: (value) => setState(() => _inset = value),
          ),
          DSwitchTile(
            title: const Text('Emphasize boundary'),
            value: _emphasized,
            onChanged: (value) => setState(() => _emphasized = value),
          ),
        ],
      ),
    ],
  );
}

/// The reference `flex h-5 items-center gap-4 text-sm` row. The 20px height
/// is a minimum so scaled text grows the row instead of overflowing it, and
/// the items are flexible so a narrow preview shrinks them like flex items.
class _VerticalPreview extends StatelessWidget {
  const _VerticalPreview();

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 20),
      child: Row(
        key: const ValueKey('separator-vertical-row'),
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          Flexible(child: Text('Blog', style: _text(context))),
          const DSeparator(orientation: Axis.vertical),
          Flexible(child: Text('Docs', style: _text(context))),
          const DSeparator(orientation: Axis.vertical),
          Flexible(child: Text('Source', style: _text(context))),
        ],
      ),
    ),
  );
}

/// The reference `flex items-center gap-2 text-sm md:gap-4` row. Items are
/// flexible so a narrow preview wraps their text instead of overflowing.
class _MenuPreview extends StatelessWidget {
  const _MenuPreview();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 768;
    return IntrinsicHeight(
      child: Row(
        key: const ValueKey('separator-menu-row'),
        mainAxisSize: MainAxisSize.min,
        spacing: wide ? 16 : 8,
        children: [
          const Flexible(
            child: _MenuItem(
              title: 'Settings',
              description: 'Manage preferences',
            ),
          ),
          const DSeparator(orientation: Axis.vertical),
          const Flexible(
            child: _MenuItem(
              title: 'Account',
              description: 'Profile & security',
            ),
          ),
          if (wide) ...[
            const DSeparator(orientation: Axis.vertical),
            const Flexible(
              child: _MenuItem(title: 'Help', description: 'Support & docs'),
            ),
          ],
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 4,
    children: [
      Text(title, style: _text(context, fontWeight: FontWeight.w500)),
      Text(
        description,
        style: _text(context, size: 12, lineHeight: 16, muted: true),
      ),
    ],
  );
}

/// The reference `flex w-full max-w-sm flex-col gap-2 text-sm` list. Each
/// item and value is flexible so narrow rows wrap text rather than overflow.
class _ListPreview extends StatelessWidget {
  const _ListPreview();

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 384),
    child: SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          for (final (index, item) in const [
            'Item 1',
            'Item 2',
            'Item 3',
          ].indexed) ...[
            if (index > 0) const DSeparator(),
            Row(
              key: ValueKey('separator-list-row-${index + 1}'),
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: Text(item, style: _text(context))),
                Flexible(
                  child: Text(
                    'Value ${index + 1}',
                    style: _text(context, muted: true),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

class _RtlPreview extends StatefulWidget {
  const _RtlPreview();

  @override
  State<_RtlPreview> createState() => _RtlPreviewState();
}

class _RtlPreviewState extends State<_RtlPreview> {
  String _language = 'ar';

  @override
  Widget build(BuildContext context) {
    final (subtitle, description) = switch (_language) {
      'ar' => (
        'الأساس لنظام التصميم الخاص بك',
        'مجموعة من المكونات المصممة بشكل جميل يمكنك تخصيصها وتوسيعها والبناء عليها.',
      ),
      'he' => (
        'הבסיס למערכת העיצוב שלך',
        'סט של רכיבים מעוצבים בצורה יפה שאתה יכול להתאים אישית, להרחיב ולבנות עליהם.',
      ),
      _ => (
        'The Foundation for your Design System',
        'A set of beautifully designed components that you can customize, '
            'extend, and build on.',
      ),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: 24,
      children: [
        DSelect<String>.controlled(
          value: _language,
          width: 180,
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
        DDirection(
          textDirection: _language == 'en'
              ? TextDirection.ltr
              : TextDirection.rtl,
          child: _ReferenceDemo(
            title: 'shadcn/ui',
            subtitle: subtitle,
            description: description,
          ),
        ),
      ],
    );
  }
}

class _StylePreview extends StatelessWidget {
  const _StylePreview();

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 384),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Start inset 24px, end inset 8px', style: _text(context)),
        const DSeparator(
          key: ValueKey('separator-inset'),
          indent: 24,
          endIndent: 8,
          space: 16,
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text('Start', style: _text(context)),
              const DSeparator(
                key: ValueKey('separator-explicit-length'),
                length: 96,
                space: 24,
              ),
              Text('End', style: _text(context)),
            ],
          ),
        ),
        Row(
          children: [
            const DSeparator(
              key: ValueKey('separator-explicit-height'),
              orientation: Axis.vertical,
              length: 48,
              space: 24,
            ),
            Expanded(
              child: Text(
                'A vertical line with an explicit length beside text that '
                'wraps onto more than one line.',
                style: _text(context),
              ),
            ),
          ],
        ),
        DSeparator(
          key: const ValueKey('separator-rounded'),
          thickness: 4,
          radius: BorderRadius.circular(2),
          color: DTokens.of(context).primary,
          space: 16,
        ),
        const DSeparator(
          key: ValueKey('separator-hairline'),
          thickness: 0,
          space: 16,
        ),
      ],
    ),
  );
}
