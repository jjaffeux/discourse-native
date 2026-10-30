import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final headerTagsExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Compact header tags with inline expansion for hidden tags.',
  notes:
      'Supply filter-sized Native tag buttons. The header keeps the tags that '
      'fit beside a count, then wraps every tag when the count is opened. '
      'Identity scopes expansion to the owning page.',
  examples: [
    StyleguideExample(
      title: 'Compact tag row',
      description:
          'Open the count to reveal all tags without leaving the page.',
      states: const ['Collapsed', 'Expanded', 'Touch', 'RTL', 'Large text'],
      code: '''DHeaderTags(
  identity: 'header-tags-example',
  expandSemanticLabel: 'All tags',
  tags: [
    for (final name in tags)
      DHeaderTag(name: name, child: tagButton(name)),
  ],
)''',
      builder: (_) => const _HeaderTagsExample(),
    ),
  ],
);

class _HeaderTagsExample extends StatelessWidget {
  const _HeaderTagsExample();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 320,
    child: DHeaderTags(
      identity: 'header-tags-example',
      expandSemanticLabel: 'All tags',
      tags: [
        for (final name in const [
          'design',
          'native',
          'accessibility',
          'announcements',
          'support',
        ])
          DHeaderTag(
            name: name,
            child: DButton(
              variant: DButtonVariant.tool,
              size: DButtonSize.filter,
              onPressed: () {},
              label: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '#',
                      style: TextStyle(
                        color: DTokens.of(context).mutedForeground,
                      ),
                    ),
                    const WidgetSpan(
                      child: SizedBox(width: DSpacing.controlGap),
                    ),
                    TextSpan(text: name),
                  ],
                ),
                maxLines: 1,
              ),
            ),
          ),
      ],
    ),
  );
}
