import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final bubbleExamples = ComponentExamples(
  status: ComponentStatus.planned,
  description: 'Conversational surfaces with alignment, grouping, reactions and interactive content.',
  notes:
      'Source-ready for independent review. The frozen base-nova surface maps '
      '12px horizontal and 8px vertical padding, 14px/22.75px text, host-relative '
      'xl radius, 80% maximum width, 8px group gaps and 3px reaction surrounds. '
      'Ghost content stays unframed and may use the full row. Static reaction '
      'rows expose one descriptive image; interactive rows retain independent '
      'button labels, counts, selected, disabled, busy and failure states. '
      'Bubble owns no author, timestamp, transport, Markdown, attachment or '
      'timeline state. Interactive content owns an internal FocusNode unless a '
      'borrowed node is supplied. Action and reaction feedback composes the '
      'accepted local DToast owner; the visible result also keeps deterministic '
      'example state.',
  examples: [
    StyleguideExample(
      title: 'Composition',
      description: 'The frozen conversation demo combines end-aligned primary bubbles, a muted group and descriptive reactions.',
      states: const ['Primary', 'Muted', 'Group', 'Reactions'],
      code: '''DBubble(
  align: DBubbleAlign.end,
  children: const [DBubbleContent(child: Text("Hey there! what's up?"))],
)
DBubbleGroup(children: [
  DBubble(variant: DBubbleVariant.muted, children: const [
    DBubbleContent(child: Text('Hey! Want to see chat bubbles?')),
  ]),
])''',
      builder: (_) => const _ConversationDemo(),
    ),
    StyleguideExample(
      title: 'Variants',
      description: 'All seven Bubble-owned treatments. Child Button variants are intentionally not added to Bubble.',
      states: const [
        'Primary',
        'Secondary',
        'Muted',
        'Tinted',
        'Outline',
        'Ghost',
        'Destructive',
      ],
      code: '''DBubble(variant: DBubbleVariant.tinted, align: DBubbleAlign.end,
  children: const [DBubbleContent(child: Text('A soft primary tint.'))])
DBubble(variant: DBubbleVariant.ghost,
  children: const [DBubbleContent(child: Text('Unframed rich content.'))])''',
      builder: (_) => const _VariantsDemo(),
    ),
    StyleguideExample(
      title: 'Alignment and groups',
      description: 'Logical start/end mirrors in RTL. Consecutive messages retain the compact 8px group gap.',
      states: const ['Start', 'End', 'RTL', 'Grouped'],
      code: '''DBubbleGroup(children: const [
  DBubble(align: DBubbleAlign.end,
    children: [DBubbleContent(child: Text('You tell me!'))]),
  DBubble(align: DBubbleAlign.end,
    children: [DBubbleContent(child: Text('Find the bug and fix it.'))]),
])''',
      builder: (_) => const _AlignmentDemo(),
    ),
    StyleguideExample(
      title: 'Links and buttons',
      description: 'Tab then Return activates links; Return or Space activates buttons. The local result proves the callback without a substitute notification system.',
      states: const ['Button', 'Link', 'Focus', 'Hover', 'Pressed'],
      code: '''DBubble(variant: DBubbleVariant.tinted, align: DBubbleAlign.end,
  children: [DBubbleContent(
    action: DBubbleContentAction.button,
    onPressed: forgotPassword,
    child: const Text('I forgot my password'),
  )],
)''',
      builder: (_) => const _ActionsDemo(),
    ),
    StyleguideExample(
      title: 'Reactions',
      description: 'Static rows announce once. Independent controls show count, selection, disabled, busy and failed states beyond color.',
      states: const [
        'Top',
        'Bottom',
        'Start',
        'End',
        'Selected',
        'Disabled',
        'Busy',
        'Error',
      ],
      code: '''DBubbleReactions(
  semanticLabel: 'Reactions: eyes, rocket, and 2 more',
  children: const [Text('👀'), Text('🚀'), Text('+2')],
)
DBubbleReactions(interactive: true, children: [
  DButton(semanticLabel: 'Thumbs up, 4 reactions, selected',
    label: const Text('👍 4 ✓'), onPressed: toggleReaction),
])''',
      builder: (_) => const _ReactionDemo(),
    ),
    StyleguideExample(
      title: 'Show more / Collapsible',
      description: 'The accepted disclosure owner controls long content and restores focus. Reduced motion removes its optional transition.',
      states: const ['Collapsed', 'Expanded', 'Keyboard', 'Reduced motion'],
      code: '''DCollapsible(
  open: open,
  onOpenChange: setOpen,
  child: DBubble(variant: DBubbleVariant.muted, children: [
    DBubbleContent(child: Column(children: [
      Text(open ? fullText : preview),
      DCollapsibleTrigger(builder: buildShowMore),
    ])),
  ]),
)''',
      builder: (_) => const _CollapsibleDemo(),
    ),
    StyleguideExample(
      title: 'Tooltip',
      description: 'A separately actionable read receipt keeps its label while hover or focus reveals metadata.',
      states: const ['Hover', 'Focus', 'Read metadata'],
      code: '''DBubbleReactions(interactive: true, children: [
  DTooltip(message: 'Read on Jan 5, 2026 at 4:32 PM',
    child: DButton.iconOnly(
      icon: const Icon(Icons.check), tooltip: 'Read receipt', onPressed: showReceipt)),
])''',
      builder: (_) => const _TooltipDemo(),
    ),
    StyleguideExample(
      title: 'Popover',
      description: 'The prepared Popover owner reveals a full failure message, restores focus and dismisses on Escape or outside press.',
      states: const ['Error text', 'Popover', 'Focus restoration', 'Escape'],
      code: '''DPopover(
  content: const DPopoverContent(
    semanticLabel: 'Command error details',
    child: DPopoverHeader(children: [
      DPopoverTitle(child: Text('Command failed with exit code 1')),
      DPopoverDescription(child: Text('ENOENT: no such file or directory')),
    ]),
  ),
  child: DPopoverTrigger(builder: buildErrorButton),
)''',
      builder: (_) => const _PopoverDemo(),
    ),
    StyleguideExample(
      title: 'Narrow, scaled and RTL',
      description: 'Long rich content wraps at 80% on a narrow row; ghost content uses the full row. Preview at 200% and RTL.',
      states: const ['Long content', '80% width', 'Ghost', '200% text', 'RTL'],
      code: '''Directionality(textDirection: TextDirection.rtl, child: Column(children: [
  DBubble(align: DBubbleAlign.end, children: const [
    DBubbleContent(child: Text('رسالة طويلة تلتف داخل المساحة المتاحة.')),
  ]),
  DBubble(variant: DBubbleVariant.ghost, children: const [
    DBubbleContent(child: SelectableText('Rich assistant response')),
  ]),
]))''',
      builder: (_) => const _EdgesDemo(),
    ),
  ],
);

