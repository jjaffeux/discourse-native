import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../../../discourse_ui.dart';
import '../styleguide_example.dart';

final typographyExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  notes:
      'Frozen 2026-09-08 Typography scope: h1–h4, p, blockquote, table, list, '
      'inline code, lead, large, small, muted and RTL. Import discourse_ui.dart. '
      'DText reproduces the frozen shadcn sizes, weights, leading and tracking '
      'using the app’s fonts, palette and inherited scaler. It does not implement '
      'the newer Typeset system. Plain h1 text balances short multiline headings. '
      'h2 has a token-colored rule; DProse adds reference spacing without '
      'outer margins. SelectionArea belongs to the document. Span code wraps '
      'with a rectangular background; standalone code has themed corners and '
      'the reference’s 4.8px/3.2px padding. '
      'Code alone uses the existing JetBrains Mono. Native controls own focus, '
      'keyboard and activation. Native Table supplies the table composition; '
      'the later Table entry owns its full component API.',
  examples: [
    StyleguideExample(
      title: 'Headings: h1, h2, h3 and h4',
      description:
          'Each heading announces its level. h1 can be centered; h2 has a '
          'bottom rule. Use headingLevel when visual size and document hierarchy '
          'differ. Select text across headings and change the preview palette.',
      states: const ['h1', 'h2', 'h3', 'h4', 'Semantics', 'Selection'],
      code: '''SelectionArea(child: DProse(children: [
  DText('A place to belong', variant: DTextVariant.h1,
    textAlign: TextAlign.center),
  DText('The people of the community', variant: DTextVariant.h2),
  DText('Make room for new voices', variant: DTextVariant.h3),
  DText('Start with a friendly introduction', variant: DTextVariant.h4),
]))''',
      builder: (_) => const SelectionArea(
        child: DProse(
          children: [
            DText(
              'A place to belong',
              variant: DTextVariant.h1,
              textAlign: TextAlign.center,
            ),
            DText('The people of the community', variant: DTextVariant.h2),
            DText('Make room for new voices', variant: DTextVariant.h3),
            DText(
              'Start with a friendly introduction',
              variant: DTextVariant.h4,
            ),
          ],
        ),
      ),
    ),
    StyleguideExample(
      title: 'Reading text: p, Lead, Large, Small and Muted',
      description:
          'Paragraphs use the reference’s 16px text and 28px leading; Small uses '
          '14px medium text with leading-none. All text wraps and grows at 200%; '
          'no fixed line-height boxes.',
      states: const ['p', 'Lead', 'Large', 'Small', 'Muted', 'Text scale'],
      code: '''const DProse(children: [
  DText('A thoughtful conversation starts with listening.',
    variant: DTextVariant.lead),
  DText('Give people time to share their experience. Ask a clear question '
    'and leave room for different answers.'),
  DText('Everyone is welcome', variant: DTextVariant.large),
  DText('Display name', variant: DTextVariant.small),
  DText('Choose a name people will recognize.', variant: DTextVariant.muted),
])''',
      builder: (_) => const SelectionArea(
        child: DProse(
          children: [
            DText(
              'A thoughtful conversation starts with listening.',
              variant: DTextVariant.lead,
            ),
            DText(
              'Give people time to share their experience. Ask a clear question '
              'and leave room for different answers.',
            ),
            DText('Everyone is welcome', variant: DTextVariant.large),
            DText('Display name', variant: DTextVariant.small),
            DText(
              'Choose a name people will recognize.',
              variant: DTextVariant.muted,
            ),
          ],
        ),
      ),
    ),
    StyleguideExample(
      title: 'Blockquote and nested lists',
      description:
          'The quote rule and list markers follow preview direction. Plain Text '
          'inherits reading styles; explicit child styles can identify an '
          'attribution. Ordered lists continue from a supplied number. Empty '
          'lists add no height. Drag to select list content without the markers.',
      states: const ['blockquote', 'list', 'Ordered', 'Nested', 'Empty', 'RTL'],
      code: '''const DProse(children: [
  DBlockquote(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('“A good question makes space for a new perspective.”'),
      SizedBox(height: DSpacing.sm),
      DText('Community handbook', variant: DTextVariant.muted,
        style: TextStyle(fontStyle: FontStyle.normal)),
    ],
  )),
  DTextList(children: [
    Text('Read the conversation before replying.'),
    DProse(spacing: DSpacing.sm, children: [
      Text('Share something useful:'),
      DTextList(ordered: true, start: 9, children: [
        Text('A concrete example from your experience.'),
        Text('A question that invites a thoughtful response.'),
      ]),
    ]),
    Text('Thank the people who helped.'),
  ]),
  DTextList(children: []),
])''',
      builder: (_) => const SelectionArea(
        child: DProse(
          children: [
            DBlockquote(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('“A good question makes space for a new perspective.”'),
                  SizedBox(height: DSpacing.sm),
                  DText(
                    'Community handbook',
                    variant: DTextVariant.muted,
                    style: TextStyle(fontStyle: FontStyle.normal),
                  ),
                ],
              ),
            ),
            DTextList(
              children: [
                Text('Read the conversation before replying.'),
                DProse(
                  spacing: DSpacing.sm,
                  children: [
                    Text('Share something useful:'),
                    DTextList(
                      ordered: true,
                      start: 9,
                      children: [
                        Text('A concrete example from your experience.'),
                        Text('A question that invites a thoughtful response.'),
                      ],
                    ),
                  ],
                ),
                Text('Thank the people who helped.'),
              ],
            ),
            DTextList(children: []),
          ],
        ),
      ),
    ),
    StyleguideExample(
      title: 'Inline code, rich text and keyboard actions',
      description:
          'Select and copy the paragraph, including its wrapping code span. '
          'Tab to “Show details” and activate with Enter or Space; the native '
          'button has visible focus. The result survives theme, width, scale '
          'and direction changes. A long token and ellipsis exercise narrow text.',
      states: const [
        'Inline code',
        'Rich text',
        'Keyboard',
        'Long text',
        'Empty',
      ],
      code: '''// In State: bool details = false;
SelectionArea(child: DProse(children: [
  const DText('community_guidelines', variant: DTextVariant.inlineCode),
  DText.rich(TextSpan(children: [
    const TextSpan(text: 'Use '),
    TextSpan(text: 'community.settings.welcome_message',
      style: DText.styleOf(context, DTextVariant.inlineCode)),
    const TextSpan(text: ' to greet new members. '),
    WidgetSpan(alignment: PlaceholderAlignment.middle,
      child: TextButton(
        onPressed: () => setState(() => details = !details),
        child: Text(details ? 'Hide details' : 'Show details'),
      ),
    ),
  ])),
  Semantics(liveRegion: true, child: DText(
    details ? 'Welcome messages can include a friendly introduction.'
      : 'Details are hidden.', variant: DTextVariant.muted)),
  const DText('LongUnbrokenCommunityConfigurationIdentifier0123456789',
    variant: DTextVariant.inlineCode),
  const DText('An intentionally abbreviated preview of a much longer '
    'community announcement.', maxLines: 1, overflow: TextOverflow.ellipsis),
  const DText(''),
]))''',
      builder: (_) => const _RichTypography(),
    ),
    StyleguideExample(
      title: 'Table composition and column alignment',
      description:
          'Flutter Table keeps paired columns, wrapping cells and intrinsic row '
          'height at narrow widths. Token borders and alternating rows update '
          'with the palette. Headers announce their column role. The first column '
          'uses start alignment; the second demonstrates center and end.',
      states: const ['table', 'Start / center / end', 'Narrow', 'Selection'],
      code: """// Also import 'dart:ui' show SemanticsRole.
const SelectionArea(child: TypographyTableSample())

$_tableSampleCode""",
      builder: (_) => const SelectionArea(child: _TypographyTable()),
    ),
    StyleguideExample(
      title: 'A complete article',
      description:
          'All building blocks combine in a selectable reading surface. The '
          'host scroll view owns the viewport. Change the preview to 360px and '
          '200% to inspect natural wrapping, heading rules, lists and the table.',
      states: const ['Composition', 'Reading', 'Selection', 'Live themes'],
      code: '''SelectionArea(child: DProse(children: [
  const DText('Building a welcoming community', variant: DTextVariant.h1),
  const DText('Small acts of kindness help a community grow.',
    variant: DTextVariant.lead),
  const DText('Begin with a conversation', variant: DTextVariant.h2),
  const DText('New members bring new perspectives. Give them a place '
    'to ask questions and tell their stories.'),
  const DBlockquote(child: Text('“Everyone has something to contribute.”')),
  const DText('Three ways to help', variant: DTextVariant.h3),
  const DTextList(children: [Text('Welcome someone new.'),
    Text('Share a useful resource.'), Text('Celebrate a small success.')]),
  const DText('Notice the difference', variant: DTextVariant.h4),
  const TypographyTableSample(),
  const DText('A little encouragement goes a long way.',
    variant: DTextVariant.large),
  const DText('Community notes', variant: DTextVariant.small),
  const DText('Updated by the community team.', variant: DTextVariant.muted),
]))

$_tableSampleCode''',
      builder: (_) => const SelectionArea(
        child: DProse(
          children: [
            DText('Building a welcoming community', variant: DTextVariant.h1),
            DText(
              'Small acts of kindness help a community grow.',
              variant: DTextVariant.lead,
            ),
            DText('Begin with a conversation', variant: DTextVariant.h2),
            DText(
              'New members bring new perspectives. Give them a place '
              'to ask questions and tell their stories.',
            ),
            DBlockquote(child: Text('“Everyone has something to contribute.”')),
            DText('Three ways to help', variant: DTextVariant.h3),
            DTextList(
              children: [
                Text('Welcome someone new.'),
                Text('Share a useful resource.'),
                Text('Celebrate a small success.'),
              ],
            ),
            DText('Notice the difference', variant: DTextVariant.h4),
            _TypographyTable(),
            DText(
              'A little encouragement goes a long way.',
              variant: DTextVariant.large,
            ),
            DText('Community notes', variant: DTextVariant.small),
            DText(
              'Updated by the community team.',
              variant: DTextVariant.muted,
            ),
          ],
        ),
      ),
    ),
    StyleguideExample(
      title: 'RTL article with a fixed LTR code island',
      description:
          'An explicit Arabic RTL document includes headings, a quote, a list '
          'and a table. Directional borders and columns mirror. The code island '
          'keeps LTR order. Selection and scaling remain native.',
      states: const ['RTL', 'Nested direction', 'Mixed scripts', 'Table'],
      code: '''const DDirection(textDirection: TextDirection.rtl,
  child: SelectionArea(child: DProse(children: [
    DText('مجتمع يرحب بالجميع', variant: DTextVariant.h1),
    DText('كل محادثة تبدأ بالاستماع.', variant: DTextVariant.lead),
    DText('أهلاً بالأعضاء الجدد', variant: DTextVariant.h2),
    DText('شارك خبرتك وامنح الآخرين فرصة لطرح الأسئلة.'),
    DBlockquote(child: Text('«لدى الجميع ما يساهمون به.»')),
    DTextList(children: [Text('رحب بعضو جديد.'), Text('شارك مورداً مفيداً.')]),
    DDirection(textDirection: TextDirection.ltr,
      child: DText('community.settings.welcome_message',
        variant: DTextVariant.inlineCode)),
    TypographyTableSample(arabic: true),
  ])),
)

$_tableSampleCode''',
      builder: (_) => const DDirection(
        textDirection: TextDirection.rtl,
        child: SelectionArea(
          child: DProse(
            children: [
              DText('مجتمع يرحب بالجميع', variant: DTextVariant.h1),
              DText('كل محادثة تبدأ بالاستماع.', variant: DTextVariant.lead),
              DText('أهلاً بالأعضاء الجدد', variant: DTextVariant.h2),
              DText('شارك خبرتك وامنح الآخرين فرصة لطرح الأسئلة.'),
              DBlockquote(child: Text('«لدى الجميع ما يساهمون به.»')),
              DTextList(
                children: [Text('رحب بعضو جديد.'), Text('شارك مورداً مفيداً.')],
              ),
              DDirection(
                textDirection: TextDirection.ltr,
                child: DText(
                  'community.settings.welcome_message',
                  variant: DTextVariant.inlineCode,
                ),
              ),
              _TypographyTable(arabic: true),
            ],
          ),
        ),
      ),
    ),
    StyleguideExample(
      title: 'Shadcn reference specimen',
      description:
          'The frozen reference text and styles for direct visual '
          'comparison at 100%. Theme controls substitute the app palette and '
          'font; size, weight, tracking, leading and spacing match shadcn.',
      states: const ['Reference fidelity', 'Typography', 'Composition'],
      code: r'''const SelectionArea(
  child: DProse(children: [
    DText('Taxing Laughter: The Joke Tax Chronicles',
      variant: DTextVariant.h1, textAlign: TextAlign.center),
    DText('A modal dialog that interrupts the user with important content '
      'and expects a response.', variant: DTextVariant.lead),
    DText('The People of the Kingdom', variant: DTextVariant.h2),
    DText('The king, seeing how much happier his subjects were, realized '
      'the error of his ways and repealed the joke tax.'),
    DBlockquote(child: Text('“After all,” he said, “everyone enjoys a good '
      'joke, so it’s only fair that they should pay for the privilege.”')),
    DText('The Joke Tax', variant: DTextVariant.h3),
    DTextList(children: [
      Text('1st level of puns: 5 gold coins'),
      Text('2nd level of jokes: 10 gold coins'),
      Text('3rd level of one-liners: 20 gold coins'),
    ]),
    DText('People stopped telling jokes', variant: DTextVariant.h4),
    DText('@radix-ui/react-alert-dialog', variant: DTextVariant.inlineCode),
    DText('Are you absolutely sure?', variant: DTextVariant.large),
    DText('Email address', variant: DTextVariant.small),
    DText('Enter your email address.', variant: DTextVariant.muted),
  ]),
)''',
      builder: (_) => const SelectionArea(
        child: DProse(
          children: [
            DText(
              'Taxing Laughter: The Joke Tax Chronicles',
              variant: DTextVariant.h1,
              textAlign: TextAlign.center,
            ),
            DText(
              'A modal dialog that interrupts the user with important content '
              'and expects a response.',
              variant: DTextVariant.lead,
            ),
            DText('The People of the Kingdom', variant: DTextVariant.h2),
            DText(
              'The king, seeing how much happier his subjects were, realized '
              'the error of his ways and repealed the joke tax.',
            ),
            DBlockquote(
              child: Text(
                '“After all,” he said, “everyone enjoys a good '
                'joke, so it’s only fair that they should pay for the privilege.”',
              ),
            ),
            DText('The Joke Tax', variant: DTextVariant.h3),
            DTextList(
              children: [
                Text('1st level of puns: 5 gold coins'),
                Text('2nd level of jokes: 10 gold coins'),
                Text('3rd level of one-liners: 20 gold coins'),
              ],
            ),
            DText('People stopped telling jokes', variant: DTextVariant.h4),
            DText(
              '@radix-ui/react-alert-dialog',
              variant: DTextVariant.inlineCode,
            ),
            DText('Are you absolutely sure?', variant: DTextVariant.large),
            DText('Email address', variant: DTextVariant.small),
            DText('Enter your email address.', variant: DTextVariant.muted),
          ],
        ),
      ),
    ),
  ],
);

