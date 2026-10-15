import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../mobile_chrome_previews.dart';
import '../styleguide_example.dart';

final mobileDockExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'A measured floating dock with an active destination retained while reading.',
  notes:
      'Labels and badges determine overflow. More appears only when needed. '
      'The action shows its label when its own slot is at least 116px wide. '
      'Compose with DScrollChrome(floatingFooter: true) and add bottomInsetOf '
      'to the primary viewport. The open dock extent stays reserved at the end '
      'of the content while the viewport remains fixed. A collapsed dock only '
      'accepts its visible reveal target. Liquid glass couples the capsule, '
      'inset and content fades through the package spring; mid-flight reversals '
      'retain velocity. Reduced motion switches immediately.',
  examples: [
    for (final collapsed in [false, true])
      StyleguideExample(
        title: collapsed ? 'Collapsed destination' : 'Floating capsule',
        description:
            'Scroll to fold the dock, then press its destination to reveal the header.',
        states: const [
          'Expanded',
          'Collapsed',
          'Large text',
          'RTL',
          'Reduced motion',
        ],
        code:
            'DMobileDock(destinations: items, more: overflow, action: action, '
            'collapsed: hidden, collapsedDestination: reveal, onOverflowChanged: onOverflow)',
        builder: (_) => SizedBox(
          width: 390,
          height: 560,
          child: MobileChromeExample(initiallyCollapsed: collapsed),
        ),
      ),
  ],
);

final composerDockExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'A retained composer above the open dock and beside its folded destination.',
  notes:
      'DComposerDock shares the navigation motion and safe area. Compose its compact value with DInputGroup.compact and action. The primary action stays reachable while block tools fold away. Focusing the editor reveals the full layout. Reduced motion changes layout immediately.',
  examples: [
    StyleguideExample(
      title: 'Chat composer',
      description:
          'Write a draft, then scroll down and back up to fold and reveal the dock.',
      states: const [
        'Expanded',
        'Compact',
        'Draft retained',
        'Reduced motion',
        'RTL',
        'Large text',
      ],
      code:
          'DComposerDock(builder: (context, compact) => DInputGroup(compact: compact, action: send, children: [editor, tools]))',
      builder: (_) => const SizedBox(
        width: 390,
        height: 560,
        child: MobileChromeExample(chatComposer: true),
      ),
    ),
  ],
);
final headerMorphExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Shared header parts move and resize between reader layouts.',
  notes:
      'Wrap shared parts using stable names supplied by the builder. Their '
      'visible artwork and hit targets travel together over 260ms. Reduced '
      'motion changes the layout immediately. DPageSurface.compactHeader '
      'switches reader layouts while retaining its full scroll spacer.',
  examples: [
    StyleguideExample(
      title: 'Full and compact',
      description: 'Change layout without replacing the header parts.',
      code:
          'DHeaderMorph(compact: compact, builder: (context, compact, part) => layout)',
      builder: (_) => const _MorphExample(),
    ),
  ],
);

class _MorphExample extends StatefulWidget {
  const _MorphExample();
  @override
  State<_MorphExample> createState() => _MorphExampleState();
}

class _MorphExampleState extends State<_MorphExample> {
  bool _compact = false;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DButton(
        label: const Text('Change layout'),
        onPressed: () => setState(() => _compact = !_compact),
      ),
      const SizedBox(height: 16),
      DHeaderMorph(
        compact: _compact,
        builder: (context, compact, part) {
          final title = part(
            'title',
            Text(
              'A community discussion',
              style: TextStyle(
                fontSize: compact ? 14 : 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
          final tools = part(
            'tools',
            DButton(label: const Text('Topic actions'), onPressed: () {}),
          );
          return compact
              ? Row(
                  children: [
                    Expanded(child: title),
                    tools,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 16), tools],
                );
        },
      ),
    ],
  );
}
