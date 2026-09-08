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
      'Text uses the host sans-serif family with reference 12/16 metrics, grows with text scale, '
      'and uses live site tokens. Highlight feedback is optional and respects '
      'reduced motion. The reference className customization maps to Flutter '
      'child, style and layout composition. Outline is a Button demo variant '
      'and inline-end is an Input Group addon position, not Kbd props. '
      'Button, Tooltip and Input Group remain separate catalogue tasks; these '
      'examples compose the available DButton/DTooltip and native TextField.',
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
          'Group arbitrary keycaps with separators, or format existing logical '
          'activators. Sequence steps are spoken and separated by “then”. '
          'The inline example uses a WidgetSpan in the public typography widget.',
      states: const ['Group', 'Sequence', 'Inline'],
      code: _groupsCode,
      builder: (_) => const DProse(
        children: [
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
          DText.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Press '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: DKbd('Esc'),
                ),
                TextSpan(text: ' to dismiss a menu.'),
              ],
            ),
          ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'Platform modifiers and named keys',
      description:
          'The same logical activators are shown using macOS, iOS and Linux '
          'notation. Formatting never changes the binding. These hints are '
          'static and add no keyboard focus stops.',
      states: const ['macOS', 'iOS', 'Linux', 'Static hint'],
      code: _platformCode,
      builder: (_) => const _PlatformHints(),
    ),
    StyleguideExample(
      title: 'Button and live tooltip composition',
      description:
          'Click Accept, focus it and press Enter, or press F6 in this preview. '
          'The count changes through the existing button/shortcut owners. '
          'Hover or long press Inspect hint; change the preview theme while '
          'the tooltip is open to inspect live keycaps.',
      states: const ['Button', 'Tooltip', 'Keyboard', 'Touch', 'Live theme'],
      code: _actionCode,
      builder: (_) => const KbdActionSample(),
    ),
    StyleguideExample(
      title: 'Search input with a trailing shortcut',
      description:
          'Click Focus search or press Command+K on macOS/iOS, Control+K on '
          'Linux. Type a query, then change theme, text size or direction; the '
          'query and focus remain native. The trailing hint wraps if necessary.',
      states: const ['Input Group composition', 'Focus', 'State retention'],
      code: _inputCode,
      builder: (_) => const KbdInputSample(),
    ),
    StyleguideExample(
      title: 'RTL and a fixed LTR shortcut island',
      description:
          'The first group follows RTL reading order. The nested keyboard '
          'notation opts into LTR. Arrow keys describe physical directions and '
          'are never mirrored. Arabic key labels retain their text direction.',
      states: const ['RTL', 'Nested direction', 'Spoken labels'],
      code: _rtlCode,
      builder: (_) => const DDirection(
        textDirection: TextDirection.rtl,
        child: DProse(
          children: [
            DText('اختصارات لوحة المفاتيح', variant: DTextVariant.h4),
            DKbdGroup(children: [DKbd('تحكم'), DKbd('ب')]),
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
    ],
  );
}

class KbdActionSample extends StatefulWidget {
  const KbdActionSample({super.key});

  @override
  State<KbdActionSample> createState() => _KbdActionSampleState();
}

class _KbdActionSampleState extends State<KbdActionSample> {
  static const shortcut = SingleActivator(LogicalKeyboardKey.f6);
  int _accepted = 0;

  void _accept() => setState(() => _accepted++);

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {shortcut: _accept},
    child: Focus(
      autofocus: true,
      child: DProse(
        children: [
          Wrap(
            spacing: DSpacing.lg,
            runSpacing: DSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DButton(
                variant: DButtonVariant.standard,
                onPressed: _accept,
                label: const DKbdGroup(
                  spacing: DSpacing.sm,
                  children: [Text('Accept'), DKbd('F6')],
                ),
              ),
              const DTooltip(
                message: 'Accept invitation',
                shortcut: DShortcut(shortcut),
                child: Padding(
                  padding: EdgeInsets.all(DSpacing.md),
                  child: Text('Inspect hint'),
                ),
              ),
            ],
          ),
          Semantics(liveRegion: true, child: DText('Accepted: $_accepted')),
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
      child: DProse(
        children: [
          TextField(
            focusNode: _focus,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              labelText: 'Search community',
              border: const OutlineInputBorder(),
              suffixIconConstraints: const BoxConstraints(maxWidth: 120),
              suffixIcon: Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: DSpacing.xs,
                  end: DSpacing.sm,
                ),
                child: DShortcutKeycaps(shortcut: DShortcut(shortcut)),
              ),
            ),
          ),
          DButton(
            onPressed: _focus.requestFocus,
            label: const Text('Focus search'),
          ),
          DText(_query.isEmpty ? 'No query yet.' : 'Query: $_query'),
        ],
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
  DKbdGroup(semanticLabel: 'Control + B',
    children: [DKbd('Ctrl'), Text('+'), DKbd('B')]),
  DShortcutKeycaps(shortcut: DShortcut.sequence(
    SingleActivator(LogicalKeyboardKey.keyG),
    [SingleActivator(LogicalKeyboardKey.keyH)],
  )),
  DText.rich(TextSpan(children: [
    TextSpan(text: 'Press '),
    WidgetSpan(alignment: PlaceholderAlignment.middle, child: DKbd('Esc')),
    TextSpan(text: ' to dismiss a menu.'),
  ])),
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
])''';

const _rtlCode = '''const DDirection(textDirection: TextDirection.rtl,
  child: DProse(children: [
    DText('اختصارات لوحة المفاتيح', variant: DTextVariant.h4),
    DKbdGroup(children: [DKbd('تحكم'), DKbd('ب')]),
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

// The two stateful usage snippets contain the complete samples below.
const _actionCode = r'''class KbdActionSample extends StatefulWidget {
  const KbdActionSample({super.key});

  @override
  State<KbdActionSample> createState() => _KbdActionSampleState();
}

class _KbdActionSampleState extends State<KbdActionSample> {
  static const shortcut = SingleActivator(LogicalKeyboardKey.f6);
  int _accepted = 0;

  void _accept() => setState(() => _accepted++);

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {shortcut: _accept},
    child: Focus(
      autofocus: true,
      child: DProse(
        children: [
          Wrap(
            spacing: DSpacing.lg,
            runSpacing: DSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DButton(
                variant: DButtonVariant.standard,
                onPressed: _accept,
                label: const DKbdGroup(
                  spacing: DSpacing.sm,
                  children: [Text('Accept'), DKbd('F6')],
                ),
              ),
              const DTooltip(
                message: 'Accept invitation',
                shortcut: DShortcut(shortcut),
                child: Padding(
                  padding: EdgeInsets.all(DSpacing.md),
                  child: Text('Inspect hint'),
                ),
              ),
            ],
          ),
          Semantics(liveRegion: true, child: DText('Accepted: $_accepted')),
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
      child: DProse(
        children: [
          TextField(
            focusNode: _focus,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              labelText: 'Search community',
              border: const OutlineInputBorder(),
              suffixIconConstraints: const BoxConstraints(maxWidth: 120),
              suffixIcon: Padding(
                padding: const EdgeInsetsDirectional.only(start: DSpacing.xs, end: DSpacing.sm),
                child: DShortcutKeycaps(shortcut: DShortcut(shortcut)),
              ),
            ),
          ),
          DButton(
            onPressed: _focus.requestFocus,
            label: const Text('Focus search'),
          ),
          DText(_query.isEmpty ? 'No query yet.' : 'Query: $_query'),
        ],
      ),
    );
  }
}''';
