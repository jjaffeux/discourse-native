import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../styleguide_example.dart';

final kbdExamples = ComponentExamples(
  description: 'Display the keys used in a keyboard shortcut.',
  status: ComponentStatus.implemented,
  notes:
      'DKbd displays a hint; existing controls and Shortcuts own actions. '
      'DKbdGroup wraps and inherits direction. Native labels use Apple modifier '
      'symbols on macOS and words on Linux. Shortcut hints are hidden on mobile; '
      'DKbd remains available for authored keyboard content. Spoken labels can be localized. '
      'Text uses the host sans-serif family with reference 12/16 metrics, grows '
      'with text scale, and uses live site tokens. Highlight feedback is '
      'optional and respects reduced motion. The reference className '
      'customization maps to Flutter child, style and layout composition. '
      'Outline is a Button variant, inline-end is the Button icon slot or an '
      'Input Group addon position, and tooltip/addon keycap colors and radius '
      'come from DKbdTheme, which DTooltip and DInputGroupAddon supply.',
  examples: [
    StyleguideExample(
      title: 'Keys, symbols and custom content',
      description:
          'The first two rows reproduce the reference key groups. '
          'Text and symbols receive spoken labels. Custom icon content requires '
          'a label. Keycaps never add a focus stop or a touch action. Highlight '
          'uses weight and underline as well as color.',
      states: const ['Default', 'Highlighted', 'Icons', 'Semantics'],
      code: _keysCode,
      builder: (_) => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DKbdGroup(children: [DKbd('⌘'), DKbd('⇧'), DKbd('⌥'), DKbd('⌃')]),
          SizedBox(height: DSpacing.lg),
          DKbdGroup(children: [DKbd('Ctrl'), Text('+'), DKbd('B')]),
          SizedBox(height: DSpacing.lg),
          DKbdGroup(
            children: [
              DKbd('Esc'),
              DKbd('↑'),
              DKbd('B', highlighted: true),
              DKbd.child(
                semanticLabel: 'Brightness up',
                child: Icon(Icons.brightness_high_outlined),
              ),
            ],
          ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'Groups, sequences and inline text',
      description:
          'The reference group sentence places a keycap group inside muted '
          'small text through a WidgetSpan. A labelled group speaks one chord; '
          'a formatted sequence is spoken and separated by “then”.',
      states: const ['Group', 'Inline', 'Labelled', 'Sequence'],
      code: _groupsCode,
      builder: (_) => const DProse(
        children: [
          DText.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Use '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: DKbdGroup(
                    children: [DKbd('Ctrl + B'), DKbd('Ctrl + K')],
                  ),
                ),
                TextSpan(text: ' to open the command palette'),
              ],
            ),
            variant: DTextVariant.muted,
          ),
          DKbdGroup(
            semanticLabel: 'Control + B',
            children: [DKbd('Ctrl'), Text('+'), DKbd('B')],
          ),
          DShortcutKeycaps(
            shortcut: DShortcut.sequence(
              SingleActivator(LogicalKeyboardKey.keyG),
              [SingleActivator(LogicalKeyboardKey.keyH)],
            ),
          ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'Platform modifiers and named keys',
      description:
          'The same logical activators are shown using macOS, iOS and Linux '
          'notation, then named keys keep their printed names. Formatting '
          'never changes the binding. These hints are static and add no '
          'keyboard focus stops.',
      states: const ['macOS', 'iOS', 'Linux', 'Named keys', 'Static hint'],
      code: _platformCode,
      builder: (_) => const _PlatformHints(),
    ),
    StyleguideExample(
      title: 'Buttons with trailing keycaps',
      description:
          'The reference small outline buttons place Enter and Escape keycaps '
          'in their inline-end icon slots, nudged 2px outward. Click either '
          'button, or focus it and press Enter; status changes through the '
          'button itself.',
      states: const [
        'Small',
        'Outline',
        'Inline-end keycaps',
        'Keyboard',
        'Touch',
      ],
      code: _buttonCode,
      builder: (_) => const KbdActionSample(),
    ),
    StyleguideExample(
      title: 'Tooltips inside a button group',
      description:
          'Two outline buttons in a Button Group carry keycap tooltips: a '
          'formatted shortcut and literal Ctrl/P content. Hover or long press '
          'a button, then change the preview theme while the tooltip is open '
          'to inspect the live keycap tint. With the group focused, S and '
          'Control+P run the actions.',
      states: const ['Button Group', 'Tooltip', 'Live theme', 'Keyboard'],
      code: _tooltipCode,
      builder: (_) => const KbdTooltipSample(),
    ),
    StyleguideExample(
      title: 'Input group with a trailing shortcut',
      description:
          'The reference search field keeps its search icon and two keycaps '
          'in an inline-end addon, bounded to 320px. Press Command+K on '
          'macOS/iOS or Control+K on Linux while the example has focus. Type '
          'a query, then change theme, text size or direction; the query and '
          'focus remain native.',
      states: const ['Input Group composition', 'Focus', 'State retention'],
      code: _inputCode,
      builder: (_) => const KbdInputSample(),
    ),
    StyleguideExample(
      title: 'RTL and a fixed LTR shortcut island',
      description:
          'The reference groups follow RTL reading order. The nested keyboard '
          'notation opts into LTR. Arrow keys describe physical directions and '
          'are never mirrored. Arabic key labels retain their text direction.',
      states: const ['RTL', 'Nested direction', 'Spoken labels'],
      code: _rtlCode,
      builder: (_) => const DDirection(
        textDirection: TextDirection.rtl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DKbdGroup(children: [DKbd('⌘'), DKbd('⇧'), DKbd('⌥'), DKbd('⌃')]),
            SizedBox(height: DSpacing.lg),
            DKbdGroup(children: [DKbd('Ctrl'), Text('+'), DKbd('B')]),
            SizedBox(height: DSpacing.lg),
            DKbdGroup(children: [DKbd('تحكم'), DKbd('ب')]),
            SizedBox(height: DSpacing.lg),
            DKbdGroup(
              textDirection: TextDirection.ltr,
              semanticLabel: 'Control + Arrow Left',
              children: [DKbd('Ctrl'), Text('+'), DKbd('←')],
            ),
          ],
        ),
      ),
    ),
    StyleguideExample(
      title: 'Narrow layouts and large text',
      description:
          'Set 360 px and 200% text. Long labels grow vertically and groups '
          'wrap without ellipsis or scaling text down. The empty group has '
          'no height. Static hints add no keyboard listeners.',
      states: const ['Wrap', '200% text', 'Long labels', 'Empty'],
      code: _narrowCode,
      builder: (_) => const DProse(
        children: [
          DKbdGroup(
            children: [
              DKbd('Control + Backspace'),
              DKbd('Page Down'),
              DKbd('KeyboardLanguageSwitch'),
            ],
          ),
          DShortcutKeycaps(
            listenToKeyboard: false,
            shortcut: DShortcut(
              SingleActivator(
                LogicalKeyboardKey.delete,
                control: true,
                alt: true,
                shift: true,
                meta: true,
              ),
            ),
          ),
          DKbdGroup(children: []),
        ],
      ),
    ),
  ],
);

