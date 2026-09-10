import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final tabsExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Switch between related layers of content with tabs.',
  notes:
      'The default list is 32px high with 3px inset, 25px triggers, 6px horizontal padding, 14/20 medium text and the host lg/md radius scale. The line variant uses 4px gaps and a 2px active rule offset 4px beyond the trigger. '
      'DTabs owns local selection, DTabs.controlled follows application routing, and DTabController is a borrowed imperative option. DTabList supports manual or automatic activation and looping roving focus. Arrow direction follows orientation and RTL; Home/End jump to the boundary; Enter/Space activate in manual mode. Disabled and dynamically removed triggers are skipped. '
      'DTabPanel unmounts hidden content by default; maintainState retains it offstage without ticking or semantics. Focus in a disappearing panel returns to its trigger. Horizontal lists scroll at narrow widths and reveal keyboard-focused tabs. Touch platforms retain a 48px interaction height around the compact artwork. All colors, font family, radius and reduced motion update live from the preview.',
  examples: [
    StyleguideExample(
      title: 'Card composition',
      description:
          'The documented overview composes four tabs with the final Card component and local panel content.',
      states: const ['Usage', 'Composition', 'Card', 'Controlled content'],
      code: '''DTabs<String>(
  initialValue: 'overview',
  children: [
    DTabList<String>(children: const [
      DTabTrigger(value: 'overview', child: Text('Overview')),
      DTabTrigger(value: 'analytics', child: Text('Analytics')),
      DTabTrigger(value: 'reports', child: Text('Reports')),
      DTabTrigger(value: 'settings', child: Text('Settings')),
    ]),
    DTabPanel(value: 'overview', child: DCard(children: [/* … */])),
    // Matching panels for analytics, reports and settings.
  ],
)''',
      builder: (_) => const _CardTabs(),
    ),
    StyleguideExample(
      title: 'Line',
      description:
          'A transparent list uses the documented active line instead of an inset surface.',
      states: const ['Line', 'Hover', 'Focus', 'Keyboard'],
      code: '''DTabs<String>(
  initialValue: 'overview',
  children: [
    DTabList<String>(
      variant: DTabListVariant.line,
      children: const [
        DTabTrigger(value: 'overview', child: Text('Overview')),
        DTabTrigger(value: 'analytics', child: Text('Analytics')),
        DTabTrigger(value: 'reports', child: Text('Reports')),
      ],
    ),
  ],
)''',
      builder: (_) => const _LineTabs(),
    ),
    StyleguideExample(
      title: 'Vertical',
      description:
          'Vertical orientation changes layout and arrow-key navigation while panels remain composable.',
      states: const ['Vertical', 'Up/Down', 'Responsive panel'],
      code: '''DTabs<String>(
  initialValue: 'account',
  orientation: Axis.vertical,
  children: [
    DTabList<String>(children: const [
      DTabTrigger(value: 'account', child: Text('Account')),
      DTabTrigger(value: 'password', child: Text('Password')),
      DTabTrigger(value: 'notifications', child: Text('Notifications')),
    ]),
    const DTabPanel(value: 'account', child: Text('Account settings')),
  ],
)''',
      builder: (_) => const _VerticalTabs(),
    ),
    StyleguideExample(
      title: 'Disabled',
      description:
          'Disabled triggers remain announced but reject pointer, keyboard and semantic activation.',
      states: const ['Disabled', 'Skip on arrow', 'Semantics'],
      code: '''DTabs<String>(
  initialValue: 'home',
  children: [
    DTabList<String>(children: const [
      DTabTrigger(value: 'home', child: Text('Home')),
      DTabTrigger(value: 'settings', enabled: false, child: Text('Disabled')),
    ]),
  ],
)''',
      builder: (_) => const _DisabledTabs(),
    ),
    StyleguideExample(
      title: 'Icons',
      description:
          'Triggers accept ordinary Flutter composition; icons inherit the documented 16px size and state color.',
      states: const ['Leading icon', '6px gap', 'Inherited color'],
      code: '''DTabList<String>(children: const [
  DTabTrigger(
    value: 'preview',
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.web_asset_outlined), SizedBox(width: 6), Text('Preview'),
    ]),
  ),
  DTabTrigger(
    value: 'code',
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.code), SizedBox(width: 6), Text('Code'),
    ]),
  ),
])''',
      builder: (_) => const _IconTabs(),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'Arabic content, logical layout and horizontal roving focus follow right-to-left direction.',
      states: const ['RTL', 'Card', 'Arrow keys'],
      code: '''Directionality(
  textDirection: TextDirection.rtl,
  child: DTabs<String>(
    initialValue: 'overview',
    children: [
      DTabList<String>(children: const [
        DTabTrigger(value: 'overview', child: Text('نظرة عامة')),
        DTabTrigger(value: 'analytics', child: Text('التحليلات')),
        DTabTrigger(value: 'reports', child: Text('التقارير')),
      ]),
    ],
  ),
)''',
      builder: (_) => const _RtlTabs(),
    ),
    StyleguideExample(
      title: 'Controlled, dynamic and retained',
      description:
          'Add and remove routes, switch with a controller, and verify a retained text field survives panel changes.',
      states: const [
        'Controlled',
        'Dynamic list',
        'Fallback',
        'Controller',
        'maintainState',
        'Narrow overflow',
      ],
      code: '''final controller = DTabController<String>('profile');

DTabs<String>(
  controller: controller,
  onSelectionChanged: (change) => print(change.reason),
  children: [
    DTabList<String>(activateOnFocus: true, children: [
      for (final route in routes)
        DTabTrigger(value: route, child: Text(route)),
    ]),
    DTabPanel(
      value: 'profile',
      maintainState: true,
      child: DInput(label: const Text('Display name')),
    ),
  ],
)''',
      builder: (_) => const _DynamicTabs(),
    ),
  ],
);

