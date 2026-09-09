import 'dart:ui' show SemanticsRole;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../discourse_ui.dart';
import '../styleguide_example.dart';

final typographyExamples = ComponentExamples(
  description:
      'Type styles for headings, paragraphs, lists, and inline content.',
  status: ComponentStatus.implemented,
  notes:
      'Current upstream Typography scope: h1–h4, p, blockquote, table, list, '
      'inline code, lead, large, small, muted and RTL. Import discourse_ui.dart. '
      'DText reproduces the current shadcn sizes, weights, leading and tracking '
      'using the app’s fonts, palette and inherited scaler; tracking follows '
      'the rendered size like the reference’s em value. It does not implement '
      'the newer Typeset system. Plain h1 text balances short multiline '
      'headings. h2 has a token-colored rule; DProse adds reference spacing '
      'without outer margins. SelectionArea belongs to the document. Span code '
      'wraps with a rectangular background; standalone code has the '
      'reference’s fixed 4px corners and 4.8px/3.2px padding. Code alone uses '
      'the existing JetBrains Mono. DText.linkStyleOf supplies the demo’s '
      'medium primary underlined link for a caller-owned span recognizer. '
      'Native controls own focus, keyboard and activation. Native Table '
      'supplies the table composition; the later Table entry owns its full '
      'component API.',
  examples: [
    StyleguideExample(
      title: 'Shadcn reference demo',
      description:
          'The current TypographyDemo composition: a balanced h1, lead text, '
          'the h2 rule, a primary link, a quote, h3 sections, the list, the '
          'table and closing paragraphs. Click or tap the link, or activate it '
          'with assistive technology; a status line reports it. Span links '
          'wrap and select like the reference but take no Tab focus.',
      states: const ['Reference fidelity', 'Link', 'Composition', 'Selection'],
      code: '''// In State: final _plan = TapGestureRecognizer()
//   ..onTap = () => setState(() => _followed = true);
// Dispose the recognizer with the State. t holds the reference strings.
SelectionArea(child: DProse(children: [
  DText(t.title, variant: DTextVariant.h1),
  DText(t.leadParagraph, variant: DTextVariant.lead),
  DText(t.kingsPlan, variant: DTextVariant.h2),
  DText.rich(TextSpan(children: [
    TextSpan(text: '\${t.kingThought} '),
    TextSpan(text: t.brilliantPlan,
      style: DText.linkStyleOf(context), recognizer: _plan),
    TextSpan(text: t.taxJokes),
  ])),
  DBlockquote(child: Text(t.blockquote)),
  DText(t.jokeTax, variant: DTextVariant.h3),
  DText(t.subjectsNotAmused),
  DTextList(children: [Text(t.level1), Text(t.level2), Text(t.level3)]),
  DText(t.stoppedTelling),
  DText(t.jokestersRevolt, variant: DTextVariant.h3),
  DText(t.sneaking),
  DText(t.discovered),
  DText(t.peoplesRebellion, variant: DTextVariant.h3),
  DText(t.uplifted),
  TypographyTableSample(rows: [
    [t.kingsTreasury, t.peoplesHappiness],
    [t.empty, t.overflowing],
    [t.modest, t.satisfied],
    [t.full, t.ecstatic],
  ]),
  DText(t.realized),
  DText(t.moral),
  if (_followed)
    Semantics(liveRegion: true,
      child: DText(t.linkFollowed, variant: DTextVariant.muted)),
]))

$_tableSampleCode''',
      builder: (_) => const _ReferenceDemo(strings: _english),
    ),
    StyleguideExample(
      title: 'Shadcn section examples',
      description:
          'The current per-section examples with their original text for direct '
          'visual comparison at 100%: centered h1, h2, h3, h4, p, blockquote, '
          'list, inline code, lead, large, small and muted. Theme controls '
          'substitute the app palette and font; size, weight, tracking, '
          'leading and spacing match shadcn.',
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
    DBlockquote(child: Text('"After all," he said, "everyone enjoys a good '
      'joke, so it\'s only fair that they should pay for the privilege."')),
    DText('The Joke Tax', variant: DTextVariant.h3),
    DTextList(children: [
      Text('1st level of puns: 5 gold coins'),
      Text('2nd level of jokes: 10 gold coins'),
      Text('3rd level of one-liners : 20 gold coins'),
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
                '"After all," he said, "everyone enjoys a good joke, so '
                "it's only fair that they should pay for the privilege.\"",
              ),
            ),
            DText('The Joke Tax', variant: DTextVariant.h3),
            DTextList(
              children: [
                Text('1st level of puns: 5 gold coins'),
                Text('2nd level of jokes: 10 gold coins'),
                Text('3rd level of one-liners : 20 gold coins'),
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
    StyleguideExample(
      title: 'Shadcn RTL reference',
      description:
          'The current RTL example: the demo in Arabic by default, with the '
          'reference’s English and Hebrew translations behind a language '
          'selector. The document sets its own direction, so the quote rule, '
          'list markers, table columns and link mirror; the selector keeps the '
          'preview direction. Selection and scaling remain native.',
      states: const ['RTL', 'Arabic', 'Hebrew', 'English', 'Table', 'Link'],
      code: '''// In State: String _language = 'ar'; _plan as in the demo.
Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  DToggleGroup<String>(
    variant: DToggleVariant.outline,
    allowEmptySelection: false,
    semanticLabel: 'Language',
    values: [_language],
    onChanged: (values) => setState(() => _language = values.single),
    items: const [
      DToggleGroupItem(value: 'en', child: Text('English')),
      DToggleGroupItem(value: 'ar', child: Text('العربية')),
      DToggleGroupItem(value: 'he', child: Text('עברית')),
    ],
  ),
  const SizedBox(height: DSpacing.xl),
  DDirection(
    textDirection: t.direction, // rtl for ar and he, ltr for en
    child: SelectionArea(child: DProse(children: [
      // The reference demo composition, as in the first example.
    ])),
  ),
])''',
      builder: (_) => const _ReferenceRtl(),
    ),
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
          'and direction changes. The first code token is a fixed LTR island: '
          'switch the preview to RTL and it keeps its order. A long token and '
          'an ellipsis exercise narrow text.',
      states: const [
        'Inline code',
        'Rich text',
        'Keyboard',
        'Nested direction',
        'Long text',
        'Empty',
      ],
      code: '''// In State: bool details = false;
SelectionArea(child: DProse(children: [
  const DDirection(textDirection: TextDirection.ltr,
    child: DText('community_guidelines', variant: DTextVariant.inlineCode)),
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
          'with the palette. Headers announce their column role. The reference '
          'aligns every cell to the start; mixedAlignment shows the center and '
          'end alignment its cell classes also support.',
      states: const ['table', 'Start / center / end', 'Narrow', 'Selection'],
      code: """// Also import 'dart:ui' show SemanticsRole.
const SelectionArea(child: TypographyTableSample(
  rows: [
    ["King's Treasury", "People's happiness"],
    ['Empty', 'Overflowing'],
    ['Modest', 'Satisfied'],
    ['Full', 'Ecstatic'],
  ],
  mixedAlignment: true,
))

$_tableSampleCode""",
      builder: (_) => const SelectionArea(
        child: _TypographyTable(rows: _treasuryRows, mixedAlignment: true),
      ),
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
  const TypographyTableSample(rows: [
    ["King's Treasury", "People's happiness"],
    ['Empty', 'Overflowing'],
    ['Modest', 'Satisfied'],
    ['Full', 'Ecstatic'],
  ]),
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
            _TypographyTable(rows: _treasuryRows),
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
  ],
);

/// The frozen demo's text in one of the reference's three languages.
class _ReferenceStrings {
  const _ReferenceStrings({
    required this.direction,
    required this.title,
    required this.leadParagraph,
    required this.kingsPlan,
    required this.kingThought,
    required this.brilliantPlan,
    required this.taxJokes,
    required this.blockquote,
    required this.jokeTax,
    required this.subjectsNotAmused,
    required this.level1,
    required this.level2,
    required this.level3,
    required this.stoppedTelling,
    required this.jokestersRevolt,
    required this.sneaking,
    required this.discovered,
    required this.peoplesRebellion,
    required this.uplifted,
    required this.kingsTreasury,
    required this.peoplesHappiness,
    required this.empty,
    required this.overflowing,
    required this.modest,
    required this.satisfied,
    required this.full,
    required this.ecstatic,
    required this.realized,
    required this.moral,
    required this.linkFollowed,
  });

  final TextDirection direction;
  final String title;
  final String leadParagraph;
  final String kingsPlan;
  final String kingThought;
  final String brilliantPlan;
  final String taxJokes;
  final String blockquote;
  final String jokeTax;
  final String subjectsNotAmused;
  final String level1;
  final String level2;
  final String level3;
  final String stoppedTelling;
  final String jokestersRevolt;
  final String sneaking;
  final String discovered;
  final String peoplesRebellion;
  final String uplifted;
  final String kingsTreasury;
  final String peoplesHappiness;
  final String empty;
  final String overflowing;
  final String modest;
  final String satisfied;
  final String full;
  final String ecstatic;
  final String realized;
  final String moral;

  /// Status text for the followed demo link; not part of the reference.
  final String linkFollowed;
}

const _english = _ReferenceStrings(
  direction: TextDirection.ltr,
  title: 'Taxing Laughter: The Joke Tax Chronicles',
  leadParagraph:
      'Once upon a time, in a far-off land, there was a very lazy king who spent all day lounging on his throne. One day, his advisors came to him with a problem: the kingdom was running out of money.',
  kingsPlan: 'The King\'s Plan',
  kingThought: 'The king thought long and hard, and finally came up with',
  brilliantPlan: 'a brilliant plan',
  taxJokes: ': he would tax the jokes in the kingdom.',
  blockquote:
      '"After all," he said, "everyone enjoys a good joke, so it\'s only fair that they should pay for the privilege."',
  jokeTax: 'The Joke Tax',
  subjectsNotAmused:
      'The king\'s subjects were not amused. They grumbled and complained, but the king was firm:',
  level1: '1st level of puns: 5 gold coins',
  level2: '2nd level of jokes: 10 gold coins',
  level3: '3rd level of one-liners : 20 gold coins',
  stoppedTelling:
      'As a result, people stopped telling jokes, and the kingdom fell into a gloom. But there was one person who refused to let the king\'s foolishness get him down: a court jester named Jokester.',
  jokestersRevolt: 'Jokester\'s Revolt',
  sneaking:
      'Jokester began sneaking into the castle in the middle of the night and leaving jokes all over the place: under the king\'s pillow, in his soup, even in the royal toilet. The king was furious, but he couldn\'t seem to stop Jokester.',
  discovered:
      'And then, one day, the people of the kingdom discovered that the jokes left by Jokester were so funny that they couldn\'t help but laugh. And once they started laughing, they couldn\'t stop.',
  peoplesRebellion: 'The People\'s Rebellion',
  uplifted:
      'The people of the kingdom, feeling uplifted by the laughter, started to tell jokes and puns again, and soon the entire kingdom was in on the joke.',
  kingsTreasury: 'King\'s Treasury',
  peoplesHappiness: 'People\'s happiness',
  empty: 'Empty',
  overflowing: 'Overflowing',
  modest: 'Modest',
  satisfied: 'Satisfied',
  full: 'Full',
  ecstatic: 'Ecstatic',
  realized:
      'The king, seeing how much happier his subjects were, realized the error of his ways and repealed the joke tax. Jokester was declared a hero, and the kingdom lived happily ever after.',
  moral:
      'The moral of the story is: never underestimate the power of a good laugh and always be careful of bad ideas.',
  linkFollowed: 'Link followed: a brilliant plan',
);

const _arabic = _ReferenceStrings(
  direction: TextDirection.rtl,
  title: 'فرض الضرائب على الضحك: سجلات ضريبة النكتة',
  leadParagraph:
      'في قديم الزمان، في أرض بعيدة، كان هناك ملك كسول جداً يقضي يومه كله مستلقياً على عرشه. في أحد الأيام، جاءه مستشاروه بمشكلة: المملكة كانت تنفد من المال.',
  kingsPlan: 'خطة الملك',
  kingThought: 'فكر الملك طويلاً وبجد، وأخيراً توصل إلى',
  brilliantPlan: 'خطة عبقرية',
  taxJokes: ': سيفرض ضريبة على النكات في المملكة.',
  blockquote:
      '"في النهاية،" قال، "الجميع يستمتع بنكتة جيدة، لذا من العدل أن يدفعوا مقابل هذا الامتياز."',
  jokeTax: 'ضريبة النكتة',
  subjectsNotAmused:
      'لم يكن رعايا الملك سعداء. تذمروا واشتكوا، لكن الملك كان حازماً:',
  level1: 'المستوى الأول من التورية: 5 قطع ذهبية',
  level2: 'المستوى الثاني من النكات: 10 قطع ذهبية',
  level3: 'المستوى الثالث من النكات القصيرة: 20 قطعة ذهبية',
  stoppedTelling:
      'نتيجة لذلك، توقف الناس عن رواية النكات، وغرقت المملكة في الكآبة. لكن كان هناك شخص واحد رفض أن تحبطه حماقة الملك: مهرج البلاط المسمى المازح.',
  jokestersRevolt: 'ثورة المازح',
  sneaking:
      'بدأ المازح يتسلل إلى القلعة في منتصف الليل ويترك النكات في كل مكان: تحت وسادة الملك، في حسائه، حتى في المرحاض الملكي. كان الملك غاضباً، لكنه لم يستطع إيقاف المازح.',
  discovered:
      'وبعد ذلك، في يوم من الأيام، اكتشف سكان المملكة أن النكات التي تركها المازح كانت مضحكة جداً لدرجة أنهم لم يستطيعوا منع أنفسهم من الضحك. وبمجرد أن بدأوا بالضحك، لم يستطيعوا التوقف.',
  peoplesRebellion: 'ثورة الشعب',
  uplifted:
      'شعر سكان المملكة بالبهجة من الضحك، وبدأوا في رواية النكات والتورية مرة أخرى، وسرعان ما أصبحت المملكة بأكملها جزءاً من النكتة.',
  kingsTreasury: 'خزينة الملك',
  peoplesHappiness: 'سعادة الشعب',
  empty: 'فارغة',
  overflowing: 'فائضة',
  modest: 'متواضعة',
  satisfied: 'راضٍ',
  full: 'ممتلئة',
  ecstatic: 'منتشٍ',
  realized:
      'الملك، عندما رأى مدى سعادة رعاياه، أدرك خطأ طرقه وألغى ضريبة النكتة. أُعلن المازح بطلاً، وعاشت المملكة في سعادة دائمة.',
  moral:
      'مغزى القصة هو: لا تستهن أبداً بقوة الضحك الجيد وكن دائماً حذراً من الأفكار السيئة.',
  linkFollowed: 'تم فتح الرابط: خطة عبقرية',
);

const _hebrew = _ReferenceStrings(
  direction: TextDirection.rtl,
  title: 'מיסוי הצחוק: כרוניקות מס הבדיחה',
  leadParagraph:
      'היה היה פעם, בארץ רחוקה, מלך עצלן מאוד שבילה את כל היום בהתרווחות על כס מלכותו. יום אחד, יועציו באו אליו עם בעיה: הממלכה נגמר לה הכסף.',
  kingsPlan: 'התוכנית של המלך',
  kingThought: 'המלך חשב ארוכות וקשות, ולבסוף העלה',
  brilliantPlan: 'תוכנית גאונית',
  taxJokes: ': הוא ימסה את הבדיחות בממלכה.',
  blockquote:
      '"אחרי הכל," אמר, "כולם נהנים מבדיחה טובה, אז זה רק הוגן שישלמו על הזכות הזו."',
  jokeTax: 'מס הבדיחה',
  subjectsNotAmused:
      'נתיני המלך לא היו מרוצים. הם התלוננו והתרעמו, אבל המלך היה נחוש:',
  level1: 'רמה ראשונה של משחקי מילים: 5 מטבעות זהב',
  level2: 'רמה שנייה של בדיחות: 10 מטבעות זהב',
  level3: 'רמה שלישית של חידודים: 20 מטבעות זהב',
  stoppedTelling:
      'כתוצאה מכך, אנשים הפסיקו לספר בדיחות, והממלכה שקעה בעצב. אבל היה אדם אחד שסירב לתת לטיפשות המלך להפיל אותו: ליצן חצר בשם הבדחן.',
  jokestersRevolt: 'המרד של הבדחן',
  sneaking:
      'הבדחן התחיל להתגנב לטירה באמצע הלילה ולהשאיר בדיחות בכל מקום: מתחת לכרית המלך, במרק שלו, אפילו בשירותים המלכותיים. המלך היה זועם, אבל הוא לא הצליח לעצור את הבדחן.',
  discovered:
      'ואז, יום אחד, תושבי הממלכה גילו שהבדיחות שהבדחן השאיר היו כל כך מצחיקות שהם לא יכלו להתאפק מלצחוק. וברגע שהתחילו לצחוק, הם לא יכלו להפסיק.',
  peoplesRebellion: 'המרד של העם',
  uplifted:
      'תושבי הממלכה, שהרגישו מרוממים מהצחוק, התחילו לספר בדיחות ומשחקי מילים שוב, ובקרוב כל הממלכה הייתה חלק מהבדיחה.',
  kingsTreasury: 'אוצר המלך',
  peoplesHappiness: 'אושר העם',
  empty: 'ריק',
  overflowing: 'גדוש',
  modest: 'צנוע',
  satisfied: 'מרוצה',
  full: 'מלא',
  ecstatic: 'אקסטטי',
  realized:
      'המלך, כשראה כמה מאושרים נתיניו, הבין את טעותו וביטל את מס הבדיחה. הבדחן הוכרז כגיבור, והממלכה חיה באושר לנצח.',
  moral:
      'המוסר של הסיפור הוא: לעולם אל תזלזל בכוח של צחוק טוב ותמיד היזהר מרעיונות רעים.',
  linkFollowed: 'הקישור נפתח: תוכנית גאונית',
);

const _referenceLanguages = {'en': _english, 'ar': _arabic, 'he': _hebrew};

const _treasuryRows = [
  ["King's Treasury", "People's happiness"],
  ['Empty', 'Overflowing'],
  ['Modest', 'Satisfied'],
  ['Full', 'Ecstatic'],
];

/// The frozen TypographyDemo composition. An explicit direction reproduces
/// the RTL example's `dir` attribute; null inherits the preview direction.
class _ReferenceDemo extends StatefulWidget {
  const _ReferenceDemo({required this.strings, this.textDirection});

  final _ReferenceStrings strings;
  final TextDirection? textDirection;

  @override
  State<_ReferenceDemo> createState() => _ReferenceDemoState();
}

class _ReferenceDemoState extends State<_ReferenceDemo> {
  late final TapGestureRecognizer _plan = TapGestureRecognizer()
    ..onTap = () => setState(() => _followed = true);
  bool _followed = false;

  @override
  void dispose() {
    _plan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.strings;
    final document = SelectionArea(
      child: DProse(
        children: [
          DText(t.title, variant: DTextVariant.h1),
          DText(t.leadParagraph, variant: DTextVariant.lead),
          DText(t.kingsPlan, variant: DTextVariant.h2),
          DText.rich(
            TextSpan(
              children: [
                TextSpan(text: '${t.kingThought} '),
                TextSpan(
                  text: t.brilliantPlan,
                  style: DText.linkStyleOf(context),
                  recognizer: _plan,
                ),
                TextSpan(text: t.taxJokes),
              ],
            ),
          ),
          DBlockquote(child: Text(t.blockquote)),
          DText(t.jokeTax, variant: DTextVariant.h3),
          DText(t.subjectsNotAmused),
          DTextList(children: [Text(t.level1), Text(t.level2), Text(t.level3)]),
          DText(t.stoppedTelling),
          DText(t.jokestersRevolt, variant: DTextVariant.h3),
          DText(t.sneaking),
          DText(t.discovered),
          DText(t.peoplesRebellion, variant: DTextVariant.h3),
          DText(t.uplifted),
          _TypographyTable(
            rows: [
              [t.kingsTreasury, t.peoplesHappiness],
              [t.empty, t.overflowing],
              [t.modest, t.satisfied],
              [t.full, t.ecstatic],
            ],
          ),
          DText(t.realized),
          DText(t.moral),
          if (_followed)
            Semantics(
              liveRegion: true,
              child: DText(t.linkFollowed, variant: DTextVariant.muted),
            ),
        ],
      ),
    );
    return switch (widget.textDirection) {
      null => document,
      final direction => DDirection(textDirection: direction, child: document),
    };
  }
}

/// The frozen RTL example: the demo with a language selector, Arabic first.
class _ReferenceRtl extends StatefulWidget {
  const _ReferenceRtl();

  @override
  State<_ReferenceRtl> createState() => _ReferenceRtlState();
}

class _ReferenceRtlState extends State<_ReferenceRtl> {
  String _language = 'ar';

  @override
  Widget build(BuildContext context) {
    final strings = _referenceLanguages[_language]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DToggleGroup<String>(
          variant: DToggleVariant.outline,
          allowEmptySelection: false,
          semanticLabel: 'Language',
          values: [_language],
          onChanged: (values) => setState(() => _language = values.single),
          items: const [
            DToggleGroupItem(value: 'en', child: Text('English')),
            DToggleGroupItem(value: 'ar', child: Text('العربية')),
            DToggleGroupItem(value: 'he', child: Text('עברית')),
          ],
        ),
        const SizedBox(height: DSpacing.xl),
        _ReferenceDemo(strings: strings, textDirection: strings.direction),
      ],
    );
  }
}

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
        const DDirection(
          textDirection: TextDirection.ltr,
          child: DText(
            'community_guidelines',
            variant: DTextVariant.inlineCode,
          ),
        ),
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

/// The frozen table: bordered 16/24 cells with 16px/8px padding, a bold
/// header row, the second body row on the muted surface and start alignment.
/// [mixedAlignment] demonstrates the center and end alignment the reference's
/// cell classes support for `align` attributes.
class _TypographyTable extends StatelessWidget {
  const _TypographyTable({required this.rows, this.mixedAlignment = false});

  /// The header row followed by body rows.
  final List<List<String>> rows;
  final bool mixedAlignment;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
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
                      textAlign: !mixedAlignment || column == 0
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
  const TypographyTableSample({required this.rows, this.mixedAlignment = false});

  /// The header row followed by body rows.
  final List<List<String>> rows;
  final bool mixedAlignment;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
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
                      textAlign: !mixedAlignment || column == 0
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
