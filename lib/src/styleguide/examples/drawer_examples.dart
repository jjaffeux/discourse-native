import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final drawerExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'A panel that slides from a viewport edge and supports touch dragging.',
  notes:
      'The examples reproduce the frozen Base UI/base-nova Drawer source: '
      'content-sized vertical panels, 75%/384px side panels, exposed-edge '
      'borders and xl radius, optional 96×4 handle, four physical and two '
      'logical directions, nested stacking, true non-modal interaction and '
      'fraction/pixel/rem snap points. Flutter owns route, gesture-arena, '
      'focus, safe-area and IME behavior. Official rendered and native macOS '
      'review passed; iOS, Linux and spoken VoiceOver were not exercised.',
  examples: [
    StyleguideExample(
      title: 'Delivery time',
      description:
          'Frozen primary composition. Select a delivery window, confirm it, or swipe down to dismiss.',
      code: _deliveryCode,
      builder: (_) => const _DeliveryDrawer(),
      states: const ['controlled', 'radio group', 'swipe', 'typed close'],
    ),
    StyleguideExample(
      title: 'Custom sizes and styling',
      description:
          'A half-height inset bottom drawer with a host-token bleed background.',
      code: _customSizeCode,
      builder: (_) => const _BasicDrawer(
        title: 'Custom size',
        height: 300,
        inset: 12,
        showHandle: true,
      ),
    ),
    StyleguideExample(
      title: 'Position',
      description:
          'Open the same composition from each physical edge or logical end.',
      code: _positionCode,
      builder: (_) => const _PositionDrawers(),
      states: const ['up', 'right', 'down', 'left', 'logical end'],
    ),
    StyleguideExample(
      title: 'Swipe handle',
      description:
          'The handle accepts mouse and touch dragging; the rest of the surface preserves mouse text selection.',
      code: _handleCode,
      builder: (_) => const _BasicDrawer(
        title: 'Drawer with a swipe handle',
        showHandle: true,
      ),
    ),
    StyleguideExample(
      title: 'Nested',
      description:
          'Open four drawers from the same edge. Only the frontmost owns gestures and Escape.',
      code: _nestedCode,
      builder: (_) => const _NestedDrawer(level: 1),
      states: const ['four levels', 'stack scale', 'focus ownership'],
    ),
    StyleguideExample(
      title: 'Non modal',
      description:
          'The page action remains clickable while the side drawer is open. Its outside press does not dismiss this example.',
      code: _nonModalCode,
      builder: (_) => const _NonModalDrawer(),
      states: const ['pointer pass-through', 'untrapped focus'],
    ),
    StyleguideExample(
      title: 'Snap points',
      description:
          'Drag between a 240px compact point and full height, or use the explicit controls.',
      code: _snapCode,
      builder: (_) => const _SnapDrawer(),
      states: const ['pixels', 'fraction', 'controlled snap'],
    ),
    StyleguideExample(
      title: 'Responsive dialog',
      description:
          'Below 768px this uses Drawer; at wider preview sizes the accepted Dialog owner renders the same form.',
      code: _responsiveCode,
      builder: (_) => const _ResponsiveEditor(),
      states: const ['drawer', 'dialog', 'form', 'live breakpoint'],
    ),
    StyleguideExample(
      title: 'RTL and logical placement',
      description:
          'Logical end resolves to the left edge for Arabic while text, radius and focus order remain directional.',
      code: _rtlCode,
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: _BasicDrawer(
          title: 'درج منطقي',
          description: 'اسحب نحو اليسار للإغلاق.',
          swipeDirection: DDrawerSwipeDirection.end,
          showHandle: true,
        ),
      ),
    ),
  ],
);

const _deliveryCode = '''DDrawer<String>(
  open: open,
  onOpenChanged: (details) => setState(() => open = details.open),
  showSwipeHandle: true,
  trigger: DDrawerTrigger(builder: (_, open) =>
    DButton(onPressed: open, variant: DButtonVariant.secondary,
      label: const Text('Open Drawer'))),
  content: DDrawerContent(children: [
    const DDrawerHeader(children: [
      DDrawerTitle(child: Text('Pick a delivery time')),
      DDrawerDescription(child: Text('We’ll prepare your order as soon as possible.')),
    ]),
    DDrawerScrollArea(child: DRadioGroup<String>.controlled(...)),
    DDrawerFooter(children: [confirm, DDrawerClose(builder: cancel)]),
  ]),
)''';

