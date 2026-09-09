import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final contextMenuExamples = ComponentExamples(
  status: ComponentStatus.baseline,
  description: 'Displays actions at a secondary click or long-press location.',
  notes:
      'Installation: import package:discourse_native/discourse_ui.dart. '
      'Composition: DContextMenu > DContextMenuTrigger + DContextMenuContent; '
      'content composes Group, Label, Item, CheckboxItem, RadioGroup/RadioItem, '
      'Separator, Shortcut and Sub. The trigger supports secondary pointer, '
      'touch long press, Context Menu, Shift+F10 and an accessibility long-press '
      'action. Context actions enhance rather than replace visible controls. '
      'The shared Dropdown Menu owner supplies navigation, selection, submenu, '
      'typeahead, positioning, dismissal and focus restoration.',
  examples: [
    StyleguideExample(
      title: 'Basic',
      description:
          'Right click or long press the target. Forward is disabled; selecting '
          'another action closes the menu and reports the local result.',
      states: const ['Secondary click', 'Long press', 'Disabled', 'Selection'],
      code: '''DContextMenu(
  content: DContextMenuContent(children: [
    DContextMenuItem(onPressed: goBack, child: const Text('Back')),
    const DContextMenuItem(child: Text('Forward')),
    DContextMenuItem(onPressed: reload, child: const Text('Reload')),
  ]),
  child: const DContextMenuTrigger(child: ContextTarget()),
)''',
      builder: (_) => const _BasicContextMenu(),
    ),
    StyleguideExample(
      title: 'Submenu',
      description:
          'More Tools opens inline-end. Hover or use the logical arrow; Escape '
          'closes the deepest popup before the root.',
      states: const ['Nested', 'Hover', 'Arrow keys', 'Deepest Escape'],
      code: '''DContextMenuSub(
  trigger: const Text('More Tools'),
  children: [
    DContextMenuItem(onPressed: savePage, child: const Text('Save Page...')),
    const DContextMenuSeparator(),
    DContextMenuItem(variant: DContextMenuItemVariant.destructive,
      onPressed: delete, child: const Text('Delete')),
  ],
)''',
      builder: (_) => _exampleMenu(children: _submenuItems()),
    ),
    StyleguideExample(
      title: 'Shortcuts',
      description:
          'Shortcut hints use muted 12px tracked text while keyboard typeahead '
          'continues to match the action label.',
      states: const ['Shortcut hints', 'Typeahead', 'Disabled'],
      code: '''DContextMenuItem(
  onPressed: reload,
  trailing: const DContextMenuShortcut('⌘R'),
  child: const Text('Reload'),
)''',
      builder: (_) => _exampleMenu(children: _shortcutItems()),
    ),
    StyleguideExample(
      title: 'Groups',
      description:
          'Related File and Edit actions use labels and full-width separators.',
      states: const ['Group', 'Label', 'Separator', 'Destructive'],
      code: '''DContextMenuGroup(children: [
  const DContextMenuLabel(child: Text('File')),
  DContextMenuItem(onPressed: newFile, child: const Text('New File')),
])''',
      builder: (_) => _exampleMenu(width: 192, children: _groupItems()),
    ),
    StyleguideExample(
      title: 'Icons',
      description: 'Caller-supplied artwork is constrained to the shared 16px leading slot.',
      states: const ['Leading icons', 'Destructive icon'],
      code: '''DContextMenuItem(
  leading: const Icon(Icons.copy_outlined),
  onPressed: copy,
  child: const Text('Copy'),
)''',
      builder: (_) => _exampleMenu(children: _iconItems()),
    ),
    StyleguideExample(
      title: 'Checkboxes',
      description: 'Toggle controlled and default-owned options without closing the menu.',
      states: const ['Checked', 'Unchecked', 'Controlled', 'Uncontrolled'],
      code: '''DContextMenuCheckboxItem(
  checked: bookmarks,
  onChanged: (value) => setState(() => bookmarks = value),
  child: const Text('Show Bookmarks Bar'),
)''',
      builder: (_) => const _CheckboxContextMenu(),
    ),
    StyleguideExample(
      title: 'Radio',
      description:
          'Two controlled radio groups choose a person and theme while retaining '
          'the open surface.',
      states: const ['Radio group', 'Selected', 'Controlled'],
      code: '''DContextMenuRadioGroup<String>(
  value: person,
  onChanged: (value) => setState(() => person = value),
  children: const [
    DContextMenuRadioItem(value: 'Pedro', child: Text('Pedro Duarte')),
    DContextMenuRadioItem(value: 'Colm', child: Text('Colm Tuite')),
  ],
)''',
      builder: (_) => const _RadioContextMenu(),
    ),
    StyleguideExample(
      title: 'Destructive',
      description:
          'Delete uses the destructive foreground and focused translucent fill; '
          'ordinary Edit and Share actions retain standard styling.',
      states: const ['Default', 'Destructive', 'Focus', 'Dark'],
      code: '''DContextMenuItem(
  variant: DContextMenuItemVariant.destructive,
  leading: const Icon(Icons.delete_outline),
  onPressed: delete,
  child: const Text('Delete'),
)''',
      builder: (_) => _exampleMenu(children: _destructiveItems()),
    ),
    StyleguideExample(
      title: 'Sides',
      description:
          'Each pointer-relative popup prefers the documented physical side and '
          'flips or shifts when the preview edge cannot fit it.',
      states: const [
        'Top',
        'Right',
        'Bottom',
        'Left',
        'Inline end',
        'Collision',
      ],
      code: '''DContextMenuContent(
  side: DPopoverSide.top,
  children: actions,
)''',
      builder: (_) => const _SidesContextMenus(),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'Arabic content mirrors inset, trailing checks, shortcut placement and '
          'inline submenu navigation. Use Left Arrow to open a submenu.',
      states: const ['RTL', 'Arabic', 'Logical submenu', '200% text'],
      code: '''Directionality(
  textDirection: TextDirection.rtl,
  child: DContextMenu(content: DContextMenuContent(children: actions),
    child: DContextMenuTrigger(child: target)),
)''',
      builder: (_) => const _RtlContextMenu(),
    ),
  ],
);

