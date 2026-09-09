import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../styleguide_example.dart';

final tooltipExamples = ComponentExamples(
  description: 'A brief description that appears on hover or keyboard focus.',
  status: ComponentStatus.implemented,
  notes:
      'Tooltip reproduces the frozen base-nova surface and arrow. The composed '
      'DButton remains the baseline control until its separate component task. '
      'Tooltips supplement a named trigger; put essential instructions inline. '
      'Hover or Tab to a control, move into its tooltip, and press Escape to dismiss. '
      'Long press is a native app extension; it never invokes the child action. '
      'The popup stays in the nearest preview overlay and uses live palette, font, '
      'direction and reduced-motion settings. No installation provider is required; '
      'DTooltipProvider adds shared delay coordination.',
  examples: [
    StyleguideExample(
      title: 'Usage and composition',
      description:
          'The trigger owns its action and focus. The hint describes it.',
      states: const ['Hover', 'Keyboard focus', 'Long press', 'Escape'],
      code: '''DTooltip(
  message: 'Add to library',
  child: DButton(label: const Text('Hover'), onPressed: addToLibrary),
)''',
      builder: (_) => const _Usage(),
    ),
    StyleguideExample(
      title: 'Side',
      description:
          'The four physical sides match the reference. Edges flip and shift when necessary.',
      states: const ['Left', 'Top', 'Bottom', 'Right', 'Collision'],
      code: '''Wrap(spacing: 8, runSpacing: 8, children: [
  for (final side in [DTooltipSide.left, DTooltipSide.top,
                     DTooltipSide.bottom, DTooltipSide.right])
    DTooltip(
      message: 'Add to library', side: side,
      child: DButton(label: Text(side.name), onPressed: addToLibrary),
    ),
])''',
      builder: (_) => _Space(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final side in [
              DTooltipSide.left,
              DTooltipSide.top,
              DTooltipSide.bottom,
              DTooltipSide.right,
            ])
              DTooltip(
                message: 'Add to library',
                side: side,
                child: DButton(label: Text(side.name), onPressed: () {}),
              ),
          ],
        ),
      ),
    ),
    StyleguideExample(
      title: 'With keyboard shortcut',
      description:
          'Save Changes with the S keycap. The example binds S through Shortcuts/Actions; Tooltip only presents it.',
      states: const [
        'Icon trigger',
        'DKbd',
        'Shortcut feedback',
        'Action ownership',
      ],
      code: '''DTooltip(
  message: 'Save Changes',
  shortcut: const DShortcut(SingleActivator(LogicalKeyboardKey.keyS)),
  child: DButton(
    semanticLabel: 'Save Changes', label: saveIcon, // A 16px icon.
    onPressed: save,
  ),
) // Keep the S binding in the surrounding Shortcuts/Actions.''',
      builder: (_) => const _Keyboard(),
    ),
    StyleguideExample(
      title: 'Disabled Button',
      description:
          'The tooltip wrapper still receives hover and long press. Its optional focusable wrapper makes the unavailable explanation reachable by Tab.',
      states: const ['Disabled action', 'Focusable wrapper', 'Semantics'],
      code: '''DTooltip(
  message: 'This feature is currently unavailable',
  focusable: true,
  child: const DButton(label: Text('Disabled'), onPressed: null),
)''',
      builder: (_) => const _Space(
        child: DTooltip(
          message: 'This feature is currently unavailable',
          focusable: true,
          child: DButton(label: Text('Disabled'), onPressed: null),
        ),
      ),
    ),
    StyleguideExample(
      title: 'RTL and logical sides',
      description:
          'Arabic matches the frozen composition. Physical sides stay fixed; inline start/end and start/end alignment follow direction.',
      states: const ['RTL', 'Inline start', 'Inline end'],
      code: '''DDirection(textDirection: TextDirection.rtl, child: Wrap(
  spacing: 8, runSpacing: 8,
  children: [
    for (final (side, label) in [
      (DTooltipSide.left, 'يسار'), (DTooltipSide.top, 'أعلى'),
      (DTooltipSide.bottom, 'أسفل'), (DTooltipSide.right, 'يمين'),
      (DTooltipSide.inlineStart, 'بداية السطر'),
      (DTooltipSide.inlineEnd, 'نهاية السطر'),
    ])
      DTooltip(message: 'إضافة إلى المكتبة', side: side,
        child: DButton(label: Text(label), onPressed: addToLibrary)),
  ],
))''',
      builder: (_) => _Space(
        child: DDirection(
          textDirection: TextDirection.rtl,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (side, label) in const [
                (DTooltipSide.left, 'يسار'),
                (DTooltipSide.top, 'أعلى'),
                (DTooltipSide.bottom, 'أسفل'),
                (DTooltipSide.right, 'يمين'),
                (DTooltipSide.inlineStart, 'بداية السطر'),
                (DTooltipSide.inlineEnd, 'نهاية السطر'),
              ])
                DTooltip(
                  message: 'إضافة إلى المكتبة',
                  side: side,
                  child: DButton(label: Text(label), onPressed: () {}),
                ),
            ],
          ),
        ),
      ),
    ),
    StyleguideExample(
      title: 'Alignment and offsets',
      description:
          'Start, center and end alignment, with an 8px side gap and a 4px directional alignment offset.',
      states: const ['Start', 'Center', 'End', 'Offsets'],
      code: '''DTooltip(
  message: 'Aligned information', align: DTooltipAlign.start,
  sideOffset: 8, alignOffset: 4,
  child: DButton(label: const Text('Start'), onPressed: inspect),
)''',
      builder: (_) => _Space(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final align in DTooltipAlign.values)
              DTooltip(
                message: 'Aligned information',
                align: align,
                sideOffset: 8,
                alignOffset: 4,
                child: DButton(label: Text(align.name), onPressed: () {}),
              ),
          ],
        ),
      ),
    ),
    StyleguideExample(
      title: 'Shared delay',
      description:
          'Wait 600ms for the first hint. Neighboring hints open immediately; the group resets after 400ms away. The 100ms close delay also permits slow pointer travel.',
      states: const ['Delay', 'Group', 'Hoverable popup'],
      code: r'''DTooltipProvider(
  delay: const Duration(milliseconds: 600),
  closeDelay: const Duration(milliseconds: 100),
  timeout: const Duration(milliseconds: 400),
  child: Wrap(spacing: 8, children: [
    for (final label in ['One', 'Two', 'Three'])
      DTooltip(message: 'Hint for $label',
        child: DButton(label: Text(label), onPressed: inspect)),
  ]),
)''',
      builder: (_) => _Space(
        child: DTooltipProvider(
          delay: const Duration(milliseconds: 600),
          closeDelay: const Duration(milliseconds: 100),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final label in ['One', 'Two', 'Three'])
                DTooltip(
                  message: 'Hint for $label',
                  child: DButton(label: Text(label), onPressed: () {}),
                ),
            ],
          ),
        ),
      ),
    ),
    StyleguideExample(
      title: 'Controlled visibility and live themes',
      description:
          'Pin the tooltip to compare live preview palettes and large text. This parent accepts focus/hover opening and Escape dismissal but deliberately ignores outside clicks while pinned. Removing the trigger always removes its popup.',
      states: const ['Controlled', 'Live theme', 'Removal', 'Large text'],
      code: '''DTooltip(
  message: 'This pinned hint uses the current palette, font and text scale.',
  open: pinned,
  onOpenChange: (next, reason) {
    if (reason == DTooltipChangeReason.escape ||
        reason == DTooltipChangeReason.lifecycle ||
        reason == DTooltipChangeReason.disabled) {
      setState(() => pinned = next);
    }
  },
  child: DButton(label: const Text('Pin hint'),
    onPressed: () => setState(() => pinned = !pinned)),
)''',
      builder: (_) => const _Controlled(),
    ),
    StyleguideExample(
      title: 'Imperative and multiple triggers',
      description:
          'One borrowed controller selects either named trigger. Use the actions to open its second hint or close the active hint.',
      states: const ['Controller', 'Multiple triggers', 'Borrowed lifecycle'],
      code:
          '''final controller = DTooltipController(); // Dispose in State.dispose.
DTooltip(controller: controller, triggerId: 'first',
  message: 'First hint', child: firstButton);
DTooltip(controller: controller, triggerId: 'second',
  message: 'Second hint', child: secondButton);
controller.show(triggerId: 'second');
controller.hide();''',
      builder: (_) => const _Imperative(),
    ),
    StyleguideExample(
      title: 'Rich content and narrow boundaries',
      description:
          'Rich labels and keycaps wrap at large text sizes. Open this hint near the preview edge to exercise viewport constraints, arrow clamping and flipping.',
      states: const ['Rich content', 'Wrapping', 'Keycaps', 'Narrow viewport'],
      code: '''DTooltip(
  message: 'Save your current changes, then publish with Control plus Enter.',
  containsKeycaps: true,
  content: const Wrap(spacing: 6, runSpacing: 6, children: [
    Text('Save your current changes, then publish'),
    DKbdGroup(children: [DKbd('Ctrl'), DKbd('↵')]),
  ]),
  child: DButton(label: const Text('Publishing hint', maxLines: null),
    onPressed: inspect),
)''',
      builder: (_) => _Space(
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: DTooltip(
            message:
                'Save your current changes, then publish with Control plus Enter.',
            containsKeycaps: true,
            content: const Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Text('Save your current changes, then publish'),
                DKbdGroup(children: [DKbd('Ctrl'), DKbd('↵')]),
              ],
            ),
            child: DButton(
              label: const Text('Publishing hint', maxLines: null),
              onPressed: () {},
            ),
          ),
        ),
      ),
    ),
    StyleguideExample(
      title: 'Cursor tracking and disabled hints',
      description:
          'The first hint follows both pointer axes. The second tooltip is disabled while its button continues to work.',
      states: const ['Cursor tracking', 'Tooltip disabled', 'Enabled action'],
      code: '''DTooltip(message: 'Following the pointer',
  trackCursorAxis: DTooltipTrackCursor.both,
  child: DButton(label: const Text('Track cursor'), onPressed: inspect));
DTooltip(message: 'Hidden hint', disabled: true,
  child: DButton(label: const Text('Action works'), onPressed: inspect));''',
      builder: (_) => const _Tracking(),
    ),
  ],
);