class _PlatformHints extends StatelessWidget {
  const _PlatformHints();

  @override
  Widget build(BuildContext context) => DProse(
    children: [
      for (final platform in const [
        TargetPlatform.macOS,
        TargetPlatform.iOS,
        TargetPlatform.linux,
      ])
        Wrap(
          spacing: DSpacing.sm,
          runSpacing: DSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DText(platform.name, variant: DTextVariant.small),
            const DShortcutKeycaps(
              listenToKeyboard: false,
              shortcut: DShortcut(
                SingleActivator(
                  LogicalKeyboardKey.arrowLeft,
                  control: true,
                  alt: true,
                  shift: true,
                  meta: true,
                ),
              ),
            ),
          ],
        ),
      const Wrap(
        spacing: DSpacing.sm,
        runSpacing: DSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DText('named keys', variant: DTextVariant.small),
          DShortcutKeycaps(
            listenToKeyboard: false,
            shortcut: DShortcut.sequence(
              SingleActivator(LogicalKeyboardKey.pageDown, control: true),
              [SingleActivator(LogicalKeyboardKey.home)],
            ),
          ),
        ],
      ),
    ],
  );
}

class KbdActionSample extends StatefulWidget {
  const KbdActionSample({super.key});

  @override
  State<KbdActionSample> createState() => _KbdActionSampleState();
}

class _KbdActionSampleState extends State<KbdActionSample> {
  String _status = 'No action yet.';

  void _accept() => setState(() => _status = 'Accepted.');

  void _cancel() => setState(() => _status = 'Cancelled.');

