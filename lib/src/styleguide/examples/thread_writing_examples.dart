import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final threadWritingExamples = ComponentExamples(
  description:
      'Redactions, welcome celebrations and status changes in a thread.',
  notes:
      'Native owns the spoiler, celebration, card transition, tab strip and recessed writing surface. The host owns notice data and which welcomes have been seen.',
  status: ComponentStatus.implemented,
  examples: [
    StyleguideExample(
      title: 'Thread writing',
      description:
          'All transitions and celebrations respect reduced motion. Hidden spoilers do not build their content.',
      code:
          'DSpoiler(text: text, builder: builder, showLabel: "Spoiler", hideLabel: "Hide spoiler")',
      builder: (_) => const ThreadWritingExample(),
    ),
  ],
);

class ThreadWritingExample extends StatefulWidget {
  const ThreadWritingExample({super.key});
  @override
  State<ThreadWritingExample> createState() => _ThreadWritingExampleState();
}

class _ThreadWritingExampleState extends State<ThreadWritingExample> {
  bool _notice = true;
  int _celebration = 0;
  String _tab = 'forum';
  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DSpacing.lg,
      children: [
        DTabs<String>.controlled(
          value: _tab,
          onChanged: (value) => setState(() => _tab = value!),
          children: [
            DTabList<String>(
              expandSelected: true,
              children: [
                for (final item in [
                  ('forum', 'Forum', DIcons.layerGroup),
                  ('chat', 'Chat', DIcons.comment),
                  ('shortcuts', 'Shortcuts', DIcons.star),
                ])
                  DTabTrigger(
                    value: item.$1,
                    semanticLabel: item.$2,
                    icon: DIcon(item.$3),
                    selectedLabelOnly: true,
                    child: Text(item.$2),
                  ),
              ],
            ),
          ],
        ),
        DCard(
          duration: DMotion.duration(context, DMotion.change),
          spacing: 0,
          backgroundColor: _notice
              ? tokens.primary.withValues(alpha: .08)
              : Colors.transparent,
          borderColor: _notice
              ? tokens.primary.withValues(alpha: .26)
              : Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DReveal(
                visible: _notice,
                child: DAlert(
                  backgroundColor: Colors.transparent,
                  borderColor: Colors.transparent,
                  icon: DConfetti(
                    key: ValueKey(_celebration),
                    child: const DIcon(DIcons.hand),
                  ),
                  description: const DAlertDescription(
                    child: Text('A first post — welcome to the community!'),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(DSpacing.lg),
                child: Text(
                  'The discussion continues here. Its content stays in place when a notice changes.',
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: DSpacing.sm,
          runSpacing: DSpacing.sm,
          children: [
            DButton(
              variant: DButtonVariant.outline,
              label: const Text('Toggle notice'),
              onPressed: () => setState(() => _notice = !_notice),
            ),
            DButton(
              variant: DButtonVariant.outline,
              label: const Text('Celebrate'),
              onPressed: () => setState(() {
                _notice = true;
                _celebration++;
              }),
            ),
          ],
        ),
        DSpoiler(
          text:
              'The secret is kept behind a redaction. Select it to read the rest of this sentence.',
          showLabel: 'Spoiler',
          hideLabel: 'Hide spoiler',
          builder: (_) => const Text(
            'The secret is kept behind a redaction. Select it to read the rest of this sentence.',
          ),
        ),
        const DCard(
          variant: DCardVariant.well,
          children: [
            DCardContent(
              child: Text(
                'A shared recessed surface for code and editable tables.',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