const _labels = {
  'overview': (
    'Overview',
    'View your key metrics and recent project activity. Track progress across all your active projects.',
    'You have 12 active projects and 3 pending tasks.',
  ),
  'analytics': (
    'Analytics',
    'Track performance and user engagement metrics. Monitor trends and identify growth opportunities.',
    'Page views are up 25% compared to last month.',
  ),
  'reports': (
    'Reports',
    'Generate and download your detailed reports. Export data in multiple formats for analysis.',
    'You have 5 reports ready and available to export.',
  ),
  'settings': (
    'Settings',
    'Manage your account preferences and options. Customize your experience to fit your needs.',
    'Configure notifications, security, and themes.',
  ),
};

class _CardTabs extends StatelessWidget {
  const _CardTabs();
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 400),
    child: DTabs<String>(
      initialValue: 'overview',
      children: [
        DTabList<String>(
          children: [
            for (final entry in _labels.entries)
              DTabTrigger(value: entry.key, child: Text(entry.value.$1)),
          ],
        ),
        for (final entry in _labels.entries)
          DTabPanel(
            value: entry.key,
            child: DCard(
              children: [
                DCardHeader(
                  title: DCardTitle(child: Text(entry.value.$1)),
                  description: DCardDescription(child: Text(entry.value.$2)),
                ),
                DCardContent(
                  child: Text(
                    entry.value.$3,
                    style: TextStyle(
                      color: DTokens.of(context).mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _LineTabs extends StatelessWidget {
  const _LineTabs();
  @override
  Widget build(BuildContext context) => const DTabs<String>(
    initialValue: 'overview',
    children: [
      DTabList<String>(
        variant: DTabListVariant.line,
        children: [
          DTabTrigger(value: 'overview', child: Text('Overview')),
          DTabTrigger(value: 'analytics', child: Text('Analytics')),
          DTabTrigger(value: 'reports', child: Text('Reports')),
        ],
      ),
    ],
  );
}

class _VerticalTabs extends StatelessWidget {
  const _VerticalTabs();
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 400),
    child: const DTabs<String>(
      initialValue: 'account',
      orientation: Axis.vertical,
      children: [
        DTabList<String>(
          children: [
            DTabTrigger(value: 'account', child: Text('Account')),
            DTabTrigger(value: 'password', child: Text('Password')),
            DTabTrigger(value: 'notifications', child: Text('Notifications')),
          ],
        ),
        DTabPanel(
          value: 'account',
          child: Text('Update your profile and account preferences.'),
        ),
        DTabPanel(
          value: 'password',
          child: Text('Choose a unique and secure password.'),
        ),
        DTabPanel(
          value: 'notifications',
          child: Text('Choose which notifications you receive.'),
        ),
      ],
    ),
  );
}

class _DisabledTabs extends StatelessWidget {
  const _DisabledTabs();
  @override
  Widget build(BuildContext context) => const DTabs<String>(
    initialValue: 'home',
    children: [
      DTabList<String>(
        children: [
          DTabTrigger(value: 'home', child: Text('Home')),
          DTabTrigger(
            value: 'settings',
            enabled: false,
            child: Text('Disabled'),
          ),
        ],
      ),
    ],
  );
}

class _IconTabs extends StatelessWidget {
  const _IconTabs();
  @override
  Widget build(BuildContext context) => const DTabs<String>(
    initialValue: 'preview',
    children: [
      DTabList<String>(
        children: [
          DTabTrigger(
            value: 'preview',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.web_asset_outlined),
                SizedBox(width: 6),
                Text('Preview'),
              ],
            ),
          ),
          DTabTrigger(
            value: 'code',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [Icon(Icons.code), SizedBox(width: 6), Text('Code')],
            ),
          ),
        ],
      ),
    ],
  );
}

class _RtlTabs extends StatelessWidget {
  const _RtlTabs();
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: const DTabs<String>(
        initialValue: 'overview',
        children: [
          DTabList<String>(
            children: [
              DTabTrigger(value: 'overview', child: Text('نظرة عامة')),
              DTabTrigger(value: 'analytics', child: Text('التحليلات')),
              DTabTrigger(value: 'reports', child: Text('التقارير')),
              DTabTrigger(value: 'settings', child: Text('الإعدادات')),
            ],
          ),
          DTabPanel(
            value: 'overview',
            child: DCard(
              children: [
                DCardHeader(
                  title: DCardTitle(child: Text('نظرة عامة')),
                  description: DCardDescription(
                    child: Text(
                      'عرض مقاييسك الرئيسية وأنشطة المشروع الأخيرة. تتبع التقدم عبر جميع مشاريعك النشطة.',
                    ),
                  ),
                ),
                DCardContent(
                  child: Text('لديك ١٢ مشروعًا نشطًا و٣ مهام معلقة.'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _DynamicTabs extends StatefulWidget {
  const _DynamicTabs();
  @override
  State<_DynamicTabs> createState() => _DynamicTabsState();
}

class _DynamicTabsState extends State<_DynamicTabs> {
  final controller = DTabController<String>('profile');
  final routes = <String>['profile', 'security', 'notifications'];
  String event = 'Ready';

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 400),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DButton(
              label: Text(
                routes.contains('security')
                    ? 'Remove security'
                    : 'Add security',
              ),
              onPressed: () => setState(() {
                routes.contains('security')
                    ? routes.remove('security')
                    : routes.insert(1, 'security');
              }),
            ),
            DButton(
              label: const Text('Select profile'),
              onPressed: () => controller.value = 'profile',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(event, key: const ValueKey('tabs-dynamic-event')),
        const SizedBox(height: 8),
        DTabs<String>(
          controller: controller,
          onSelectionChanged: (change) => setState(() {
            event = '${change.reason.name}: ${change.value ?? 'none'}';
          }),
          children: [
            DTabList<String>(
              activateOnFocus: true,
              children: [
                for (final route in routes)
                  DTabTrigger(
                    key: ValueKey('dynamic-$route'),
                    value: route,
                    child: Text(route),
                  ),
              ],
            ),
            DTabPanel(
              value: 'profile',
              maintainState: true,
              child: DInput(
                labelText: 'Display name',
                hintText: 'Kept while hidden',
              ),
            ),
            const DTabPanel(value: 'security', child: Text('Security options')),
            const DTabPanel(
              value: 'notifications',
              child: Text('Notification options'),
            ),
          ],
        ),
      ],
    ),
  );
}