const _customSizeCode = '''DDrawer(
  showSwipeHandle: true,
  content: DDrawerContent(height: 300, inset: 12,
    bleedBackground: DTokens.of(context).surface,
    children: [...]),
)''';

const _positionCode = '''for (final direction in DDrawerSwipeDirection.values)
  DDrawer(swipeDirection: direction, content: drawerContent)''';

const _handleCode = '''DDrawer(
  showSwipeHandle: true,
  content: DDrawerContent(children: [header, body, footer]),
)''';

const _nestedCode = '''DDrawer(content: DDrawerContent(children: [
  const DDrawerHeader(children: [DDrawerTitle(child: Text('Drawer'))]),
  DDrawer(content: nestedContent, trigger: nestedTrigger),
]))''';

const _nonModalCode = '''DDrawer(
  modalMode: DDrawerModalMode.nonModal,
  disablePointerDismissal: true,
  swipeDirection: DDrawerSwipeDirection.right,
  content: sideDrawer,
)''';

const _snapCode = '''const points = [
  DDrawerSnapPoint.pixels(240),
  DDrawerSnapPoint.fraction(1),
];
DDrawer(
  snapPoints: points,
  snapPoint: point,
  onSnapPointChanged: (details) => setState(() => point = details.point),
  snapToSequentialPoints: true,
  showSwipeHandle: true,
  content: snapContent,
)''';

const _responsiveCode = '''LayoutBuilder(builder: (context, constraints) {
  return constraints.maxWidth >= 768
    ? DDialog(content: profileDialog, trigger: trigger)
    : DDrawer(content: profileDrawer, trigger: trigger);
})''';

const _rtlCode = '''Directionality(
  textDirection: TextDirection.rtl,
  child: DDrawer(
    swipeDirection: DDrawerSwipeDirection.end,
    content: arabicContent,
  ),
)''';

class _BasicDrawer extends StatelessWidget {
  const _BasicDrawer({
    required this.title,
    this.description = 'A faithful base-nova edge panel.',
    this.swipeDirection = DDrawerSwipeDirection.down,
    this.showHandle = false,
    this.height,
    this.inset = 0,
  });

  final String title;
  final String description;
  final DDrawerSwipeDirection swipeDirection;
  final bool showHandle;
  final double? height;
  final double inset;

