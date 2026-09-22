import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/topic.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'forum_theme_surfaces.dart';
import 'topic_list_view.dart';

/// Uses the production topic rows without allowing sample content to navigate.
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
    ),
  ];

  @override
  Widget build(BuildContext context) => Theme(
    data: theme,
    child: Builder(
      builder: (context) => ExcludeFocus(
        child: IgnorePointer(
          child: ForumWindowBackground(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                DSpacing.md,
                Theme.of(context).extension<ForumThemeEffects>()?.background ==
                        null
                    ? DSpacing.md
                    : 80,
                DSpacing.md,
                DSpacing.md,
              ),
              child: DCard(
                key: const ValueKey('forum-theme-preview'),
                spacing: 0,
                footer: DCardFooter(
                  rounded: true,
                  padding: const EdgeInsets.all(DSpacing.lg),
                  backgroundColor: DTokens.of(context).footerBackground,
                  borderColor: DTokens.of(context).footerBorder,
                  child: Wrap(
                    spacing: DSpacing.controlGap,
                    runSpacing: DSpacing.sm,
                    children: [
                      DButton(
                        variant: DButtonVariant.primary,
                        icon: const DIcon(DIcons.plus),
                        label: const Text('New topic'),
                        onPressed: () {},
                      ),
                      DSelect<String>.controlled(
                        value: 'normal',
                        semanticLabel: 'Tracking',
                        entries: const [
                          DSelectOption(
                            value: 'normal',
                            label: 'Normal',
                            child: Text('Normal'),
                          ),
                        ],
                        onChanged: (_) {},
                      ),
                    ],
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(DSpacing.lg),
                    child: Wrap(
                      spacing: DSpacing.lg,
                      runSpacing: DSpacing.md,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'The Commons',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        SizedBox(
                          width: 210,
                          child: DInput(
                            key: const ValueKey('theme-preview-search'),
                            semanticLabel: 'Search the forum preview',
                            hintText: 'Search the forum',
                            readOnly: true,
                            prefix: const DIcon(DIcons.magnifyingGlass),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const DSeparator(),
                  LayoutBuilder(
                    builder: (context, bounds) => SizedBox(
                      height: 380,
                      child: DSidebarProvider(
                        mobileBreakpoint: 0,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (bounds.maxWidth >= 440 &&
                                MediaQuery.textScalerOf(context).scale(14) < 22)
                              ForumSidebarTheme(
                                child: DSidebar(
                                  key: const ValueKey('theme-preview-sidebar'),
                                  width: 132,
                                  collapsible: DSidebarCollapsible.none,
                                  child: DSidebarContent(
                                    children: [
                                      DSidebarGroup(
                                        child: DSidebarMenu(
                                          children: [
                                            for (final (label, icon) in [
                                              ('Latest', DIcons.house),
                                              ('Unread', DIcons.bell),
                                              ('Bookmarks', DIcons.bookmark),
                                            ])
                                              DSidebarMenuItem(
                                                child: DSidebarMenuButton(
                                                  icon: DIcon(icon),
                                                  isActive: label == 'Latest',
                                                  onPressed: () {},
                                                  child: Text(label),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      DSidebarGroup(
                                        label: const DSidebarGroupLabel(
                                          child: Text('Categories'),
                                        ),
                                        child: DSidebarMenu(
                                          children: [
                                            for (final label in [
                                              'General',
                                              'Design',
                                              'Support',
                                            ])
                                              DSidebarMenuItem(
                                                child: DSidebarMenuButton(
                                                  icon: const DIcon(
                                                    DIcons.circle,
                                                  ),
                                                  onPressed: () {},
                                                  child: Text(label),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(
                                        DSpacing.lg,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        spacing: DSpacing.md,
                                        children: [
                                          Text(
                                            'Latest topics',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                          ),
                                          DToggleGroup<String>(
                                            values: const ['latest'],
                                            onChanged: (_) {},
                                            items: const [
                                              DToggleGroupItem(
                                                value: 'latest',
                                                child: Text('Latest'),
                                              ),
                                              DToggleGroupItem(
                                                value: 'unread',
                                                child: Text('Unread'),
                                              ),
                                              DToggleGroupItem(
                                                value: 'top',
                                                child: Text('Top'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    for (final topic in topics)
                                      TopicListRow(
                                        key: ValueKey(
                                          'theme-preview-topic-${topic.id}',
                                        ),
                                        topic: topic,
                                        siteUrl: siteUrl,
                                        onTap: () {},
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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
}
