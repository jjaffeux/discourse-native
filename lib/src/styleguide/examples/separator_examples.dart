import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final separatorExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  notes:
      'Import package:discourse_native/discourse_ui.dart; no extra dependency. '
      'DSeparator defaults to a horizontal, decorative one-pixel line using '
      'the live border token. orientation uses Axis; length includes indent '
      'and endIndent, and space centers the line in its cross-axis extent. '
      'Horizontal insets follow RTL; vertical insets mean top and bottom. '
      'For unbounded length, set length or constrain the parent. An '
      'IntrinsicHeight row with stretched children fits a vertical line to '
      'wrapping text. Without either, an unbounded line collapses. '
      'thickness: 0 uses Flutter’s device-pixel hairline; color and radius '
      'customize the line. Use normal Padding and layout composition for web '
      'className/style/render equivalents. Meaningful boundaries require '
      'decorative: false and a localized semanticLabel. Flutter has no '
      'separator accessibility role, so these are static labeled boundaries, '
      'with no Tab stop or resize action. The separator has no interactive '
      'state, animation or overlay; adjacent controls own their behavior.',
  examples: [
    StyleguideExample(
      title: 'Horizontal and meaningful boundaries',
      description:
          'Change the insets and emphasis, or expose a meaningful boundary to '
          'accessibility. Decorative lines stay silent. Tab skips the line; '
          'switches remain native keyboard and touch controls. Change the '
          'preview theme, direction and text scale without resetting them.',
      states: const ['Horizontal', 'Decorative', 'Meaningful', 'Live tokens'],
      code: '''// A visual boundary:
const DSeparator()

// A meaningful boundary with a localized description:
const DSeparator(
  decorative: false,
  semanticLabel: 'End of introduction',
  indent: DSpacing.xl,
  endIndent: DSpacing.sm,
  space: DSpacing.xl,
  thickness: 3,
)''',
      builder: (_) => const _HorizontalPreview(),
    ),
    StyleguideExample(
      title: 'Vertical navigation',
      description:
          'Choose Blog, Docs or Source with touch, Tab and Enter. Vertical '
          'lines stretch to the intrinsic button height as text grows. The '
          'navigation scrolls horizontally when the available width is small.',
      states: const ['Vertical', 'Intrinsic height', 'Keyboard', 'Scrolling'],
      code: '''SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DButton(
          variant: DButtonVariant.flat,
          onPressed: openBlog,
          label: const Text('Blog'),
        ),
        const DSeparator(orientation: Axis.vertical, space: DSpacing.lg),
        DButton(
          variant: DButtonVariant.flat,
          onPressed: openDocs,
          label: const Text('Docs'),
        ),
        const DSeparator(orientation: Axis.vertical, space: DSpacing.lg),
        DButton(
          variant: DButtonVariant.flat,
          onPressed: openSource,
          label: const Text('Source'),
        ),
      ],
    ),
  ),
)''',
      builder: (_) => const _VerticalPreview(),
    ),
    StyleguideExample(
      title: 'Responsive menu with descriptions',
      description:
          'Select a destination. Wide menus use vertical separators between '
          'descriptions; narrow menus stack with horizontal separators. All '
          'destinations remain available at large text sizes, including Help.',
      states: const ['Menu', 'Responsive', 'Wrapping text', 'Selection'],
      code: '''// Actions use DButton(variant: DButtonVariant.flat, label: ...).
// A fresh DefaultTextStyle in each label allows descriptions to wrap.
// The menu owns its actions and responsive layout.
LayoutBuilder(builder: (context, constraints) {
  if (constraints.maxWidth < 520) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      settingsAction,
      const DSeparator(space: DSpacing.lg),
      accountAction,
      const DSeparator(space: DSpacing.lg),
      helpAction,
    ]);
  }
  return IntrinsicHeight(child: Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: settingsAction),
      const DSeparator(orientation: Axis.vertical, space: DSpacing.xl),
      Expanded(child: accountAction),
      const DSeparator(orientation: Axis.vertical, space: DSpacing.xl),
      Expanded(child: helpAction),
    ],
  ));
})''',
      builder: (_) => const _MenuPreview(),
    ),
    StyleguideExample(
      title: 'Scrollable list and empty state',
      description:
          'Select a row, scroll the local list, add an item or clear it. '
          'Separators appear only between items and do not receive focus. '
          'An empty list has no dividing rules.',
      states: const ['List', 'Scrolling', 'Empty', 'Local updates'],
      code: '''ListView.separated(
  itemCount: items.length,
  separatorBuilder: (_, _) => const DSeparator(),
  itemBuilder: (context, index) => ListTile(
    title: Text(items[index].label),
    subtitle: Text(items[index].value),
    onTap: () => select(items[index]),
  ),
)''',
      builder: (_) => const _ListPreview(),
    ),
    StyleguideExample(
      title: 'Explicit length and RTL insets',
      description:
          'This RTL section has a longer start inset, which appears on the '
          'right. The vertical line has a finite length beside wrapping text. '
          'The last row scrolls horizontally and gives its horizontal line an '
          'explicit length because the row offers no finite width.',
      states: const ['RTL', 'Asymmetric insets', 'Unbounded parent'],
      code: '''DDirection(
  textDirection: TextDirection.rtl,
  child: Column(children: [
    const Text('مجتمع ديسكورس'),
    const DSeparator(indent: DSpacing.xl, endIndent: DSpacing.sm),
    const Row(children: [
      DSeparator(orientation: Axis.vertical, length: 48, space: DSpacing.xl),
      Expanded(child: Text('مساحة للنقاش وتبادل الأفكار')),
    ]),
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        const Text('البداية'),
        const DSeparator(length: 96, indent: 24, endIndent: 8),
        const Text('النهاية'),
      ]),
    ),
  ]),
)''',
      builder: (_) => const _RtlPreview(),
    ),
  ],
);