  @override
  Widget build(BuildContext context) {
    // The reference nudges the keycap 2px toward the inline end.
    final nudge = Directionality.of(context) == TextDirection.rtl ? -2.0 : 2.0;
    return DProse(
      children: [
        Wrap(
          spacing: DSpacing.lg,
          runSpacing: DSpacing.lg,
          children: [
            DButton(
              variant: DButtonVariant.outline,
              size: DButtonSize.small,
              label: const Text('Accept'),
              icon: DControlStyle.isTouch(context)
                  ? null
                  : Transform.translate(
                      offset: Offset(nudge, 0),
                      child: const DKbd('⏎'),
                    ),
              iconPosition: DButtonIconPosition.end,
              semanticLabel: DControlStyle.isTouch(context)
                  ? 'Accept'
                  : 'Accept, Enter',
              onPressed: _accept,
            ),
            DButton(
              variant: DButtonVariant.outline,
              size: DButtonSize.small,
              label: const Text('Cancel'),
              icon: DControlStyle.isTouch(context)
                  ? null
                  : Transform.translate(
                      offset: Offset(nudge, 0),
                      child: const DKbd('Esc'),
                    ),
              iconPosition: DButtonIconPosition.end,
              semanticLabel: DControlStyle.isTouch(context)
                  ? 'Cancel'
                  : 'Cancel, Escape',
              onPressed: _cancel,
            ),
          ],
        ),
        Semantics(liveRegion: true, child: DText(_status)),
      ],
    );
  }
}

class KbdTooltipSample extends StatefulWidget {
  const KbdTooltipSample({super.key});

  @override
  State<KbdTooltipSample> createState() => _KbdTooltipSampleState();
}

class _KbdTooltipSampleState extends State<KbdTooltipSample> {
  static const save = SingleActivator(LogicalKeyboardKey.keyS);
  static const print = SingleActivator(LogicalKeyboardKey.keyP, control: true);
  String _status = 'No action yet.';

  void _save() => setState(() => _status = 'Saved changes.');

  void _print() => setState(() => _status = 'Printed document.');

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {save: _save, print: _print},
    child: Focus(
      autofocus: true,
      child: DProse(
        children: [
          // The reference group never wraps; narrow previews scroll it.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DButtonGroup(
              semanticLabel: 'Document actions',
              children: [
                DButton(
                  variant: DButtonVariant.outline,
                  label: const Text('Save'),
                  tooltip: 'Save Changes',
                  shortcut: const DShortcut(save),
                  onPressed: _save,
                ),
                DTooltip(
                  message: 'Print Document, Control + P',

                  content: const Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Print Document'),
                      DKbdGroup(children: [DKbd('Ctrl'), DKbd('P')]),
                    ],
                  ),
                  child: DButton(
                    variant: DButtonVariant.outline,
                    label: const Text('Print'),
                    onPressed: _print,
                  ),
                ),
              ],
            ),
          ),
          Semantics(liveRegion: true, child: DText(_status)),
        ],
      ),
    ),
  );
}

class KbdInputSample extends StatefulWidget {
  const KbdInputSample({super.key});

  @override
  State<KbdInputSample> createState() => _KbdInputSampleState();
}

class _KbdInputSampleState extends State<KbdInputSample> {
  final _focus = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final apple =
        platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;
    final shortcut = SingleActivator(
      LogicalKeyboardKey.keyK,
      meta: apple,
      control: !apple,
    );
    return CallbackShortcuts(
      bindings: {shortcut: _focus.requestFocus},
      child: Focus(
        autofocus: true,
        child: DProse(
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: DInputGroup(
                  children: [
                    DInputGroupInput(
                      hintText: 'Search...',
                      semanticLabel: 'Search',
                      focusNode: _focus,
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const DInputGroupAddon(child: Icon(Icons.search)),
                    if (!DControlStyle.isTouch(context))
                      DInputGroupAddon(
                        alignment: DInputGroupAddonAlignment.inlineEnd,
                        child: DShortcutKeycaps(shortcut: DShortcut(shortcut)),
                      ),
                  ],
                ),
              ),
            ),
            DText(_query.isEmpty ? 'No query yet.' : 'Query: $_query'),
          ],
        ),
      ),
    );
  }
}

const _keysCode = '''const Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    DKbdGroup(children: [DKbd('⌘'), DKbd('⇧'), DKbd('⌥'), DKbd('⌃')]),
    SizedBox(height: DSpacing.lg),
    DKbdGroup(children: [DKbd('Ctrl'), Text('+'), DKbd('B')]),
    SizedBox(height: DSpacing.lg),
    DKbdGroup(children: [
      DKbd('Esc'), DKbd('↑'), DKbd('B', highlighted: true),
      DKbd.child(semanticLabel: 'Brightness up',
        child: Icon(Icons.brightness_high_outlined)),
    ]),
  ],
)''';

