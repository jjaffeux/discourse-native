import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final pageSurfaceExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'The shared page frame, tabs, reading width and scroll header.',
  notes:
      'Use DPageSurface.headed for route titles and persistent controls. '
      'The kit owns 22px title typography, platform spacing and the 14px soft scroll edge. '
      'Titles retract on downward input and return on upward input or at the top. '
      'The first 48px and pages with less than 120px of overflow keep their title. '
      'foldTitleAtTop keeps indexed directories compact away from the top. '
      'bodyBuilder retains a fixed viewport. Reserve header.spacer in its content, '
      'or use DPageScrollInsets for list padding. child retains a bounded body. '
      'adaptiveBodyBuilder keeps directories lazy while the full heading fits and '
      'scrolls the whole page when the keyboard leaves too little room. '
      'DScrollChrome couples mobile headers and navigation. DScrollChromePagination '
      'keeps temporary page boundaries compact while another page loads. '
      'Motion uses 40ms smoothing, 40px reversal slack, a 400ms endpoint hold and '
      'a 120ms settling pause. DHeaderMotionSettings supplies account preferences. '
      'Nested and horizontal scrolling do not retract the heading. Identity changes '
      'reset it. Hidden titles leave focus, semantics and pointer hit testing together. '
      'Specialized readers use DPageSurface.scrollable for custom compact headers '
      'or headerSuppressed. Their full spacer stays reserved and their existing '
      'two-viewport short-content policy remains. '
      'DPageSurface also supplies the outer frame, tabs and footer. Its width policy '
      'centers the heading and content together. Tabs and the viewport stay full width.',
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
    child: DPageSurface.headed(
      title: title,
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
          child: DPageSurface.headed(
            title: const Text('Reading a topic'),
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
      code: '''DPageSurface.headed(
  title: title,
  bodyBuilder: (context, header) => CustomScrollView(
    slivers: [
      SliverToBoxAdapter(child: header.spacer),
      postSliver,
    ],
  ),
)''',
      builder: (_) => SizedBox(
        height: 460,
        child: DPageSurface.headed(
          title: const Text('Topic'),
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
      code: """DPageSurface.headed(
  identity: selectedPage,
  limitContentSize: limited,
  title: Text(selectedPage),
  controls: controls,
  footer: footer,
  child: scrollingBody,
)""",
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
  Widget build(BuildContext context) => DPageSurface.headed(
    identity: _page,
    limitContentSize: _limited,
    title: Text(_page),
    controls: DControlWrap(
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
