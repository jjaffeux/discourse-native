import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final sidebarExamples = ComponentExamples(
  description:
      'Composable navigation with collapsible panels, groups, and menus.',
  status: ComponentStatus.implemented,
  notes:
      'Sidebar ports base-nova geometry and native focus/navigation. Its mobile panel, search, group disclosure, workspace/account menus and account identity compose the accepted Sheet, Input, Collapsible, Dropdown Menu and Avatar owners. Persistence and routing remain with the app.',
  examples: [
    StyleguideExample(
      title: 'Application sidebar',
      description:
          'Header workspace menu, Input search, collapsible groups, active destinations, badges, actions and Avatar account menu. These compact demos switch to a Sheet below 500px; the component default is 768px. Cmd/Ctrl+B toggles, Tab navigates, Enter/Space activates and Escape dismisses.',
      code: '''DSidebarProvider(mobileBreakpoint: 500, child: Row(children: [
  DSidebar(header: DSidebarHeader(child: DDropdownMenu(
    child: DDropdownMenuTrigger(builder: workspaceButton),
    content: DDropdownMenuContent(children: workspaceItems))),
    child: DSidebarContent(children: [
      DSidebarGroup(label: DSidebarGroupLabel(child: Text('Application')),
        child: DSidebarMenu(children: [
          DSidebarMenuItem(child: DSidebarMenuButton(
            icon: Icon(Icons.home), isActive: true,
            onPressed: selectHome, child: Text('Home'))),
        ])),
    ])),
  Expanded(child: Column(children: [DSidebarTrigger(), content])),
]))''',
      builder: (_) => const _SidebarDemo(),
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
  ],
);

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