class _HorizontalPreview extends StatefulWidget {
  const _HorizontalPreview();

  @override
  State<_HorizontalPreview> createState() => _HorizontalPreviewState();
}

class _HorizontalPreviewState extends State<_HorizontalPreview> {
  bool _meaningful = false;
  bool _inset = false;
  bool _emphasized = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Discourse UI', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: DSpacing.sm),
      const Text('A shared foundation for native community experiences.'),
      DSeparator(
        key: const ValueKey('separator-configurable'),
        decorative: !_meaningful,
        semanticLabel: _meaningful ? 'End of introduction' : null,
        indent: _inset ? DSpacing.xl : 0,
        endIndent: _inset ? DSpacing.sm : 0,
        thickness: _emphasized ? 3 : 1,
        space: DSpacing.xl,
      ),
      const Text(
        'Use a separator to mark a boundary between related sections.',
      ),
      const SizedBox(height: DSpacing.lg),
      SwitchListTile.adaptive(
        title: const Text('Meaningful boundary'),
        subtitle: const Text('Accessibility label: End of introduction'),
        contentPadding: EdgeInsets.zero,
        value: _meaningful,
        onChanged: (value) => setState(() => _meaningful = value),
      ),
      SwitchListTile.adaptive(
        title: const Text('Asymmetric insets'),
        contentPadding: EdgeInsets.zero,
        value: _inset,
        onChanged: (value) => setState(() => _inset = value),
      ),
      SwitchListTile.adaptive(
        title: const Text('Emphasize boundary'),
        contentPadding: EdgeInsets.zero,
        value: _emphasized,
        onChanged: (value) => setState(() => _emphasized = value),
      ),
    ],
  );
}

class _VerticalPreview extends StatefulWidget {
  const _VerticalPreview();

  @override
  State<_VerticalPreview> createState() => _VerticalPreviewState();
}

class _VerticalPreviewState extends State<_VerticalPreview> {
  String _selected = 'Docs';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, label) in [
                'Blog',
                'Docs',
                'Source',
              ].indexed) ...[
                if (index > 0)
                  const DSeparator(
                    orientation: Axis.vertical,
                    space: DSpacing.lg,
                  ),
                DButton(
                  variant: DButtonVariant.flat,
                  onPressed: () => setState(() => _selected = label),
                  label: Text(label),
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: DSpacing.lg),
      Text('Destination: $_selected'),
    ],
  );
}

