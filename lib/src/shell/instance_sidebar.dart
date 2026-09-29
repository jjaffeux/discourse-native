import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/sidebar_section_store.dart';
import '../models/content_route.dart';
import '../models/group_route.dart';
import '../models/sidebar.dart';
import '../plugin_api/plugin_scope.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'adaptive_dialog_action.dart';
import 'avatar_image.dart';
import 'composer_presentation.dart';
import 'emoji.dart';
import 'external_link.dart';
import 'forum_search.dart';
import 'forum_theme_surfaces.dart';
import 'instance_actions.dart';
import 'mobile_navigation.dart';
import 'open_link.dart';
import 'platform.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';
import 'site_url.dart';
import 'skeleton_fill.dart';
import 'user_menu_button.dart';

@immutable
final class _SidebarSnapshot {
  const _SidebarSnapshot({
    required this.siteUrl,
    required this.name,
    required this.iconUrl,
    required this.monogram,
    required this.accentColor,
    required this.destinationId,
    required this.draftCount,
    required this.canCreateTopic,
    required this.sections,
    required this.navigationSections,
    required this.presentationToken,
    required this.topicTrackingRevision,
    required this.navigationLoading,
  });

  final String? siteUrl;
  final String? name;
  final String? iconUrl;
  final String? monogram;
  final Color? accentColor;
  final String? destinationId;
  final int draftCount;
  final bool canCreateTopic;
  final List<SidebarSection> sections;
  final List<SidebarSection> navigationSections;
  final Object? presentationToken;
  final int topicTrackingRevision;
  final bool navigationLoading;

  @override
  bool operator ==(Object other) {
    if (other is! _SidebarSnapshot ||
        siteUrl != other.siteUrl ||
        name != other.name ||
        iconUrl != other.iconUrl ||
        monogram != other.monogram ||
        accentColor != other.accentColor ||
        destinationId != other.destinationId ||
        draftCount != other.draftCount ||
        canCreateTopic != other.canCreateTopic ||
        !identical(presentationToken, other.presentationToken) ||
        topicTrackingRevision != other.topicTrackingRevision ||
        navigationLoading != other.navigationLoading ||
        sections.length != other.sections.length ||
        navigationSections.length != other.navigationSections.length) {
      return false;
    }
    for (var index = 0; index < sections.length; index++) {
      if (!identical(sections[index], other.sections[index])) return false;
    }
    for (var index = 0; index < navigationSections.length; index++) {
      if (!identical(
        navigationSections[index],
        other.navigationSections[index],
      )) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    siteUrl,
    name,
    iconUrl,
    monogram,
    accentColor,
    destinationId,
    draftCount,
    canCreateTopic,
    identityHashCode(presentationToken),
    topicTrackingRevision,
    navigationLoading,
    Object.hashAll(sections.map(identityHashCode)),
    Object.hashAll(navigationSections.map(identityHashCode)),
  );
}

@immutable
final class _SidebarPanelSnapshot {
  const _SidebarPanelSnapshot({
    required this.contentId,
    required this.presentation,
  });

  final String? contentId;
  final Object? presentation;

  @override
  bool operator ==(Object other) =>
      other is _SidebarPanelSnapshot &&
      contentId == other.contentId &&
      presentation == other.presentation;

  @override
  int get hashCode => Object.hash(contentId, presentation);
}

/// Everything the panel body reads from the plugin panels. A panel's
/// listenable also fires for each change to its tab's badge — Chat's fires for
/// every message in every followed channel — and only the tabs show that.
@immutable
final class _SidebarPanelShape {
  const _SidebarPanelShape(this.panels);

  final List<OwnedSidebarPanel> panels;

  static bool _sameShape(OwnedSidebarPanel a, OwnedSidebarPanel b) =>
      a.owner == b.owner &&
      listEquals(a.sectionOwners, b.sectionOwners) &&
      a.panel.label == b.panel.label &&
      a.panel.active == b.panel.active &&
      a.panel.selectedDestinationId == b.panel.selectedDestinationId &&
      (a.panel.mobileBuilder == null) == (b.panel.mobileBuilder == null) &&
      (a.panel.footerBuilder == null) == (b.panel.footerBuilder == null);

