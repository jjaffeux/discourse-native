import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final breadcrumbExamples = ComponentExamples(
  topLevelExampleIndex: 7,
  status: ComponentStatus.implemented,
  description: 'Compact, composable paths to the current resource.',
  notes:
      'Matches the frozen Base UI/base-nova Breadcrumb: 14/20 type, 6px list '
      'gap, 4px item gap, 14px logical chevrons and a 20px ellipsis. Links '
      'own focus, link semantics and caller callbacks; the selected disabled '
      'page is current. Separators and ellipses are decorative. Wrapping is '
      'the reference default; horizontal scrolling is an explicit native '
      'option for paths that must remain intact. Dropdown examples compose '
      'the shared Dropdown Menu owner and restore focus to their triggers.',
  examples: [
    StyleguideExample(
      title: 'Basic',
      description:
          'Tab through the ancestor links; Return, Space, or a pointer activates the local route callback.',
      code: '''DBreadcrumb(
  child: DBreadcrumbList(children: [
    DBreadcrumbItem(child: DBreadcrumbLink(onPressed: openHome, child: Text('Home'))),
    DBreadcrumbSeparator(),
    DBreadcrumbItem(child: DBreadcrumbLink(onPressed: openComponents, child: Text('Components'))),
    DBreadcrumbSeparator(),
    DBreadcrumbItem(child: DBreadcrumbPage(child: Text('Breadcrumb'))),
  ]),
)''',
      builder: (_) => const _BasicBreadcrumb(),
    ),
    StyleguideExample(
      title: 'Custom separator',
      description:
          'Any widget can replace the directional chevron. The dot remains hidden from accessibility clients.',
      code: '''DBreadcrumbSeparator(
  child: Icon(Icons.circle, size: 4),
)''',
      builder: (_) => const _CustomSeparatorBreadcrumb(),
    ),
    StyleguideExample(
      title: 'Dropdown',
      description:
          'A breadcrumb level can open a start-aligned menu. Use arrows, Home/End or typeahead, then Escape to restore trigger focus.',
      code: '''DDropdownMenu(
  content: DDropdownMenuContent(
    align: DPopoverAlign.start,
    children: [DDropdownMenuItem(onPressed: openDocs, child: Text('Documentation'))],
  ),
  child: DDropdownMenuTrigger(
    builder: (context, state) => DButton(
      label: Text('Components'), hasPopup: true, expanded: state.open,
      focusNode: state.focusNode, onPressed: state.toggle,
      variant: DButtonVariant.ghost,
    ),
  ),
)''',
      builder: (_) => const _DropdownBreadcrumb(),
    ),
    StyleguideExample(
      title: 'Collapsed',
      description:
          'Omitted middle levels stay available from the labeled ellipsis menu instead of disappearing.',
      code: '''DBreadcrumbItem(
  child: DDropdownMenu(
    content: DDropdownMenuContent(children: hiddenRoutes),
    child: DDropdownMenuTrigger(
      builder: (context, state) => DButton.iconOnly(
        icon: DBreadcrumbEllipsis(), tooltip: 'More pages',
        size: DButtonSize.small, variant: DButtonVariant.ghost,
        hasPopup: true, expanded: state.open,
        focusNode: state.focusNode, onPressed: state.toggle,
      ),
    ),
  ),
)''',
      builder: (_) => const _CollapsedBreadcrumb(),
    ),
    StyleguideExample(
      title: 'Link component',
      description:
          'A typed destination and optional adapter integrate a routing library without moving route logic into the component.',
      code: '''DBreadcrumbLink.route<String>(
  destination: '/components',
  onNavigate: openRoute,
  adapter: (context, route, child) => KeyedSubtree(
    key: ValueKey(route), child: child,
  ),
  child: const Text('Components'),
)''',
      builder: (_) => const _TypedRouteBreadcrumb(),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'The path order follows the Arabic reading direction and default chevrons flip logically.',
      code: '''DBreadcrumb(
  textDirection: TextDirection.rtl,
  semanticLabel: 'مسار التنقل',
  child: DBreadcrumbList(children: [/* Arabic path */]),
)''',
      builder: (_) => const _RtlBreadcrumb(),
    ),
    StyleguideExample(
      title: 'Narrow and scrolling',
      description:
          'A long application path stays on one line and scrolls its focused link into view. Compare with the wrapping examples at 200% text.',
      code: '''DBreadcrumbList(
  overflow: DBreadcrumbOverflow.scroll,
  children: longPath,
)''',
      builder: (_) => const SizedBox(width: 240, child: _LongBreadcrumb()),
    ),
    StyleguideExample(
      title: 'Reference demo',
      description:
          'The canonical path keeps omitted pages available from an ellipsis menu between Home and Components.',
      states: const ['Links', 'Collapsed menu', 'Current page'],
      code: '''DBreadcrumb(
  child: DBreadcrumbList(children: [
    DBreadcrumbItem(
      child: DBreadcrumbLink(onPressed: openHome, child: Text('Home')),
    ),
    DBreadcrumbSeparator(),
    DBreadcrumbItem(
      child: DDropdownMenu(
        content: DDropdownMenuContent(
          align: DPopoverAlign.start,
          children: [
            DDropdownMenuGroup(children: [
              DDropdownMenuItem(child: Text('Documentation')),
              DDropdownMenuItem(child: Text('Themes')),
              DDropdownMenuItem(child: Text('GitHub')),
            ]),
          ],
        ),
        child: DDropdownMenuTrigger(
          builder: (context, state) => DButton.iconOnly(
            icon: DBreadcrumbEllipsis(), tooltip: 'Toggle menu',
            variant: DButtonVariant.ghost, size: DButtonSize.small,
            hasPopup: true, expanded: state.open,
            focusNode: state.focusNode, onPressed: state.toggle,
          ),
        ),
      ),
    ),
    DBreadcrumbSeparator(),
    DBreadcrumbItem(
      child: DBreadcrumbLink(
        onPressed: openComponents, child: Text('Components')),
    ),
    DBreadcrumbSeparator(),
    DBreadcrumbItem(child: DBreadcrumbPage(child: Text('Breadcrumb'))),
  ]),
)''',
      builder: (_) => const _BreadcrumbReferenceDemo(),
    ),
  ],
);