class _Space extends StatelessWidget {
  const _Space({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 64),
    child: Center(child: child),
  );
}

class _Usage extends StatefulWidget {
  const _Usage();
  @override
  State<_Usage> createState() => _UsageState();
}

class _UsageState extends State<_Usage> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Space(
        child: DTooltip(
          message: 'Add to library',
          child: DButton(
            label: const Text('Hover'),
            onPressed: () => setState(() => count++),
          ),
        ),
      ),
      Text('Added: $count'),
    ],
  );
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

// The 16px Lucide Save artwork from the official keyboard-shortcut example.
// Copyright (c) 2026 Lucide Icons and Contributors, ISC license:
// docs/component-library/reference/LICENSE.tooltip-lucide.md.
const _saveSvg = '''<svg xmlns="http://www.w3.org/2000/svg"
  viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
  stroke-linecap="round" stroke-linejoin="round">
<path d="M15.2 3a2 2 0 0 1 1.4.6l3.8 3.8a2 2 0 0 1 .6 1.4V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z"/>
<path d="M17 21v-7a1 1 0 0 0-1-1H8a1 1 0 0 0-1 1v7"/>
<path d="M7 3v4a1 1 0 0 0 1 1h7"/>
</svg>''';

class _SaveIcon extends StatelessWidget {
  const _SaveIcon();

