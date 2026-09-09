import 'package:flutter/material.dart';

import '../../../discourse_ui.dart';
import '../styleguide_example.dart';

final directionExamples = ComponentExamples(
  description:
      'Set the reading direction for a component or part of your interface.',
  status: ComponentStatus.implemented,
  notes:
      'Import discourse_ui.dart; no additional dependency is needed. '
      'DDirection uses Flutter Directionality for both native controls and '
      'DDirection.of(context), the useDirection equivalent. A null textDirection '
      'inherits the host locale; an explicit value overrides only its subtree. '
      'of requires an ancestor; maybeOf returns null without one. '
      'Direction changes preserve state and focus. Themes, text scale and motion '
      'remain owned by the host. Use directional padding/alignment; text is not '
      'translated and physical geometry or arbitrary icons are not mirrored. '
      'Put the scope above a Navigator for its routes, or use an OverlayPortal '
      'consumer such as DDropdownMenu for a local live overlay.',
  examples: [
    StyleguideExample(
      title: 'Live direction and editing',
      description:
          'Edit and save a name, then switch Inherit / LTR / RTL. Inherit follows '
          'the preview Right to left control. Tab between the actions and use '
          'Enter or Space to activate them. The draft, saved value and native '
          'focus survive direction and theme changes.',
      states: const ['Inherited', 'LTR', 'RTL', 'Keyboard', 'Live changes'],
      code: '''// In a State: TextDirection? direction; null means inherit.
Column(
  children: [
    Wrap(
      spacing: DSpacing.sm,
      children: [
        for (final value in [null, TextDirection.ltr, TextDirection.rtl])
          ChoiceChip(
            label: Text(value?.name.toUpperCase() ?? 'Inherit'),
            selected: direction == value,
            onSelected: (_) => setState(() => direction = value),
          ),
      ],
    ),
    // Keep the editor mounted when the selected direction changes.
    DDirection(
      textDirection: direction,
      child: Builder(builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current direction: \${DDirection.of(context).name.toUpperCase()}'),
          const TextField(decoration: InputDecoration(labelText: 'Display name')),
        ],
      )),
    ),
  ],
)''',
      builder: (_) => const _LiveDirectionPreview(),
    ),
    StyleguideExample(
      title: 'Nested overrides and fixed content',
      description:
          'An RTL section contains an LTR URL island. Its inner inherited scope '
          'reads LTR; a sibling resumes RTL. Changing the preview direction does '
          'not override these explicit boundaries.',
      states: const ['Nested', 'Nearest lookup', 'Fixed LTR content'],
      code: '''DDirection(
  textDirection: TextDirection.rtl,
  child: Column(children: [
    const Text('مرحبًا بك'),
    DDirection(
      textDirection: TextDirection.ltr,
      child: Column(children: [
        const SelectableText('https://example.com/topics/42'),
        DDirection(child: Builder(builder: (context) =>
          Text('Inherited: \${DDirection.of(context).name}'),
        )),
      ]),
    ),
    const Text('العودة إلى القسم'),
  ]),
)''',
      builder: (_) => const _NestedDirectionPreview(),
    ),
    StyleguideExample(
      title: 'Inherited direction in a dropdown menu',
      description:
          'The menu inherits preview direction and theme, including host '
          'updates while open. Arrow keys navigate; '
          'Enter selects; Escape or an outside click dismisses. DDropdownMenu owns '
          'positioning, scrolling, dismissal and focus restoration.',
      states: const ['Live overlay', 'Keyboard', 'Theme changes'],
      code: '''// Own menuFocus = FocusNode() in State and dispose it there.
DDirection(
  child: DDropdownMenu(
    content: DDropdownMenuContent(children: [
      Builder(builder: (context) => DDropdownMenuItem(
        onPressed: select,
        child: Text(
          'Menu direction: \${DDirection.of(context).name.toUpperCase()}',
        ),
      )),
    ]),
    child: DDropdownMenuTrigger(
      focusNode: menuFocus,
      builder: (context, menu) => DButton(
        focusNode: menu.focusNode,
        label: const Text('Open direction menu'),
        variant: DButtonVariant.outline,
        hasPopup: true,
        expanded: menu.open,
        onPressed: menu.toggle,
      ),
    ),
  ),
)''',
      builder: (_) => const _DirectionMenuPreview(),
    ),
  ],
);

class _LiveDirectionPreview extends StatefulWidget {
  const _LiveDirectionPreview();

  @override
  State<_LiveDirectionPreview> createState() => _LiveDirectionPreviewState();
}