class _MenuPreview extends StatefulWidget {
  const _MenuPreview();

  @override
  State<_MenuPreview> createState() => _MenuPreviewState();
}

class _MenuPreviewState extends State<_MenuPreview> {
  String? _selected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 520;
          final children = <Widget>[];
          for (final (title, description) in const [
            ('Settings', 'Manage preferences'),
            ('Account', 'Profile and security'),
            ('Help', 'Support and docs'),
          ]) {
            if (children.isNotEmpty) {
              children.add(
                DSeparator(
                  orientation: wide ? Axis.vertical : Axis.horizontal,
                  space: wide ? DSpacing.xl : DSpacing.lg,
                ),
              );
            }
            final action = DButton(
              variant: DButtonVariant.flat,
              onPressed: () => setState(() => _selected = title),
              // DButton's single-line default must not truncate descriptions.
              label: DefaultTextStyle(
                style: Theme.of(context).textTheme.labelLarge!,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: DSpacing.xs),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: DTokens.of(context).mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            );
            children.add(wide ? Expanded(child: action) : action);
          }
          return wide
              ? IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                );
        },
      ),
      const SizedBox(height: DSpacing.lg),
      Text(_selected == null ? 'Choose a destination' : 'Selected: $_selected'),
    ],
  );
}

class _ListPreview extends StatefulWidget {
  const _ListPreview();

  @override
  State<_ListPreview> createState() => _ListPreviewState();
}

class _ListPreviewState extends State<_ListPreview> {
  int _count = 12;
  int? _selected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: DSpacing.sm,
        runSpacing: DSpacing.sm,
        children: [
          DButton(
            variant: DButtonVariant.flat,
            onPressed: () => setState(() => _count++),
            label: const Text('Add item'),
          ),
          DButton(
            variant: DButtonVariant.flat,
            onPressed: _count == 0
                ? null
                : () => setState(() {
                    _count = 0;
                    _selected = null;
                  }),
            label: const Text('Clear list'),
          ),
        ],
      ),
      Text(
        _selected == null
            ? '$_count ${_count == 1 ? 'item' : 'items'}'
            : 'Selected: Item $_selected',
      ),
      const SizedBox(height: DSpacing.sm),
      SizedBox(
        height: 240,
        child: _count == 0
            ? const Center(child: Text('No items. Add one to start again.'))
            : ListView.separated(
                key: const ValueKey('separator-example-list'),
                itemCount: _count,
                separatorBuilder: (_, _) => const DSeparator(),
                itemBuilder: (context, index) => ListTile(
                  selected: _selected == index + 1,
                  title: Text('Item ${index + 1}'),
                  subtitle: Text('Value ${index + 1}'),
                  trailing: _selected == index + 1
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => setState(() => _selected = index + 1),
                ),
              ),
      ),
    ],
  );
}

class _RtlPreview extends StatelessWidget {
  const _RtlPreview();

  @override
  Widget build(BuildContext context) => DDirection(
    textDirection: TextDirection.rtl,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('مجتمع ديسكورس', style: Theme.of(context).textTheme.titleMedium),
        const DSeparator(
          indent: DSpacing.xl,
          endIndent: DSpacing.sm,
          space: DSpacing.xl,
        ),
        const Row(
          children: [
            DSeparator(
              orientation: Axis.vertical,
              length: DSpacing.touchTarget,
              space: DSpacing.xl,
            ),
            Expanded(child: Text('مساحة للنقاش وتبادل الأفكار')),
          ],
        ),
        const SizedBox(height: DSpacing.lg),
        const SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text('البداية'),
              DSeparator(
                length: 96,
                space: DSpacing.xl,
                indent: DSpacing.xl,
                endIndent: DSpacing.sm,
              ),
              Text('النهاية'),
            ],
          ),
        ),
      ],
    ),
  );
}