  @override
  Widget build(BuildContext context) => SvgPicture.string(
    _saveSvg,
    width: 16,
    height: 16,
    excludeFromSemantics: true,
    theme: SvgTheme(
      currentColor:
          IconTheme.of(context).color ?? DTokens.of(context).foreground,
    ),
  );
}

class _Keyboard extends StatefulWidget {
  const _Keyboard();
  @override
  State<_Keyboard> createState() => _KeyboardState();
}

class _KeyboardState extends State<_Keyboard> {
  int count = 0;
  void save() => setState(() => count++);
  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {SingleActivator(LogicalKeyboardKey.keyS): _SaveIntent()},
    child: Actions(
      actions: {
        _SaveIntent: CallbackAction<_SaveIntent>(
          onInvoke: (_) {
            save();
            return null;
          },
        ),
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Space(
            child: DTooltip(
              message: 'Save Changes',
              shortcut: const DShortcut(
                SingleActivator(LogicalKeyboardKey.keyS),
              ),
              child: DButton(
                semanticLabel: 'Save Changes',
                label: const _SaveIcon(),
                onPressed: save,
              ),
            ),
          ),
          Text('Saved: $count'),
        ],
      ),
    ),
  );
}

class _Controlled extends StatefulWidget {
  const _Controlled();
  @override
  State<_Controlled> createState() => _ControlledState();
}

class _ControlledState extends State<_Controlled> {
  bool pinned = false;
  bool present = true;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Space(
        child: present
            ? DTooltip(
                message:
                    'This pinned hint uses the current palette, font and text scale.',
                open: pinned,
                onOpenChange: (next, reason) {
                  if (reason == DTooltipChangeReason.escape ||
                      reason == DTooltipChangeReason.lifecycle ||
                      reason == DTooltipChangeReason.disabled) {
                    setState(() => pinned = next);
                  }
                },
                child: DButton(
                  label: const Text('Pin hint'),
                  onPressed: () => setState(() => pinned = !pinned),
                ),
              )
            : const Text('Trigger removed'),
      ),
      DButton(
        label: Text(present ? 'Remove trigger' : 'Restore trigger'),
        onPressed: () => setState(() {
          present = !present;
          pinned = false;
        }),
      ),
      Text('Pinned: $pinned'),
    ],
  );
}

class _Imperative extends StatefulWidget {
  const _Imperative();
  @override
  State<_Imperative> createState() => _ImperativeState();
}

class _ImperativeState extends State<_Imperative> {
  final controller = DTooltipController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Space(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in ['first', 'second'])
              DTooltip(
                controller: controller,
                triggerId: id,
                message: '$id hint',
                child: DButton(label: Text(id), onPressed: () {}),
              ),
          ],
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          DButton(
            label: const Text('Open second'),
            onPressed: () => controller.show(triggerId: 'second'),
          ),
          DButton(label: const Text('Close hint'), onPressed: controller.hide),
        ],
      ),
    ],
  );
}

class _Tracking extends StatefulWidget {
  const _Tracking();
  @override
  State<_Tracking> createState() => _TrackingState();
}

class _TrackingState extends State<_Tracking> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Space(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DTooltip(
              message: 'Following the pointer',
              trackCursorAxis: DTooltipTrackCursor.both,
              child: DButton(
                label: const Text('Track cursor'),
                onPressed: () => setState(() => count++),
              ),
            ),
            DTooltip(
              message: 'Hidden hint',
              disabled: true,
              child: DButton(
                label: const Text('Action works'),
                onPressed: () => setState(() => count++),
              ),
            ),
          ],
        ),
      ),
      Text('Actions: $count'),
    ],
  );
}