class _BreadcrumbReferenceDemo extends StatelessWidget {
  const _BreadcrumbReferenceDemo();

  @override
  Widget build(BuildContext context) => DBreadcrumb(
    child: DBreadcrumbList(
      children: [
        const DBreadcrumbItem(
          child: DBreadcrumbLink(onPressed: _noop, child: Text('Home')),
        ),
        const DBreadcrumbSeparator(),
        DBreadcrumbItem(
          child: DDropdownMenu(
            content: DDropdownMenuContent(
              semanticLabel: 'Hidden pages',
              align: DPopoverAlign.start,
              children: [
                DDropdownMenuGroup(
                  children: [
                    for (final page in ['Documentation', 'Themes', 'GitHub'])
                      DDropdownMenuItem(onPressed: _noop, child: Text(page)),
                  ],
                ),
              ],
            ),
            child: DDropdownMenuTrigger(
              builder: (context, state) => DButton.iconOnly(
                icon: const DBreadcrumbEllipsis(),
                tooltip: 'Toggle menu',
                variant: DButtonVariant.ghost,
                size: DButtonSize.small,
                hasPopup: true,
                expanded: state.open,
                focusNode: state.focusNode,
                onPressed: state.toggle,
              ),
            ),
          ),
        ),
        const DBreadcrumbSeparator(),
        const DBreadcrumbItem(
          child: DBreadcrumbLink(onPressed: _noop, child: Text('Components')),
        ),
        const DBreadcrumbSeparator(),
        const DBreadcrumbItem(
          child: DBreadcrumbPage(child: Text('Breadcrumb')),
        ),
      ],
    ),
  );
}

class _BasicBreadcrumb extends StatefulWidget {
  const _BasicBreadcrumb();

  @override
  State<_BasicBreadcrumb> createState() => _BasicBreadcrumbState();
}

