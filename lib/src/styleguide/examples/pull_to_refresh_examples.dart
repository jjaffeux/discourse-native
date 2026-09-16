import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final pullToRefreshExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Refresh a list by pulling down from its top edge.',
  notes:
      'The Native spinner follows Flutter’s refresh gesture lifecycle. '
      'Use AlwaysScrollableScrollPhysics for short and empty lists. '
      'The child retains its scroll controller. A null callback disables refresh; '
      'the caller handles request errors. A screen-reader Refresh action is '
      'available, and reduced motion keeps the spinner stationary.',
  examples: [
    for (final (title, count) in [
      ('Topics', 20),
      ('Short list', 2),
      ('Empty list', 0),
      ('Disabled', 4),
    ])
      StyleguideExample(
        title: title,
        description: title == 'Disabled'
            ? 'This list scrolls but cannot refresh.'
            : 'Pull down at the top and release. The request completes after one second.',
        states: [title, 'Loading', 'Reduced motion'],
        code:
            '''DPullToRefresh(
  onRefresh: ${title == 'Disabled' ? 'null' : 'reloadTopics'},
  child: ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: topics,
  ),
)''',
        builder: (_) =>
            _RefreshExample(count: count, enabled: title != 'Disabled'),
      ),
  ],
);

class _RefreshExample extends StatefulWidget {
  const _RefreshExample({required this.count, required this.enabled});
  final int count;
  final bool enabled;

  @override
  State<_RefreshExample> createState() => _RefreshExampleState();
}

class _RefreshExampleState extends State<_RefreshExample> {
  int _refreshes = 0;

  Future<void> _refresh() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    if (mounted) setState(() => _refreshes++);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 280,
    child: DPullToRefresh(
      onRefresh: widget.enabled ? _refresh : null,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(DSpacing.md),
        children: [
          Text('Refreshed $_refreshes times'),
          const SizedBox(height: DSpacing.md),
          if (widget.count == 0)
            const DEmpty(
              children: [
                DEmptyHeader(children: [DEmptyTitle('No topics yet')]),
              ],
            ),
          for (var i = 1; i <= widget.count; i++)
            DItem(
              children: [
                DItemContent(children: [DItemTitle(child: Text('Topic $i'))]),
              ],
            ),
        ],
      ),
    ),
  );
}
