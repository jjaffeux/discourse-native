import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/content_route.dart';
import '../models/sidebar.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/d_icons.dart';
import 'forum_icon.dart';
import 'forum_search.dart';
import 'open_link.dart';
import 'shell_scope.dart';

/// The landing surface for an otherwise empty forum tab.
class NewTabPage extends StatefulWidget {
  const NewTabPage({super.key, required this.onBrowseTopics});

  final VoidCallback onBrowseTopics;

  @override
  State<NewTabPage> createState() => _NewTabPageState();
}

class _NewTabPageState extends State<NewTabPage> {
  static const _dismissedKey = 'discourse_native.panel_tutorial_dismissed';
  bool? _dismissed;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreference());
  }

  Future<void> _loadPreference() async {
    bool dismissed;
    try {
      dismissed =
          (await SharedPreferences.getInstance()).getBool(_dismissedKey) ??
          false;
    } catch (_) {
      dismissed = false;
    }
    if (mounted) setState(() => _dismissed = dismissed);
  }

  Future<void> _dismiss() async {
    setState(() => _dismissed = true);
    try {
      await (await SharedPreferences.getInstance()).setBool(
        _dismissedKey,
        true,
      );
    } catch (_) {
      // The current tab still honors the choice if local storage is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.maybeOf(context);
    final forum = shell?.currentInstance;
    final registry = PluginScope.maybeOf(context)?.registry;
    final siteUrl = forum?.url;
    final pluginSections =
        registry?.sidebarSections(context) ?? const <SidebarSection>[];
    final availableChannels = {
      for (final section in pluginSections)
        for (final destination in section.destinations)
          if (destination.enabled &&
              RegExp(r'^chat-channel-[1-9][0-9]*$').hasMatch(destination.id))
            destination.id: destination,
    };
    final hasChat = pluginSections.any(
      (section) =>
          section.id.startsWith('chat') || section.id == 'direct-messages',
    );
    final events = registry
        ?.communitySidebarDestinations(context)
        .where(
          (destination) =>
              destination.id == 'events-upcoming' && destination.enabled,
        )
        .firstOrNull;
    final categories = siteUrl == null
        ? <ContentRoute>[]
        : shell!.recentCategoriesFor(siteUrl);
    final channels = siteUrl == null
        ? <ContentRoute>[]
        : shell!
              .recentChannelsFor(siteUrl)
              .where((route) => availableChannels.containsKey(route.id))
              .toList();
    final topics = siteUrl == null
        ? <ContentRoute>[]
        : shell!.recentTopicsFor(siteUrl);

    return SingleChildScrollView(
      child: Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1500),
          child: Padding(
            padding: const EdgeInsets.all(DSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DSpacing.lg,
              children: [
                if (forum != null)
                  Row(
                    spacing: DSpacing.md,
                    children: [
                      ForumIcon(forum: forum, size: 56),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              forum.title,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            Text(
                              Uri.tryParse(forum.url)?.host ?? forum.url,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    'Start page',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                if (shell != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: const ForumSearch(showNavigationControls: false),
                  ),
                if (_dismissed == false &&
                    (ShellScope.maybeRead(context)?.desktopPanelsEnabled ??
                        true))
                  _PanelTutorial(onDismiss: _dismiss),
                if (shell != null) ...[
                  if (categories.isNotEmpty ||
                      channels.isNotEmpty ||
                      topics.isNotEmpty)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final columns = width >= 1050
                            ? 3
                            : width >= 650
                            ? 2
                            : 1;
                        final columnWidth =
                            (width - (columns - 1) * DSpacing.lg) / columns;
                        return Wrap(
                          spacing: DSpacing.lg,
                          runSpacing: DSpacing.xl,
                          children: [
                            if (categories.isNotEmpty)
                              SizedBox(
                                width: columnWidth,
                                child: _RecentSection(
                                  title: 'Categories',
                                  icon: DIcons.layerGroup,
                                  onHeading: () =>
                                      openLink(context, '/categories'),
                                  routes: categories,
                                  onRoute: (route) =>
                                      _openRoute(context, route),
                                ),
                              ),
                            if (hasChat && channels.isNotEmpty)
                              SizedBox(
                                width: columnWidth,
                                child: _RecentSection(
                                  title: 'Chat',
                                  icon: DIcons.comments,
                                  onHeading: () => shell.selectDestination(
                                    const SidebarDestination(
                                      id: 'chat-channels',
                                      label: 'Chat',
                                      icon: DIcons.comments,
                                    ),
                                  ),
                                  routes: channels,
                                  onRoute: (route) =>
                                      availableChannels[route.id]?.onTap
                                          ?.call(),
                                ),
                              ),
                            if (topics.isNotEmpty)
                              SizedBox(
                                width: columnWidth,
                                child: _RecentSection(
                                  title: 'Latest topics',
                                  icon: DIcons.layerGroup,
                                  onHeading: widget.onBrowseTopics,
                                  routes: topics,
                                  onRoute: (route) =>
                                      _openRoute(context, route),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  Text(
                    'Everything else',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Wrap(
                    spacing: DSpacing.sm,
                    runSpacing: DSpacing.sm,
                    children: [
                      if (forum?.user != null)
                        _LinkButton(
                          label: 'Messages',
                          icon: DIcons.inbox,
                          onPressed: () => openLink(context, '/my/messages'),
                        ),
                      _LinkButton(
                        label: 'Groups',
                        icon: DIcons.users,
                        onPressed: () => openLink(context, '/g'),
                      ),
                      _LinkButton(
                        label: 'Badges',
                        icon: DIcons.certificate,
                        onPressed: () => openLink(context, '/badges'),
                      ),
                      if (events != null)
                        _LinkButton(
                          label: 'Upcoming events',
                          icon: events.icon,
                          onPressed: () => shell.selectDestination(events),
                        ),
                      _LinkButton(
                        label: 'Users',
                        icon: DIcons.users,
                        onPressed: () => openLink(context, '/u'),
                      ),
                      _LinkButton(
                        label: 'Themes',
                        icon: DIcons.layerGroup,
                        onPressed: () => shell.openForumSettings(siteUrl!),
                      ),
                      if (forum?.user != null)
                        _LinkButton(
                          label: 'Preferences',
                          icon: DIcons.gear,
                          onPressed: () => shell.openPreferences(siteUrl!),
                        ),
                    ],
                  ),
                ] else if (_dismissed != null)
                  DButton(
                    onPressed: widget.onBrowseTopics,
                    label: const Text('Browse latest topics'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openRoute(BuildContext context, ContentRoute route) {
    final site = ShellScope.read(context).currentInstance;
    if (site == null) return;
    if (route.topicId case final id?) {
      unawaited(
        openLink(
          context,
          '/t/${route.slug ?? 'topic'}/$id',
          title: route.title,
        ),
      );
    } else if (route.feedPath case final path?) {
      final url = path.endsWith('.json')
          ? path.substring(0, path.length - 5)
          : path;
      unawaited(openLink(context, url, title: route.title));
    }
  }
}

class _RecentSection extends StatelessWidget {
  const _RecentSection({
    required this.title,
    required this.icon,
    required this.onHeading,
    required this.routes,
    required this.onRoute,
  });

  final String title;
  final DIconData icon;
  final VoidCallback onHeading;
  final List<ContentRoute> routes;
  final ValueChanged<ContentRoute> onRoute;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: DSpacing.sm,
    children: [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: DButton(
          variant: DButtonVariant.transparentBackground,
          icon: DIcon(icon, size: 17),
          label: Text(title),
          onPressed: onHeading,
        ),
      ),
      for (final route in routes)
        DItem(
          variant: DItemVariant.muted,
          link: true,
          onPressed: () => onRoute(route),
          children: [
            DIcon(route.icon, size: 17, color: route.color),
            DItemContent(
              children: [
                DItemTitle(
                  child: Text(
                    route.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
    ],
  );
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final DIconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return DButton(
      variant: DButtonVariant.secondary,
      backgroundColor: tokens.footerBackground,
      interactiveBackgroundColor: tokens.buttonTheme.accent.hover,
      borderColor: Colors.transparent,
      icon: DIcon(icon, size: 16),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}

class _PanelTutorial extends StatelessWidget {
  const _PanelTutorial({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 920),
    child: DCard(
      spacing: 0,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final instructions = Padding(
            padding: const EdgeInsets.all(DSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DSpacing.md,
              children: [
                Text(
                  'Work with two panels',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const _PanelGestureHint(
                  keys: ['Middle click'],
                  description: 'Opens a new tab in main panel',
                ),
                const _PanelGestureHint(
                  keys: ['Shift', 'Click'],
                  description: 'Open in secondary panel',
                ),
                const _PanelGestureHint(
                  keys: ['Shift', 'Middle click'],
                  description: 'Open in a new tab in secondary panel',
                ),
                const SizedBox(height: DSpacing.md),
                DButton(
                  key: const ValueKey('dismiss-panel-tutorial'),
                  onPressed: onDismiss,
                  variant: DButtonVariant.outline,
                  label: const Text("Don't show again"),
                ),
              ],
            ),
          );
          final diagram = _PanelTutorialDiagram();
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [instructions, const DSeparator(), diagram],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: instructions),
                const DSeparator(orientation: Axis.vertical),
                Expanded(child: diagram),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _PanelTutorialDiagram extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return ColoredBox(
      color: tokens.surface,
      child: Padding(
        padding: const EdgeInsets.all(DSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: DSpacing.md,
          children: [
            Text(
              'TWO PANELS',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: tokens.mutedForeground),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DSpacing.sm,
              children: [
                const Expanded(
                  child: DCard(
                    size: DCardSize.small,
                    children: [Text('Main'), DSeparator(), Text('This page')],
                  ),
                ),
                Expanded(
                  child: DCard(
                    size: DCardSize.small,
                    backgroundColor: tokens.selected,
                    children: const [
                      Text('Secondary'),
                      DSeparator(),
                      Text('Opened link'),
                    ],
                  ),
                ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                'Shift + click opens here',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.mutedForeground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelGestureHint extends StatelessWidget {
  const _PanelGestureHint({required this.keys, required this.description});

  final List<String> keys;
  final String description;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: DSpacing.sm,
    runSpacing: DSpacing.xs,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [for (final key in keys) DKbd(key), Text(description)],
  );
}
