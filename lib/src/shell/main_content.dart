import 'package:flutter/material.dart';

import '../models/content_route.dart';
import '../plugins/site_plugin.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'adaptive_shell.dart';
import 'composer_panel.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';
import 'title_bar.dart';
import 'topic_list_view.dart';
import 'topic_view.dart';
import 'user_menu_button.dart';

/// The main region. There is only ever one of these on screen; navigating
/// deeper replaces what it shows rather than opening beside it.
class MainContent extends StatelessWidget {
  const MainContent({super.key, required this.layout});

  final ShellLayout layout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.of(context);

    final route = controller.currentContent;
    if (route == null) return ColoredBox(color: theme.shell.content);

    return ColoredBox(
      color: theme.shell.content,
      child: SafeArea(
        left: false,
        child: Column(
          children: [
            _ContentHeader(layout: layout, route: route),
            Expanded(
              child: switch ((
                route.isTopic,
                _pluginContent(context, route),
                controller.currentFeed,
              )) {
                // A topic route wins over the list it was opened from.
                (true, _, _) => const TopicView(),
                // A route an optional feature claims is that feature's,
                // whichever list happens to still be cached behind it.
                (false, final content?, _) => content,
                // Destinations backed by a topic list show the real thing;
                // the rest keep the placeholder until they have a screen.
                (false, null, final feed?) => TopicListView(feed: feed),
                (false, null, null) => _ContentPlaceholder(route: route),
              },
            ),
            // Takes room from the stream rather than covering it, so the topic
            // stays readable while a reply is being written.
            if (controller.visibleComposer case final composer?)
              ComposerPanel(composer: composer),
          ],
        ),
      ),
    );
  }
}

/// The screen an optional feature draws for this route, or null when none of
/// them claims it.
///
/// The body of [PostFooter] with a route in place of a post, and asked before
/// core for the same reason it is there: the first plugin with something to say
/// wins, and core's answer is what is left when none of them do.
Widget? _pluginContent(BuildContext context, ContentRoute route) {
  for (final plugin in sitePlugins) {
    final content = plugin.content(context, route);
    if (content != null) return content;
  }
  return null;
}

class _ContentHeader extends StatelessWidget {
  const _ContentHeader({required this.layout, required this.route});

  final ShellLayout layout;
  final ContentRoute route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.of(context);

    // On compact the main region has replaced the sidebar, so back always has
    // somewhere to go. On wider layouts it only matters inside the stack.
    final showBack = layout.isCompact || controller.canPopContent;

    return Container(
      height: shellHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.shell.divider)),
      ),
      child: Row(
        children: [
          if (showBack)
            IconButton(
              onPressed: () =>
                  controller.handleBack(canReturnToSidebar: layout.isCompact),
              icon: const DIcon(DIcons.arrowLeft, size: 20),
              tooltip: 'Back',
            )
          else
            const SizedBox(width: 8),
          if (route.color case final color?)
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: DIcon(
                route.icon,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  route.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (route.subtitle case final subtitle?)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (route.isTopic && controller.canReplyHere)
            IconButton(
              onPressed: () => controller.openReply(),
              icon: const DIcon(DIcons.reply, size: 20),
              tooltip: 'Reply to this topic',
            ),
          // Only where there is no title bar above to hold it: this is the
          // furthest right the shell goes once the strip is gone.
          if (ShellTitleBar.columnsCarryUserMenu)
            UserMenuButton(ringColor: theme.shell.content),
        ],
      ),
    );
  }
}

/// Stand-in for real content. Doubles as a way to exercise every navigation
/// mode the shell supports before any of the real screens exist.
class _ContentPlaceholder extends StatelessWidget {
  const _ContentPlaceholder({required this.route});

  final ContentRoute route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.of(context);
    final depth = controller.contentStack.length;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DIcon(
              route.icon,
              size: 56,
              color: route.color ?? theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              route.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            if (depth > 1) ...[
              const SizedBox(height: 4),
              Text(
                controller.contentStack.map((r) => r.title).join('  ›  '),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => controller.pushContent(
                    ContentRoute(
                      id: '${route.id}-$depth',
                      title: 'Topic $depth',
                      icon: DIcons.comments,
                      subtitle: 'opened from ${route.title}',
                    ),
                  ),
                  icon: const DIcon(DIcons.upRightFromSquare, size: 18),
                  label: const Text('Replace with deeper view'),
                ),
                OutlinedButton.icon(
                  onPressed: () => showShellSheet(
                    context: context,
                    title: route.title,
                    builder: (context) => Text(
                      'Sheets sit over the shell instead of replacing the main '
                      'region. Use them for composing, quick actions and '
                      'anything the user should be able to dismiss without '
                      'losing their place.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  icon: const DIcon(DIcons.arrowUp, size: 18),
                  label: const Text('Show sheet'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