  @override
  bool operator ==(Object other) {
    if (other is! _SidebarPanelShape || other.panels.length != panels.length) {
      return false;
    }
    for (var index = 0; index < panels.length; index++) {
      if (!_sameShape(panels[index], other.panels[index])) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(panels.map((entry) => entry.owner));
}

/// What a plugin's sidebar panel contribution is read from.
Listenable _sidebarPanelChanges(BuildContext context) => Listenable.merge([
  ShellScope.read(context).accountActivity.totalsListenable,
  ...PluginScope.of(context).registry.sidebarPanelListenables(context),
]);

const String _newTopicDestinationId = 'new-topic';
const String _moreDestinationId = 'sidebar-more-destinations';
const double _sidebarRowGap = 2;

SidebarDestination get _newTopicDestination => SidebarDestination(
  id: _newTopicDestinationId,
  label: appL10n.newTopicInstancesidebar,
  icon: DIcons.plus,
);

SidebarDestination get _moreDestination => SidebarDestination(
  id: _moreDestinationId,
  label: appL10n.more,
  icon: DIcons.ellipsisVertical,
);

class InstanceSidebar extends StatelessWidget {
  const InstanceSidebar({
    super.key,
    this.showUserMenu = false,
    this.sectionStore,
    this.mobile = false,
    this.panelOwner,
    this.onNavigate,
  });

  final bool showUserMenu;
  final SidebarSectionStore? sectionStore;

  /// Mobile roots own their header and select sidebar modes in the bottom bar.
  final bool mobile;
  final String? panelOwner;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) => ForumSidebarTheme(
    child: ShellSelector<_SidebarSnapshot>(
      select: (controller) {
        final instance = controller.currentInstance;
        final currentContent = controller.currentContent;
        // The focused document owns the highlighted sidebar destination.
        var selectedDestinationId = controller.topicListTab?.rootDestinationId;
        if (currentContent?.groupRoute != null) {
          selectedDestinationId = 'groups';
        } else if (currentContent?.isBadges == true) {
          selectedDestinationId = 'badges';
        } else if (currentContent?.isTopic == true &&
            selectedDestinationId == 'drafts') {
          // Reply drafts keep Drafts in their back stack, but the topic itself
          // is not the Drafts route.
          selectedDestinationId = null;
        }
        final categorySection = instance == null
            ? null
            : controller.categorySidebarSectionFor(instance.url);
        final tagSection = instance == null
            ? null
            : controller.tagSidebarSectionFor(instance.url);
        return _SidebarSnapshot(
          siteUrl: instance?.url,
          name: instance?.title,
          iconUrl: instance?.iconUrl,
          monogram: instance?.monogram,
          accentColor: instance?.accentColor,
          // Mobile shows navigation instead of the retained content route.
          destinationId: mobile ? null : selectedDestinationId,
          draftCount: instance?.user?.draftCount ?? 0,
          canCreateTopic: instance?.user?.canCreateTopic ?? false,
          navigationLoading:
              instance != null &&
              controller.sidebarNavigationLoadingFor(instance.url),
          presentationToken: instance == null
              ? null
              : controller.presentationTokenFor(instance.url),
          topicTrackingRevision: instance == null
              ? 0
              : controller.topicTrackingRevisionFor(instance.url),
          sections: instance == null
              ? const <SidebarSection>[]
              : controller.sidebarSectionsFor(instance),
          navigationSections: [?categorySection, ?tagSection],
        );
      },
      builder: (context, sidebar, _) {
        if (sidebar.siteUrl == null) {
          return ColoredBox(
            color: ForumWindowBackground.surfaceColor(
              context,
              DTokens.of(context).muted,
            ),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) => DSidebarProvider(
            mobileBreakpoint: 0,
            open: true,
            child: SafeArea(
              top: !mobile,
              bottom: !mobile,
              left: false,
              child: _SidebarPanelBody(
                sidebar: sidebar,
                width: constraints.maxWidth,
                showUserMenu: showUserMenu,
                mobile: mobile,
                panelOwner: panelOwner,
                onNavigate: onNavigate,
                sectionStore:
                    sectionStore ?? ShellScope.read(context).sidebarSections,
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _SidebarPanelBody extends StatefulWidget {
  const _SidebarPanelBody({
    required this.sidebar,
    required this.width,
    required this.showUserMenu,
    required this.sectionStore,
    required this.mobile,
    required this.panelOwner,
    required this.onNavigate,
  });

  final _SidebarSnapshot sidebar;
  final double width;
  final bool showUserMenu;
  final SidebarSectionStore sectionStore;
  final bool mobile;
  final String? panelOwner;
  final VoidCallback? onNavigate;

  @override
  State<_SidebarPanelBody> createState() => _SidebarPanelBodyState();
}

class _SidebarPanelBodyState extends State<_SidebarPanelBody> {
  String? _selectedOwner;
  Object? _navigation;

  _SidebarSnapshot get sidebar => widget.sidebar;
  SidebarSectionStore get sectionStore => widget.sectionStore;
  bool get showUserMenu => widget.showUserMenu;
  double get width => widget.width;

  bool _shortcuts = false;
  final _linkEdit = _SidebarLinkEditController();

  @override
  void dispose() {
    _linkEdit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only the tabs follow every panel notification. The body, including a
    // panel's footer and mobile root builders, is read again when the panels
    // change shape or the forum's connection, user, config or content change.
    return _SidebarPanelShapeSelector(
      listenable: _sidebarPanelChanges(context),
      builder: (context) => ShellSelector<_SidebarPanelSnapshot>(
        select: (controller) {
          final instance = controller.currentInstance;
          return _SidebarPanelSnapshot(
            contentId:
                '${controller.activeTabId}:${controller.currentContent?.id}',
            presentation: instance == null
                ? null
                : (
                    instance.isConnected,
                    instance.user,
                    instance.config,
                    controller.currentTotals,
                  ),
          );
        },
        builder: (context, _, _) => _buildPanel(context),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final controller = ShellScope.read(context);
    final registry = PluginScope.of(context).registry;
    final panels = registry.sidebarPanels(context);
    final routedPanel = panels.where((panel) => panel.panel.active).firstOrNull;
    final navigation = (
      sidebar.siteUrl,
      controller.activeTabId,
      controller.currentContent?.id,
      routedPanel?.owner,
    );
    if (_navigation != navigation) {
      _navigation = navigation;
      _selectedOwner = routedPanel?.owner.value;
      if (routedPanel != null) _shortcuts = false;
    }
    if (widget.mobile) _selectedOwner = widget.panelOwner;
    final selectedPanel = panels
        .where((panel) => panel.owner.value == _selectedOwner)
        .firstOrNull;
    // A revoked capability immediately falls back to Forum.
    if (selectedPanel == null) _selectedOwner = null;
    final activePanel = selectedPanel;
    final showCoreSections = activePanel == null;
    final showShortcuts = showCoreSections && _shortcuts;

    if (activePanel?.panel.mobileBuilder case final builder?
        when widget.mobile) {
      return PluginUiScope.own(activePanel!.owner, Builder(builder: builder));
    }

    bool includePluginOwner(PluginId owner) {
      if (activePanel case final active?) return active.includesOwner(owner);
      return !panels.any((candidate) => candidate.includesOwner(owner));
    }

    final mobileNavigationOwners = <PluginId>{
      if (widget.mobile && showCoreSections)
        for (final group in panels)
          if (group.panel.mobileBuilder != null)
            ...group.sectionOwners.where((owner) => owner != group.owner),
    };
    // A custom mobile root owns the primary plugin's content. Keep its
    // auxiliary plugins reachable through the main navigation instead.
    bool includeSidebarOwner(PluginId owner) => showShortcuts && !widget.mobile
        ? false
        : widget.mobile && showCoreSections
        ? mobileNavigationOwners.contains(owner)
        : includePluginOwner(owner);

    final customSections = [
      for (final section in sidebar.sections)
        if (section.id.startsWith('custom-')) section,
      for (final section in sidebar.sections)
        if (section.id == 'community' &&
            section.moreDestinations.any(
              (destination) => destination.url != null,
            ))
          SidebarSection(
            id: widget.mobile ? 'mobile-shortcuts' : 'community-shortcuts',
            title: section.title,
            showHeader: !widget.mobile,
            collapsible: !widget.mobile,
            destinations: section.moreDestinations
                .where((destination) => destination.url != null)
                .toList(),
          ),
    ];
    final forumSections = widget.mobile
        ? <SidebarSection>[]
        : [
            for (final section in sidebar.sections)
              if (section.id == 'community' &&
                  section.moreDestinations.any(
                    (destination) => destination.url != null,
                  ))
                SidebarSection(
                  id: section.id,
                  title: section.title,
                  destinations: section.destinations,
                  moreDestinations: section.moreDestinations
                      .where((destination) => destination.url == null)
                      .toList(),
                  showHeader: section.showHeader,
                  collapsible: section.collapsible,
                )
              else if (!section.id.startsWith('custom-'))
                section,
          ];

    return DSidebar(
      backgroundColor: ForumWindowBackground.surfaceColor(
        context,
        DTokens.of(context).muted,
      ),
      width: width,
      collapsible: DSidebarCollapsible.none,
      semanticLabel: context.l10n.navigationInstancesidebar(
        (showShortcuts).toString(),
        ((showShortcuts) ? (context.l10n.shortcutsInstancesidebar) : '')
            .toString(),
        ((!(showShortcuts))
                ? (activePanel?.panel.label ?? context.l10n.forum)
                : '')
            .toString(),
      ),
      footer: switch (activePanel) {
        final panel? when !widget.mobile && panel.panel.footerBuilder != null =>
          PluginUiScope.own(
            panel.owner,
            Builder(builder: panel.panel.footerBuilder!),
          ),
        _ => null,
      },
      header: widget.mobile
          ? showCoreSections
                ? DSidebarHeader(
                    child: DTabs<bool>.controlled(
                      value: _shortcuts,
                      onChanged: (value) =>
                          setState(() => _shortcuts = value ?? false),
                      children: [
                        DTabList<bool>(
                          children: [
                            DTabTrigger(
                              value: false,
                              child: Text(context.l10n.forum),
                            ),
                            DTabTrigger(
                              value: true,
                              child: Text(
                                context.l10n.shortcutsInstancesidebar,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showUserMenu) const _SidebarUserHeader(),
                DSidebarHeader(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: ForumIdentityHeader(
                    siteUrl: sidebar.siteUrl!,
                    name: sidebar.name!,
                    iconUrl: sidebar.iconUrl,
                    monogram: sidebar.monogram!,
                    accentColor: sidebar.accentColor!,
                  ),
                ),
                DSidebarHeader(
                  child: _SidebarPanelTabs(
                    selectedOwner: selectedPanel?.owner.value,
                    shortcutsSelected: _shortcuts,
                    onSelected: (owner) => setState(() {
                      _shortcuts = owner == 'shortcuts';
                      _selectedOwner = owner == 'forum' || _shortcuts
                          ? null
                          : owner;
                    }),
                  ),
                ),
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showUserMenu && showCoreSections && !showShortcuts)
            const _SidebarSearchRow(),
          Expanded(
            child: DSidebarReorderScope(
              key: ValueKey(sidebar.siteUrl),
              child: DSidebarContent.slivers(
                slivers: [
                  DSidebarGroup.sliver(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                    sliver: SliverMainAxisGroup(
                      slivers: [
                        if (showCoreSections)
                          ListenableBuilder(
                            listenable: Listenable.merge([
                              _linkEdit,
                              controller.accountActivity.totalsListenable,
                              controller.draftList,
                              controller.topicFeeds,
                              ...registry.communitySidebarListenables(
                                context,
                                includeOwner: includePluginOwner,
                              ),
                            ]),
                            builder: (context, _) => SliverMainAxisGroup(
                              slivers: [
                                for (final (sections, loading) in [
                                  (
                                    showShortcuts
                                        ? customSections
                                        : forumSections,
                                    false,
                                  ),
                                  (
                                    showShortcuts
                                        ? <SidebarSection>[]
                                        : sidebar.navigationSections,
                                    sidebar.navigationLoading,
                                  ),
                                ])
                                  _RestoredSidebarSections(
                                    siteUrl: sidebar.siteUrl!,
                                    sections: sections,
                                    store: sectionStore,
                                    loading: loading,
                                    child: SliverMainAxisGroup(
                                      slivers: [
                                        for (final section in sections)
                                          _Section(
                                            key: ValueKey((
                                              sidebar.siteUrl,
                                              section.id,
                                            )),
                                            siteUrl: sidebar.siteUrl!,
                                            section: section,
                                            linkEdit: _linkEdit,
                                            appendedDestinations:
                                                section.id == 'community'
                                                ? registry
                                                      .communitySidebarDestinations(
                                                        context,
                                                        includeOwner:
                                                            includePluginOwner,
                                                      )
                                                : const [],
                                            store: sectionStore,
                                            selectedId: sidebar.destinationId,
                                            loadingDestinationId:
                                                switch (controller
                                                    .currentFeed) {
                                                  final feed?
                                                      when feed.loading &&
                                                          feed
                                                              .topicIds
                                                              .isNotEmpty =>
                                                    controller.currentFeedId,
                                                  _ => null,
                                                },
                                            badgeFor:
                                                controller.sidebarBadgeFor,
                                            insertedDestination:
                                                sidebar.canCreateTopic &&
                                                    section.destinations.any(
                                                      (destination) =>
                                                          destination.id ==
                                                          'messages',
                                                    )
                                                ? _newTopicDestination
                                                : null,
                                            insertAfterDestinationId:
                                                'messages',
                                            onSelect: (destination) {
                                              widget.onNavigate?.call();
                                              if (destination.id ==
                                                  _newTopicDestinationId) {
                                                unawaited(
                                                  controller
                                                      .openNewTopicFromSidebar(),
                                                );
                                                return;
                                              }
                                              if (destination.id == 'admin') {
                                                unawaited(
                                                  openExternalLink(
                                                    resolveSitePath(
                                                      sidebar.siteUrl!,
                                                      'admin',
                                                    ),
                                                  ),
                                                );
                                                return;
                                              }
                                              final url = destination.url;
                                              if (url == null) {
                                                if (widget.mobile) {
                                                  controller
                                                      .selectMobileDestination(
                                                        MobileTab.topics,
                                                        destination,
                                                      );
                                                } else {
                                                  controller.selectDestination(
                                                    destination,
                                                  );
                                                }
                                              } else {
                                                unawaited(
                                                  openLink(
                                                    context,
                                                    url,
                                                    title: destination.label,
                                                    siteUrl: sidebar.siteUrl,
                                                  ),
                                                );
                                              }
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if ((!widget.mobile ||
                                !showCoreSections ||
                                mobileNavigationOwners.isNotEmpty) &&
                            !showShortcuts)
                          ListenableBuilder(
                            listenable: Listenable.merge(
                              registry.sidebarListenables(
                                context,
                                includeOwner: includeSidebarOwner,
                              ),
                            ),
                            builder: (context, _) {
                              final sections = registry.sidebarSections(
                                context,
                                includeOwner: includeSidebarOwner,
                              );
                              return _RestoredSidebarSections(
                                siteUrl: sidebar.siteUrl!,
                                sections: sections,
                                store: sectionStore,
                                child: SliverMainAxisGroup(
                                  slivers: [
                                    for (final section in sections)
                                      _Section(
                                        key: ValueKey((
                                          sidebar.siteUrl,
                                          section.id,
                                        )),
                                        siteUrl: sidebar.siteUrl!,
                                        section: section,
                                        store: sectionStore,
                                        selectedId: widget.mobile
                                            ? null
                                            : selectedPanel
                                                      ?.panel
                                                      .selectedDestinationId ??
                                                  sidebar.destinationId,
                                        badgeFor: controller.sidebarBadgeFor,
                                        onSelect: controller.selectDestination,
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarSearchRow extends StatelessWidget {
  const _SidebarSearchRow();

  static const EdgeInsets _padding = EdgeInsets.fromLTRB(8, 6, 8, 5);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 44,
      padding: _padding,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.shell.divider)),
      ),
      child: const ForumSearch(
        key: ValueKey('instance-sidebar-search-target'),
        dense: true,
      ),
    );
  }
}

/// Rebuilds [builder] only when the plugin panels change shape, not for each
/// notification that leaves them the same (see [_SidebarPanelShape]).
class _SidebarPanelShapeSelector extends StatefulWidget {
  const _SidebarPanelShapeSelector({
    required this.listenable,
    required this.builder,
  });

  final Listenable listenable;
  final WidgetBuilder builder;

  @override
  State<_SidebarPanelShapeSelector> createState() =>
      _SidebarPanelShapeSelectorState();
}

class _SidebarPanelShapeSelectorState
    extends State<_SidebarPanelShapeSelector> {
  _SidebarPanelShape? _shape;

  _SidebarPanelShape _read() => _SidebarPanelShape(
    PluginScope.of(context).registry.sidebarPanels(context),
  );

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(_SidebarPanelShapeSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.listenable, widget.listenable)) {
      oldWidget.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
  }

  void _changed() {
    if (_read() != _shape) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _shape = _read();
    return widget.builder(context);
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }
}

class _SidebarPanelTabs extends StatelessWidget {
  const _SidebarPanelTabs({
    required this.selectedOwner,
    required this.shortcutsSelected,
    required this.onSelected,
  });

  final String? selectedOwner;
  final bool shortcutsSelected;
  final ValueChanged<String> onSelected;

  // The tabs read the panels for themselves, so a badge change redraws them
  // without the sections beneath.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _sidebarPanelChanges(context),
    builder: (context, _) => _tabs(context),
  );

  Widget _tabs(BuildContext context) {
    final panels = PluginScope.of(context).registry.sidebarPanels(context);
    return DTabs<String>.controlled(
      key: const ValueKey('sidebar-panel-tabs'),
      value: shortcutsSelected ? 'shortcuts' : selectedOwner ?? 'forum',
      onChanged: (value) {
        if (value != null) onSelected(value);
      },
      children: [
        DTabList<String>(
          variant: DTabListVariant.line,
          children: [
            DTabTrigger(
              key: const ValueKey('sidebar-panel-switch-main'),
              value: 'forum',
              child: Text(context.l10n.forum),
            ),
            for (final candidate in panels)
              if (candidate.panel.showSwitch)
                DTabTrigger(
                  key: ValueKey(
                    'sidebar-panel-switch-${candidate.owner.value}',
                  ),
                  value: candidate.owner.value,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: DSpacing.xs,
                    children: [
                      Text(candidate.panel.label),
                      ?candidate.panel.badge,
                    ],
                  ),
                ),
            DTabTrigger(
              key: const ValueKey('sidebar-panel-switch-shortcuts'),
              value: 'shortcuts',
              child: Text(context.l10n.shortcutsInstancesidebar),
            ),
          ],
        ),
      ],
    );
  }
}

class _SidebarUserHeader extends StatelessWidget {
  const _SidebarUserHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('sidebar-user-header'),
      constraints: const BoxConstraints(minHeight: shellHeaderHeight),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.shell.divider)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ...PluginScope.of(context).registry.shellHeaderActions(
            context,
            surface: PluginHeaderSurface.content,
            compact: true,
            ringColor: theme.shell.sidebar,
          ),
          const UserMenuButton(),
        ],
      ),
    );
  }
}

class ForumIdentityHeader extends StatelessWidget {
  const ForumIdentityHeader({
    super.key,
    required this.siteUrl,
    required this.name,
    required this.iconUrl,
    required this.monogram,
    required this.accentColor,
    this.compact = false,
    this.showName = false,
  });
  final String siteUrl;
  final String name;
  final String? iconUrl;
  final String monogram;
  final Color accentColor;
  final bool compact;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final fallbackForeground =
        ThemeData.estimateBrightnessForColor(accentColor) == Brightness.dark
        ? Colors.white
        : Colors.black;
    final logo = DAvatar.frame(
      key: const ValueKey('forum-identity-logo'),
      border: false,
      borderRadius: BorderRadius.circular(6),
      child: AvatarImage(
        url: iconUrl,
        size: 32,
        fit: BoxFit.contain,
        fallback: ColoredBox(
          color: accentColor,
          child: Center(
            child: Text(monogram, style: TextStyle(color: fallbackForeground)),
          ),
        ),
      ),
    );
    return DDropdownMenu(
      key: const ValueKey('forum-identity-header'),
      content: DDropdownMenuContent(
        width: 240,
        children: [
          DDropdownMenuItem(
            key: const ValueKey('forum-identity-open-browser'),
            leading: const DIcon(DIcons.upRightFromSquare, size: 16),
            onPressed: () => unawaited(openExternalLink(siteUrl)),
            child: Text(context.l10n.openForumInBrowser),
          ),
          const DDropdownMenuSeparator(),
          DDropdownMenuItem(
            key: const ValueKey('forum-identity-remove'),
            leading: const DIcon(DIcons.trashCan, size: 16),
            variant: DDropdownMenuItemVariant.destructive,
            onPressed: () async {
              final instance = ShellScope.read(context).currentInstance;
              if (instance != null) {
                await confirmInstanceRemoval(context, instance);
              }
            },
            child: Text(context.l10n.removeForum),
          ),
        ],
      ),
      child: DDropdownMenuTrigger(
        builder: (context, menu) => compact && showName
            ? DButton(
                key: const ValueKey('forum-identity-button'),
                icon: logo,
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: DSpacing.sm),
                    const Icon(Icons.unfold_more_rounded),
                  ],
                ),
                tooltip: name,
                semanticLabel: context.l10n.forumMenu((name).toString()),
                variant: DButtonVariant.inline,
                size: compact ? DButtonSize.regular : DButtonSize.large,
                focusNode: menu.focusNode,
                hasPopup: true,
                expanded: menu.open,
                onPressed: menu.toggle,
              )
            : compact
            ? DButton.iconOnly(
                key: const ValueKey('forum-identity-button'),
                icon: logo,
                tooltip: name,
                semanticLabel: context.l10n.forumMenu((name).toString()),
                variant: DButtonVariant.ghost,
                size: compact ? DButtonSize.regular : DButtonSize.large,
                focusNode: menu.focusNode,
                hasPopup: true,
                expanded: menu.open,
                onPressed: menu.toggle,
              )
            : DSidebarMenuButton(
                key: const ValueKey('forum-identity-button'),
                size: DSidebarMenuButtonSize.large,
                focusNode: menu.focusNode,
                expanded: menu.open,
                onPressed: menu.toggle,
                iconSize: 32,
                icon: logo,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (!compact)
                            Text(
                              siteUrl.replaceFirst(RegExp(r'^https?://'), ''),
                              key: const ValueKey('forum-identity-url'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: DiscourseTypography.xs,
                                height: 16 / 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: DSpacing.sm),
                    const Icon(Icons.unfold_more_rounded, size: 16),
                  ],
                ),
              ),
      ),
    );
  }
}

class _SidebarLinkEdit {
  const _SidebarLinkEdit(this.siteUrl, this.destinations);
  final String siteUrl;
  final Map<SidebarSection, List<SidebarDestination>> destinations;
}

class _SidebarLinkEditController extends ValueNotifier<_SidebarLinkEdit?> {
  _SidebarLinkEditController() : super(null);
  bool _disposed = false;

  void finish(_SidebarLinkEdit edit) {
    if (!_disposed && identical(value, edit)) value = null;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _Section extends StatefulWidget {
  const _Section({
    super.key,
    required this.siteUrl,
    required this.section,
    required this.store,
    required this.selectedId,
    required this.badgeFor,
    required this.onSelect,
    this.loadingDestinationId,
    this.linkEdit,
    this.insertedDestination,
    this.insertAfterDestinationId,
    this.appendedDestinations = const [],
  });

  final String siteUrl;
  final SidebarSection section;
  final _SidebarLinkEditController? linkEdit;
  final SidebarSectionStore store;
  final String? selectedId;
  final String? loadingDestinationId;
  final SidebarBadge Function(String destinationId) badgeFor;
  final ValueChanged<SidebarDestination> onSelect;
  final SidebarDestination? insertedDestination;
  final String? insertAfterDestinationId;
  final List<SidebarDestination> appendedDestinations;

  @override
  State<_Section> createState() => _SectionState();
}

class _RestoredSidebarSections extends StatefulWidget {
  const _RestoredSidebarSections({
    required this.siteUrl,
    required this.sections,
    required this.store,
    required this.child,
    this.loading = false,
  });

  final String siteUrl;
  final List<SidebarSection> sections;
  final SidebarSectionStore store;
  final Widget child;
  final bool loading;

  @override
  State<_RestoredSidebarSections> createState() =>
      _RestoredSidebarSectionsState();
}

class _RestoredSidebarSectionsState extends State<_RestoredSidebarSections> {
  int _generation = 0;

  Iterable<SidebarSection> get _unrestored => widget.sections.where(
    (section) =>
        section.collapsible &&
        widget.store.collapsedFor(
              siteUrl: widget.siteUrl,
              sectionId: section.id,
            ) ==
            null,
  );

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void didUpdateWidget(_RestoredSidebarSections oldWidget) {
    super.didUpdateWidget(oldWidget);
    _restore();
  }

  void _restore() {
    final generation = ++_generation;
    final pending = [
      for (final section in _unrestored)
        widget.store.ensure(siteUrl: widget.siteUrl, sectionId: section.id),
    ];
    if (pending.isEmpty) return;
    unawaited(
      Future.wait(pending).then((_) {
        if (mounted && generation == _generation) setState(() {});
      }),
    );
  }

  @override
  Widget build(BuildContext context) => widget.loading || _unrestored.isNotEmpty
      ? const SliverToBoxAdapter(child: _SidebarLoadingSkeleton())
      : widget.child;
}

class _SidebarLoadingSkeleton extends StatelessWidget {
  const _SidebarLoadingSkeleton({this._semanticsLabel, this.rowCount = 8});

  final String? _semanticsLabel;
  String get semanticsLabel => _semanticsLabel ?? appL10n.loadingNavigation;
  final int rowCount;

  @override
  Widget build(BuildContext context) => DSkeletonRegion(
    expand: true,
    key: const ValueKey('sidebar-loading-skeleton'),
    semanticsLabel: semanticsLabel,
    color: skeletonFill(context, on: SkeletonSurface.panel),
    child: DSidebarMenu(
      children: [
        for (var row = 0; row < rowCount; row++)
          DSidebarMenuSkeleton(
            showIcon: true,
            widthFactor: row.isEven ? .7 : .55,
          ),
      ],
    ),
  );
}

class _SectionState extends State<_Section> {
  bool _collapsed = false;
  bool _reordering = false;
  List<SidebarDestination>? _pendingDestinations;

  bool get _busy =>
      _reordering || widget.linkEdit?.value?.siteUrl == widget.siteUrl;

  bool _canMove(DSidebarMove move) =>
      !_busy &&
      move.sourceId is SidebarSection &&
      move.targetId == widget.section &&
      ShellScope.read(context).canMoveSidebarLink(
        siteUrl: widget.siteUrl,
        source: move.sourceId as SidebarSection,
        target: widget.section,
        oldIndex: move.oldIndex,
        newIndex: move.newIndex,
      );

  Future<void> _move(DSidebarMove move) async {
    final edits = widget.linkEdit;
    if (edits == null || !_canMove(move)) return;
    final controller = ShellScope.read(context);
    final source = move.sourceId as SidebarSection;
    final target = widget.section;
    final siteUrl = widget.siteUrl;
    final sourceRows = source.destinations.toList();
    final moved = sourceRows.removeAt(move.oldIndex);
    final targetRows = target.destinations.toList()
      ..insert(move.newIndex, moved);
    final edit = _SidebarLinkEdit(siteUrl, {
      source: sourceRows,
      target: targetRows,
    });
    edits.value = edit;
    try {
      if (source.public || target.public) {
        final confirmed = await showDiscourseAlertDialog<bool>(
          context: context,
          title: Text(appL10n.movePublicLink),
          description: Text(
            appL10n.thisChangesAPublicSidebarSectionForEveryoneOnThisForum,
          ),
          cancelLabel: Text(appL10n.cancel),
          actionLabel: Text(appL10n.move),
          actionResult: true,
        );
        if (confirmed != true) return;
      }
      if (!mounted ||
          widget.siteUrl != siteUrl ||
          !identical(widget.section, target)) {
        return;
      }
      await controller.moveSidebarLink(
        siteUrl: siteUrl,
        source: source,
        target: target,
        oldIndex: move.oldIndex,
        newIndex: move.newIndex,
      );
    } catch (_) {
      if (mounted && widget.siteUrl == siteUrl) {
        DToast.show(
          context,
          appL10n.couldnTMoveLinkTryAgain,
          type: DToastType.error,
        );
      }
    } finally {
      edits.finish(edit);
    }
  }

  void _selectDestination(SidebarDestination destination) {
    ComposerPresentationHost.redockForNavigation(context);
    final onTap = destination.onTap;
    if (onTap != null) {
      onTap();
    } else {
      widget.onSelect(destination);
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (_busy || newIndex == oldIndex || newIndex == oldIndex + 1) return;
    final controller = ShellScope.read(context);
    final section = widget.section;
    final siteUrl = widget.siteUrl;
    final destinations = section.destinations.toList();
    final moved = destinations.removeAt(oldIndex);
    destinations.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, moved);
    final edit = _SidebarLinkEdit(siteUrl, {section: destinations});
    widget.linkEdit?.value = edit;
    // Keep the dropped order visible while confirming and saving. The
    // controller retains the saved order until the server accepts the change.
    setState(() {
      _reordering = true;
      _pendingDestinations = destinations;
    });
    try {
      if (section.public) {
        final confirmed = await showDiscourseAlertDialog<bool>(
          context: context,
          title: Text(appL10n.reorderPublicLinks),
          description: Text(
            appL10n.thisChangesTheSidebarLinkOrderForEveryoneOnThisForum,
          ),
          cancelLabel: Text(appL10n.cancel),
          actionLabel: Text(appL10n.reorder),
          actionResult: true,
        );
        if (confirmed != true) return;
      }
      if (!mounted ||
          widget.siteUrl != siteUrl ||
          !identical(widget.section, section)) {
        return;
      }
      await controller.reorderSidebarLinks(
        siteUrl: siteUrl,
        section: section,
        oldIndex: oldIndex,
        newIndex: newIndex,
      );
    } catch (_) {
      if (mounted && widget.siteUrl == siteUrl) {
        DToast.show(
          context,
          appL10n.couldnTReorderLinksTryAgain,
          type: DToastType.error,
        );
      }
    } finally {
      widget.linkEdit?.finish(edit);
      if (mounted) {
        setState(() {
          _reordering = false;
          _pendingDestinations = null;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _collapsed =
        widget.store.collapsedFor(
          siteUrl: widget.siteUrl,
          sectionId: widget.section.id,
        ) ??
        false;
  }

  @override
  void didUpdateWidget(_Section oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl ||
        !identical(oldWidget.section, widget.section)) {
      _pendingDestinations = null;
    }
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.section.id != widget.section.id ||
        oldWidget.section.collapsible != widget.section.collapsible ||
        !identical(oldWidget.store, widget.store)) {
      _collapsed =
          widget.store.collapsedFor(
            siteUrl: widget.siteUrl,
            sectionId: widget.section.id,
          ) ??
          false;
    }
  }

  void _setOpen(bool open) {
    final collapsed = !open;
    setState(() => _collapsed = collapsed);
    unawaited(
      widget.store.write(
        siteUrl: widget.siteUrl,
        sectionId: widget.section.id,
        collapsed: collapsed,
      ),
    );
  }

  Widget _destinationMenus(
    BuildContext context,
    SidebarSection section,
    bool canEdit,
  ) {
    final preview = widget.linkEdit?.value;
    final pending = preview?.siteUrl == widget.siteUrl
        ? preview?.destinations[section]
        : null;
    final destinations = <SidebarDestination>[
      ...canEdit
          ? pending ?? _pendingDestinations ?? section.destinations
          : section.destinations,
      ...widget.appendedDestinations,
      for (final destination in section.moreDestinations)
        if (destination.id == widget.selectedId) destination,
      if (section.moreDestinations.isNotEmpty) _moreDestination,
    ];
    final rows = <SidebarDestination>[
      for (final destination in destinations) ...[
        destination,
        if (destination.id == widget.insertAfterDestinationId &&
            widget.insertedDestination != null)
          widget.insertedDestination!,
      ],
    ];
    final more = [
      for (final destination in section.moreDestinations)
        if (destination.id != widget.selectedId) destination,
    ];
    final runs = <List<SidebarDestination>>[];
    for (final destination in rows) {
      if (runs.isEmpty || runs.last.first.indent != destination.indent) {
        runs.add([]);
      }
      runs.last.add(destination);
    }
    final scalable = MediaQuery.textScalerOf(context).scale(14) > 14;
    final menus = <Widget>[];
    for (final run in runs) {
      final submenu = run.first.indent > 0;
      final indexes = {for (final (index, row) in run.indexed) row.id: index};
      final reorderable =
          !submenu &&
          runs.length == 1 &&
          rows.length == section.destinations.length &&
          canEdit;
      int? findIndex(Key key) =>
          key is ValueKey<String> ? indexes[key.value] : null;
      Widget rowBuilder(BuildContext context, int index) {
        final destination = run[index];
        if (destination.id == _moreDestinationId) {
          return _MoreDestinationsTile(
            destinations: more,
            onSelect: _selectDestination,
          );
        }
        return SidebarDestinationTile(
          key: submenu ? ValueKey(destination.id) : null,
          destination: destination,
          selected: destination.id == widget.selectedId,
          loading: destination.id == widget.loadingDestinationId,
          badge: widget.badgeFor(destination.id),
          submenu: submenu,
          iconSize: section.id.startsWith('custom-') ? 12 : 16,
          reorderable: reorderable,
          onTap: () => _selectDestination(destination),
        );
      }

      final extent = scalable
          ? null
          : context.isTouch
          ? 48.0
          : DControlStyle.height(
              DSidebarMenuButtonSize.large,
              context: context,
            );
      Widget paddedRow(BuildContext context, int index) => Padding(
        key: ValueKey(run[index].id),
        padding: const EdgeInsets.only(bottom: _sidebarRowGap),
        child: rowBuilder(context, index),
      );
      final menu = submenu
          ? DSidebarMenuSub.sliverBuilder(
              itemCount: run.length,
              itemBuilder: rowBuilder,
              itemExtent: extent,
              findChildIndexCallback: findIndex,
            )
          : reorderable
          ? DSidebarReorderableMenu.sliverBuilder(
              itemCount: run.length,
              itemBuilder: paddedRow,
              itemExtent: extent == null ? null : extent + _sidebarRowGap,
              onReorder: _busy ? null : _reorder,
              sectionId: section,
              onMove: _busy ? null : _move,
              canMove: _canMove,
            )
          : DSidebarMenu.sliverBuilder(
              itemCount: run.length,
              itemBuilder: paddedRow,
              itemExtent: extent == null ? null : extent + _sidebarRowGap,
              findChildIndexCallback: findIndex,
            );
      menus.add(
        submenu && run.first.indent > 1
            ? SliverPadding(
                padding: EdgeInsetsDirectional.only(
                  start: (run.first.indent - 1) * 24,
                ),
                sliver: menu,
              )
            : menu,
      );
    }
    return SliverMainAxisGroup(slivers: menus);
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    if (section.loading) {
      return SliverToBoxAdapter(
        child: _SidebarLoadingSkeleton(
          semanticsLabel: context.l10n.loadingInstancesidebar(
            (section.title).toString(),
          ),
          rowCount: 4,
        ),
      );
    }
    final canEdit = ShellScope.read(
      context,
    ).canEditSidebarLinks(widget.siteUrl, section);
    // A section drawn by its own body never lays out its destinations.
    final content = switch (section.bodyBuilder) {
      final builder? => Builder(builder: builder),
      null => _destinationMenus(context, section, canEdit),
    };
    final header = _SectionHeader(
      section: section,
      collapsed: _collapsed,
      onPressed: () => _setOpen(_collapsed),
    );
    final group = SliverMainAxisGroup(
      slivers: [
        if (section.actionAboveHeader && section.onAction != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: DSpacing.sm),
              child: DButton(
                key: ValueKey('sidebar-section-action-${section.id}'),
                variant: DButtonVariant.primary,
                label: Text(section.actionLabel ?? section.title),
                icon: DIcon(section.actionIcon ?? DIcons.plus, size: 16),
                tooltip: section.actionLabel ?? section.title,
                shortcut: section.actionShortcut == null
                    ? null
                    : DShortcut(section.actionShortcut!),
                onPressed: section.onAction,
              ),
            ),
          ),
        if (section.showHeader)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: _sidebarRowGap),
              child: section.remoteId == null
                  ? header
                  : DSidebarDropTarget(
                      sectionId: section,
                      index: section.destinations.length,
                      append: true,
                      onMove: canEdit && !_busy ? _move : null,
                      canMove: _canMove,
                      child: header,
                    ),
            ),
          ),
        if (section.collapsible)
          DCollapsibleContent.sliver(sliver: content)
        else
          content,
        if (section.moreDestinations.isNotEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: DSeparator(),
            ),
          ),
      ],
    );
    return section.collapsible
        ? DCollapsible(open: !_collapsed, onOpenChange: _setOpen, child: group)
        : group;
  }
}

class _MoreDestinationsTile extends StatelessWidget {
  const _MoreDestinationsTile({
    required this.destinations,
    required this.onSelect,
  });
  final List<SidebarDestination> destinations;
  final ValueChanged<SidebarDestination> onSelect;

  @override
  Widget build(BuildContext context) => DDropdownMenu(
    content: DDropdownMenuContent(
      width: 240,
      children: [
        for (final destination in destinations)
          DDropdownMenuItem(
            leading: DIcon(
              destination.icon,
              size: 16,
              color: destination.iconColor,
            ),
            onPressed: destination.enabled ? () => onSelect(destination) : null,
            child: Text(destination.label),
          ),
      ],
    ),
    child: DDropdownMenuTrigger(
      builder: (context, menu) => DSidebarMenuButton(
        size: DSidebarMenuButtonSize.large,
        icon: const DIcon(DIcons.ellipsisVertical, size: 16),
        focusNode: menu.focusNode,
        expanded: menu.open,
        onPressed: menu.toggle,
        child: Text(context.l10n.more),
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.section,
    required this.collapsed,
    required this.onPressed,
  });
  final SidebarSection section;
  final bool collapsed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final unreadDescription = section.unreadCount > 0
        ? context.l10n.unreadInstancesidebar(section.unreadCount)
        : '';
    final description = context.l10n.messageInstancesidebar(
      (collapsed).toString(),
      ((collapsed) ? (context.l10n.expand) : '').toString(),
      (section.title).toString(),
      (unreadDescription).toString(),
      ((!(collapsed)) ? (context.l10n.collapse) : '').toString(),
    );
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DSpacing.xs,
      children: [
        Flexible(
          child: Text(
            section.title,
            maxLines: MediaQuery.textScalerOf(context).scale(14) > 14 ? 2 : 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (section.unreadCount > 0)
          DBadge(
            key: ValueKey('sidebar-section-unread-${section.id}'),
            size: DBadgeSize.compact,
            backgroundColor: Theme.of(context).discourse.success,
            foregroundColor: Theme.of(context).discourse.notificationForeground,
            child: Text(
              section.unreadCount > 99 ? '99+' : '${section.unreadCount}',
            ),
          ),
      ],
    );
    final expandIcon = Directionality.of(context) == TextDirection.rtl
        ? DIcons.chevronLeft
        : DIcons.chevronRight;
    return DSidebarMenuItem(
      action:
          section.headerActionsBuilder != null ||
              (!section.actionAboveHeader && section.onAction != null)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (section.headerActionsBuilder != null)
                  section.headerActionsBuilder!(context),
                if (!section.actionAboveHeader && section.onAction != null)
                  DTooltip(
                    message: section.actionLabel ?? section.title,
                    shortcut: section.actionShortcut == null
                        ? null
                        : DShortcut(section.actionShortcut!),
                    child: DSidebarMenuAction(
                      semanticLabel: section.actionLabel ?? section.title,
                      onPressed: section.onAction,
                      child: DIcon(section.actionIcon ?? DIcons.plus, size: 16),
                    ),
                  ),
              ],
            )
          : null,
      child: section.collapsible
          ? DSidebarMenuButton(
              size: DSidebarMenuButtonSize.large,
              icon: DIcon(
                collapsed ? expandIcon : DIcons.chevronDown,
                size: 16,
              ),
              iconSize: context.isTouch ? 22 : 18,
              semanticLabel: description,
              expanded: !collapsed,
              onPressed: onPressed,
              child: ExcludeSemantics(child: label),
            )
          : DSidebarGroupLabel(child: label),
    );
  }
}

/// Shared destination presentation for forum navigation and appearance previews.
class SidebarDestinationTile extends StatelessWidget {
  const SidebarDestinationTile({
    super.key,
    required this.destination,
    required this.selected,
    this.loading = false,
    required this.badge,
    this.submenu = false,
    this.iconSize = 16,
    this.reorderable = false,
    required this.onTap,
  });
  final SidebarDestination destination;
  final bool selected;
  final bool loading;
  final SidebarBadge badge;
  final bool submenu;
  final double iconSize;

  /// Whether a touch long press on this row starts a reordering drag, which
  /// the link context menu must then leave to the reorderable list.
  final bool reorderable;
  final VoidCallback onTap;

  Widget _prefixArt(BuildContext context, Color foreground) {
    final theme = Theme.of(context);
    final artSize = context.isTouch ? 22.0 : 18.0;

    if (loading) {
      return SizedBox.square(
        key: ValueKey('sidebar-destination-loading-${destination.id}'),
        dimension: 16.0,
        child: DSkeletonRegion(
          semanticsLabel: context.l10n.loadingInstancesidebarValue(
            (destination.label).toString(),
          ),
          color: skeletonFill(context, on: SkeletonSurface.row),
          child: const DSkeleton.circle(diameter: 16),
        ),
      );
    }

    if (destination.prefixBuilder case final builder?) {
      return builder(context, artSize);
    }

    if (destination.avatarUrl case final url?) {
      return DAvatar.frame(
        child: SizedBox(
          width: artSize,
          height: artSize,
          child: AvatarImage(
            url: url,
            size: artSize,
            fallback: ColoredBox(color: theme.shell.floating),
          ),
        ),
      );
    }

    if (destination.emoji case final emoji?) {
      final controller = ShellScope.read(context);
      final siteUrl = controller.currentInstance?.url;
      if (siteUrl != null) {
        return EmojiImage(
          url: controller.emojiUrlFor(siteUrl, emoji),
          size: 16.0,
          alt: ':$emoji:',
          style: theme.textTheme.labelSmall,
        );
      }
    }

    if (destination.color case final color?) {
      final parentColor = destination.parentColor;
      return Container(
        key: ValueKey('sidebar-prefix-${destination.id}'),
        width: context.isTouch ? 12 : 10,
        height: context.isTouch ? 12 : 10,
        decoration: BoxDecoration(
          color: parentColor == null ? color : null,
          gradient: parentColor == null
              ? null
              : LinearGradient(
                  colors: [parentColor, color],
                  stops: const [0.5, 0.5],
                ),
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }

    return DIcon(
      destination.icon,
      size: iconSize,
      color: destination.iconColor ?? foreground,
    );
  }

  Widget _prefix(BuildContext context, Color foreground) {
    final art = _prefixArt(context, foreground);
    final badge = destination.prefixBadgeIcon;
    if (badge == null) return art;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        art,
        Positioned(
          top: -3,
          right: -3,
          child: DIcon(badge, size: 9, color: foreground),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = DTokens.of(context).foreground;
    final badge = destination.badge ?? this.badge;
    final trailingLabel = destination.trailingLabel;
    final action = destination.onSecondaryTap;
    final description = destination.semanticDescription;
    final count = badge.isVisible && !badge.dot ? badge.count : null;
    final dotLabel = badge.urgent
        ? context.l10n.unreadMentions
        : context.l10n.unread;
    // The trailing texts sit beside the button, outside its node, so they are
    // spoken as part of its name instead: otherwise a screen reader stops on
    // a bare number before it reaches the destination the number belongs to.
    // The count wording matches the forum tab badges; the drafts count is
    // not unread activity, so it stays a plain number as in the user menu.
    final semanticDetails = [
      ?description,
      ?trailingLabel,
      if (count != null)
        destination.id == 'drafts'
            ? '$count'
            : context.l10n.messageInstancesidebarValue(
                count,
                ((count == 1) ? (context.l10n.unreadItem) : '').toString(),
                ((!(count == 1)) ? (context.l10n.unreadItems) : '').toString(),
              ),
    ];
    Widget tile = DSidebarMenuItem(
      badge: trailingLabel != null || count != null
          ? DSidebarMenuBadge(
              child: ExcludeSemantics(
                child: Wrap(
                  spacing: 4,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (trailingLabel != null)
                      Text(
                        trailingLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (count != null)
                      Text(
                        '$count',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            )
          : null,
      action:
          destination.hoverActionBuilder?.call(context) ??
          (action == null
              ? null
              : DSidebarMenuAction(
                  semanticLabel: context.l10n.openInstancesidebar(
                    (destination.label).toString(),
                  ),
                  onPressed: destination.enabled ? action : null,
                  child: DIcon(
                    destination.trailingIcon ?? DIcons.chevronRight,
                    size: 16,
                  ),
                )),
      child: DSidebarMenuButton(
        size: DSidebarMenuButtonSize.large,
        isActive: selected,
        onPressed: destination.enabled ? onTap : null,
        iconSize: context.isTouch ? 22 : 18,
        icon: Center(child: _prefix(context, foreground)),
        // A label replaces the row's own text semantics, dot included.
        semanticLabel: semanticDetails.isEmpty
            ? null
            : [
                destination.label,
                ...semanticDetails,
                if (badge.isVisible && badge.dot) dotLabel,
              ].join(', '),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                destination.label,
                maxLines: MediaQuery.textScalerOf(context).scale(14) > 14
                    ? 2
                    : 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (destination.labelSuffixBuilder case final builder?)
              builder(context, 14),
            if (badge.isVisible && badge.dot)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: DNotificationDot(
                  key: ValueKey('sidebar-badge-${destination.id}'),
                  semanticLabel: dotLabel,
                  color: badge.urgent
                      ? theme.discourse.success
                      : theme.discourse.unreadIndicator,
                ),
              ),
          ],
        ),
      ),
    );
    if (!destination.enabled) return tile;
    if (destination.contextMenuBuilder case final builder?) {
      tile = builder(context, tile);
    }
    if (destination.url case final url?) {
      return LinkTarget(
        url: url,
        title: destination.label,
        longPressEnabled: !reorderable,
        child: tile,
      );
    }
    if (destination.onTap != null) return tile;
    return LinkTarget.content(
      content: destination.id == 'groups'
          ? ContentRoute.group(const GroupRoute.directory())
          : ContentRoute.fromDestination(destination),
      longPressEnabled: !reorderable,
      child: tile,
    );
  }
}