class _BasicBreadcrumbState extends State<_BasicBreadcrumb> {
  String lastRoute = 'No route opened';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    spacing: 12,
    children: [
      DBreadcrumb(
        child: DBreadcrumbList(
          children: [
            DBreadcrumbItem(
              child: DBreadcrumbLink(
                onPressed: () => setState(() => lastRoute = 'Opened Home'),
                child: const Text('Home'),
              ),
            ),
            const DBreadcrumbSeparator(),
            DBreadcrumbItem(
              child: DBreadcrumbLink(
                onPressed: () =>
                    setState(() => lastRoute = 'Opened Components'),
                child: const Text('Components'),
              ),
            ),
            const DBreadcrumbSeparator(),
            const DBreadcrumbItem(
              child: DBreadcrumbPage(child: Text('Breadcrumb')),
            ),
          ],
        ),
      ),
      Text(lastRoute, key: const ValueKey('breadcrumb-basic-status')),
    ],
  );
}

class _CustomSeparatorBreadcrumb extends StatelessWidget {
  const _CustomSeparatorBreadcrumb();

  @override
  Widget build(BuildContext context) => const DBreadcrumb(
    child: DBreadcrumbList(
      children: [
        DBreadcrumbItem(
          child: DBreadcrumbLink(onPressed: _noop, child: Text('Home')),
        ),
        DBreadcrumbSeparator(child: Icon(Icons.circle, size: 4)),
        DBreadcrumbItem(
          child: DBreadcrumbLink(onPressed: _noop, child: Text('Components')),
        ),
        DBreadcrumbSeparator(child: Icon(Icons.circle, size: 4)),
        DBreadcrumbItem(child: DBreadcrumbPage(child: Text('Breadcrumb'))),
      ],
    ),
  );
}

class _DropdownBreadcrumb extends StatefulWidget {
  const _DropdownBreadcrumb();

  @override
  State<_DropdownBreadcrumb> createState() => _DropdownBreadcrumbState();
}

class _DropdownBreadcrumbState extends State<_DropdownBreadcrumb> {
  String selected = 'No page selected';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    spacing: 12,
    children: [
      DBreadcrumb(
        child: DBreadcrumbList(
          children: [
            const DBreadcrumbItem(
              child: DBreadcrumbLink(onPressed: _noop, child: Text('Home')),
            ),
            const DBreadcrumbSeparator(child: Icon(Icons.circle, size: 4)),
            DBreadcrumbItem(child: _levelMenu(label: 'Components')),
            const DBreadcrumbSeparator(child: Icon(Icons.circle, size: 4)),
            const DBreadcrumbItem(
              child: DBreadcrumbPage(child: Text('Breadcrumb')),
            ),
          ],
        ),
      ),
      Text(selected, key: const ValueKey('breadcrumb-dropdown-status')),
    ],
  );

  Widget _levelMenu({required String label}) => DDropdownMenu(
    content: DDropdownMenuContent(
      semanticLabel: '$label pages',
      align: DPopoverAlign.start,
      children: [
        for (final page in ['Documentation', 'Themes', 'GitHub'])
          DDropdownMenuItem(
            onPressed: () => setState(() => selected = '$page selected'),
            child: Text(page),
          ),
      ],
    ),
    child: DDropdownMenuTrigger(
      builder: (context, state) => DButton(
        label: Text(label),
        icon: const Icon(Icons.keyboard_arrow_down),
        iconPosition: DButtonIconPosition.end,
        variant: DButtonVariant.ghost,
        size: DButtonSize.small,
        hasPopup: true,
        expanded: state.open,
        focusNode: state.focusNode,
        onPressed: state.toggle,
      ),
    ),
  );
}

class _CollapsedBreadcrumb extends StatefulWidget {
  const _CollapsedBreadcrumb();

  @override
  State<_CollapsedBreadcrumb> createState() => _CollapsedBreadcrumbState();
}

