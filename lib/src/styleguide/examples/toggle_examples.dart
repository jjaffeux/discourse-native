import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';
import 'toggle_reference_icons.dart';

final toggleExamples = ComponentExamples(
  description: 'A two-state button that can be either on or off.',
  status: ComponentStatus.implemented,
  notes:
      'Audited against the current base-nova Toggle source, examples and Base UI API. '
      'DToggle accepts controlled pressed/onPressedChanged state or internally owned initialPressed state. '
      'Controlled state remains interactive when its optional callback is omitted. Borrowed focus nodes are never disposed. '
      'Space, Enter, pointer and native semantics toggle the value; disabled controls do not enter traversal or activate. '
      'Visual surfaces are 28/32/36px with 48px touch targets, 14/16px icons, exact icon-side padding, '
      'Lucide example artwork, live palette/font/radius, RTL composition and reduced motion.',
  examples: [
    StyleguideExample(
      title: 'Default',
      description:
          'The frozen lead example: a small outline bookmark toggle with a filled pressed icon.',
      states: const ['Outline', 'Small', 'Pressed', 'Icon and text'],
      code: '''DToggle(
  pressed: bookmarked,
  onPressedChanged: (value) => setState(() => bookmarked = value),
  variant: DToggleVariant.outline,
  size: DToggleSize.small,
  semanticLabel: 'Toggle bookmark',
  icon: const ToggleReferenceIcon(ToggleReferenceIcon.bookmark),
  selectedIcon: const ToggleReferenceIcon(ToggleReferenceIcon.bookmark, filled: true),
  child: const Text('Bookmark'),
)''',
      builder: (_) => const _BookmarkDemo(),
    ),
    StyleguideExample(
      title: 'Outline',
      description:
          'Two independent outline formatting preferences; each keeps its own state.',
      states: const ['Outline', 'Icon and text', 'Independent values'],
      code:
          "DToggle(pressed: italic, onPressedChanged: setItalic, variant: DToggleVariant.outline, icon: const ToggleReferenceIcon(ToggleReferenceIcon.italic), child: const Text('Italic'))",
      builder: (_) => const _OutlineDemo(),
    ),
    StyleguideExample(
      title: 'With Text',
      description:
          'Default treatment with the documented italic icon and label.',
      states: const ['Default', 'Icon and text', 'Hover', 'Focus'],
      code:
          "DToggle(pressed: italic, onPressedChanged: setItalic, semanticLabel: 'Toggle italic', icon: const ToggleReferenceIcon(ToggleReferenceIcon.italic), child: const Text('Italic'))",
      builder: (_) => const _TextDemo(),
    ),
    StyleguideExample(
      title: 'Size',
      description:
          'Small, default and large preserve the measured base-nova bounds.',
      states: const ['Small 28px', 'Default 32px', 'Large 36px'],
      code:
          "DToggle(initialPressed: true, size: DToggleSize.small, variant: DToggleVariant.outline, child: const Text('Small'))",
      builder: (_) => const _SizeDemo(),
    ),
    StyleguideExample(
      title: 'Disabled',
      description:
          'Both variants retain pressed semantics while blocking every activation path.',
      states: const ['Disabled', 'Default', 'Outline', 'Pressed'],
      code:
          "DToggle(initialPressed: true, enabled: false, child: const Text('Disabled'))",
      builder: (_) => const Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          DToggle(enabled: false, child: Text('Disabled')),
          DToggle(
            initialPressed: true,
            enabled: false,
            variant: DToggleVariant.outline,
            child: Text('Disabled'),
          ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'The Arabic bookmark composition uses logical icon placement and spacing.',
      states: const ['RTL', 'Arabic', 'Outline', 'Small'],
      code:
          "Directionality(textDirection: TextDirection.rtl, child: DToggle(initialPressed: true, variant: DToggleVariant.outline, size: DToggleSize.small, icon: const ToggleReferenceIcon(ToggleReferenceIcon.bookmark), child: const Text('إشارة مرجعية'))) ",
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: _BookmarkDemo(arabic: true),
      ),
    ),
    StyleguideExample(
      title: 'Ownership and states',
      description:
          'Compare controlled and uncontrolled state, an icon-only button and invalid semantics.',
      states: const [
        'Controlled',
        'Uncontrolled',
        'Icon-only',
        'Invalid',
        'External update',
      ],
      code:
          '''DToggle(pressed: controlled, onPressedChanged: setControlled, child: const Text('Controlled'));
DToggle(initialPressed: true, onPressedChanged: observe, child: const Text('Uncontrolled'));
DToggle.iconOnly(semanticLabel: 'Toggle bold', icon: const ToggleReferenceIcon(ToggleReferenceIcon.bold));''',
      builder: (_) => const _OwnershipDemo(),
    ),
  ],
);