const _groupsCode = '''const DProse(children: [
  DText.rich(TextSpan(children: [
    TextSpan(text: 'Use '),
    WidgetSpan(alignment: PlaceholderAlignment.middle,
      child: DKbdGroup(children: [DKbd('Ctrl + B'), DKbd('Ctrl + K')])),
    TextSpan(text: ' to open the command palette'),
  ]), variant: DTextVariant.muted),
  DKbdGroup(semanticLabel: 'Control + B',
    children: [DKbd('Ctrl'), Text('+'), DKbd('B')]),
  DShortcutKeycaps(shortcut: DShortcut.sequence(
    SingleActivator(LogicalKeyboardKey.keyG),
    [SingleActivator(LogicalKeyboardKey.keyH)],
  )),
])''';

const _platformCode =
    "DProse(children: [\n  for (final platform in const [TargetPlatform.macOS, TargetPlatform.iOS, TargetPlatform.linux])\n    Wrap(spacing: DSpacing.sm, runSpacing: DSpacing.sm,\n      crossAxisAlignment: WrapCrossAlignment.center,\n      children: [\n        DText(platform.name, variant: DTextVariant.small),\n        DShortcutKeycaps( listenToKeyboard: false,\n          shortcut: const DShortcut(SingleActivator(LogicalKeyboardKey.arrowLeft,\n            control: true, alt: true, shift: true, meta: true))),\n      ],\n    ),\n  const Wrap(spacing: DSpacing.sm, runSpacing: DSpacing.sm,\n    crossAxisAlignment: WrapCrossAlignment.center,\n    children: [\n      DText('named keys', variant: DTextVariant.small),\n      DShortcutKeycaps( listenToKeyboard: false,\n        shortcut: DShortcut.sequence(\n          SingleActivator(LogicalKeyboardKey.pageDown, control: true),\n          [SingleActivator(LogicalKeyboardKey.home)])),\n    ],\n  ),\n])";

const _rtlCode = '''const DDirection(textDirection: TextDirection.rtl,
  child: Column(mainAxisSize: MainAxisSize.min, children: [
    DKbdGroup(children: [DKbd('⌘'), DKbd('⇧'), DKbd('⌥'), DKbd('⌃')]),
    SizedBox(height: DSpacing.lg),
    DKbdGroup(children: [DKbd('Ctrl'), Text('+'), DKbd('B')]),
    SizedBox(height: DSpacing.lg),
    DKbdGroup(children: [DKbd('تحكم'), DKbd('ب')]),
    SizedBox(height: DSpacing.lg),
    DKbdGroup(textDirection: TextDirection.ltr,
      semanticLabel: 'Control + Arrow Left',
      children: [DKbd('Ctrl'), Text('+'), DKbd('←')]),
  ]),
)''';

const _narrowCode =
    "const DProse(children: [\n  DKbdGroup(children: [DKbd('Control + Backspace'), DKbd('Page Down'),\n    DKbd('KeyboardLanguageSwitch')]),\n  DShortcutKeycaps( listenToKeyboard: false,\n    shortcut: DShortcut(SingleActivator(LogicalKeyboardKey.delete,\n      control: true, alt: true, shift: true, meta: true))),\n  DKbdGroup(children: []),\n])";

// The three stateful usage snippets contain the complete samples below.
const _buttonCode = r'''class KbdActionSample extends StatefulWidget {
  const KbdActionSample({super.key});

  @override
  State<KbdActionSample> createState() => _KbdActionSampleState();
}

class _KbdActionSampleState extends State<KbdActionSample> {
  String _status = 'No action yet.';

  void _accept() => setState(() => _status = 'Accepted.');

  void _cancel() => setState(() => _status = 'Cancelled.');

  @override
  Widget build(BuildContext context) {
    // The reference nudges the keycap 2px toward the inline end.
    final nudge = Directionality.of(context) == TextDirection.rtl ? -2.0 : 2.0;
    return DProse(
      children: [
        Wrap(
          spacing: DSpacing.lg,
          runSpacing: DSpacing.lg,
          children: [
            DButton(
              variant: DButtonVariant.outline,
              size: DButtonSize.small,
              label: const Text('Accept'),
              icon: DControlStyle.isTouch(context) ? null : Transform.translate(
                offset: Offset(nudge, 0),
                child: const DKbd('⏎'),
              ),
              iconPosition: DButtonIconPosition.end,
              semanticLabel: DControlStyle.isTouch(context) ? 'Accept' : 'Accept, Enter',
              onPressed: _accept,
            ),
            DButton(
              variant: DButtonVariant.outline,
              size: DButtonSize.small,
              label: const Text('Cancel'),
              icon: DControlStyle.isTouch(context) ? null : Transform.translate(
                offset: Offset(nudge, 0),
                child: const DKbd('Esc'),
              ),
              iconPosition: DButtonIconPosition.end,
              semanticLabel: DControlStyle.isTouch(context) ? 'Cancel' : 'Cancel, Escape',
              onPressed: _cancel,
            ),
          ],
        ),
        Semantics(liveRegion: true, child: DText(_status)),
      ],
    );
  }
}''';

