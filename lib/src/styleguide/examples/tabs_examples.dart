import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../theme/d_icons.dart';
import '../styleguide_example.dart';

final tabsExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Switch between related layers of content with tabs.',
  notes:
      'The default list is 32px high with 3px inset, 25px triggers, 6px horizontal padding, 14/20 medium text and the host lg/md radius scale. Horizontal line tabs use 20px gaps, content-width labels, a 2px active underline inside the trigger and a subtle full-width divider. Regular triggers are 42px high (at least 48px on touch), with semibold selection and muted regular inactive labels. Vertical line tabs retain their trailing rule. '
      'The pill variant uses the shared control size and radius, semibold labels, 4px gaps and an immediate neutral selected fill without a surrounding track, border or shadow. '
      'The outlinePill variant keeps every tab capsule-shaped, with 6px gaps, outlined inactive tabs and the shared button accent fill on selection. Mobile notification menus use small, horizontally scrolling labels with full touch targets. '
      'DTabs owns local selection, DTabs.controlled follows application routing, and DTabController is a borrowed imperative option. DTabList supports manual or automatic activation and looping roving focus. Arrow direction follows orientation and RTL; Home/End jump to the boundary; Enter/Space activate in manual mode. Disabled and dynamically removed triggers are skipped. '
      'Pointer activation retains focus without an outline. Keyboard entry, arrow navigation, and Enter/Space activation show the focus ring by default. '
      'DTabPanel unmounts hidden content by default; maintainState retains it offstage without ticking or semantics. Focus in a disappearing panel returns to its trigger. Horizontal lists scroll at narrow widths and reveal keyboard-focused tabs. Touch platforms retain a 48px interaction height around the compact artwork. All colors, font family, radius and reduced motion update live from the preview.',
  examples: [
    StyleguideExample(
      title: 'Mobile navigation',
      description:
          'Start-aligned icon tabs with a top selection marker and a fixed New topic action. Tabs scroll independently when space is tight; the action stays visible.',
      states: const ['Navigation', 'Icons', 'Action', 'Keyboard', 'RTL'],
      code: '''DTabs<String>(
  initialValue: 'home',
  children: [
    DTabList<String>(
      variant: DTabListVariant.navigation,
      expandNavigationTabs: false,
      trailing: DButton.iconOnly(icon: DIcon(DIcons.plus), tooltip: 'New topic', onPressed: createTopic),
      children: [
        DTabTrigger(value: 'home', semanticLabel: 'Home', child: DIcon(DIcons.house)),
        DTabTrigger(value: 'chat', semanticLabel: 'Chat', child: DIcon(DIcons.comment)),
        DTabTrigger(value: 'voice', semanticLabel: 'Voice', child: DIcon(DIcons.microphoneLines)),
      ],
    ),
  ],
)''',
      builder: (_) => DTabs<String>(
        initialValue: 'home',
        children: [
          DTabList<String>(
            variant: DTabListVariant.navigation,
            expandNavigationTabs: false,
            trailing: Builder(
              builder: (context) => DButton.iconOnly(
                icon: const DIcon(DIcons.plus),
                tooltip: 'New topic',
                onPressed: () => DToast.show(context, 'New topic'),
              ),
            ),
            children: const [
              DTabTrigger(
                value: 'home',
                semanticLabel: 'Home',
                child: DIcon(DIcons.house),
              ),
              DTabTrigger(
                value: 'chat',
                semanticLabel: 'Chat',
                child: DIcon(DIcons.comment),
              ),
              DTabTrigger(
                value: 'voice',
                semanticLabel: 'Voice',
                child: DIcon(DIcons.microphoneLines),
              ),
            ],
          ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'Compact mobile navigation',
      description:
          'The navigation bar animates to 85% while its layout allocation stays fixed, so scrolling content does not jump. Reduced motion applies the change immediately.',
      states: const ['Navigation', 'Animation', 'Reduced motion'],
      code:
          'DTabList<String>(variant: DTabListVariant.navigation, navigationCompact: compact, children: tabs)',
      builder: (_) => const _CompactNavigation(),
    ),
    StyleguideExample(
      title: 'Document tabs',
      description:
          'Workspace tabs use 35px pill surfaces with 13px labels and an 18px close action. The selected tab has a raised fill and subtle outline. Inactive tabs stay transparent and give their close space to the label.',
      states: const ['Selected', 'Hover', 'Close', 'Keyboard'],
      code:
          "DDocumentTab(size: DControlSize.documentTab, selected: true, closeOnlyWhenSelected: true, onSelect: select, onClose: close, closeLabel: 'Close Side chat', child: Text('Side chat'))",
      builder: (_) => const _DocumentTabs(),
    ),
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
          'A transparent list marks selection with an underline. Click a tab, then use arrow keys or Enter/Space to reveal its keyboard focus ring.',
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
      title: 'Pill',
      description:
          'A transparent navigation row with muted labels and a rounded neutral selection. Topic feeds use this variant with inline counts.',
      states: const ['Pill', 'Counts', 'Hover', 'Focus', 'Keyboard'],
      code: '''DTabs<String>(
  initialValue: 'unread',
  children: [
    DTabList<String>(
      variant: DTabListVariant.pill,
      children: const [
        DTabTrigger(value: 'latest', child: Text('Latest')),
        DTabTrigger(value: 'new', child: Text('New 3')),
        DTabTrigger(value: 'unread', child: Text('Unread 4')),
        DTabTrigger(value: 'top', child: Text('Top')),
      ],
    ),
  ],
)''',
      builder: (_) => const DTabs<String>(
        initialValue: 'unread',
        children: [
          DTabList<String>(
            variant: DTabListVariant.pill,
            children: [
              DTabTrigger(value: 'latest', child: Text('Latest')),
              DTabTrigger(value: 'new', child: Text('New 3')),
              DTabTrigger(value: 'unread', child: Text('Unread 4')),
              DTabTrigger(value: 'top', child: Text('Top')),
            ],
          ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'Outlined pills',
      description:
          'Mobile notification categories scroll horizontally. Selection uses the forum accent, with outlined inactive tabs and full touch targets.',
      states: const ['Outline', 'Accent', 'Scroll', 'Touch', 'Keyboard', 'RTL'],
      code: '''DTabs<String>(
  initialValue: 'all',
  children: [
    DTabList<String>(
      variant: DTabListVariant.outlinePill,
      size: DControlSize.small,
      children: [
        DTabTrigger(value: 'all', child: Text('Notifications')),
        DTabTrigger(value: 'replies', child: Text('Replies')),
        DTabTrigger(value: 'likes', child: Text('Likes')),
        DTabTrigger(value: 'messages', child: Text('Messages')),
        DTabTrigger(value: 'bookmarks', child: Text('Bookmarks')),
      ],
    ),
  ],
)''',
      builder: (_) => const DTabs<String>(
        initialValue: 'all',
        children: [
          DTabList<String>(
            variant: DTabListVariant.outlinePill,
            size: DControlSize.small,
            children: [
              DTabTrigger(value: 'all', child: Text('Notifications')),
              DTabTrigger(value: 'replies', child: Text('Replies')),
              DTabTrigger(value: 'likes', child: Text('Likes')),
              DTabTrigger(value: 'messages', child: Text('Messages')),
              DTabTrigger(value: 'bookmarks', child: Text('Bookmarks')),
            ],
          ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'Plain',
      description:
          'Text-only vertical tabs for the notification menu. Selection brightens the label without a background, border, shadow or indicator.',
      states: const ['Plain', 'Vertical', 'Keyboard'],
      code:
          "DTabList<String>(variant: DTabListVariant.plain, children: [/* triggers */])",
      builder: (_) => const DTabs<String>(
        initialValue: 'notifications',
        orientation: Axis.vertical,
        children: [
          DTabList<String>(
            variant: DTabListVariant.plain,
            size: DControlSize.large,
            children: [
              DTabTrigger(value: 'notifications', child: Text('Notifications')),
              DTabTrigger(value: 'replies', child: Text('Replies')),
              DTabTrigger(value: 'likes', child: Text('Likes')),
            ],
          ),
        ],
      ),
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

class _DocumentTabs extends StatefulWidget {
  const _DocumentTabs();

  @override
  State<_DocumentTabs> createState() => _DocumentTabsState();
}

class _DocumentTabsState extends State<_DocumentTabs> {
  final _tabs = ['Review', 'Side chat'];
  String? _selected = 'Side chat';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        height: DControlStyle.scaledHeight(
          DControlSize.documentTab,
          MediaQuery.textScalerOf(context),
          context: context,
        ),
        child: Row(
          children: [
            for (final title in _tabs) ...[
              Expanded(
                child: DDocumentTab(
                  size: DControlSize.documentTab,
                  selected: _selected == title,
                  closeOnlyWhenSelected: true,
                  onSelect: () => setState(() => _selected = title),
                  onClose: () => setState(() {
                    _tabs.remove(title);
                    if (_selected == title) _selected = _tabs.firstOrNull;
                  }),
                  closeLabel: 'Close $title',
                  child: Row(
                    children: [
                      DIcon(
                        title == 'Review' ? DIcons.layerGroup : DIcons.comment,
                        size: 12,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(title, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      DButton(
        variant: DButtonVariant.ghost,
        onPressed: () => setState(() {
          _tabs
            ..clear()
            ..addAll(['Review', 'Side chat']);
          _selected = 'Side chat';
        }),
        label: const Text('Reset tabs'),
      ),
    ],
  );
}

class _CompactNavigation extends StatefulWidget {
  const _CompactNavigation();

  @override
  State<_CompactNavigation> createState() => _CompactNavigationState();
}

class _CompactNavigationState extends State<_CompactNavigation> {
  bool _compact = false;

  @override
  Widget build(BuildContext context) => Column(
    spacing: DSpacing.sm,
    children: [
      DToggle(
        pressed: _compact,
        onPressedChanged: (value) => setState(() => _compact = value),
        child: const Text('Compact navigation'),
      ),
      DTabs<String>(
        initialValue: 'home',
        children: [
          DTabList<String>(
            variant: DTabListVariant.navigation,
            navigationCompact: _compact,
            children: const [
              DTabTrigger(
                value: 'home',
                semanticLabel: 'Home',
                child: DIcon(DIcons.house),
              ),
              DTabTrigger(
                value: 'chat',
                semanticLabel: 'Chat',
                child: DIcon(DIcons.comment),
              ),
              DTabTrigger(
                value: 'voice',
                semanticLabel: 'Voice',
                child: DIcon(DIcons.microphoneLines),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
