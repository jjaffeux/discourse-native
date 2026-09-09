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
      'symbols on macOS/iOS and words on Linux. Spoken labels can be localized. '
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
      title: 'Button with a trailing keycap',
      description:
          'The reference outline button places the Enter keycap in its '
          'inline-end icon slot, nudged 2px outward. Click Accept, or focus it '
          'and press Enter; the count changes through the button itself.',
      states: const ['Outline', 'Inline-end keycap', 'Keyboard', 'Touch'],
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
            platform: TargetPlatform.linux,
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
            DShortcutKeycaps(
              platform: platform,
              listenToKeyboard: false,
              shortcut: const DShortcut(
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
            platform: TargetPlatform.linux,
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
  int _accepted = 0;

  void _accept() => setState(() => _accepted++);

  @override
  Widget build(BuildContext context) {
    // The reference nudges the keycap 2px toward the inline end.
    final nudge = Directionality.of(context) == TextDirection.rtl ? -2.0 : 2.0;
    return DProse(
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DButton(
            variant: DButtonVariant.outline,
            label: const Text('Accept'),
            icon: Transform.translate(
              offset: Offset(nudge, 0),
              child: const DKbd('⏎'),
            ),
            iconPosition: DButtonIconPosition.end,
            semanticLabel: 'Accept, Enter',
            onPressed: _accept,
          ),
        ),
        Semantics(liveRegion: true, child: DText('Accepted: $_accepted')),
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
                  containsKeycaps: true,
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
                    DInputGroupAddon(
                      alignment: DInputGroupAddonAlignment.inlineEnd,
                      children: [DKbd(apple ? '⌘' : 'Ctrl'), const DKbd('K')],
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

const _platformCode = '''DProse(children: [
  for (final platform in const [TargetPlatform.macOS, TargetPlatform.iOS, TargetPlatform.linux])
    Wrap(spacing: DSpacing.sm, runSpacing: DSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DText(platform.name, variant: DTextVariant.small),
        DShortcutKeycaps(platform: platform, listenToKeyboard: false,
          shortcut: const DShortcut(SingleActivator(LogicalKeyboardKey.arrowLeft,
            control: true, alt: true, shift: true, meta: true))),
      ],
    ),
  const Wrap(spacing: DSpacing.sm, runSpacing: DSpacing.sm,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      DText('named keys', variant: DTextVariant.small),
      DShortcutKeycaps(platform: TargetPlatform.linux, listenToKeyboard: false,
        shortcut: DShortcut.sequence(
          SingleActivator(LogicalKeyboardKey.pageDown, control: true),
          [SingleActivator(LogicalKeyboardKey.home)])),
    ],
  ),
])''';

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

const _narrowCode = '''const DProse(children: [
  DKbdGroup(children: [DKbd('Control + Backspace'), DKbd('Page Down'),
    DKbd('KeyboardLanguageSwitch')]),
  DShortcutKeycaps(platform: TargetPlatform.linux, listenToKeyboard: false,
    shortcut: DShortcut(SingleActivator(LogicalKeyboardKey.delete,
      control: true, alt: true, shift: true, meta: true))),
  DKbdGroup(children: []),
])''';

// The three stateful usage snippets contain the complete samples below.
const _buttonCode = r'''class KbdActionSample extends StatefulWidget {
  const KbdActionSample({super.key});

  @override
  State<KbdActionSample> createState() => _KbdActionSampleState();
}

class _KbdActionSampleState extends State<KbdActionSample> {
  int _accepted = 0;

  void _accept() => setState(() => _accepted++);

  @override
  Widget build(BuildContext context) {
    // The reference nudges the keycap 2px toward the inline end.
    final nudge = Directionality.of(context) == TextDirection.rtl ? -2.0 : 2.0;
    return DProse(
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DButton(
            variant: DButtonVariant.outline,
            label: const Text('Accept'),
            icon: Transform.translate(
              offset: Offset(nudge, 0),
              child: const DKbd('⏎'),
            ),
            iconPosition: DButtonIconPosition.end,
            semanticLabel: 'Accept, Enter',
            onPressed: _accept,
          ),
        ),
        Semantics(liveRegion: true, child: DText('Accepted: $_accepted')),
      ],
    );
  }
}''';

const _tooltipCode = r'''class KbdTooltipSample extends StatefulWidget {
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
                  containsKeycaps: true,
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
}''';

const _inputCode = r'''class KbdInputSample extends StatefulWidget {
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
    final apple = platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;
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
                    DInputGroupAddon(
                      alignment: DInputGroupAddonAlignment.inlineEnd,
                      children: [DKbd(apple ? '⌘' : 'Ctrl'), const DKbd('K')],
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
}''';
