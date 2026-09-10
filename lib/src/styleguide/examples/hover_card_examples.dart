import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final hoverCardExamples = ComponentExamples(
  description: 'Shows a supplementary visual preview for a destination.',
  status: ComponentStatus.implemented,
  notes:
      'Frozen source: Base UI Hover Card Markdown SHA-256 '
      '8f30193c745aaf270cdf63043ca452cdffb895e8643a86c662ca0804c6022dc8 '
      'and base-nova hover-card registry. Composition is DHoverCard(trigger: '
      'DHoverCardTrigger(...), content: DHoverCardContent(...)). The 256px '
      'popover surface has 10px padding, a 4px side and alignment offset, '
      'host-relative lg radius, 14/20 text and a 100ms fade/95% scale/8px '
      'directional transition. Hover waits 600ms and closes after 300ms by '
      'default; keyboard focus opens immediately. Per Base UI accessibility '
      'guidance, content is supplementary, excluded from focus and screen '
      'reader navigation, and is not opened on touch. The composed trigger '
      'retains its real navigation/action, while visible text remains '
      'selectable and pointer travel across the gap retains the card. '
      'DHoverCardGroup<T> covers the Base UI API-reference case where one '
      'root and surface are shared by multiple strongly typed payload triggers.',
  examples: [
    StyleguideExample(
      title: 'Basic',
      description:
          'Hover the link-style button or focus it with the keyboard. The '
          'trigger action remains independent from the visual preview.',
      states: const ['Hover', 'Keyboard focus', 'Escape', 'Link trigger'],
      code: '''DHoverCard(
  trigger: DHoverCardTrigger(
    delay: const Duration(milliseconds: 10),
    closeDelay: const Duration(milliseconds: 100),
    builder: (context, state) => DButton(
      label: const Text('Hover Here'),
      variant: DButtonVariant.link,
      isLink: true,
      focusNode: state.focusNode,
      onPressed: openDestination,
    ),
  ),
  content: const DHoverCardContent(child: NextJsPreview()),
)''',
      builder: (_) => const _BasicHoverCard(),
    ),
    StyleguideExample(
      title: 'Composition',
      description:
          'The root composes one trigger and one content surface. Avatar is '
          'real library content; identity and navigation stay on the trigger.',
      states: const ['Avatar', 'Rich composition', 'Selectable text'],
      code: '''DHoverCard(
  trigger: DHoverCardTrigger(builder: buildProfileLink),
  content: DHoverCardContent(child: Row(children: [
    DAvatar(fallback: DAvatarFallback(child: Text('SC'))),
    Expanded(child: Column(children: [Text('@alex'), Text('Design systems')])),
  ])),
)''',
      builder: (_) => const _AvatarHoverCard(),
    ),
    StyleguideExample(
      title: 'Trigger delays',
      description:
          'This trigger uses the documented 100ms open and 200ms close '
          'delays. Crossing the four-pixel gap does not flicker.',
      states: const ['100ms open', '200ms close', 'Gap travel'],
      code: '''DHoverCardTrigger(
  delay: const Duration(milliseconds: 100),
  closeDelay: const Duration(milliseconds: 200),
  builder: buildTrigger,
)''',
      builder: (_) => const _SimpleHoverCard(
        label: 'Timed preview',
        body: 'Opens after 100ms and closes after 200ms.',
        delay: Duration(milliseconds: 100),
        closeDelay: Duration(milliseconds: 200),
      ),
    ),
    StyleguideExample(
      title: 'Positioning',
      description:
          'Top/start placement uses logical alignment and collision correction '
          'inside the preview viewport.',
      states: const ['Top', 'Start alignment', 'Collision'],
      code: '''const DHoverCardContent(
  side: DPopoverSide.top,
  align: DPopoverAlign.start,
  child: Text('Top/start content'),
)''',
      builder: (_) => const Padding(
        padding: EdgeInsets.only(top: 84),
        child: _SimpleHoverCard(
          label: 'Top and start',
          body: 'This card prefers the top/start of its trigger.',
          side: DPopoverSide.top,
          align: DPopoverAlign.start,
        ),
      ),
    ),
    StyleguideExample(
      title: 'Sides',
      description:
          'Each outline trigger requests the matching physical side. Cards '
          'flip or shift only when the viewport cannot fit that request.',
      states: const ['Left', 'Top', 'Bottom', 'Right'],
      code: '''for (final side in const [
  DPopoverSide.left, DPopoverSide.top,
  DPopoverSide.bottom, DPopoverSide.right,
]) DHoverCard(content: DHoverCardContent(side: side, child: ...), trigger: ...)''',
      builder: (_) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 84),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _SideHoverCard(label: 'left', side: DPopoverSide.left),
            _SideHoverCard(label: 'top', side: DPopoverSide.top),
            _SideHoverCard(label: 'bottom', side: DPopoverSide.bottom),
            _SideHoverCard(label: 'right', side: DPopoverSide.right),
          ],
        ),
      ),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'Arabic physical sides remain physical. Inline start/end resolve '
          'from the ambient RTL direction, including alignment offsets.',
      states: const [
        'Arabic',
        'RTL',
        'Physical sides',
        'Inline start',
        'Inline end',
      ],
      code: '''Directionality(
  textDirection: TextDirection.rtl,
  child: DHoverCard(
    content: DHoverCardContent(side: DPopoverSide.inlineStart, child: ...),
    trigger: DHoverCardTrigger(builder: buildArabicButton),
  ),
)''',
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 84),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _RtlHoverCard(label: 'يسار', side: DPopoverSide.left),
              _RtlHoverCard(label: 'أعلى', side: DPopoverSide.top),
              _RtlHoverCard(label: 'أسفل', side: DPopoverSide.bottom),
              _RtlHoverCard(label: 'يمين', side: DPopoverSide.right),
              _RtlHoverCard(
                label: 'بداية السطر',
                side: DPopoverSide.inlineStart,
              ),
              _RtlHoverCard(label: 'نهاية السطر', side: DPopoverSide.inlineEnd),
            ],
          ),
        ),
      ),
    ),
    StyleguideExample(
      title: 'Multiple triggers and payloads',
      description:
          'One root owns both destination triggers. Moving between them while '
          'open immediately moves the shared preview and swaps typed content.',
      states: const [
        'Multiple triggers',
        'Typed payload',
        'Rapid handoff',
        'Shared root',
      ],
      code: '''DHoverCardGroup<Destination>(
  items: destinations.map((destination) => DHoverCardGroupItem(
    id: destination.id,
    payload: destination,
    builder: (context, state) => DButton(
      focusNode: state.focusNode,
      label: Text(destination.label),
      onPressed: () => open(destination),
    ),
  )).toList(),
  builder: (context, triggers) => Wrap(children: triggers),
  contentBuilder: (context, destination) =>
      DHoverCardContent(child: Text(destination.summary)),
)''',
      builder: (_) => const _PayloadHoverCardGroup(),
    ),
    StyleguideExample(
      title: 'Controlled and controller',
      description:
          'The first preview is parent-controlled and reports the reason. The '
          'second uses a borrowed controller for an explicit visual preview.',
      states: const ['Controlled', 'Controller', 'Lifecycle', 'Disabled'],
      code: '''DHoverCard(
  open: open,
  onOpenChange: (value, reason) => setState(() => open = value),
  trigger: DHoverCardTrigger(builder: buildTrigger),
  content: const DHoverCardContent(child: Text('Controlled preview')),
)''',
      builder: (_) => const _ControlledHoverCards(),
    ),
  ],
);