class _RichTypography extends StatefulWidget {
  const _RichTypography();

  @override
  State<_RichTypography> createState() => _RichTypographyState();
}

class _RichTypographyState extends State<_RichTypography> {
  bool _details = false;

  @override
  Widget build(BuildContext context) => SelectionArea(
    child: DProse(
      children: [
        const DText('community_guidelines', variant: DTextVariant.inlineCode),
        DText.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Use '),
              TextSpan(
                text: 'community.settings.welcome_message',
                style: DText.styleOf(context, DTextVariant.inlineCode),
              ),
              const TextSpan(text: ' to greet new members. '),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: TextButton(
                  onPressed: () => setState(() => _details = !_details),
                  child: Text(_details ? 'Hide details' : 'Show details'),
                ),
              ),
            ],
          ),
        ),
        Semantics(
          liveRegion: true,
          child: DText(
            _details
                ? 'Welcome messages can include a friendly introduction.'
                : 'Details are hidden.',
            variant: DTextVariant.muted,
          ),
        ),
        const DText(
          'LongUnbrokenCommunityConfigurationIdentifier0123456789',
          variant: DTextVariant.inlineCode,
        ),
        const DText(
          'An intentionally abbreviated preview of a much longer '
          'community announcement.',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const DText(''),
      ],
    ),
  );
}