class _Frame extends StatelessWidget {
  const _Frame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 384),
    child: DefaultTextStyle.merge(
      style: Theme.of(context).textTheme.bodyMedium,
      child: child,
    ),
  );
}

class _ConversationDemo extends StatelessWidget {
  const _ConversationDemo();

  @override
  Widget build(BuildContext context) => const _Frame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 32,
      children: [
        DBubble(
          align: DBubbleAlign.end,
          children: [DBubbleContent(child: Text("Hey there! what's up?"))],
        ),
        DBubbleGroup(
          children: [
            DBubble(
              variant: DBubbleVariant.muted,
              children: [
                DBubbleContent(child: Text('Hey! Want to see chat bubbles?')),
              ],
            ),
            DBubble(
              variant: DBubbleVariant.muted,
              children: [
                DBubbleContent(
                  child: Text(
                    'I can group messages, switch sides, and keep the whole thread easy to scan.',
                  ),
                ),
                DBubbleReactions(
                  semanticLabel: 'Reaction: thumbs up',
                  children: [Text('👍')],
                ),
              ],
            ),
          ],
        ),
        DBubble(
          align: DBubbleAlign.end,
          children: [
            DBubbleContent(child: Text('Sure. Hit me with your best demo.')),
          ],
        ),
        DBubble(
          variant: DBubbleVariant.muted,
          children: [
            DBubbleContent(
              child: Text(
                'Yes. You are reading a demo that is demoing itself. Very meta. Very on-brand.',
              ),
            ),
            DBubbleReactions(
              semanticLabel: 'Reactions: thumbs up, fire, eyes, and 2 more',
              children: [Text('👍'), Text('🔥'), Text('👀'), Text('+2')],
            ),
          ],
        ),
      ],
    ),
  );
}