class _BasicHoverCard extends StatelessWidget {
  const _BasicHoverCard();

  @override
  Widget build(BuildContext context) => DHoverCard(
    trigger: DHoverCardTrigger(
      delay: const Duration(milliseconds: 10),
      closeDelay: const Duration(milliseconds: 100),
      builder: (context, state) => DButton(
        label: const Text('Hover Here'),
        variant: DButtonVariant.link,
        isLink: true,
        focusNode: state.focusNode,
        onPressed: () {},
      ),
    ),
    content: const DHoverCardContent(child: _NextJsPreview()),
  );
}

class _NextJsPreview extends StatelessWidget {
  const _NextJsPreview();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 2,
    children: [
      const Text('@nextjs', style: TextStyle(fontWeight: FontWeight.w600)),
      const Text('The React Framework – created and maintained by @vercel.'),
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          'Joined December 2021',
          style: TextStyle(
            color: DTokens.of(context).mutedForeground,
            fontSize: 12,
            height: 16 / 12,
          ),
        ),
      ),
    ],
  );
}

class _AvatarHoverCard extends StatelessWidget {
  const _AvatarHoverCard();

  @override
  Widget build(BuildContext context) => DHoverCard(
    trigger: DHoverCardTrigger(
      builder: (context, state) => DButton(
        label: const Text('@alex'),
        variant: DButtonVariant.link,
        isLink: true,
        focusNode: state.focusNode,
        onPressed: () {},
      ),
    ),
    content: const DHoverCardContent(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          DAvatar(
            size: DAvatarSize.lg,
            decorative: true,
            fallback: DAvatarFallback(child: Text('SC')),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text('@alex', style: TextStyle(fontWeight: FontWeight.w600)),
                Text('Design systems and open-source interface components.'),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _SimpleHoverCard extends StatelessWidget {
  const _SimpleHoverCard({
    required this.label,
    required this.body,
    this.delay = const Duration(milliseconds: 10),
    this.closeDelay = const Duration(milliseconds: 100),
    this.side = DPopoverSide.bottom,
    this.align = DPopoverAlign.center,
  });

  final String label;
  final String body;
  final Duration delay;
  final Duration closeDelay;
  final DPopoverSide side;
  final DPopoverAlign align;

  @override
  Widget build(BuildContext context) => DHoverCard(
    trigger: DHoverCardTrigger(
      delay: delay,
      closeDelay: closeDelay,
      builder: (context, state) => DButton(
        label: Text(label),
        variant: DButtonVariant.outline,
        focusNode: state.focusNode,
        onPressed: () {},
      ),
    ),
    content: DHoverCardContent(side: side, align: align, child: Text(body)),
  );
}

class _SideHoverCard extends StatelessWidget {
  const _SideHoverCard({required this.label, required this.side});

  final String label;
  final DPopoverSide side;

  @override
  Widget build(BuildContext context) => DHoverCard(
    trigger: DHoverCardTrigger(
      delay: const Duration(milliseconds: 100),
      closeDelay: const Duration(milliseconds: 100),
      builder: (context, state) => DButton(
        label: Text(label),
        variant: DButtonVariant.outline,
        focusNode: state.focusNode,
        onPressed: () {},
      ),
    ),
    content: DHoverCardContent(
      side: side,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          const Text(
            'Hover Card',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          Text('This hover card appears on the $label side of the trigger.'),
        ],
      ),
    ),
  );
}

class _RtlHoverCard extends StatelessWidget {
  const _RtlHoverCard({required this.label, required this.side});

  final String label;
  final DPopoverSide side;

  @override
  Widget build(BuildContext context) => DHoverCard(
    trigger: DHoverCardTrigger(
      delay: const Duration(milliseconds: 10),
      closeDelay: const Duration(milliseconds: 100),
      builder: (context, state) => DButton(
        label: Text(label),
        variant: DButtonVariant.outline,
        focusNode: state.focusNode,
        onPressed: () {},
      ),
    ),
    content: DHoverCardContent(
      side: side,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          const Text(
            'سماعات لاسلكية',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            r'٩٩.٩٩ $',
            style: TextStyle(color: DTokens.of(context).mutedForeground),
          ),
        ],
      ),
    ),
  );
}

class _PayloadDestination {
  const _PayloadDestination(this.id, this.label, this.summary);

