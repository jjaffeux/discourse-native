import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../styleguide_example.dart';

final sidebarExamples = ComponentExamples(
  description:
      'Composable navigation with collapsible panels, groups, and menus.',
  status: ComponentStatus.implemented,
  notes:
      'Sidebar ports base-nova geometry and native focus/navigation. Content scrolls with hidden scrollbar artwork and drag targets. Its mobile panel, search, group disclosure, workspace/account menus and account identity compose the accepted Sheet, Input, Collapsible, Dropdown Menu and Avatar owners. Persistence and routing remain with the app.',
  examples: [
    StyleguideExample(
      title: 'Application sidebar',
      description:
          'A close native reproduction of the shadcn Base UI demo: team and account switchers, the Platform hierarchy, project action menus, icon collapse and rail. Each project’s three-dot menu offers View, Share and Delete with local feedback. Below 500px it uses the shared Sheet adaptation. Cmd/Ctrl+B toggles, Tab navigates, Enter/Space activates and Escape dismisses.',
      code: '''DSidebarProvider(mobileBreakpoint: 500, child: Row(children: [
  DSidebar(
    collapsible: DSidebarCollapsible.icon,
    header: DSidebarHeader(child: teamSwitcher),
    footer: DSidebarFooter(child: accountMenu),
    rail: const DSidebarRail(),
    child: DSidebarContent(children: [
      DSidebarGroup(
        label: const DSidebarGroupLabel(child: Text('Platform')),
        child: DSidebarMenu(children: platformItems),
      ),
      DSidebarGroup(
        label: const DSidebarGroupLabel(child: Text('Projects')),
        child: DSidebarMenu(children: projectItems),
      ),
    ]),
  ),
  Expanded(child: Column(children: [DSidebarTrigger(), content])),
]))''',
      builder: (_) => const _ShadcnSidebarDemo(),
    ),
    StyleguideExample(
      title: 'Icon, floating and inset',
      description:
          'Floating panel and icon collapse. Collapsed icons keep accessible names and Tooltip. The icon rail toggle remains pointer accessible.',
      code: '''DSidebar(collapsible: DSidebarCollapsible.icon,
  variant: DSidebarVariant.floating, rail: DSidebarRail(),
  child: DSidebarContent(children: groups))''',
      builder: (_) => const _SidebarDemo(
        mode: DSidebarCollapsible.icon,
        variant: DSidebarVariant.floating,
      ),
    ),
    StyleguideExample(
      title: 'Controlled inset',
      description:
          'The parent owns open state. The inset main surface uses the live background and radius; the button reflects the requested state.',
      code: '''DSidebarProvider(mobileBreakpoint: 500,
  open: open, onOpenChange: (value) => setState(() => open = value),
  child: Row(children: [DSidebar(variant: DSidebarVariant.inset, child: menu),
    Expanded(child: DSidebarInset(child: content))]))''',
      builder: (_) =>
          const _SidebarDemo(controlled: true, variant: DSidebarVariant.inset),
    ),
    StyleguideExample(
      title: 'Documentation',
      description:
          'Same-background, static navigation with 30px minimum rows. Long labels grow at large text sizes. Search filters self-contained examples. This is the composition used by the styleguide shell.',
      code: '''DSidebarProvider(mobileBreakpoint: 900, child: DSidebar(
  width: 240, collapsible: DSidebarCollapsible.none,
  backgroundColor: DTokens.of(context).background,
  child: DSidebarContent(children: [DSidebarGroup(
    label: DSidebarGroupLabel(child: Text('Components')),
    child: DSidebarMenu(children: [DSidebarMenuButton(height: 30,
      isActive: true, onPressed: select, child: Text('Sidebar'))]))])))''',
      builder: (_) => const _SidebarDemo(
        documentation: true,
        mode: DSidebarCollapsible.none,
      ),
    ),
    StyleguideExample(
      title: 'Right side and nested menus',
      description:
          'Physical right placement works in either text direction. DCollapsible owns project disclosure and retains local selection. Small/default/large buttons, outline rows, submenus, disabled actions and action feedback are interactive.',
      code: '''DCollapsible(open: expanded, onOpenChange: setExpanded, child:
  DSidebarGroup(
    label: DCollapsibleTrigger(builder: projectLabel),
    child: DCollapsibleContent(child: DSidebarMenuSub(children: [
      DSidebarMenuSubButton(onPressed: select, child: Text('Design')),
    ]))))''',
      builder: (_) => const _SidebarDemo(side: DSidebarSide.right),
    ),
    StyleguideExample(
      title: 'Loading and recovery',
      description:
          'Skeleton composes the completed Skeleton owner. Load switches to ready navigation; simulate failure and retry preserve the surrounding sidebar. All state is local.',
      code: '''DSkeletonRegion(semanticsLabel: 'Loading navigation', child:
  DSidebarMenu(children: [DSidebarMenuSkeleton(showIcon: true)]))''',
      builder: (_) => const _SidebarDemo(loading: true),
    ),
    StyleguideExample(
      title: 'Lazy navigation',
      description:
          '400 destinations share one scroll area. Collapse Channels, scroll to the end, increase the unread count, or open a row action. Headers and footer stay fixed. Large text grows rows and trailing counts reserve their actual width.',
      code: '''DSidebarContent.slivers(slivers: [
  DCollapsible(defaultOpen: true, child: DSidebarGroup.sliver(
    label: DCollapsibleTrigger(child:
      DSidebarGroupLabel(child: Text('Channels'))),
    sliver: DCollapsibleContent.sliver(sliver:
      DSidebarMenu.sliverBuilder(
        itemCount: channels.length,
        itemBuilder: buildChannel,
        findChildIndexCallback: findChannelIndex,
      )),
  )),
])''',
      builder: (_) => const _LazySidebarDemo(),
    ),
  ],
);