class _LiveDirectionPreviewState extends State<_LiveDirectionPreview> {
  TextDirection? _direction;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: DSpacing.sm,
        runSpacing: DSpacing.xs,
        children: [
          for (final direction in [null, TextDirection.ltr, TextDirection.rtl])
            ChoiceChip(
              label: Text(direction?.name.toUpperCase() ?? 'Inherit'),
              selected: _direction == direction,
              onSelected: (_) => setState(() => _direction = direction),
            ),
        ],
      ),
      const SizedBox(height: DSpacing.md),
      DDirection(textDirection: _direction, child: const _DirectionEditor()),
    ],
  );
}

class _DirectionEditor extends StatefulWidget {
  const _DirectionEditor();

  @override
  State<_DirectionEditor> createState() => _DirectionEditorState();
}

class _DirectionEditorState extends State<_DirectionEditor> {
  final _name = TextEditingController(text: 'Ada');
  String? _saved;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _DirectionSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _DirectionReadout(label: 'Current direction'),
        const SizedBox(height: DSpacing.md),
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: 'Display name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: DSpacing.md),
        Wrap(
          spacing: DSpacing.sm,
          runSpacing: DSpacing.sm,
          children: [
            DButton(
              label: const Text('Save locally'),
              variant: DButtonVariant.primary,
              onPressed: () => setState(() => _saved = _name.text),
            ),
            DButton(
              label: const Text('Clear'),
              onPressed: () => setState(() {
                _name.clear();
                _saved = null;
              }),
            ),
          ],
        ),
        const SizedBox(height: DSpacing.sm),
        Semantics(
          liveRegion: true,
          child: Text(_saved == null ? 'No saved name' : 'Saved: $_saved'),
        ),
      ],
    ),
  );
}

class _NestedDirectionPreview extends StatelessWidget {
  const _NestedDirectionPreview();

  @override
  Widget build(BuildContext context) => const DDirection(
    textDirection: TextDirection.rtl,
    child: _DirectionSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DirectionReadout(label: 'Outer section'),
          Text('مرحبًا بك'),
          SizedBox(height: DSpacing.md),
          DDirection(
            textDirection: TextDirection.ltr,
            child: _DirectionSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DirectionReadout(label: 'URL island'),
                  SelectableText('https://example.com/topics/42'),
                  SizedBox(height: DSpacing.sm),
                  DDirection(
                    child: _DirectionReadout(label: 'Inherited island'),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: DSpacing.md),
          _DirectionReadout(label: 'Outer sibling'),
        ],
      ),
    ),
  );
}

class _DirectionMenuPreview extends StatefulWidget {
  const _DirectionMenuPreview();

  @override
  State<_DirectionMenuPreview> createState() => _DirectionMenuPreviewState();
}

class _DirectionMenuPreviewState extends State<_DirectionMenuPreview> {
  final _focusNode = FocusNode(debugLabel: 'Direction menu trigger');
  String _selection = 'No selection';

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DDirection(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _DirectionReadout(label: 'Inherited direction'),
        const SizedBox(height: DSpacing.md),
        DDropdownMenu(
          content: DDropdownMenuContent(
            semanticLabel: 'Direction menu',
            children: [
              Builder(
                builder: (context) {
                  final direction = DDirection.of(context).name.toUpperCase();
                  return DDropdownMenuItem(
                    onPressed: () => setState(() => _selection = direction),
                    child: Text('Menu direction: $direction'),
                  );
                },
              ),
              DDropdownMenuItem(
                onPressed: () => setState(() => _selection = 'Second action'),
                child: const Text('Second action'),
              ),
            ],
          ),
          child: DDropdownMenuTrigger(
            focusNode: _focusNode,
            builder: (context, menu) => DButton(
              focusNode: menu.focusNode,
              label: const Text('Open direction menu'),
              variant: DButtonVariant.outline,
              hasPopup: true,
              expanded: menu.open,
              onPressed: menu.toggle,
            ),
          ),
        ),
        const SizedBox(height: DSpacing.sm),
        Semantics(liveRegion: true, child: Text('Selected: $_selection')),
      ],
    ),
  );
}

class _DirectionReadout extends StatelessWidget {
  const _DirectionReadout({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Row(
      children: [
        const Icon(Icons.arrow_forward),
        const SizedBox(width: DSpacing.sm),
        Expanded(
          child: Text('$label: ${DDirection.of(context).name.toUpperCase()}'),
        ),
      ],
    ),
  );
}

class _DirectionSurface extends StatelessWidget {
  const _DirectionSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(DSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: tokens.borderRadius,
      ),
      child: child,
    );
  }
}
