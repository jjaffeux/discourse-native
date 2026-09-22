import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final historyTransitionExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Back and forward pages follow a touch swipe from the edge.',
  notes:
      'Open a page to populate history, then drag inward from the first or last '
      '24 pixels using touch. Release past one quarter of the width or flick '
      'to commit; release a short drag to return. RTL mirrors both directions. '
      'The page underneath brightens as it is revealed, while a soft shadow '
      'follows the front page’s edge. Forward navigation reverses that depth. '
      'Only the current page stays live: previews use bounded in-memory images '
      'of recently visited pages. Reduced motion disables page movement. '
      'Buttons remain available for keyboard, mouse and assistive technology.',
  examples: [
    StyleguideExample(
      title: 'Ordered tabs',
      description:
          'Select tabs in either direction. The destination pushes the previous card toward the opposite edge, including its border and rounded corners; the controls stay still.',
      states: const ['Tab order', 'RTL', 'Reduced motion'],
      code:
          'DHistoryTransition(history: journeyId, entry: visitId, tabIndex: selectedIndex, tabOwner: accountId, child: currentPage)',
      builder: (_) => const _TabTransitionExample(),
    ),
    for (final direction in TextDirection.values)
      StyleguideExample(
        title: direction == TextDirection.ltr ? 'Back and forward' : 'RTL',
        description:
            'Open Topics, then a Topic. Touch-drag from either edge to navigate '
            'or cancel. The count changes only after a committed swipe.',
        states: const ['Touch', 'Cancel', 'History limits', 'Reduced motion'],
        code: '''DHistoryTransition(
  history: journeyId,
  entry: currentVisitId,
  previousEntry: previousVisitId,
  nextEntry: nextVisitId,
  onBack: goBack,
  onForward: goForward,
  child: currentPage,
)''',
        builder: (_) => Directionality(
          textDirection: direction,
          child: const _HistoryExample(),
        ),
      ),
  ],
);

class _HistoryExample extends StatefulWidget {
  const _HistoryExample();

  @override
  State<_HistoryExample> createState() => _HistoryExampleState();
}

class _HistoryExampleState extends State<_HistoryExample> {
  static const _pages = ['Home', 'Topics', 'A topic'];
  final _history = Object();
  int _index = 0;
  int _furthest = 0;
  int _visits = 0;

  void _visit(int index) => setState(() {
    _index = index;
    if (index > _furthest) _furthest = index;
    _visits++;
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 320,
    child: DHistoryTransition(
      history: _history,
      entry: _index,
      previousEntry: _index > 0 ? _index - 1 : null,
      nextEntry: _index < _furthest ? _index + 1 : null,
      onBack: _index > 0 ? () => _visit(_index - 1) : null,
      onForward: _index < _furthest ? () => _visit(_index + 1) : null,
      child: DCard(
        child: DCardContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DSpacing.md,
            children: [
              DText(_pages[_index], variant: DTextVariant.h3),
              Text('$_visits completed navigations'),
              const Text('Drag inward from an edge to preview another page.'),
              Wrap(
                spacing: DSpacing.controlGap,
                runSpacing: DSpacing.controlGap,
                children: [
                  DButton(
                    onPressed: _index > 0 ? () => _visit(_index - 1) : null,
                    label: const Text('Back'),
                  ),
                  DButton(
                    onPressed: _index < _furthest
                        ? () => _visit(_index + 1)
                        : null,
                    label: const Text('Forward'),
                  ),
                  if (_index < _pages.length - 1)
                    DButton(
                      onPressed: () => _visit(_index + 1),
                      label: Text('Open ${_pages[_index + 1]}'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TabTransitionExample extends StatefulWidget {
  const _TabTransitionExample();
  @override
  State<_TabTransitionExample> createState() => _TabTransitionExampleState();
}

class _TabTransitionExampleState extends State<_TabTransitionExample> {
  static const _tabs = ['Topics', 'Chat', 'Messages', 'Users'];
  int _index = 0;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 280,
    child: Column(
      children: [
        Expanded(
          child: DHistoryTransition(
            history: _index,
            entry: _index,
            tabIndex: _index,
            tabOwner: 'example',
            child: DCard(
              child: DCardContent(
                child: Center(
                  child: DText(
                    '${_tabs[_index]} page',
                    variant: DTextVariant.h3,
                  ),
                ),
              ),
            ),
          ),
        ),
        Wrap(
          spacing: DSpacing.controlGap,
          children: [
            for (final (index, label) in _tabs.indexed)
              DButton(
                label: Text(label),
                variant: index == _index
                    ? DButtonVariant.primary
                    : DButtonVariant.outline,
                onPressed: () => setState(() => _index = index),
              ),
          ],
        ),
      ],
    ),
  );
}