const _tooltipCode =
    "class KbdTooltipSample extends StatefulWidget {\n  const KbdTooltipSample({super.key});\n\n  @override\n  State<KbdTooltipSample> createState() => _KbdTooltipSampleState();\n}\n\nclass _KbdTooltipSampleState extends State<KbdTooltipSample> {\n  static const save = SingleActivator(LogicalKeyboardKey.keyS);\n  static const print = SingleActivator(LogicalKeyboardKey.keyP, control: true);\n  String _status = 'No action yet.';\n\n  void _save() => setState(() => _status = 'Saved changes.');\n\n  void _print() => setState(() => _status = 'Printed document.');\n\n  @override\n  Widget build(BuildContext context) => CallbackShortcuts(\n    bindings: {save: _save, print: _print},\n    child: Focus(\n      autofocus: true,\n      child: DProse(\n        children: [\n          // The reference group never wraps; narrow previews scroll it.\n          SingleChildScrollView(\n            scrollDirection: Axis.horizontal,\n            child: DButtonGroup(\n              semanticLabel: 'Document actions',\n              children: [\n                DButton(\n                  variant: DButtonVariant.outline,\n                  label: const Text('Save'),\n                  tooltip: 'Save Changes',\n                  shortcut: const DShortcut(save),\n                  onPressed: _save,\n                ),\n                DTooltip(\n                  message: 'Print Document, Control + P',\n                  \n                  content: const Wrap(\n                    spacing: 6,\n                    runSpacing: 6,\n                    crossAxisAlignment: WrapCrossAlignment.center,\n                    children: [\n                      Text('Print Document'),\n                      DKbdGroup(children: [DKbd('Ctrl'), DKbd('P')]),\n                    ],\n                  ),\n                  child: DButton(\n                    variant: DButtonVariant.outline,\n                    label: const Text('Print'),\n                    onPressed: _print,\n                  ),\n                ),\n              ],\n            ),\n          ),\n          Semantics(liveRegion: true, child: DText(_status)),\n        ],\n      ),\n    ),\n  );\n}";

const _inputCode =
    "class KbdInputSample extends StatefulWidget {\n  const KbdInputSample({super.key});\n\n  @override\n  State<KbdInputSample> createState() => _KbdInputSampleState();\n}\n\nclass _KbdInputSampleState extends State<KbdInputSample> {\n  final _focus = FocusNode();\n  String _query = '';\n\n  @override\n  void dispose() {\n    _focus.dispose();\n    super.dispose();\n  }\n\n  @override\n  Widget build(BuildContext context) {\n    final platform = Theme.of(context).platform;\n    final apple = platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;\n    final shortcut = SingleActivator(\n      LogicalKeyboardKey.keyK,\n      meta: apple,\n      control: !apple,\n    );\n    return CallbackShortcuts(\n      bindings: {shortcut: _focus.requestFocus},\n      child: Focus(\n        autofocus: true,\n        child: DProse(\n          children: [\n            Align(\n              alignment: AlignmentDirectional.centerStart,\n              child: ConstrainedBox(\n                constraints: const BoxConstraints(maxWidth: 320),\n                child: DInputGroup(\n                  children: [\n                    DInputGroupInput(\n                      hintText: 'Search...',\n                      semanticLabel: 'Search',\n                      focusNode: _focus,\n                      onChanged: (value) => setState(() => _query = value),\n                    ),\n                    const DInputGroupAddon(child: Icon(Icons.search)),\n                    if (!DControlStyle.isTouch(context)) DInputGroupAddon(\n                      alignment: DInputGroupAddonAlignment.inlineEnd,\n                      \n                    ),\n                  ],\n                ),\n              ),\n            ),\n            DText(_query.isEmpty ? 'No query yet.' : 'Query: \$_query'),\n          ],\n        ),\n      ),\n    );\n  }\n}";