class _BasicContextMenu extends StatefulWidget {
  const _BasicContextMenu();

  @override
  State<_BasicContextMenu> createState() => _BasicContextMenuState();
}

class _BasicContextMenuState extends State<_BasicContextMenu> {
  String _result = 'No action selected';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _contextMenu(
        children: [
          DContextMenuItem(
            onPressed: () => setState(() => _result = 'Back'),
            child: const Text('Back'),
          ),
          const DContextMenuItem(child: Text('Forward')),
          DContextMenuItem(
            onPressed: () => setState(() => _result = 'Reload'),
            child: const Text('Reload'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(_result),
    ],
  );
}

Widget _exampleMenu({required List<Widget> children, double width = 176}) =>
    _contextMenu(children: children, width: width);

Widget _contextMenu({
  required List<Widget> children,
  double width = 176,
  DPopoverSide side = DPopoverSide.right,
  String label = 'Right click or long press here',
}) => DContextMenu(
  content: DContextMenuContent(
    semanticLabel: 'Context actions',
    width: width,
    side: side,
    children: children,
  ),
  child: DContextMenuTrigger(
    semanticLabel: 'Context menu target',
    child: _ContextTarget(label: label),
  ),
);

List<Widget> _submenuItems() => [
  DContextMenuItem(onPressed: () {}, child: const Text('Copy')),
  DContextMenuItem(onPressed: () {}, child: const Text('Cut')),
  DContextMenuSub(
    trigger: const Text('More Tools'),
    width: 176,
    children: [
      DContextMenuItem(onPressed: () {}, child: const Text('Save Page...')),
      DContextMenuItem(
        onPressed: () {},
        child: const Text('Create Shortcut...'),
      ),
      DContextMenuItem(onPressed: () {}, child: const Text('Name Window...')),
      const DContextMenuSeparator(),
      DContextMenuItem(onPressed: () {}, child: const Text('Developer Tools')),
      const DContextMenuSeparator(),
      DContextMenuItem(
        onPressed: () {},
        variant: DContextMenuItemVariant.destructive,
        child: const Text('Delete'),
      ),
    ],
  ),
];

List<Widget> _shortcutItems() => [
  DContextMenuItem(
    onPressed: () {},
    trailing: const DContextMenuShortcut('⌘['),
    child: const Text('Back'),
  ),
  const DContextMenuItem(
    trailing: DContextMenuShortcut('⌘]'),
    child: Text('Forward'),
  ),
  DContextMenuItem(
    onPressed: () {},
    trailing: const DContextMenuShortcut('⌘R'),
    child: const Text('Reload'),
  ),
  const DContextMenuSeparator(),
  DContextMenuItem(
    onPressed: () {},
    trailing: const DContextMenuShortcut('⇧⌘S'),
    child: const Text('Save As...'),
  ),
];

List<Widget> _groupItems() => [
  DContextMenuGroup(
    children: [
      const DContextMenuLabel(child: Text('File')),
      DContextMenuItem(
        onPressed: () {},
        trailing: const DContextMenuShortcut('⌘N'),
        child: const Text('New File'),
      ),
      DContextMenuItem(
        onPressed: () {},
        trailing: const DContextMenuShortcut('⌘O'),
        child: const Text('Open File'),
      ),
      DContextMenuItem(
        onPressed: () {},
        trailing: const DContextMenuShortcut('⌘S'),
        child: const Text('Save'),
      ),
    ],
  ),
  const DContextMenuSeparator(),
  DContextMenuGroup(
    children: [
      const DContextMenuLabel(child: Text('Edit')),
      DContextMenuItem(onPressed: () {}, child: const Text('Undo')),
      DContextMenuItem(onPressed: () {}, child: const Text('Redo')),
    ],
  ),
  const DContextMenuSeparator(),
  DContextMenuItem(
    onPressed: () {},
    variant: DContextMenuItemVariant.destructive,
    trailing: const DContextMenuShortcut('⌫'),
    child: const Text('Delete'),
  ),
];

List<Widget> _iconItems() => [
  DContextMenuItem(
    onPressed: () {},
    leading: const Icon(Icons.copy_outlined),
    child: const Text('Copy'),
  ),
  DContextMenuItem(
    onPressed: () {},
    leading: const Icon(Icons.content_cut),
    child: const Text('Cut'),
  ),
  DContextMenuItem(
    onPressed: () {},
    leading: const Icon(Icons.content_paste_outlined),
    child: const Text('Paste'),
  ),
  const DContextMenuSeparator(),
  DContextMenuItem(
    onPressed: () {},
    leading: const Icon(Icons.delete_outline),
    variant: DContextMenuItemVariant.destructive,
    child: const Text('Delete'),
  ),
];

List<Widget> _destructiveItems() => [
  DContextMenuItem(
    onPressed: () {},
    leading: const Icon(Icons.edit_outlined),
    child: const Text('Edit'),
  ),
  DContextMenuItem(
    onPressed: () {},
    leading: const Icon(Icons.ios_share_outlined),
    child: const Text('Share'),
  ),
  const DContextMenuSeparator(),
  DContextMenuItem(
    onPressed: () {},
    leading: const Icon(Icons.delete_outline),
    variant: DContextMenuItemVariant.destructive,
    child: const Text('Delete'),
  ),
];

class _CheckboxContextMenu extends StatefulWidget {
  const _CheckboxContextMenu();

  @override
  State<_CheckboxContextMenu> createState() => _CheckboxContextMenuState();
}

class _CheckboxContextMenuState extends State<_CheckboxContextMenu> {
  bool _bookmarks = true;

  @override
  Widget build(BuildContext context) => _contextMenu(
    width: 208,
    children: [
      DContextMenuCheckboxItem(
        checked: _bookmarks,
        onChanged: (value) => setState(() => _bookmarks = value),
        child: const Text('Show Bookmarks Bar'),
      ),
      const DContextMenuCheckboxItem(child: Text('Show Full URLs')),
      const DContextMenuCheckboxItem(
        defaultChecked: true,
        child: Text('Show Developer Tools'),
      ),
    ],
  );
}

class _RadioContextMenu extends StatefulWidget {
  const _RadioContextMenu();

  @override
  State<_RadioContextMenu> createState() => _RadioContextMenuState();
}

class _RadioContextMenuState extends State<_RadioContextMenu> {
  String _person = 'Pedro';
  String _theme = 'Light';

  @override
  Widget build(BuildContext context) => _contextMenu(
    width: 176,
    children: [
      const DContextMenuLabel(child: Text('People')),
      DContextMenuRadioGroup<String>(
        value: _person,
        onChanged: (value) => setState(() => _person = value),
        children: const [
          DContextMenuRadioItem(value: 'Pedro', child: Text('Pedro Duarte')),
          DContextMenuRadioItem(value: 'Colm', child: Text('Colm Tuite')),
        ],
      ),
      const DContextMenuSeparator(),
      const DContextMenuLabel(child: Text('Theme')),
      DContextMenuRadioGroup<String>(
        value: _theme,
        onChanged: (value) => setState(() => _theme = value),
        children: const [
          DContextMenuRadioItem(value: 'Light', child: Text('Light')),
          DContextMenuRadioItem(value: 'Dark', child: Text('Dark')),
          DContextMenuRadioItem(value: 'System', child: Text('System')),
        ],
      ),
    ],
  );
}

class _SidesContextMenus extends StatelessWidget {
  const _SidesContextMenus();

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 16,
    runSpacing: 16,
    children: [
      for (final entry in const [
        ('top', DPopoverSide.top),
        ('right', DPopoverSide.right),
        ('bottom', DPopoverSide.bottom),
        ('left', DPopoverSide.left),
        ('inline-end', DPopoverSide.inlineEnd),
      ])
        SizedBox(
          width: 144,
          child: _contextMenu(
            side: entry.$2,
            label: 'Right click (${entry.$1})',
            children: [
              DContextMenuItem(onPressed: () {}, child: const Text('Back')),
              DContextMenuItem(onPressed: () {}, child: const Text('Forward')),
              DContextMenuItem(onPressed: () {}, child: const Text('Reload')),
            ],
          ),
        ),
    ],
  );
}

class _RtlContextMenu extends StatefulWidget {
  const _RtlContextMenu();

