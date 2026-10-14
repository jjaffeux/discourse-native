import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final pageSurfaceExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'The shared page frame, tabs, reading width and scroll header.',
  notes:
      'DPageSurface owns the Card border and clipping, persistent tabs and footer, '
      'and the retracting header. Scroll distance moves one continuous target; '
      '40ms smoothing follows it once per frame. Reversals consume 40px slack. '
      'Pages shorter than twice the viewport keep the header visible. '
      'This also works in reversed chat lists. Reaching the top reveals it. '
      'revealHeaderAtEnd also reveals it at the physical bottom and keeps it '
      'visible through viewport changes until scrolling back up. '
      'Focused header controls remain visible. '
      'Inside DScrollChrome, mobile headers share the footer’s visibility and '
      'progress. Wrap paginated viewports in DScrollChromePagination with their '
      'hasMore and loading state. Temporary bottom boundaries keep the chrome '
      'compact through requests and appended rows; upward scrolling still reveals '
      'it. Only a completed feed reveals at the bottom. For reversed chat lists, '
      'report newer paging at the visual bottom. Fully shown or hidden chrome '
      'holds for 400ms; after a 120ms '
      'pause a partial header settles in the last accepted direction. '
      'DHeaderMotionSettings selects the settling rule, threshold and timing. '
      'The first 48px and content shorter than two screens stay visible. '
      'headerControls places a persistent bar below a retracting title and '
      'reserves the full header space so the body does not move. '
      'scrollBody owns the scroll view and lets rows pass through the title’s '
      'former space below the control bar. Give it non-scrolling content. '
      'DPageSurface.scrollable keeps an existing virtualized viewport fixed; '
      'insert header.spacer at the start of its scroll content. '
      'headerSuppressed accepts a caller-owned boolean listenable: it yields the '
      'title, controls and obstruction over 240ms while retaining the spacer, '
      'and restores the scroll position on release. Reduced motion is immediate. '
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
      title: 'Yield the header',
      description:
          'An end panel can own the viewport without moving its scroll spacer.',
      states: const ['Visible', 'Suppressed', 'Restored', 'Reduced motion'],
      code: """DPageSurface.scrollable(
  headerSuppressed: covered,
  header: title,
  bodyBuilder: (_, header) => CustomScrollView(slivers: [
    SliverToBoxAdapter(child: header.spacer), content,
  ]),
)""",
      builder: (_) => const _SuppressedHeaderExample(),
    ),

    StyleguideExample(
      title: 'Mobile navigation',
      description:
          'Scroll forward to move both bars together. Reverse past the slack '
          'to reveal them, or stop partway to let them settle.',
      states: const ['Partial scroll', 'Settle', 'Reverse', 'Reduced motion'],
      code: """DScrollChrome(
  identity: pageId,
  footerBuilder: (_) => navigation,
  child: DScrollChromePagination(
    hasMore: feed.hasMore,
    loading: feed.loadingMore,
    child: DPageSurface.scrollable(
      hideHeaderOnScroll: true,
      header: title,
      bodyBuilder: (_, header) => CustomScrollView(
        slivers: [SliverToBoxAdapter(child: header.spacer), rows],
      ),
    ),
  ),
)""",
      builder: (_) => SizedBox(
        height: 460,
        child: DScrollChrome(
          identity: 'mobile-preview',
          footerBuilder: (_) => Padding(
            padding: const EdgeInsets.all(DSpacing.sm),
            child: DButton(label: const Text('Navigation'), onPressed: () {}),
          ),
          child: DPageSurface.scrollable(
            framed: false,
            hideHeaderOnScroll: true,
            header: const Padding(
              padding: EdgeInsets.all(DSpacing.lg),
              child: Text('Reading a topic'),
            ),
            bodyBuilder: (_, header) => CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: header.spacer),
                SliverList.builder(
                  itemCount: 100,
                  itemBuilder: (_, index) => Padding(
                    padding: const EdgeInsets.all(DSpacing.lg),
                    child: Text('Post ${index + 1}'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
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
      code:
          "DPageSurface(\n  hideHeaderOnScroll: true,\n  revealHeaderAtEnd: true,\n  \n  identity: selectedPage,\n  limitContentSize: limited,\n  tabs: tabs,\n  header: header,\n  headerControls: controls,\n  footer: footer,\n  child: DPageReadingLaneBox(\n    child: Column(children: rows),\n  ),\n)",
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
    child: SingleChildScrollView(
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
    ),
  );
}

class _SuppressedHeaderExample extends StatefulWidget {
  const _SuppressedHeaderExample();
  @override
  State<_SuppressedHeaderExample> createState() =>
      _SuppressedHeaderExampleState();
}

class _SuppressedHeaderExampleState extends State<_SuppressedHeaderExample> {
  final covered = ValueNotifier(false);
  @override
  void dispose() {
    covered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 260,
    child: DPageSurface.scrollable(
      headerSuppressed: covered,
      header: const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Topic title'),
      ),
      bodyBuilder: (_, header) => CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: header.spacer),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DButton(
                label: const Text('Toggle header'),
                onPressed: () => covered.value = !covered.value,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
