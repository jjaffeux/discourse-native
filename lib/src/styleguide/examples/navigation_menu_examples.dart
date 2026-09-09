import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final navigationMenuExamples = ComponentExamples(
  description: 'A collection of links for navigating websites.',
  status: ComponentStatus.implemented,
  notes:
      'Frozen Markdown SHA-256: 2f4297e419617d26545e1c71dbc5336f6878dd8ab687f71663fe0e2bc2126546. '
      'Base Nova registry SHA-256: 1fdd735ea7449af8ebbd932b3e89b34a1efa8a3b193ac979d0d723660526c017; '
      'Basic example source SHA-256: 4a2fd068c7b5c3543500d82a37cd115951e2657e4926ade4cdfa5f06ec2c752a. '
      'Mapping: triggers are 36px high with 10px inline/6px block padding, '
      '14px medium text, host-relative lg radius and a 12px rotating chevron. '
      'Content has 4px padding, an 8px side offset, a one-pixel 10%-foreground '
      'ring, shared shadow, clipped viewport and 350ms panel travel. Links use '
      '8px padding and host-relative md radius. The 8px indicator diamond sits '
      'in a 6px strip. Pointer hover uses 50ms open/close delays; touch uses '
      'press and iOS keeps a 48px target. Arrow keys rove logically in RTL, '
      'Home/End move to boundaries, Up/Down enter content, and Escape/outside '
      'press dismiss. Framework Link composition maps to typed callbacks and '
      'active/current-page semantics. Core and bundled-plugin navigation was '
      'audited: Sidebar, route tabs, calendar paging, command menus and ordinary '
      'buttons keep their specialized owners; there is no genuine site-wide '
      'rich horizontal navigation surface to migrate.',
  examples: [
    StyleguideExample(
      title: 'Basic',
      description:
          'The frozen reference composition: three rich trigger panels and a '
          'direct Documentation link. Every destination updates local output.',
      states: const ['Viewport', 'Indicator', 'Hover', 'Keyboard', 'Routing'],
      code: '''DNavigationMenu<String>(
  child: DNavigationMenuList(children: [
    DNavigationMenuItem(
      value: 'getting-started',
      trigger: DNavigationMenuTrigger(child: Text('Getting started')),
      content: DNavigationMenuContent(width: 384, child: links),
    ),
    DNavigationMenuItem.link(
      value: 'docs',
      link: DNavigationMenuLink(triggerStyle: true, child: Text('Documentation')),
    ),
  ]),
)''',
      builder: (_) => const _ReferenceMenu(),
    ),
    StyleguideExample(
      title: 'Link component and current page',
      description:
          'Typed callbacks stand in for a framework router. The active link '
          'exposes current-page selection semantics and content links close.',
      states: const ['Custom link', 'Active', 'Close on activate', 'Semantics'],
      code: '''DNavigationMenuLink(
  active: route == '/docs',
  closeOnActivate: true,
  onPressed: () => setState(() => route = '/docs'),
  child: const Text('Documentation'),
)''',
      builder: (_) => const _RoutingMenu(),
    ),
    StyleguideExample(
      title: 'Controlled, dynamic and disabled',
      description:
          'The parent owns the open panel. Entries can be disabled or removed '
          'without leaving stale selection or focus behind.',
      states: const ['Controlled', 'Disabled', 'Dynamic', 'Controller'],
      code: '''DNavigationMenu<String>.controlled(
  value: openPanel,
  onValueChanged: (value) => setState(() => openPanel = value),
  child: DNavigationMenuList(children: items),
)''',
      builder: (_) => const _ControlledMenu(),
    ),
    StyleguideExample(
      title: 'Inline viewport and RTL',
      description:
          'Without the shared viewport, each popup anchors to its trigger. '
          'Arabic direction mirrors logical arrow travel and alignment.',
      states: const ['RTL', 'Inline popup', 'Narrow', 'Large text'],
      code: '''Directionality(
  textDirection: TextDirection.rtl,
  child: DNavigationMenu<String>(viewport: false, child: arabicItems),
)''',
      builder: (_) => const _RtlMenu(),
    ),
  ],
);

class _ReferenceMenu extends StatefulWidget {
  const _ReferenceMenu();

  @override
  State<_ReferenceMenu> createState() => _ReferenceMenuState();
}

class _ReferenceMenuState extends State<_ReferenceMenu> {
  String _destination = 'None';

