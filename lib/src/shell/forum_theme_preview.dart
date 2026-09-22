import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/content_route.dart';
import '../models/sidebar.dart';
import '../models/topic.dart';
import '../theme/d_icons.dart';
import 'forum_theme_surfaces.dart';
import 'instance_sidebar.dart';
import 'platform.dart';
import 'shell_metrics.dart';
import 'shell_panel.dart';
import 'topic_create_button.dart';
import 'topic_list_bottom_bar.dart';
import 'topic_list_filter_bar.dart';
import 'topic_list_navigation.dart';
import 'topic_list_view.dart';

/// A scaled forum viewport composed from the production navigation and topics.
/// Sample actions are excluded from pointer, keyboard and accessibility input.
class ForumThemePreview extends StatelessWidget {
  const ForumThemePreview({
    super.key,
    required this.theme,
    required this.siteUrl,
  });

  final ThemeData theme;
  final String siteUrl;

  static const topics = [
    Topic(
      id: -1001,
      title: 'What are you making this weekend?',
      slug: 'weekend-projects',
      excerpt:
          'I’m turning a sunny corner into a reading nook. Share your latest project.',
      lastPosterUsername: 'maya',
      postsCount: 25,
      likeCount: 8,
      pinned: true,
      tags: [TopicTag(name: 'community')],
    ),
    Topic(
      id: -1002,
      title: 'A small discovery worth sharing',
      slug: 'small-discovery',
      excerpt:
          'The best ideas often start with a conversation. What have you learned lately?',
      lastPosterUsername: 'leo',
      postsCount: 9,
      bookmarked: true,
      unreadPosts: 2,
      tags: [TopicTag(name: 'design')],
    ),
  ];

  static const _destinations = [
    SidebarDestination(id: 'latest', label: 'Topics', icon: DIcons.layerGroup),
    SidebarDestination(id: 'new', label: 'New', icon: DIcons.circle),
    SidebarDestination(id: 'unread', label: 'Unread', icon: DIcons.envelope),
    SidebarDestination(
      id: 'bookmarks',
      label: 'Bookmarks',
      icon: DIcons.bookmark,
    ),
  ];

  static const _categories = [
    TopicCategory(id: -101, name: 'General', color: '3AB54A'),
    TopicCategory(id: -102, name: 'Design', color: '12A89D'),
    TopicCategory(id: -103, name: 'Support', color: 'F1592A'),
  ];

  @override
  Widget build(BuildContext context) => Theme(
    data: theme,
    child: Builder(
      builder: (context) {
        // A settings column is narrower than the workspace it previews. Lay
        // out at the real pane width before scaling, so desktop topic rows
        // keep desktop typography and metadata instead of becoming mobile rows.
        final viewport = Size(context.isTouch ? 390 : 900, 560);
        return Semantics(
          label: 'Forum appearance preview',
          image: true,
          child: ExcludeSemantics(
            child: ExcludeFocus(
              child: IgnorePointer(
                child: DAspectRatio(
                  ratio: viewport.aspectRatio,
                  child: FittedBox(
                    child: SizedBox.fromSize(
                      size: viewport,
                      child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          size: viewport,
                          padding: EdgeInsets.zero,
                          viewPadding: EdgeInsets.zero,
                          viewInsets: EdgeInsets.zero,
                        ),
                        child: ForumWindowBackground(
                          key: const ValueKey('forum-theme-preview'),
                          child: Padding(
                            padding: const EdgeInsets.all(workspaceEdgeInset),
                            child: Row(
                              spacing: workspacePanelGap,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (!context.isTouch) _sidebar(),
                                Expanded(child: _topics()),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _sidebar() => ForumSidebarTheme(
    child: Builder(
      builder: (context) => SizedBox(
        width: 220,
        child: WorkspacePanel(
          child: DSidebarProvider(
            mobileBreakpoint: 0,
            child: DSidebar(
              key: const ValueKey('theme-preview-sidebar'),
              width: 220,
              collapsible: DSidebarCollapsible.none,
              backgroundColor: ForumWindowBackground.surfaceColor(
                context,
                DTokens.of(context).muted,
              ),
              header: DSidebarHeader(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: ForumIdentityHeader(
                  siteUrl: siteUrl,
                  name: 'The Commons',
                  iconUrl: null,
                  monogram: 'C',
                  accentColor: Theme.of(context).colorScheme.primary,
                ),
              ),
              child: DSidebarContent(
                children: [
                  DSidebarGroup(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                    child: DSidebarMenu(
                      children: [
                        for (final destination in _destinations)
                          SidebarDestinationTile(
                            destination: destination,
                            selected: destination.id == 'latest',
                            badge: SidebarBadge.none,
                            onTap: () {},
                          ),
                      ],
                    ),
                  ),
                  DSidebarGroup(
                    label: const DSidebarGroupLabel(child: Text('Categories')),
                    child: DSidebarMenu(
                      children: [
                        for (final category in _categories)
                          SidebarDestinationTile(
                            destination: SidebarDestination(
                              id: 'category-${category.id}',
                              label: category.name,
                              icon: DIcons.folder,
                              color: Color(category.colorValue),
                            ),
                            selected: false,
                            badge: SidebarBadge.none,
                            onTap: () {},
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _topics() => WorkspacePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TopicListFilterBar(
            siteUrl: siteUrl,
            categories: _categories,
            knownTags: const [],
            selectedCategoryId: null,
            selectedTagName: null,
            taggingEnabled: true,
            searchTags: (_) async => const [],
            onCategorySelected: (_) {},
            onTagSelected: (_) {},
            inline: true,
            wrap: true,
            leading: TopicFeedMenu(
              mode: TopicListMode.latest,
              onSelected: (_) {},
            ),
          ),
        ),
        Expanded(
          child: DScrollArea(
            child: Column(
              children: [
                for (final topic in topics)
                  TopicListRow(
                    key: ValueKey('theme-preview-topic-${topic.id}'),
                    topic: topic,
                    siteUrl: siteUrl,
                    onTap: () {},
                  ),
              ],
            ),
          ),
        ),
        TopicListFooter(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TopicCreateAction(compact: true, onPressed: () {}),
          ),
        ),
      ],
    ),
  );
}
