import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_actions.dart';
import 'package:discourse_native/src/shell/topic_inbox_header.dart';
import 'package:discourse_native/src/shell/topic_list_filter_bar.dart';
import 'package:discourse_native/src/shell/topic_progress.dart';
import 'package:discourse_native/src/styleguide/examples/control_comparison_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';

import '../test/support/fakes.dart';

const _siteUrl = 'https://taxonomy-review.invalid';
const _categories = [
  TopicCategory(id: 1, name: 'sales', color: 'ED167D'),
  TopicCategory(
    id: 2,
    name: 'Discourse Native',
    color: '483576',
    readRestricted: true,
  ),
  TopicCategory(id: 3, name: 'dev', color: '383838'),
  TopicCategory(id: 4, name: 'todo', color: 'D344BC'),
  TopicCategory(id: 5, name: 'biz', color: '94D045'),
  TopicCategory(id: 6, name: 'sysadmin', color: 'FF9519'),
  TopicCategory(id: 7, name: 'staff', color: '888888'),
  TopicCategory(id: 8, name: 'credentials', color: 'FA4C22'),
  TopicCategory(id: 9, name: 'urgent - DO NOT REPLY', color: '66268D'),
  TopicCategory(id: 10, name: 'legal', color: 'C8162E'),
  TopicCategory(id: 11, name: 'ISMS', color: '008AC5'),
];
const _tags = [
  TopicTag(id: 1, name: 'discovery'),
  TopicTag(id: 2, name: 'approved'),
  TopicTag(id: 3, name: 'commit'),
  TopicTag(id: 4, name: 'runbook-authored'),
  TopicTag(id: 5, name: 'vuln-status-create'),
  TopicTag(id: 6, name: 'auto-generated'),
];
const _row = Topic(
  id: 101,
  title: 'A consistent family of controls',
  slug: 'deal-with-internet-society',
  categoryId: 2,
);
const _topic = TopicDetail(
  id: 101,
  title: 'A consistent family of controls',
  categoryId: 2,
  stream: [101],
  postsCount: 1,
  replyCount: 18,
  notificationLevel: TopicNotificationLevel.tracking,
  canEdit: true,
  canEditTags: true,
  tags: [],
);

/// Exercises the actual topic header and editors with in-memory API/stores.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = _ReviewApi();
  final site = instance('taxonomy-review.invalid').copyWith(
    user: const DiscourseUser(id: 1, username: 'reviewer'),
    config: const SiteConfig(taggingEnabled: true),
  );
  final shell = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: api,
    authenticator: FakeAuthenticator()..keys[site.url] = 'local-fixture',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  await shell.loadFeed('latest');
  shell.openTopicFromList(_row);
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(_Review(shell: shell, api: api));
}

class _Review extends StatefulWidget {
  const _Review({required this.shell, required this.api});
  final ShellController shell;
  final _ReviewApi api;

  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  StyleguideTheme _palette = StyleguideTheme.dark;
  bool _narrow = false;
  bool _large = false;
  bool _rtl = false;
  bool _comparison = false;
  bool _replying = false;
  bool _comparePalette = false;
  int? _category;
  String? _tag;
  final _appearance = SiteAppearance.fromJson(
    jsonDecode(
          const String.fromEnvironment(
            'CONTEXTUAL_PALETTE',
            defaultValue: '{}',
          ),
        )
        as Map<String, dynamic>,
  );
  final _comparisonAppearance = SiteAppearance.fromJson(
    jsonDecode(
          const String.fromEnvironment(
            'CONTEXTUAL_COMPARISON_PALETTE',
            defaultValue: '{}',
          ),
        )
        as Map<String, dynamic>,
  );