  @override
  Widget build(BuildContext context) => DDrawer<void>(
    swipeDirection: swipeDirection,
    showSwipeHandle: showHandle,
    trigger: DDrawerTrigger(
      builder: (_, open) => DButton(
        onPressed: open,
        variant: DButtonVariant.secondary,
        label: Text('Open $title'),
      ),
    ),
    content: DDrawerContent(
      height: height,
      inset: inset,
      semanticLabel: title,
      children: [
        DDrawerHeader(
          children: [
            DDrawerTitle(child: Text(title)),
            DDrawerDescription(child: Text(description)),
          ],
        ),
        const DDrawerScrollArea(
          padding: EdgeInsets.all(16),
          child: SizedBox(
            height: 96,
            child: ColoredBox(color: Colors.transparent),
          ),
        ),
        DDrawerFooter(
          children: [
            DDrawerClose<void>(
              builder: (_, close) => DButton(
                onPressed: close,
                variant: DButtonVariant.outline,
                label: const Text('Close'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _DeliveryDrawer extends StatefulWidget {
  const _DeliveryDrawer();

  @override
  State<_DeliveryDrawer> createState() => _DeliveryDrawerState();
}

class _DeliveryDrawerState extends State<_DeliveryDrawer> {
  bool _open = false;
  String _time = 'asap';
  String? _confirmed;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DDrawer<String>(
          open: _open,
          onOpenChanged: (details) => setState(() {
            _open = details.open;
            if (details.result != null) _confirmed = details.result;
          }),
          showSwipeHandle: isMobile,
          swipeDirection: isMobile
              ? DDrawerSwipeDirection.down
              : DDrawerSwipeDirection.right,
          trigger: DDrawerTrigger(
            builder: (_, open) => DButton(
              onPressed: open,
              variant: DButtonVariant.secondary,
              label: const Text('Open Drawer'),
            ),
          ),
          content: DDrawerContent(
            semanticLabel: 'Pick a delivery time',
            children: [
              const DDrawerHeader(
                children: [
                  DDrawerTitle(child: Text('Pick a delivery time')),
                  DDrawerDescription(
                    child: Text(
                      'We’ll prepare your order as soon as possible.',
                    ),
                  ),
                ],
              ),
              DDrawerScrollArea(
                padding: const EdgeInsets.all(16),
                child: DRadioGroup<String>.controlled(
                  groupValue: _time,
                  onChanged: (value) => setState(() => _time = value ?? _time),
                  child: Column(
                    children: [
                      for (final choice in const [
                        (
                          'asap',
                          'Standard delivery',
                          '25–35 min · Driver assigned now',
                          'Fastest',
                        ),
                        (
                          '5:00',
                          '5:00 PM – 5:15 PM',
                          'Prep starts at 4:45 PM',
                          null,
                        ),
                        (
                          '5:30',
                          '5:30 PM – 5:45 PM',
                          "Good if you're heading home",
                          null,
                        ),
                        (
                          '6:00',
                          '6:00 PM – 6:15 PM',
                          'Most popular · High demand',
                          null,
                        ),
                        (
                          '6:30',
                          '6:30 PM – 6:45 PM',
                          'Last slot before kitchen closes',
                          null,
                        ),
                      ])
                        DRadioGroupItem<String>(
                          value: choice.$1,
                          label: Wrap(
                            spacing: DSpacing.sm,
                            runSpacing: DSpacing.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(choice.$2),
                              if (choice.$4 != null)
                                DBadge(
                                  variant: DBadgeVariant.secondary,
                                  child: Text(choice.$4!),
                                ),
                            ],
                          ),
                          description: Text(choice.$3),
                          card: true,
                        ),
                    ],
                  ),
                ),
              ),
              DDrawerFooter(
                children: [
                  DDrawerClose<String>(
                    result: _time,
                    builder: (_, close) => DButton(
                      onPressed: close,
                      label: const Text('Confirm Delivery Time'),
                    ),
                  ),
                  DDrawerClose<String>(
                    builder: (_, close) => DButton(
                      onPressed: close,
                      variant: DButtonVariant.outline,
                      label: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_confirmed != null) ...[
          const SizedBox(height: 8),
          Text('Confirmed: $_confirmed'),
        ],
      ],
    );
  }
}

class _PositionDrawers extends StatelessWidget {
  const _PositionDrawers();

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final entry in const [
        ('Up', DDrawerSwipeDirection.up),
        ('Right', DDrawerSwipeDirection.right),
        ('Down', DDrawerSwipeDirection.down),
        ('Left', DDrawerSwipeDirection.left),
        ('Logical end', DDrawerSwipeDirection.end),
      ])
        _BasicDrawer(title: entry.$1, swipeDirection: entry.$2),
    ],
  );
}

class _NestedDrawer extends StatelessWidget {
  const _NestedDrawer({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) => DDrawer<void>(
    showSwipeHandle: true,
    trigger: DDrawerTrigger(
      builder: (_, open) => DButton(
        onPressed: open,
        variant: level == 1 ? DButtonVariant.secondary : DButtonVariant.outline,
        label: Text(level == 1 ? 'Open Drawer' : 'Open Nested Drawer'),
      ),
    ),
    content: DDrawerContent(
      children: [
        DDrawerHeader(
          children: [
            DDrawerTitle(child: Text(level == 1 ? 'Drawer' : 'Drawer $level')),
            DDrawerDescription(
              child: Text('Level $level stays mounted when another opens.'),
            ),
          ],
        ),
        DDrawerScrollArea(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 100,
            child: ColoredBox(color: DTokens.of(context).muted),
          ),
        ),
        DDrawerFooter(
          children: [
            if (level < 4) _NestedDrawer(level: level + 1),
            DDrawerClose<void>(
              builder: (_, close) => DButton(
                onPressed: close,
                variant: DButtonVariant.outline,
                label: const Text('Close'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _NonModalDrawer extends StatefulWidget {
  const _NonModalDrawer();

  @override
  State<_NonModalDrawer> createState() => _NonModalDrawerState();
}

class _NonModalDrawerState extends State<_NonModalDrawer> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 160,
    child: Stack(
      children: [
        Align(
          alignment: Alignment.bottomLeft,
          child: DButton(
            onPressed: () => setState(() => _count++),
            variant: DButtonVariant.outline,
            label: Text('Page action · $_count'),
          ),
        ),
        Align(
          alignment: Alignment.topLeft,
          child: DDrawer<void>(
            modalMode: DDrawerModalMode.nonModal,
            disablePointerDismissal: true,
            swipeDirection: DDrawerSwipeDirection.right,
            trigger: DDrawerTrigger(
              builder: (_, open) =>
                  DButton(onPressed: open, label: const Text('Non Modal')),
            ),
            content: DDrawerContent(
              semanticLabel: 'Non modal drawer',
              children: [
                const DDrawerHeader(
                  children: [DDrawerTitle(child: Text('Non Modal Drawer'))],
                ),
                const Spacer(),
                DDrawerFooter(
                  children: [
                    DDrawerClose<void>(
                      builder: (_, close) =>
                          DButton(onPressed: close, label: const Text('Close')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _SnapDrawer extends StatefulWidget {
  const _SnapDrawer();

  @override
  State<_SnapDrawer> createState() => _SnapDrawerState();
}

class _SnapDrawerState extends State<_SnapDrawer> {
  static const _compact = DDrawerSnapPoint.pixels(240);
  static const _expanded = DDrawerSnapPoint.fraction(1);
  DDrawerSnapPoint _point = _compact;

  @override
  Widget build(BuildContext context) => DDrawer<void>(
    snapPoints: const [_compact, _expanded],
    snapPoint: _point,
    onSnapPointChanged: (details) {
      if (details.point != null) setState(() => _point = details.point!);
    },
    snapToSequentialPoints: true,
    showSwipeHandle: true,
    trigger: DDrawerTrigger(
      builder: (_, open) => DButton(
        onPressed: open,
        variant: DButtonVariant.outline,
        label: const Text('Open Snap Drawer'),
      ),
    ),
    content: DDrawerContent(
      children: [
        const DDrawerHeader(
          children: [
            DDrawerTitle(child: Text('Snap points')),
            DDrawerDescription(
              child: Text('Drag between a compact peek and full height.'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            children: [
              DButton(
                onPressed: () => setState(() => _point = _compact),
                variant: DButtonVariant.outline,
                label: const Text('Compact'),
              ),
              DButton(
                onPressed: () => setState(() => _point = _expanded),
                variant: DButtonVariant.outline,
                label: const Text('Expanded'),
              ),
            ],
          ),
        ),
        const Spacer(),
        DDrawerFooter(
          children: [
            DDrawerClose<void>(
              builder: (_, close) =>
                  DButton(onPressed: close, label: const Text('Close')),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ResponsiveEditor extends StatelessWidget {
  const _ResponsiveEditor();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const header = [
        DDrawerTitle(child: Text('Edit profile')),
        DDrawerDescription(
          child: Text('Make changes to your profile, then save.'),
        ),
      ];
      if (constraints.maxWidth < 768) {
        return DDrawer<void>(
          trigger: DDrawerTrigger(builder: (_, open) => _editButton(open)),
          content: const DDrawerContent(
            children: [
              DDrawerHeader(textAlign: TextAlign.start, children: header),
              DDrawerScrollArea(
                padding: EdgeInsets.all(16),
                child: _ProfileForm(),
              ),
            ],
          ),
        );
      }
      return DDialog<void>(
        trigger: DDialogTrigger(builder: (_, open) => _editButton(open)),
        content: const DDialogContent(
          children: [
            DDialogHeader(
              children: [
                DDialogTitle(child: Text('Edit profile')),
                DDialogDescription(
                  child: Text('Make changes to your profile, then save.'),
                ),
              ],
            ),
            _ProfileForm(),
          ],
        ),
      );
    },
  );

  static Widget _editButton(VoidCallback open) => DButton(
    onPressed: open,
    variant: DButtonVariant.outline,
    label: const Text('Edit Profile'),
  );
}

class _ProfileForm extends StatelessWidget {
  const _ProfileForm();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DInput(
        labelText: 'Email',
        keyboardType: TextInputType.emailAddress,
        initialValue: 'alex@example.com',
      ),
      const SizedBox(height: 12),
      DInput(labelText: 'Username', initialValue: '@alex'),
      const SizedBox(height: 16),
      DButton(onPressed: () {}, label: const Text('Save changes')),
    ],
  );
}