class _TypographyTable extends StatelessWidget {
  const _TypographyTable({this.arabic = false});

  final bool arabic;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final rows = arabic
        ? const [
            ['الخزينة', 'السعادة'],
            ['فارغة', 'فائضة'],
            ['متواضعة', 'راضٍ'],
            ['ممتلئة', 'منتشٍ'],
          ]
        : const [
            ['Treasury', 'Happiness'],
            ['Empty', 'Overflowing'],
            ['Modest', 'Satisfied'],
            ['Full', 'Ecstatic'],
          ];
    return Table(
      border: TableBorder.all(color: tokens.border),
      defaultColumnWidth: const FlexColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (final (index, row) in rows.indexed)
          TableRow(
            decoration: BoxDecoration(
              color: index.isEven && index > 0 ? tokens.muted : null,
            ),
            children: [
              for (final (column, value) in row.indexed)
                Semantics(
                  role: index == 0
                      ? SemanticsRole.columnHeader
                      : SemanticsRole.cell,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DSpacing.lg,
                      vertical: DSpacing.sm,
                    ),
                    child: DText(
                      value,
                      style: DText.bodyStyleOf(context).copyWith(
                        fontWeight: index == 0
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      textAlign: column == 0
                          ? TextAlign.start
                          : index.isEven
                          ? TextAlign.end
                          : TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

// Include the complete native composition in the table and article usage.
const _tableSampleCode = r'''
class TypographyTableSample extends StatelessWidget {
  const TypographyTableSample({this.arabic = false});

  final bool arabic;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final rows = arabic
        ? const [
            ['الخزينة', 'السعادة'],
            ['فارغة', 'فائضة'],
            ['متواضعة', 'راضٍ'],
            ['ممتلئة', 'منتشٍ'],
          ]
        : const [
            ['Treasury', 'Happiness'],
            ['Empty', 'Overflowing'],
            ['Modest', 'Satisfied'],
            ['Full', 'Ecstatic'],
          ];
    return Table(
      border: TableBorder.all(color: tokens.border),
      defaultColumnWidth: const FlexColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (final (index, row) in rows.indexed)
          TableRow(
            decoration: BoxDecoration(
              color: index.isEven && index > 0 ? tokens.muted : null,
            ),
            children: [
              for (final (column, value) in row.indexed)
                Semantics(
                  role: index == 0
                      ? SemanticsRole.columnHeader
                      : SemanticsRole.cell,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DSpacing.lg,
                      vertical: DSpacing.sm,
                    ),
                    child: DText(
                      value,
                      style: DText.bodyStyleOf(context).copyWith(
                        fontWeight: index == 0
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      textAlign: column == 0
                          ? TextAlign.start
                          : index.isEven
                          ? TextAlign.end
                          : TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
''';
