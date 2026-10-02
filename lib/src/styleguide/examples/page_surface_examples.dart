import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final pageSurfaceExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'The shared page frame, tabs, reading width and scroll header.',
  notes:
      'DPageSurface owns the Card border and clipping, persistent tabs and footer, '
      'and the retracting header. A few pixels animate the header down or up; '
      'hiding requires scroll speed, so slow reads keep the controls visible. '
      'This also works in reversed chat lists. Reaching the top reveals it. '
      'revealHeaderAtEnd also reveals it at the physical bottom and keeps it '
      'visible through viewport changes until scrolling back up. '
      'Focused header controls remain visible. '
      'headerControls places a persistent bar below a retracting title and '
      'reserves the full header space so the body does not move. '
      'scrollBody owns the scroll view and lets rows pass through the title’s '
      'former space below the control bar. Give it non-scrolling content. '
      'DPageSurface.scrollable keeps an existing virtualized viewport fixed; '
      'insert header.spacer at the start of its scroll content. '
      'Programmatic restoration and '
      'nested or horizontal scrolling do not retract it. Changing identity resets '
      'the header. Use framed: false inside an existing page frame or touch shell. '
      'Use border: false to retain the rounded surface without an outer outline. '
      'backgroundColor changes the frame fill without changing descendant tokens. '
      'The width setting centers the header, scroll body, and footer together; '
      'tabs and the outer frame stay full width. DPageReadingLane adds optional '
      'padding inside that shared column. This app composition is separate from the '
      'frozen upstream catalogue.',
  examples: [
    StyleguideExample(
      title: 'Virtualized body',
      description:
          'The header slides over a fixed viewport. Its leading spacer keeps '
          'the first row below the header without moving rows during animation.',
      states: const ['Scroll', 'Keyboard', 'RTL'],
      code: '''DPageSurface.scrollable(
  hideHeaderOnScroll: true,
  header: header,
  bodyBuilder: (context, header) => CustomScrollView(
    slivers: [
      SliverToBoxAdapter(child: header.spacer),
      postSliver,
    ],
  ),
)''',
      builder: (_) => SizedBox(
        height: 460,
        child: DPageSurface.scrollable(
          hideHeaderOnScroll: true,
          header: const Padding(
            padding: EdgeInsets.all(DSpacing.lg),
            child: Text('Topic'),
          ),
          bodyBuilder: (_, header) => CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: header.spacer),
              SliverList.builder(
                itemCount: 100,
                itemBuilder: (_, index) => DPageReadingLaneBox(
                  child: Padding(
                    padding: const EdgeInsets.all(DSpacing.lg),
                    child: Text('Post ${index + 1}'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    StyleguideExample(
      title: 'Page structure',
      description:
          'Scroll in either direction, switch pages, and toggle the width limit. '
          'The tabs and footer remain visible. Widen the preview beyond 825px '
          'to compare full-width and limited content.',
      states: const [
        'Full width',
        'Limited width',
        'Scroll',
        'Keyboard',
        'RTL',
      ],
      code: '''DPageSurface(
  hideHeaderOnScroll: true,
  revealHeaderAtEnd: true,
  scrollBody: true,
  identity: selectedPage,
  limitContentSize: limited,
  tabs: tabs,
  header: header,
  headerControls: controls,
  footer: footer,
  child: DPageReadingLaneBox(
    child: Column(children: rows),
  ),
)''',
      builder: (_) => const SizedBox(height: 460, child: _PageExample()),
    ),
  ],
);

class _PageExample extends StatefulWidget {
  const _PageExample();
  @override
  State<_PageExample> createState() => _PageExampleState();
}

class _PageExampleState extends State<_PageExample> {
  bool _limited = false;
  String _page = 'Topics';

  @override
  Widget build(BuildContext context) => DPageSurface(
    hideHeaderOnScroll: true,
    revealHeaderAtEnd: true,
    scrollBody: true,
    identity: _page,
    limitContentSize: _limited,
    tabs: DTabs<String>.controlled(
      value: _page,
      onChanged: (page) {
        if (page != null) setState(() => _page = page);
      },
      children: const [
        DTabList<String>(
          children: [
            DTabTrigger(value: 'Topics', child: Text('Topics')),
            DTabTrigger(value: 'Topic', child: Text('Topic')),
          ],
        ),
      ],
    ),
    header: Padding(
      padding: const EdgeInsets.all(DSpacing.lg),
      child: Text(_page, style: Theme.of(context).textTheme.titleLarge),
    ),
    headerControls: Padding(
      padding: const EdgeInsets.symmetric(horizontal: DSpacing.lg),
      child: DControlWrap(
        children: [
          DButton(
            size: DButtonSize.filter,
            label: const Text('Browse topics'),
            onPressed: () => setState(() => _page = 'Topics'),
          ),
          DButton(
            size: DButtonSize.filter,
            label: const Text('Open topic'),
            onPressed: () => setState(() => _page = 'Topic'),
          ),
        ],
      ),
    ),
    footer: DCardFooter(
      rounded: true,
      child: DToggle(
        pressed: _limited,
        onPressedChanged: (value) => setState(() => _limited = value),
        child: const Text('Limit content width'),
      ),
    ),
    child: DPageReadingLaneBox(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DSpacing.lg),
        child: Column(
          key: ValueKey(_page),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < 100; index++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: DSpacing.lg),
                child: Text('$_page · ${index + 1}'),
              ),
              const DSeparator(),
            ],
          ],
        ),
      ),
    ),
  );
}