class _BookmarkDemo extends StatefulWidget {
  const _BookmarkDemo({this.arabic = false});
  final bool arabic;

  @override
  State<_BookmarkDemo> createState() => _BookmarkDemoState();
}

class _BookmarkDemoState extends State<_BookmarkDemo> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => DToggle(
    pressed: _pressed,
    onPressedChanged: (value) => setState(() => _pressed = value),
    variant: DToggleVariant.outline,
    size: DToggleSize.small,
    semanticLabel: 'Toggle bookmark',
    icon: const ToggleReferenceIcon(ToggleReferenceIcon.bookmark),
    selectedIcon: const ToggleReferenceIcon(
      ToggleReferenceIcon.bookmark,
      filled: true,
    ),
    child: Text(widget.arabic ? 'إشارة مرجعية' : 'Bookmark'),
  );
}

class _OutlineDemo extends StatefulWidget {
  const _OutlineDemo();

  @override
  State<_OutlineDemo> createState() => _OutlineDemoState();
}

class _OutlineDemoState extends State<_OutlineDemo> {
  bool _italic = false;
  bool _bold = false;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      DToggle(
        pressed: _italic,
        onPressedChanged: (value) => setState(() => _italic = value),
        variant: DToggleVariant.outline,
        semanticLabel: 'Toggle italic',
        icon: const ToggleReferenceIcon(ToggleReferenceIcon.italic),
        child: const Text('Italic'),
      ),
      DToggle(
        pressed: _bold,
        onPressedChanged: (value) => setState(() => _bold = value),
        variant: DToggleVariant.outline,
        semanticLabel: 'Toggle bold',
        icon: const ToggleReferenceIcon(ToggleReferenceIcon.bold),
        child: const Text('Bold'),
      ),
    ],
  );
}

class _TextDemo extends StatefulWidget {
  const _TextDemo();

  @override
  State<_TextDemo> createState() => _TextDemoState();
}

class _TextDemoState extends State<_TextDemo> {
  bool _italic = false;

  @override
  Widget build(BuildContext context) => DToggle(
    pressed: _italic,
    onPressedChanged: (value) => setState(() => _italic = value),
    semanticLabel: 'Toggle italic',
    icon: const ToggleReferenceIcon(ToggleReferenceIcon.italic),
    child: const Text('Italic'),
  );
}

class _SizeDemo extends StatelessWidget {
  const _SizeDemo();

  @override
  Widget build(BuildContext context) => const Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      DToggle(
        initialPressed: true,
        size: DToggleSize.small,
        variant: DToggleVariant.outline,
        child: Text('Small'),
      ),
      DToggle(
        initialPressed: true,
        variant: DToggleVariant.outline,
        child: Text('Default'),
      ),
      DToggle(
        initialPressed: true,
        size: DToggleSize.large,
        variant: DToggleVariant.outline,
        child: Text('Large'),
      ),
    ],
  );
}

class _OwnershipDemo extends StatefulWidget {
  const _OwnershipDemo();

  @override
  State<_OwnershipDemo> createState() => _OwnershipDemoState();
}

class _OwnershipDemoState extends State<_OwnershipDemo> {
  bool _controlled = false;
  String _observed = 'Uncontrolled changes: 0';
  int _changes = 0;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DToggle(
            pressed: _controlled,
            onPressedChanged: (value) => setState(() => _controlled = value),
            child: const Text('Controlled'),
          ),
          DToggle(
            initialPressed: true,
            onPressedChanged: (_) => setState(() {
              _changes++;
              _observed = 'Uncontrolled changes: $_changes';
            }),
            variant: DToggleVariant.outline,
            child: const Text('Uncontrolled'),
          ),
          const DToggle.iconOnly(
            semanticLabel: 'Toggle bold',
            icon: ToggleReferenceIcon(ToggleReferenceIcon.bold),
            variant: DToggleVariant.outline,
          ),
          const DToggle(
            initialPressed: true,
            invalid: true,
            child: Text('Invalid'),
          ),
          DButton(
            size: DButtonSize.small,
            variant: DButtonVariant.secondary,
            onPressed: () => setState(() => _controlled = !_controlled),
            label: const Text('Change externally'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(_observed),
    ],
  );
}