  final String id;
  final String label;
  final String summary;
}

class _PayloadHoverCardGroup extends StatelessWidget {
  const _PayloadHoverCardGroup();

  static const destinations = [
    _PayloadDestination(
      'typography',
      'Typography',
      'Clear, readable type systems for interfaces and long-form content.',
    ),
    _PayloadDestination(
      'design',
      'Design',
      'Intentional visual and interaction choices for useful products.',
    ),
    _PayloadDestination(
      'art',
      'Art',
      'Creative work shaped by imagination, craft, and expression.',
    ),
  ];

  @override
  Widget build(BuildContext context) => DHoverCardGroup<_PayloadDestination>(
    items: [
      for (final destination in destinations)
        DHoverCardGroupItem(
          id: destination.id,
          payload: destination,
          delay: const Duration(milliseconds: 100),
          closeDelay: const Duration(milliseconds: 150),
          builder: (context, state) => DButton(
            label: Text(destination.label),
            variant: DButtonVariant.link,
            isLink: true,
            focusNode: state.focusNode,
            onPressed: () {},
          ),
        ),
    ],
    builder: (context, triggers) => Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: triggers,
    ),
    contentBuilder: (context, destination) => DHoverCardContent(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          Text(
            destination.label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(destination.summary),
        ],
      ),
    ),
  );
}

class _ControlledHoverCards extends StatefulWidget {
  const _ControlledHoverCards();

  @override
  State<_ControlledHoverCards> createState() => _ControlledHoverCardsState();
}

class _ControlledHoverCardsState extends State<_ControlledHoverCards> {
  final DHoverCardController _controller = DHoverCardController();
  bool _open = false;
  DHoverCardChangeReason? _reason;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      DHoverCard(
        open: _open,
        onOpenChange: (value, reason) => setState(() {
          _open = value;
          _reason = reason;
        }),
        trigger: DHoverCardTrigger(
          delay: const Duration(milliseconds: 10),
          builder: (context, state) => DButton(
            label: const Text('Controlled'),
            variant: DButtonVariant.outline,
            focusNode: state.focusNode,
            onPressed: () {},
          ),
        ),
        content: const DHoverCardContent(child: Text('Controlled preview')),
      ),
      Text(_reason == null ? 'No change yet' : 'Reason: ${_reason!.name}'),
      DHoverCard(
        controller: _controller,
        trigger: DHoverCardTrigger(
          builder: (context, state) => DButton(
            label: const Text('Controller target'),
            variant: DButtonVariant.outline,
            focusNode: state.focusNode,
            onPressed: () {},
          ),
        ),
        content: const DHoverCardContent(child: Text('Controller preview')),
      ),
      DButton(
        label: const Text('Open preview'),
        variant: DButtonVariant.secondary,
        onPressed: _controller.open,
      ),
    ],
  );
}
