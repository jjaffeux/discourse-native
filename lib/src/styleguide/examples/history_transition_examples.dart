import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final historyTransitionExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Back and forward pages follow a touch swipe from the edge.',
  notes:
      'Open a page to populate history, then drag inward from the first or last '
      '48 pixels using touch. Travel at least 64 pixels or flick '
      'to commit; release a short drag to return. RTL mirrors both directions. '
      'A shallow parallax and soft shadow follow the front page’s edge. '
      'Forward navigation reverses that depth. History previews use bounded '
      'in-memory images; navigation previews stay ready offstage for the first '
      'reveal. Reduced motion disables page movement. '
      'Buttons remain available for keyboard, mouse and assistive technology.',
  examples: [
    StyleguideExample(
      title: 'Ordered tabs',
      description:
          'Select tabs in either direction. A short slide and crossfade indicate the tab order while the controls stay still.',
      states: const ['Tab order', 'RTL', 'Reduced motion'],
      code:
          'DHistoryTransition(history: journeyId, entry: visitId, tabIndex: selectedIndex, tabOwner: accountId, child: currentPage)',
      builder: (_) => const _TabTransitionExample(),
    ),
    StyleguideExample(
      title: 'Live navigation preview',
      description:
          'Drag inward from the left edge to reveal navigation immediately, even before its first visit. Cancel a short drag or release to open it. The preview cannot receive focus or interaction.',
      states: const ['First reveal', 'Cancel', 'Preserved state'],
      code:
          'DHistoryTransition(history: journeyId, entry: pageId, previousEntry: navigationId, previousPreview: navigation, onBack: openNavigation, child: currentPage)',
      builder: (_) => const _NavigationPreviewExample(),
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

class _NavigationPreviewExample extends StatefulWidget {
  const _NavigationPreviewExample();

  @override
  State<_NavigationPreviewExample> createState() =>
      _NavigationPreviewExampleState();
}

class _NavigationPreviewExampleState extends State<_NavigationPreviewExample> {
  final _history = Object();
  final _navigationKey = GlobalKey();
  bool _open = false;

  void _toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    final navigation = DPageSurface(
      key: _navigationKey,
      child: Center(
        child: DButton(label: const Text('Return to page'), onPressed: _toggle),
      ),
    );
    return SizedBox(
      height: 280,
      child: Column(
        spacing: DSpacing.md,
        children: [
          Expanded(
            child: DHistoryTransition(
              history: _history,
              entry: _open ? 'navigation' : 'page',
              previousEntry: _open ? null : 'navigation',
              nextEntry: _open ? 'page' : null,
              previousPreview: _open ? null : navigation,
              onBack: _open ? null : _toggle,
              onForward: _open ? _toggle : null,
              tabIndex: _open ? -1 : 0,
              tabOwner: _history,
              child: _open
                  ? navigation
                  : const DPageSurface(
                      child: Center(child: Text('Swipe to reveal navigation')),
                    ),
            ),
          ),
          DButton(
            label: Text(_open ? 'Close navigation' : 'Open navigation'),
            onPressed: _toggle,
          ),
        ],
      ),
    );
  }
}

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