  @override
  State<_RtlContextMenu> createState() => _RtlContextMenuState();
}

class _RtlContextMenuState extends State<_RtlContextMenu> {
  bool _bookmarks = true;
  String _person = 'Pedro';

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: _contextMenu(
      width: 192,
      label: 'انقر بزر الماوس الأيمن هنا',
      children: [
        DContextMenuSub(
          trigger: const Text('التنقل'),
          children: [
            DContextMenuItem(
              onPressed: () {},
              leading: const Icon(Icons.arrow_back),
              trailing: const DContextMenuShortcut('⌘['),
              child: const Text('رجوع'),
            ),
            const DContextMenuItem(child: Text('تقدم')),
            DContextMenuItem(
              onPressed: () {},
              leading: const Icon(Icons.refresh),
              child: const Text('إعادة تحميل'),
            ),
          ],
        ),
        const DContextMenuSeparator(),
        DContextMenuCheckboxItem(
          checked: _bookmarks,
          onChanged: (value) => setState(() => _bookmarks = value),
          child: const Text('إظهار الإشارات المرجعية'),
        ),
        const DContextMenuSeparator(),
        const DContextMenuLabel(child: Text('الأشخاص')),
        DContextMenuRadioGroup<String>(
          value: _person,
          onChanged: (value) => setState(() => _person = value),
          children: const [
            DContextMenuRadioItem(value: 'Pedro', child: Text('Pedro Duarte')),
            DContextMenuRadioItem(value: 'Colm', child: Text('Colm Tuite')),
          ],
        ),
      ],
    ),
  );
}

class _ContextTarget extends StatelessWidget {
  const _ContextTarget({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: tokens.border,
            radius: tokens.radius * 1.4,
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(label, textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    final metric = path.computeMetrics().single;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (double offset = 0; offset < metric.length; offset += 7) {
      canvas.drawPath(metric.extractPath(offset, offset + 4), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      color != oldDelegate.color || radius != oldDelegate.radius;
}