  void _go(String value) => setState(() => _destination = value);

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DNavigationMenu<String>(
        child: DNavigationMenuList<String>(
          children: [
            DNavigationMenuItem<String>(
              value: 'getting-started',
              trigger: const DNavigationMenuTrigger(
                child: Text('Getting started'),
              ),
              content: DNavigationMenuContent(
                width: 384,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _link(
                      'Introduction',
                      'Reusable components built for the app.',
                    ),
                    _link(
                      'Installation',
                      'Add the library through its public barrel.',
                    ),
                    _link(
                      'Typography',
                      'Headings, paragraphs, lists and tables.',
                    ),
                  ],
                ),
              ),
            ),
            DNavigationMenuItem<String>(
              value: 'components',
              trigger: const DNavigationMenuTrigger(child: Text('Components')),
              content: DNavigationMenuContent(
                width: 600,
                child: Wrap(
                  children: [
                    for (final item in const [
                      ('Alert Dialog', 'An important modal response.'),
                      ('Hover Card', 'Preview content behind a link.'),
                      ('Progress', 'Show task completion.'),
                      ('Scroll area', 'Scroll content in a bounded region.'),
                      ('Tabs', 'Layer related content panels.'),
                      ('Tooltip', 'Describe a focused or hovered control.'),
                    ])
                      SizedBox(width: 292, child: _link(item.$1, item.$2)),
                  ],
                ),
              ),
            ),
            DNavigationMenuItem<String>(
              value: 'icon',
              trigger: const DNavigationMenuTrigger(child: Text('With Icon')),
              content: DNavigationMenuContent(
                width: 200,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (label, icon) in const [
                      ('Backlog', Icons.error_outline),
                      ('To Do', Icons.circle_outlined),
                      ('Done', Icons.check_circle_outline),
                    ])
                      DNavigationMenuLink(
                        closeOnActivate: true,
                        onPressed: () => _go(label),
                        child: Row(
                          children: [
                            Icon(icon),
                            const SizedBox(width: 8),
                            Text(label),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            DNavigationMenuItem<String>.link(
              value: 'docs',
              link: DNavigationMenuLink(
                triggerStyle: true,
                onPressed: () => _go('Documentation'),
                child: const Text('Documentation'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Destination: $_destination',
        key: const ValueKey('navigation-output'),
      ),
    ],
  );

  Widget _link(String title, String description) => DNavigationMenuLink(
    closeOnActivate: true,
    onPressed: () => _go(title),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(
          description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: DTokens.of(context).mutedForeground),
        ),
      ],
    ),
  );
}

class _RoutingMenu extends StatefulWidget {
  const _RoutingMenu();

  @override
  State<_RoutingMenu> createState() => _RoutingMenuState();
}

class _RoutingMenuState extends State<_RoutingMenu> {
  String _route = '/docs';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DNavigationMenu<String>(
        child: DNavigationMenuList<String>(
          children: [
            DNavigationMenuItem<String>(
              value: 'learn',
              trigger: const DNavigationMenuTrigger(child: Text('Learn')),
              content: DNavigationMenuContent(
                width: 240,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final route in const ['/docs', '/examples'])
                      DNavigationMenuLink(
                        active: _route == route,
                        closeOnActivate: true,
                        onPressed: () => setState(() => _route = route),
                        child: Text(
                          route == '/docs' ? 'Documentation' : 'Examples',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      Text('Route: $_route'),
    ],
  );
}

class _ControlledMenu extends StatefulWidget {
  const _ControlledMenu();

  @override
  State<_ControlledMenu> createState() => _ControlledMenuState();
}

class _ControlledMenuState extends State<_ControlledMenu> {
  String? _open;
  bool _showSecond = true;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DNavigationMenu<String>.controlled(
        value: _open,
        onValueChanged: (value) => setState(() => _open = value),
        child: DNavigationMenuList<String>(
          children: [
            const DNavigationMenuItem<String>(
              value: 'disabled',
              disabled: true,
              trigger: DNavigationMenuTrigger(child: Text('Disabled')),
              content: DNavigationMenuContent(child: Text('Unavailable')),
            ),
            if (_showSecond)
              const DNavigationMenuItem<String>(
                value: 'dynamic',
                trigger: DNavigationMenuTrigger(child: Text('Dynamic')),
                content: DNavigationMenuContent(
                  width: 220,
                  child: Text('This entry can be removed while open.'),
                ),
              ),
          ],
        ),
      ),
      DButton(
        size: DButtonSize.small,
        variant: DButtonVariant.outline,
        label: Text(_showSecond ? 'Remove dynamic' : 'Restore dynamic'),
        onPressed: () => setState(() {
          _showSecond = !_showSecond;
          if (!_showSecond) _open = null;
        }),
      ),
    ],
  );
}

class _RtlMenu extends StatefulWidget {
  const _RtlMenu();

  @override
  State<_RtlMenu> createState() => _RtlMenuState();
}

class _RtlMenuState extends State<_RtlMenu> {
  String _destination = 'None';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Directionality(
        textDirection: TextDirection.rtl,
        child: DNavigationMenu<String>(
          viewport: false,
          semanticLabel: 'التنقل الرئيسي',
          child: DNavigationMenuList<String>(
            children: [
              DNavigationMenuItem<String>(
                value: 'start',
                trigger: const DNavigationMenuTrigger(child: Text('البدء')),
                content: DNavigationMenuContent(
                  width: 260,
                  child: DNavigationMenuLink(
                    closeOnActivate: true,
                    onPressed: () =>
                        setState(() => _destination = 'Introduction'),
                    child: const Text('مقدمة المكونات'),
                  ),
                ),
              ),
              DNavigationMenuItem<String>(
                value: 'parts',
                trigger: const DNavigationMenuTrigger(child: Text('المكونات')),
                content: DNavigationMenuContent(
                  width: 260,
                  child: DNavigationMenuLink(
                    closeOnActivate: true,
                    onPressed: () =>
                        setState(() => _destination = 'Components'),
                    child: const Text('قائمة المكونات'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text('Destination: $_destination'),
    ],
  );
}