  SiteAppearance get _activeAppearance =>
      _comparePalette ? _comparisonAppearance : _appearance;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: widget.shell,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: switch (_palette) {
        StyleguideTheme.dark when _activeAppearance.alternate != null =>
          AppTheme.fromPalette(_activeAppearance.alternate!),
        StyleguideTheme.light when _activeAppearance.base != null =>
          AppTheme.fromPalette(_activeAppearance.base!),
        _ => _palette.resolve(AppTheme.light),
      },
      home: DToaster(
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_comparisonAppearance.isKnown)
                        DButton(
                          label: Text(
                            _comparePalette
                                ? 'Palette: dev.discourse.org'
                                : 'Palette: meta.discourse.org',
                          ),
                          onPressed: () => setState(
                            () => _comparePalette = !_comparePalette,
                          ),
                        ),
                      DButton(
                        label: Text(
                          _comparison
                              ? 'Show topic controls'
                              : 'Show control comparison',
                        ),
                        onPressed: () =>
                            setState(() => _comparison = !_comparison),
                      ),
                      for (final palette in [
                        StyleguideTheme.light,
                        StyleguideTheme.dark,
                        StyleguideTheme.plum,
                      ])
                        DButton(
                          label: Text(palette.label),
                          variant: DButtonVariant.outline,
                          onPressed: () => setState(() => _palette = palette),
                        ),
                      DButton(
                        label: Text(_narrow ? 'Width: 320' : 'Width: 740'),
                        onPressed: () => setState(() => _narrow = !_narrow),
                      ),
                      DButton(
                        label: Text(_large ? 'Text: 200%' : 'Text: 100%'),
                        onPressed: () => setState(() => _large = !_large),
                      ),
                      DButton(
                        label: Text(_rtl ? 'RTL' : 'LTR'),
                        onPressed: () => setState(() => _rtl = !_rtl),
                      ),
                      DButton(
                        label: Text(
                          widget.api.empty
                              ? 'Results: empty'
                              : 'Results: ready',
                        ),
                        onPressed: () => setState(
                          () => widget.api.empty = !widget.api.empty,
                        ),
                      ),
                      DButton(
                        label: Text(
                          widget.api.fail ? 'Search: error' : 'Search: normal',
                        ),
                        onPressed: () =>
                            setState(() => widget.api.fail = !widget.api.fail),
                      ),
                      DButton(
                        label: const Text('Toggle saved bookmark'),
                        onPressed: () {
                          final topic = widget.shell.currentTopic ?? _topic;
                          widget.shell.store.put<TopicDetail>(
                            _siteUrl,
                            topic.copyWith(
                              bookmarks: topic.topicBookmark == null
                                  ? const [
                                      Bookmark(
                                        id: 701,
                                        bookmarkableId: 101,
                                        bookmarkableType: 'Topic',
                                      ),
                                    ]
                                  : const [],
                            ),
                          );
                          setState(() {});
                        },
                      ),
                      DButton(
                        label: const Text('Reset topic'),
                        onPressed: () {
                          widget.shell.store.put<TopicDetail>(_siteUrl, _topic);
                          widget.shell.openTopicFromList(_row);
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: _narrow ? 320 : 740,
                      child: Builder(
                        builder: (context) => MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            textScaler: TextScaler.linear(_large ? 2 : 1),
                          ),
                          child: Directionality(
                            textDirection: _rtl
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            child: AnimatedBuilder(
                              animation: widget.shell,
                              builder: (context, _) => _comparison
                                  ? const ControlComparisonExample()
                                  : DScrollArea(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.all(20),
                                            child: Column(
                                              children: [
                                                TopicListFilterBar(
                                                  siteUrl: _siteUrl,
                                                  categories: _categories,
                                                  knownTags: const [],
                                                  selectedCategoryId: _category,
                                                  selectedTagName: _tag,
                                                  taggingEnabled: true,
                                                  compact: true,
                                                  searchTags: (term) async => [
                                                    for (final tag
                                                        in _tags.where(
                                                          (tag) => tag.name
                                                              .contains(term),
                                                        ))
                                                      TopicFilterLookupValue(
                                                        name: tag.name,
                                                      ),
                                                  ],
                                                  onCategorySelected:
                                                      (category) => setState(
                                                        () => _category =
                                                            category?.id,
                                                      ),
                                                  onTagSelected: (tag) =>
                                                      setState(
                                                        () => _tag = tag,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          TopicInboxHeader(
                                            title: _topic.title,
                                            siteUrl: _siteUrl,
                                            canReturnToSidebar: false,
                                            keepTopicListOpen: true,
                                            registry: PluginRegistry.empty,
                                            topic:
                                                widget.shell.currentTopic ??
                                                _topic,
                                          ),
                                          const DSeparator(),
                                          const Padding(
                                            padding: EdgeInsets.all(20),
                                            child: DText(
                                              'Contextual tints',
                                              variant: DTextVariant.h3,
                                            ),
                                          ),
                                          const Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 20,
                                            ),
                                            child: Text(
                                              'Neutral controls share their shape and border. Accent colors indicate the action or category.',
                                            ),
                                          ),
                                          const SizedBox(height: 24),
                                          Padding(
                                            padding: const EdgeInsets.all(20),
                                            child: Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                DButton(
                                                  label: const Text('Reply'),
                                                  icon: const DIcon(
                                                    DIcons.reply,
                                                  ),
                                                  onPressed: () => setState(
                                                    () =>
                                                        _replying = !_replying,
                                                  ),
                                                ),
                                                DButtonGroup(
                                                  children: [
                                                    TopicBookmarkButton(
                                                      siteUrl: _siteUrl,
                                                      topic:
                                                          widget
                                                              .shell
                                                              .currentTopic ??
                                                          _topic,
                                                      busy: false,
                                                      variant: DButtonVariant
                                                          .outline,
                                                      size: DButtonSize.regular,
                                                    ),
                                                    TopicNotificationLevelButton(
                                                      siteUrl: _siteUrl,
                                                      topic:
                                                          widget
                                                              .shell
                                                              .currentTopic ??
                                                          _topic,
                                                      showLabel: !_narrow,
                                                      variant: DButtonVariant
                                                          .outline,
                                                      size: DButtonSize.regular,
                                                    ),
                                                  ],
                                                ),
                                                TopicProgressPopover(
                                                  controller: widget.shell,
                                                  position: 1,
                                                  total: 4,
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (_replying)
                                            DTextarea(
                                              hintText: 'Write a local draft…',
                                            ),
                                          Text(
                                            'Category saves: ${widget.api.topicsUpdated.length} · Tag saves: ${widget.api.topicTagsUpdated.length}',
                                          ),
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
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ReviewApi extends FakeDiscourseApi {
  _ReviewApi()
    : super(
        categoryList: _categories,
        feeds: {
          '/latest.json': [_row],
        },
        composerCapabilities: const TopicComposerCapabilities(
          canTagTopics: true,
          canCreateTag: true,
        ),
        topics: {
          101: (
            detail: _topic,
            posts: [
              const Post(
                id: 101,
                postNumber: 1,
                username: 'reviewer',
                cooked: '<p>Local fixture</p>',
              ),
            ],
          ),
        },
      );

  bool empty = false;
  bool fail = false;

  @override
  Future<List<TopicCategory>> searchCategories({
    required String siteUrl,
    required String term,
    required String apiKey,
    bool includeUncategorized = true,
    bool includeAncestors = false,
    String? clientId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (fail) throw StateError('Local search failure');
    return empty
        ? []
        : _categories
              .where(
                (category) =>
                    category.name.toLowerCase().contains(term.toLowerCase()),
              )
              .toList();
  }

  @override
  Future<TopicTagSearch> searchTopicTags({
    required String siteUrl,
    required String apiKey,
    required String term,
    int? categoryId,
    Iterable<int> selectedTagIds = const [],
    int limit = SiteConfig.defaultMaxTagSearchResults,
    String? clientId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (fail) throw StateError('Local search failure');
    return TopicTagSearch(
      tags: empty
          ? []
          : _tags
                .where(
                  (tag) => tag.name.toLowerCase().contains(term.toLowerCase()),
                )
                .toList(),
    );
  }
}
