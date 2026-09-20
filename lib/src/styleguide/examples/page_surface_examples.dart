import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final pageSurfaceExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'The shared page frame, tabs, reading width and scroll header.',
  notes:
      'DPageSurface owns the Card border and clipping, persistent tabs and footer, '
      'and the retracting header. The header follows scroll distance down and up '
      'without easing, including in reversed chat lists. Reaching the top reveals it. '
      'Focused header controls remain visible. '
      'Programmatic restoration and '
      'nested or horizontal scrolling do not retract it. Changing identity resets '
      'the header. Use framed: false inside an existing page frame or touch shell. '
      'DPageReadingLane supplies padding inside a full-width viewport; its width '
      'policy inherits from the page. This app composition is separate from the '
      'frozen upstream catalogue.',
  examples: [
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
  identity: selectedPage,
  limitContentSize: limited,
  tabs: tabs,
  header: header,
  footer: footer,
  child: DPageReadingLane(
    builder: (context, lane) => ListView.builder(
      padding: lane.padding,
      itemCount: 100,
      itemBuilder: buildRow,
    ),
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
    header: DPageReadingLaneBox(
      padding: const EdgeInsets.all(DSpacing.lg),
      child: Text(_page, style: Theme.of(context).textTheme.titleLarge),
    ),
    footer: DCardFooter(
      rounded: true,
      child: DToggle(
        pressed: _limited,
        onPressedChanged: (value) => setState(() => _limited = value),
        child: const Text('Limit content width'),
      ),
    ),
    child: DPageReadingLane(
      basePadding: const EdgeInsets.symmetric(horizontal: DSpacing.lg),
      builder: (context, lane) => ListView.builder(
        key: ValueKey(_page),
        padding: lane.padding,
        itemCount: 100,
        itemBuilder: (_, index) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: DSpacing.lg),
              child: Text('$_page · ${index + 1}'),
            ),
            const DSeparator(),
          ],
        ),
      ),
    ),
  );
}