class _CollapsedBreadcrumbState extends State<_CollapsedBreadcrumb> {
  String selected = 'No hidden page selected';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    spacing: 12,
    children: [
      DBreadcrumb(
        child: DBreadcrumbList(
          children: [
            const DBreadcrumbItem(
              child: DBreadcrumbLink(onPressed: _noop, child: Text('Home')),
            ),
            const DBreadcrumbSeparator(),
            DBreadcrumbItem(
              child: DDropdownMenu(
                content: DDropdownMenuContent(
                  semanticLabel: 'Hidden pages',
                  align: DPopoverAlign.start,
                  children: [
                    for (final page in ['Documentation', 'Themes', 'GitHub'])
                      DDropdownMenuItem(
                        onPressed: () =>
                            setState(() => selected = '$page selected'),
                        child: Text(page),
                      ),
                  ],
                ),
                child: DDropdownMenuTrigger(
                  builder: (context, state) => DButton.iconOnly(
                    icon: const DBreadcrumbEllipsis(),
                    tooltip: 'More pages',
                    variant: DButtonVariant.ghost,
                    size: DButtonSize.small,
                    hasPopup: true,
                    expanded: state.open,
                    focusNode: state.focusNode,
                    onPressed: state.toggle,
                  ),
                ),
              ),
            ),
            const DBreadcrumbSeparator(),
            const DBreadcrumbItem(
              child: DBreadcrumbLink(
                onPressed: _noop,
                child: Text('Components'),
              ),
            ),
            const DBreadcrumbSeparator(),
            const DBreadcrumbItem(
              child: DBreadcrumbPage(child: Text('Breadcrumb')),
            ),
          ],
        ),
      ),
      Text(selected, key: const ValueKey('breadcrumb-collapsed-status')),
    ],
  );
}

class _TypedRouteBreadcrumb extends StatefulWidget {
  const _TypedRouteBreadcrumb();

  @override
  State<_TypedRouteBreadcrumb> createState() => _TypedRouteBreadcrumbState();
}

class _TypedRouteBreadcrumbState extends State<_TypedRouteBreadcrumb> {
  String route = 'No route opened';

  Widget _link(String label, String destination) =>
      DBreadcrumbLink.route<String>(
        destination: destination,
        onNavigate: (value) => setState(() => route = value),
        adapter: (context, value, child) =>
            KeyedSubtree(key: ValueKey('route:$value'), child: child),
        child: Text(label),
      );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    spacing: 12,
    children: [
      DBreadcrumb(
        child: DBreadcrumbList(
          children: [
            DBreadcrumbItem(child: _link('Home', '/')),
            const DBreadcrumbSeparator(),
            DBreadcrumbItem(child: _link('Components', '/components')),
            const DBreadcrumbSeparator(),
            const DBreadcrumbItem(
              child: DBreadcrumbPage(child: Text('Breadcrumb')),
            ),
          ],
        ),
      ),
      Text(route, key: const ValueKey('breadcrumb-route-status')),
    ],
  );
}

class _RtlBreadcrumb extends StatelessWidget {
  const _RtlBreadcrumb();

  @override
  Widget build(BuildContext context) => const DBreadcrumb(
    textDirection: TextDirection.rtl,
    semanticLabel: 'مسار التنقل',
    child: DBreadcrumbList(
      children: [
        DBreadcrumbItem(
          child: DBreadcrumbLink(onPressed: _noop, child: Text('الرئيسية')),
        ),
        DBreadcrumbSeparator(),
        DBreadcrumbItem(
          child: DBreadcrumbLink(onPressed: _noop, child: Text('المكونات')),
        ),
        DBreadcrumbSeparator(),
        DBreadcrumbItem(child: DBreadcrumbPage(child: Text('مسار التنقل'))),
      ],
    ),
  );
}

class _LongBreadcrumb extends StatelessWidget {
  const _LongBreadcrumb();

  @override
  Widget build(BuildContext context) => const DBreadcrumb(
    child: DBreadcrumbList(
      overflow: DBreadcrumbOverflow.scroll,
      children: [
        DBreadcrumbItem(
          child: DBreadcrumbLink(onPressed: _noop, child: Text('Workspace')),
        ),
        DBreadcrumbSeparator(),
        DBreadcrumbItem(
          child: DBreadcrumbLink(
            onPressed: _noop,
            child: Text('Documentation'),
          ),
        ),
        DBreadcrumbSeparator(),
        DBreadcrumbItem(
          child: DBreadcrumbLink(
            onPressed: _noop,
            child: Text('Component library'),
          ),
        ),
        DBreadcrumbSeparator(),
        DBreadcrumbItem(child: DBreadcrumbPage(child: Text('Breadcrumb'))),
      ],
    ),
  );
}

void _noop() {}