class _VariantsDemo extends StatelessWidget {
  const _VariantsDemo();

  @override
  Widget build(BuildContext context) {
    const examples = <(DBubbleVariant, DBubbleAlign, String)>[
      (
        DBubbleVariant.primary,
        DBubbleAlign.start,
        'This is the default primary bubble.',
      ),
      (
        DBubbleVariant.secondary,
        DBubbleAlign.end,
        'This is the secondary variant.',
      ),
      (
        DBubbleVariant.muted,
        DBubbleAlign.start,
        'This muted bubble has lower emphasis.',
      ),
      (
        DBubbleVariant.tinted,
        DBubbleAlign.end,
        'This tint is softly derived from primary.',
      ),
      (
        DBubbleVariant.outline,
        DBubbleAlign.start,
        'A bordered bubble for rich content.',
      ),
      (
        DBubbleVariant.destructive,
        DBubbleAlign.end,
        'Error: the command could not be run.',
      ),
    ];
    return _Frame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 36,
        children: [
          for (final example in examples)
            DBubble(
              variant: example.$1,
              align: example.$2,
              children: [DBubbleContent(child: Text(example.$3))],
            ),
          const DBubble(
            variant: DBubbleVariant.ghost,
            children: [
              DBubbleContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 8,
                  children: [
                    Text(
                      'Ghost bubbles work for assistant text and rich content.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'They are unframed and may span the full conversation row.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlignmentDemo extends StatelessWidget {
  const _AlignmentDemo();

  @override
  Widget build(BuildContext context) => const _Frame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 32,
      children: [
        DBubble(
          variant: DBubbleVariant.muted,
          children: [
            DBubbleContent(child: Text("Can you tell me what's the issue?")),
          ],
        ),
        DBubbleGroup(
          children: [
            DBubble(
              align: DBubbleAlign.end,
              children: [DBubbleContent(child: Text('You tell me!'))],
            ),
            DBubble(
              align: DBubbleAlign.end,
              children: [
                DBubbleContent(
                  child: Text('It worked yesterday. You broke it!'),
                ),
              ],
            ),
            DBubble(
              align: DBubbleAlign.end,
              children: [
                DBubbleContent(child: Text('Find the bug and fix it.')),
                DBubbleReactions(
                  align: DBubbleAlign.start,
                  semanticLabel: 'Reaction: eyes',
                  children: [Text('👀')],
                ),
              ],
            ),
          ],
        ),
        Directionality(
          textDirection: TextDirection.rtl,
          child: DBubble(
            align: DBubbleAlign.end,
            variant: DBubbleVariant.tinted,
            children: [
              DBubbleContent(
                child: Text('تنعكس محاذاة النهاية مع اتجاه القراءة.'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ActionsDemo extends StatefulWidget {
  const _ActionsDemo();

  @override
  State<_ActionsDemo> createState() => _ActionsDemoState();
}

class _ActionsDemoState extends State<_ActionsDemo> {
  String result = 'No action selected';

  void choose(BuildContext context, String value) {
    DToast.show(context, 'You selected: $value');
    setState(() => result = value);
  }

  @override
  Widget build(BuildContext context) => _Frame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 24,
      children: [
        const DBubble(
          variant: DBubbleVariant.muted,
          children: [DBubbleContent(child: Text('How can I help you today?'))],
        ),
        DBubbleGroup(
          children: [
            for (final label in [
              'I forgot my password',
              'I need help with my subscription',
              'Something else. Talk to a human.',
            ])
              DBubble(
                variant: DBubbleVariant.tinted,
                align: DBubbleAlign.end,
                children: [
                  DBubbleContent(
                    action: DBubbleContentAction.button,
                    onPressed: () => choose(context, label),
                    child: Text(label),
                  ),
                ],
              ),
            DBubble(
              variant: DBubbleVariant.outline,
              align: DBubbleAlign.end,
              children: [
                DBubbleContent(
                  action: DBubbleContentAction.link,
                  onPressed: () => choose(context, 'Help center link'),
                  semanticHint: 'Opens local example content',
                  child: const Text('Open the help center'),
                ),
              ],
            ),
          ],
        ),
        Semantics(
          liveRegion: true,
          child: Text(
            result,
            key: const ValueKey('bubble-action-result'),
            style: TextStyle(color: DTokens.of(context).mutedForeground),
          ),
        ),
      ],
    ),
  );
}

class _ReactionDemo extends StatefulWidget {
  const _ReactionDemo();

  @override
  State<_ReactionDemo> createState() => _ReactionDemoState();
}

class _ReactionDemoState extends State<_ReactionDemo> {
  bool selected = true;
  bool saving = false;
  bool failed = false;
  int count = 4;

  Future<void> toggle() async {
    if (saving) return;
    setState(() {
      saving = true;
      failed = false;
    });
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() {
      selected = !selected;
      count += selected ? 1 : -1;
      saving = false;
    });
    DToast.show(
      context,
      selected ? 'Thumbs up reaction added.' : 'Thumbs up reaction removed.',
      type: DToastType.success,
    );
  }

  @override
  Widget build(BuildContext context) => _Frame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 44,
      children: [
        const DBubble(
          variant: DBubbleVariant.muted,
          align: DBubbleAlign.end,
          children: [
            DBubbleContent(
              child: Text("I don't need tests, I know my code works."),
            ),
            DBubbleReactions(
              align: DBubbleAlign.start,
              semanticLabel: 'Reactions: thumbs up and surprised',
              children: [Text('👍'), Text('😮')],
            ),
          ],
        ),
        const DBubble(
          variant: DBubbleVariant.primary,
          align: DBubbleAlign.end,
          children: [
            DBubbleContent(child: Text('Tests passed on the first try.')),
            DBubbleReactions(
              side: DBubbleReactionSide.top,
              align: DBubbleAlign.start,
              semanticLabel: 'Reactions: party popper and clapping hands',
              children: [Text('🎉'), Text('👏')],
            ),
          ],
        ),
        DBubble(
          variant: failed ? DBubbleVariant.destructive : DBubbleVariant.muted,
          children: [
            DBubbleContent(
              child: Text(
                failed
                    ? 'Reaction failed. Try again.'
                    : 'Interactive reaction controls',
              ),
            ),
            DBubbleReactions(
              interactive: true,
              children: [
                DButton(
                  size: DButtonSize.extraSmall,
                  variant: selected
                      ? DButtonVariant.secondary
                      : DButtonVariant.ghost,
                  semanticLabel:
                      'Thumbs up, $count reactions${selected ? ', selected' : ''}',
                  loading: saving,
                  loadingSemanticLabel: 'Updating thumbs up reaction',
                  onPressed: saving ? null : toggle,
                  label: Text('👍 $count${selected ? ' ✓' : ''}'),
                ),
                const DButton(
                  size: DButtonSize.extraSmall,
                  variant: DButtonVariant.ghost,
                  onPressed: null,
                  semanticLabel: 'Fire, 2 reactions, disabled',
                  label: Text('🔥 2'),
                ),
                DButton(
                  size: DButtonSize.extraSmall,
                  variant: DButtonVariant.ghost,
                  onPressed: () {
                    setState(() => failed = !failed);
                    if (failed) {
                      DToast.show(
                        context,
                        'Could not update the reaction.',
                        type: DToastType.error,
                      );
                    }
                  },
                  invalid: failed,
                  semanticLabel: failed
                      ? 'Retry failed reaction'
                      : 'Simulate reaction failure',
                  label: Text(failed ? 'Retry !' : 'Fail'),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

const _longText =
    'The accessibility review found two focus states that were visually too subtle in dark mode.\n\n'
    'I checked the dialog, menu, and drawer paths because each one renders focusable controls inside a layered surface.\n\n'
    'The dialog and drawer are fine. The menu needs the hover and focus tokens split so keyboard focus stays visible.';

class _CollapsibleDemo extends StatefulWidget {
  const _CollapsibleDemo();

  @override
  State<_CollapsibleDemo> createState() => _CollapsibleDemoState();
}

class _CollapsibleDemoState extends State<_CollapsibleDemo> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final preview = '${_longText.substring(0, 180)}…';
    return _Frame(
      child: DCollapsible(
        open: open,
        onOpenChange: (value) => setState(() => open = value),
        child: DBubble(
          variant: DBubbleVariant.muted,
          align: DBubbleAlign.end,
          children: [
            DBubbleContent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(open ? _longText : preview),
                  DCollapsibleTrigger(
                    semanticLabel: open ? 'Show less' : 'Show more',
                    builder: (context, state) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Flexible(
                            child: Text(
                              open ? 'Show less' : 'Show more',
                              style: TextStyle(
                                color: DTokens.of(context).mutedForeground,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            open
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TooltipDemo extends StatelessWidget {
  const _TooltipDemo();

  @override
  Widget build(BuildContext context) => _Frame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        const DBubble(
          variant: DBubbleVariant.secondary,
          children: [
            DBubbleContent(child: Text('Did you remove the stale route?')),
          ],
        ),
        DBubble(
          align: DBubbleAlign.end,
          children: [
            const DBubbleContent(
              child: Text('Yes, removed it from the registry.'),
            ),
            DBubbleReactions(
              interactive: true,
              children: [
                DTooltip(
                  message: 'Read on Jan 5, 2026 at 4:32 PM',
                  child: DButton.iconOnly(
                    icon: const Icon(Icons.check, size: 14),
                    tooltip: 'Read receipt',
                    size: DButtonSize.extraSmall,
                    variant: DButtonVariant.ghost,
                    onPressed: () {},
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

class _PopoverDemo extends StatelessWidget {
  const _PopoverDemo();

  @override
  Widget build(BuildContext context) => _Frame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        const DBubble(
          align: DBubbleAlign.end,
          children: [DBubbleContent(child: Text('Run the build script.'))],
        ),
        DBubble(
          variant: DBubbleVariant.destructive,
          children: [
            const DBubbleContent(child: Text('Failed to run the command.')),
            DBubbleReactions(
              interactive: true,
              children: [
                DPopover(
                  content: const DPopoverContent(
                    semanticLabel: 'Command error details',
                    align: DPopoverAlign.start,
                    child: DPopoverHeader(
                      children: [
                        DPopoverTitle(
                          child: Text('Command failed with exit code 1'),
                        ),
                        DPopoverDescription(
                          child: Text(
                            'ENOENT: no such file or directory, open pnpm-lock.yaml',
                          ),
                        ),
                      ],
                    ),
                  ),
                  child: DPopoverTrigger(
                    builder: (context, trigger) => DButton.iconOnly(
                      icon: const Icon(Icons.info_outline, size: 14),
                      tooltip: 'Show error details',
                      size: DButtonSize.extraSmall,
                      variant: DButtonVariant.ghost,
                      hasPopup: true,
                      expanded: trigger.open,
                      focusNode: trigger.focusNode,
                      onPressed: trigger.toggle,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

class _EdgesDemo extends StatelessWidget {
  const _EdgesDemo();

  @override
  Widget build(BuildContext context) => const _Frame(
    child: Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 28,
        children: [
          DBubble(
            align: DBubbleAlign.end,
            variant: DBubbleVariant.tinted,
            children: [
              DBubbleContent(
                child: Text(
                  'هذه رسالة طويلة تلتف داخل ثمانين بالمائة من المساحة المتاحة وتحافظ على اتجاه القراءة الصحيح.',
                ),
              ),
            ],
          ),
          DBubble(
            variant: DBubbleVariant.ghost,
            children: [
              DBubbleContent(
                child: SelectableText(
                  'Ghost content remains selectable, unframed, and may use the full row for rich assistant output.',
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