class _LazySidebarDemo extends StatefulWidget {
  const _LazySidebarDemo();
  @override
  State<_LazySidebarDemo> createState() => _LazySidebarDemoState();
}

class _LazySidebarDemoState extends State<_LazySidebarDemo> {
  var _open = true;
  var _count = 1234;
  var _selected = 0;
  var _message = '400 channels';

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 440,
    child: DSidebarProvider(
      mobileBreakpoint: 0,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final touch = switch (Theme.of(context).platform) {
            TargetPlatform.iOS || TargetPlatform.android => true,
            _ => false,
          };
          final scalable = MediaQuery.textScalerOf(context).scale(14) > 14;
          return DSidebar(
            width: constraints.maxWidth,
            collapsible: DSidebarCollapsible.none,
            header: DSidebarHeader(
              child: Row(
                children: [
                  const Expanded(child: Text('Community')),
                  DButton.iconOnly(
                    tooltip: 'Increase unread count',
                    icon: const Icon(Icons.add),
                    onPressed: () => setState(() => _count += 1000),
                  ),
                ],
              ),
            ),
            footer: DSidebarFooter(child: Text(_message)),
            child: DSidebarContent.slivers(
              slivers: [
                DCollapsible(
                  open: _open,
                  onOpenChange: (value) => setState(() => _open = value),
                  child: DSidebarGroup.sliver(
                    label: DCollapsibleTrigger(
                      child: DSidebarGroupLabel(
                        child: Row(
                          children: [
                            const Expanded(child: Text('Channels')),
                            Icon(
                              _open
                                  ? Icons.keyboard_arrow_down
                                  : Icons.chevron_right,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                    sliver: DCollapsibleContent.sliver(
                      sliver: DSidebarMenu.sliverBuilder(
                        itemCount: 400,
                        itemExtent: scalable
                            ? null
                            : touch
                            ? 48
                            : 32,
                        findChildIndexCallback: (key) =>
                            key is ValueKey<int> ? key.value : null,
                        itemBuilder: (context, index) => DSidebarMenuItem(
                          key: ValueKey(index),
                          badge: index < 2
                              ? DSidebarMenuBadge(
                                  child: Text(index == 0 ? '$_count' : 'muted'),
                                )
                              : null,
                          action: DDropdownMenu(
                            content: DDropdownMenuContent(
                              side: DPopoverSide.bottom,
                              align: DPopoverAlign.end,
                              children: [
                                DDropdownMenuItem(
                                  onPressed: () => setState(
                                    () =>
                                        _message = 'Actions for channel $index',
                                  ),
                                  child: const Text('View channel details'),
                                ),
                              ],
                            ),
                            child: DDropdownMenuTrigger(
                              builder: (context, menu) => DSidebarMenuAction(
                                semanticLabel: 'Channel $index actions',
                                showOnHover: true,
                                focusNode: menu.focusNode,
                                expanded: menu.open,
                                onPressed: menu.toggle,
                                child: const Icon(Icons.more_horiz),
                              ),
                            ),
                          ),
                          child: DSidebarMenuButton(
                            icon: const Icon(Icons.tag, size: 16),
                            isActive: _selected == index,
                            onPressed: () => setState(() {
                              _selected = index;
                              _message = 'Selected channel $index';
                            }),
                            child: Text(
                              index == 0
                                  ? 'Announcements and community updates'
                                  : 'Channel $index',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _ShadcnSidebarDemo extends StatefulWidget {
  const _ShadcnSidebarDemo();

  @override
  State<_ShadcnSidebarDemo> createState() => _ShadcnSidebarDemoState();
}

class _ShadcnSidebarDemoState extends State<_ShadcnSidebarDemo> {
  static const _avatarAsset =
      'packages/discourse_native/src/styleguide/assets/item/shadcn.png';
  static const _teams = <({String name, String plan, IconData icon})>[
    (name: 'Acme Inc', plan: 'Enterprise', icon: Icons.view_column_outlined),
    (name: 'Acme Corp.', plan: 'Startup', icon: Icons.graphic_eq),
    (name: 'Evil Corp.', plan: 'Free', icon: Icons.code),
  ];
  static const _navigation =
      <({String title, String icon, List<String> children})>[
        (
          title: 'Playground',
          icon: _SidebarReferenceIcon.squareTerminal,
          children: ['History', 'Starred', 'Settings'],
        ),
        (
          title: 'Models',
          icon: _SidebarReferenceIcon.bot,
          children: ['Genesis', 'Explorer', 'Quantum'],
        ),
        (
          title: 'Documentation',
          icon: _SidebarReferenceIcon.bookOpen,
          children: ['Introduction', 'Get Started', 'Tutorials', 'Changelog'],
        ),
        (
          title: 'Settings',
          icon: _SidebarReferenceIcon.settings,
          children: ['General', 'Team', 'Billing', 'Limits'],
        ),
      ];
  static const _projects = <({String title, String icon})>[
    (title: 'Design Engineering', icon: _SidebarReferenceIcon.frame),
    (title: 'Sales & Marketing', icon: _SidebarReferenceIcon.chartPie),
    (title: 'Travel', icon: _SidebarReferenceIcon.map),
  ];

  var _activeTeam = 0;
  var _message = 'Select a destination';

  DPopoverSide _menuSide(BuildContext context) =>
      DSidebarProvider.of(context).isMobile
      ? DPopoverSide.bottom
      : DPopoverSide.right;

  void _select(BuildContext context, String value) {
    setState(() => _message = '$value selected');
    DSidebarProvider.of(context).setOpenMobile(false);
  }

  Widget _teamMark(
    BuildContext context, {
    required Widget icon,
    required double dimension,
    required bool filled,
  }) {
    final tokens = DTokens.of(context);
    return Container(
      width: dimension,
      height: dimension,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? tokens.foreground : null,
        border: filled ? null : Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radius * 1.6),
      ),
      child: IconTheme(
        data: IconThemeData(
          size: dimension / 2,
          color: filled ? tokens.background : tokens.foreground,
        ),
        child: icon,
      ),
    );
  }

  Widget _identityText(BuildContext context, String title, String subtitle) {
    final tokens = DTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            height: 20 / 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tokens.mutedForeground,
            fontSize: 12,
            height: 16 / 12,
          ),
        ),
      ],
    );
  }

  Widget _teamSwitcher(BuildContext context) {
    final team = _teams[_activeTeam];
    return DDropdownMenu(
      content: DDropdownMenuContent(
        semanticLabel: 'Team menu',
        side: _menuSide(context),
        width: 224,
        children: [
          DDropdownMenuGroup(
            semanticLabel: 'Teams',
            children: [
              const DDropdownMenuLabel(child: Text('Teams')),
              for (final (index, candidate) in _teams.indexed)
                DDropdownMenuItem(
                  leading: Builder(
                    builder: (context) => _teamMark(
                      context,
                      dimension: 24,
                      filled: false,
                      icon: Icon(candidate.icon),
                    ),
                  ),
                  trailing: DDropdownMenuShortcut('⌘${index + 1}'),
                  onPressed: () => setState(() {
                    _activeTeam = index;
                    _message = '${candidate.name} team selected';
                  }),
                  child: Text(candidate.name),
                ),
            ],
          ),
          const DDropdownMenuSeparator(),
          DDropdownMenuItem(
            leading: const Icon(Icons.add),
            onPressed: () => setState(() => _message = 'Add team selected'),
            child: const Text('Add team'),
          ),
        ],
      ),
      child: DDropdownMenuTrigger(
        builder: (context, state) => DSidebarMenuButton(
          iconSize: 32,
          size: DSidebarMenuButtonSize.large,
          icon: _teamMark(
            context,
            dimension: 32,
            filled: true,
            icon: const _SidebarReferenceIcon(
              _SidebarReferenceIcon.galleryVerticalEnd,
            ),
          ),
          tooltip: team.name,
          semanticLabel: 'Switch team, ${team.name}, ${team.plan}',
          focusNode: state.focusNode,
          expanded: state.open,
          onPressed: state.toggle,
          child: Row(
            children: [
              Expanded(child: _identityText(context, team.name, team.plan)),
              const _SidebarReferenceIcon(_SidebarReferenceIcon.chevronsUpDown),
            ],
          ),
        ),
      ),
    );
  }

  Widget _platformNavigation(BuildContext context) => DSidebarGroup(
    label: const DSidebarGroupLabel(child: Text('Platform')),
    child: DSidebarMenu(
      children: [
        for (final item in _navigation)
          DCollapsible(
            defaultOpen: item.title == 'Playground',
            child: DSidebarMenuItem(
              submenu: DCollapsibleContent(
                child: DSidebarMenuSub(
                  children: [
                    for (final child in item.children)
                      DSidebarMenuSubItem(
                        child: DSidebarMenuSubButton(
                          onPressed: () => _select(context, child),
                          child: Text(child),
                        ),
                      ),
                  ],
                ),
              ),
              child: DCollapsibleTrigger(
                semanticLabel: 'Toggle ${item.title}',
                focusBorderRadius: BorderRadius.circular(
                  DTokens.of(context).radius * .8,
                ),
                builder: (context, state) => ExcludeFocus(
                  child: IgnorePointer(
                    child: DSidebarMenuButton(
                      icon: _SidebarReferenceIcon(item.icon),
                      tooltip: item.title,
                      expanded: state.open,
                      onPressed: () {},
                      child: Row(
                        children: [
                          Expanded(child: Text(item.title)),
                          AnimatedRotation(
                            turns: state.open ? .25 : 0,
                            duration: DMotion.duration(
                              context,
                              const Duration(milliseconds: 200),
                            ),
                            child: const _SidebarReferenceIcon(
                              _SidebarReferenceIcon.chevronRight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _projectNavigation(BuildContext context) => DSidebarGroup(
    label: const DSidebarGroupLabel(child: Text('Projects')),
    child: DSidebarMenu(
      children: [
        for (final project in _projects)
          DSidebarMenuItem(
            action: DDropdownMenu(
              content: DDropdownMenuContent(
                semanticLabel: '${project.title} project menu',
                side: _menuSide(context),
                align: DSidebarProvider.of(context).isMobile
                    ? DPopoverAlign.end
                    : DPopoverAlign.start,
                children: [
                  DDropdownMenuItem(
                    leading: const _SidebarReferenceIcon(
                      _SidebarReferenceIcon.folder,
                    ),
                    onPressed: () => setState(
                      () => _message = 'View ${project.title} selected',
                    ),
                    child: const Text('View Project'),
                  ),
                  DDropdownMenuItem(
                    leading: const _SidebarReferenceIcon(
                      _SidebarReferenceIcon.arrowRight,
                    ),
                    onPressed: () => setState(
                      () => _message = 'Share ${project.title} selected',
                    ),
                    child: const Text('Share Project'),
                  ),
                  const DDropdownMenuSeparator(),
                  DDropdownMenuItem(
                    variant: DDropdownMenuItemVariant.destructive,
                    leading: const _SidebarReferenceIcon(
                      _SidebarReferenceIcon.trash2,
                    ),
                    onPressed: () => setState(
                      () => _message = 'Delete ${project.title} selected',
                    ),
                    child: const Text('Delete Project'),
                  ),
                ],
              ),
              child: DDropdownMenuTrigger(
                builder: (context, state) => DSidebarMenuAction(
                  semanticLabel: 'More options for ${project.title}',
                  showOnHover: true,
                  focusNode: state.focusNode,
                  expanded: state.open,
                  onPressed: state.toggle,
                  child: const _SidebarReferenceIcon(
                    _SidebarReferenceIcon.ellipsis,
                  ),
                ),
              ),
            ),
            child: DSidebarMenuButton(
              icon: _SidebarReferenceIcon(project.icon),
              tooltip: project.title,
              onPressed: () => _select(context, project.title),
              child: Text(project.title),
            ),
          ),
        DSidebarMenuItem(
          child: DSidebarMenuButton(
            icon: const _SidebarReferenceIcon(_SidebarReferenceIcon.ellipsis),
            tooltip: 'More projects',
            onPressed: () =>
                setState(() => _message = 'More projects selected'),
            child: const Text('More'),
          ),
        ),
      ],
    ),
  );

  Widget _accountMenu(BuildContext context) => DDropdownMenu(
    content: DDropdownMenuContent(
      semanticLabel: 'Account menu',
      side: _menuSide(context),
      align: DPopoverAlign.end,
      width: 224,
      children: [
        DDropdownMenuLabel(
          child: Row(
            children: [
              _avatar(context),
              const SizedBox(width: 8),
              Expanded(
                child: _identityText(context, 'shadcn', 'm@example.com'),
              ),
            ],
          ),
        ),
        const DDropdownMenuSeparator(),
        DDropdownMenuItem(
          leading: const Icon(Icons.auto_awesome_outlined),
          onPressed: () => setState(() => _message = 'Upgrade selected'),
          child: const Text('Upgrade to Pro'),
        ),
        const DDropdownMenuSeparator(),
        DDropdownMenuGroup(
          children: [
            DDropdownMenuItem(
              leading: const Icon(Icons.verified_outlined),
              onPressed: () => setState(() => _message = 'Account selected'),
              child: const Text('Account'),
            ),
            DDropdownMenuItem(
              leading: const Icon(Icons.credit_card_outlined),
              onPressed: () => setState(() => _message = 'Billing selected'),
              child: const Text('Billing'),
            ),
            DDropdownMenuItem(
              leading: const Icon(Icons.notifications_none),
              onPressed: () =>
                  setState(() => _message = 'Notifications selected'),
              child: const Text('Notifications'),
            ),
          ],
        ),
        const DDropdownMenuSeparator(),
        DDropdownMenuItem(
          leading: const Icon(Icons.logout),
          onPressed: () => setState(() => _message = 'Logged out locally'),
          child: const Text('Log out'),
        ),
      ],
    ),
    child: DDropdownMenuTrigger(
      builder: (context, state) => DSidebarMenuButton(
        iconSize: 32,
        icon: _avatar(context),
        size: DSidebarMenuButtonSize.large,
        tooltip: 'shadcn',
        semanticLabel: 'Open shadcn account menu',
        focusNode: state.focusNode,
        expanded: state.open,
        onPressed: state.toggle,
        child: Row(
          children: [
            Expanded(child: _identityText(context, 'shadcn', 'm@example.com')),
            const _SidebarReferenceIcon(_SidebarReferenceIcon.chevronsUpDown),
          ],
        ),
      ),
    ),
  );

  Widget _avatar(BuildContext context) => DAvatar(
    dimension: 32,
    borderRadius: BorderRadius.circular(DTokens.of(context).radius * 1.6),
    image: const DAvatarImage(image: AssetImage(_avatarAsset)),
    fallback: const DAvatarFallback(child: Text('CN')),
    decorative: true,
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 440,
    child: DSidebarProvider(
      mobileBreakpoint: 500,
      child: Builder(
        builder: (context) {
          final provider = DSidebarProvider.of(context);
          final panel = DSidebar(
            width: 256,
            collapsible: DSidebarCollapsible.icon,
            rail: const DSidebarRail(),
            header: DSidebarHeader(child: _teamSwitcher(context)),
            footer: DSidebarFooter(child: _accountMenu(context)),
            child: DSidebarContent(
              children: [
                _platformNavigation(context),
                if (provider.open || provider.isMobile)
                  _projectNavigation(context),
              ],
            ),
          );
          return Row(
            textDirection: TextDirection.ltr,
            children: [
              panel,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DSidebarTrigger(),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_message),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// Exact Lucide outlines used by the upstream Sidebar demo. Lucide is ISC;
/// the repository attribution is in `licenses/lucide.txt`.
class _SidebarReferenceIcon extends StatelessWidget {
  const _SidebarReferenceIcon(this.svg);

  final String svg;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    return SvgPicture.string(
      svg,
      width: theme.size ?? 16,
      height: theme.size ?? 16,
      theme: SvgTheme(
        currentColor: theme.color ?? DTokens.of(context).foreground,
      ),
      excludeFromSemantics: true,
    );
  }

  static const galleryVerticalEnd =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 2h10"/><path d="M5 6h14"/><rect width="18" height="12" x="3" y="10" rx="2"/></svg>''';
  static const squareTerminal =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m7 11 2-2-2-2"/><path d="M11 13h4"/><rect width="18" height="18" x="3" y="3" rx="2"/></svg>''';
  static const bot =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 8V4H8"/><rect width="16" height="12" x="4" y="8" rx="2"/><path d="M2 14h2"/><path d="M20 14h2"/><path d="M15 13v2"/><path d="M9 13v2"/></svg>''';
  static const bookOpen =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 7v14"/><path d="M3 18a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h5a4 4 0 0 1 4 4 4 4 0 0 1 4-4h5a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-6a3 3 0 0 0-3 3 3 3 0 0 0-3-3z"/></svg>''';
  static const settings =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 7h-9"/><path d="M14 17H5"/><circle cx="17" cy="17" r="3"/><circle cx="7" cy="7" r="3"/></svg>''';
  static const chevronRight =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>''';
  static const chevronsUpDown =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m7 15 5 5 5-5"/><path d="m7 9 5-5 5 5"/></svg>''';
  static const frame =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 6H2"/><path d="M22 18H2"/><path d="M6 2v20"/><path d="M18 2v20"/></svg>''';
  static const chartPie =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12c.552 0 1.005-.449.95-.998a10 10 0 0 0-8.953-8.951c-.55-.055-.998.398-.998.95v8a1 1 0 0 0 1 1z"/><path d="M21.21 15.89A10 10 0 1 1 8 2.83"/></svg>''';
  static const map =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.106 5.553a2 2 0 0 0 1.788 0l3.659-1.83A1 1 0 0 1 21 4.619v12.764a1 1 0 0 1-.553.894l-4.553 2.277a2 2 0 0 1-1.788 0l-4.212-2.106a2 2 0 0 0-1.788 0l-3.659 1.83A1 1 0 0 1 3 19.381V6.618a1 1 0 0 1 .553-.894l4.553-2.277a2 2 0 0 1 1.788 0z"/><path d="M15 5.764v15"/><path d="M9 3.236v15"/></svg>''';
  static const ellipsis =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/></svg>''';
  static const folder =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 20H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h3.9a2 2 0 0 1 1.69.9l.81 1.2a2 2 0 0 0 1.67.9H20a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2Z"/></svg>''';
  static const arrowRight =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="m12 5 7 7-7 7"/></svg>''';
  static const trash2 =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><path d="M10 11v6"/><path d="M14 11v6"/></svg>''';
}

class _SidebarDemo extends StatefulWidget {
  const _SidebarDemo({
    this.mode = DSidebarCollapsible.offcanvas,
    this.variant = DSidebarVariant.sidebar,
    this.side = DSidebarSide.left,
    this.controlled = false,
    this.documentation = false,
    this.loading = false,
  });
  final DSidebarCollapsible mode;
  final DSidebarVariant variant;
  final DSidebarSide side;
  final bool controlled, documentation, loading;
  @override
  State<_SidebarDemo> createState() => _SidebarDemoState();
}

class _SidebarDemoState extends State<_SidebarDemo> {
  bool open = true, expanded = true;
  late bool loading = widget.loading;
  bool error = false;
  String selected = 'Home', query = '', message = 'Select a destination';
  String workspace = 'Acme Inc';
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void select(BuildContext context, String value) {
    setState(() {
      selected = value;
      message = '$value selected';
    });
    DSidebarProvider.of(context).setOpenMobile(false);
  }

  DPopoverSide _menuSide(BuildContext context) =>
      DSidebarProvider.of(context).isMobile
      ? DPopoverSide.bottom
      : widget.side == DSidebarSide.left
      ? DPopoverSide.right
      : DPopoverSide.left;

  Widget _workspaceMenu(BuildContext context) => DDropdownMenu(
    content: DDropdownMenuContent(
      semanticLabel: 'Workspace menu',
      side: _menuSide(context),
      width: 208,
      children: [
        const DDropdownMenuLabel(child: Text('Workspaces')),
        for (final name in [
          'Acme Inc',
          'Stark Industries',
          'Wayne Enterprises',
        ])
          DDropdownMenuItem(
            onPressed: () => setState(() {
              workspace = name;
              message = '$name workspace selected';
            }),
            trailing: workspace == name ? const Icon(Icons.check) : null,
            child: Text(name),
          ),
      ],
    ),
    child: DDropdownMenuTrigger(
      builder: (context, state) => DSidebarMenuButton(
        icon: const Icon(Icons.layers_outlined),
        tooltip: workspace,
        semanticLabel: 'Switch workspace, $workspace',
        focusNode: state.focusNode,
        expanded: state.open,
        onPressed: state.toggle,
        child: Row(
          children: [
            Expanded(child: Text(workspace)),
            Icon(state.open ? Icons.expand_less : Icons.expand_more),
          ],
        ),
      ),
    ),
  );

  Widget _accountMenu(BuildContext context) => DDropdownMenu(
    content: DDropdownMenuContent(
      semanticLabel: 'Account menu',
      side: _menuSide(context),
      align: DPopoverAlign.end,
      width: 192,
      children: [
        const DDropdownMenuLabel(child: Text('Alex Morgan')),
        DDropdownMenuItem(
          leading: const Icon(Icons.person_outline),
          onPressed: () => setState(() => message = 'Profile selected'),
          child: const Text('Profile'),
        ),
        DDropdownMenuItem(
          leading: const Icon(Icons.settings_outlined),
          onPressed: () => setState(() => message = 'Settings selected'),
          child: const Text('Settings'),
        ),
        const DDropdownMenuSeparator(),
        DDropdownMenuItem(
          leading: const Icon(Icons.logout),
          onPressed: () => setState(() => message = 'Signed out locally'),
          child: const Text('Sign out'),
        ),
      ],
    ),
    child: DDropdownMenuTrigger(
      builder: (context, state) => DSidebarMenuButton(
        iconSize: 32,
        icon: const DAvatar(
          dimension: 32,
          fallback: DAvatarFallback(child: Text('AM')),
          semanticLabel: 'Alex Morgan',
        ),
        size: DSidebarMenuButtonSize.large,
        tooltip: 'Alex Morgan',
        semanticLabel: 'Open Alex Morgan account menu',
        focusNode: state.focusNode,
        expanded: state.open,
        onPressed: state.toggle,
        child: const Text('Alex Morgan'),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 440,
    child: DSidebarProvider(
      mobileBreakpoint: widget.documentation ? 0 : 500,
      open: widget.controlled ? open : null,
      onOpenChange: widget.controlled ? (v) => setState(() => open = v) : null,
      child: Builder(
        builder: (context) {
          final panel = DSidebar(
            width: widget.documentation ? 240 : 256,
            side: widget.side,
            collapsible: widget.mode,
            variant: widget.variant,
            backgroundColor: widget.documentation
                ? DTokens.of(context).background
                : null,
            rail: widget.mode == DSidebarCollapsible.icon
                ? const DSidebarRail()
                : null,
            header: DSidebarHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  _workspaceMenu(context),
                  if (DSidebarProvider.of(context).open ||
                      DSidebarProvider.of(context).isMobile ||
                      widget.documentation)
                    DSidebarInput(
                      controller: search,
                      hintText: 'Search navigation',
                      onChanged: (v) => setState(() => query = v),
                    ),
                ],
              ),
            ),
            footer: DSidebarFooter(child: _accountMenu(context)),
            child: DSidebarContent(
              children: [
                if (loading)
                  DSkeletonRegion(
                    semanticsLabel: 'Loading navigation',
                    child: DSidebarGroup(
                      child: DSidebarMenu(
                        children: [
                          for (var i = 0; i < 7; i++)
                            DSidebarMenuSkeleton(
                              showIcon: true,
                              widthFactor: .5 + i * .05,
                            ),
                        ],
                      ),
                    ),
                  )
                else if (error)
                  DSidebarGroup(
                    child: Column(
                      children: [
                        const Text('Navigation unavailable'),
                        DButton(
                          onPressed: () => setState(() => error = false),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                else ...[
                  DSidebarGroup(
                    label: DSidebarGroupLabel(
                      child: Text(
                        widget.documentation ? 'Components' : 'Application',
                      ),
                    ),
                    child: DSidebarMenu(
                      children: [
                        for (final (index, name) in [
                          'Home',
                          'Inbox',
                          'Calendar',
                          'Search',
                          'Settings',
                          'A long navigation title that wraps with large text',
                        ].indexed)
                          if (name.toLowerCase().contains(query.toLowerCase()))
                            DSidebarMenuItem(
                              badge: name == 'Inbox'
                                  ? const DSidebarMenuBadge(child: Text('24'))
                                  : null,
                              action: name == 'Home' && !widget.documentation
                                  ? DSidebarMenuAction(
                                      semanticLabel: 'Add home shortcut',
                                      showOnHover: true,
                                      onPressed: () => setState(
                                        () => message = 'Shortcut added',
                                      ),
                                      child: const Icon(Icons.add),
                                    )
                                  : null,
                              child: DSidebarMenuButton(
                                height: widget.documentation ? 30 : null,
                                icon: widget.documentation
                                    ? null
                                    : Icon(
                                        [
                                          Icons.home_outlined,
                                          Icons.inbox_outlined,
                                          Icons.calendar_today_outlined,
                                          Icons.search,
                                          Icons.settings_outlined,
                                          Icons.description_outlined,
                                        ][index],
                                      ),
                                tooltip: name,
                                semanticLabel: name,
                                isActive: selected == name,
                                onPressed: () => select(context, name),
                                child: Text(name),
                              ),
                            ),
                        const DSidebarMenuButton(
                          icon: Icon(Icons.lock_outline),
                          child: Text('Disabled'),
                        ),
                      ],
                    ),
                  ),
                  const DSidebarSeparator(),
                  DCollapsible(
                    open: expanded,
                    onOpenChange: (value) => setState(() => expanded = value),
                    child: DSidebarGroup(
                      label: DCollapsibleTrigger(
                        focusBorderRadius: BorderRadius.circular(
                          DTokens.of(context).radius * .8,
                        ),
                        builder: (context, state) => DSidebarGroupLabel(
                          child: Row(
                            children: [
                              const Expanded(child: Text('Projects')),
                              AnimatedRotation(
                                turns: state.open ? .5 : 0,
                                duration: DMotion.duration(
                                  context,
                                  const Duration(milliseconds: 200),
                                ),
                                child: const Icon(Icons.expand_more),
                              ),
                            ],
                          ),
                        ),
                      ),
                      action: DSidebarGroupAction(
                        semanticLabel: 'New project',
                        onPressed: () =>
                            setState(() => message = 'Project created'),
                        child: const Icon(Icons.add),
                      ),
                      child: DCollapsibleContent(
                        child: DSidebarGroupContent(
                          child: DSidebarMenu(
                            children: [
                              DSidebarMenuSub(
                                children: [
                                  for (final name in ['Design', 'Engineering'])
                                    DSidebarMenuSubItem(
                                      child: DSidebarMenuSubButton(
                                        isActive: selected == name,
                                        onPressed: () => select(context, name),
                                        child: Text(name),
                                      ),
                                    ),
                                ],
                              ),
                              DSidebarMenuButton(
                                size: DSidebarMenuButtonSize.small,
                                onPressed: () => select(context, 'Small'),
                                child: const Text('Small row'),
                              ),
                              DSidebarMenuButton(
                                size: DSidebarMenuButtonSize.large,
                                variant: DSidebarMenuButtonVariant.outline,
                                onPressed: () => select(context, 'Upgrade'),
                                child: const Text('Upgrade workspace'),
                              ),
                              for (var i = 1; i <= 12; i++)
                                DSidebarMenuButton(
                                  onPressed: () =>
                                      select(context, 'Project $i'),
                                  child: Text('Project $i'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
          final body = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DSidebarTrigger(),
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 12,
                      children: [
                        Text(message),
                        if (widget.controlled)
                          Text(open ? 'Expanded' : 'Collapsed'),
                        if (widget.loading) ...[
                          DButton(
                            onPressed: () => setState(() {
                              loading = false;
                              error = false;
                            }),
                            label: const Text('Load'),
                          ),
                          DButton(
                            onPressed: () => setState(() {
                              loading = false;
                              error = true;
                            }),
                            label: const Text('Simulate failure'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
          if (widget.documentation) {
            return Align(
              alignment: AlignmentDirectional.centerStart,
              child: panel,
            );
          }
          return Row(
            textDirection: widget.side == DSidebarSide.left
                ? TextDirection.ltr
                : TextDirection.rtl,
            children: [
              panel,
              Expanded(
                child: widget.variant == DSidebarVariant.inset
                    ? DSidebarInset(child: body)
                    : body,
              ),
            ],
          );
        },
      ),
    ),
  );
}
