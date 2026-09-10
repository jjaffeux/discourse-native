import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_inbox_header.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/fakes.dart';

const _siteUrl = 'https://taxonomy-review.invalid';
const _categories = [
  TopicCategory(id: 1, name: 'sales', color: 'ED167D'),
  TopicCategory(id: 2, name: 'deals', color: '008DBD', parentCategoryId: 1),
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
  title: 'Deal with Internet Society',
  slug: 'deal-with-internet-society',
  categoryId: 2,
);
const _topic = TopicDetail(
  id: 101,
  title: 'Deal with Internet Society',
  categoryId: 2,
  stream: [101],
  postsCount: 1,
  replyCount: 18,
  canEdit: true,
  canEditTags: true,
  tags: [TopicTag(id: 1, name: 'discovery')],
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

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: widget.shell,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _palette.resolve(AppTheme.light),
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
                              builder: (context, _) => Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TopicInboxHeader(
                                    title: _topic.title,
                                    siteUrl: _siteUrl,
                                    canReturnToSidebar: false,
                                    keepTopicListOpen: true,
                                    registry: PluginRegistry.empty,
                                    topic: widget.shell.currentTopic ?? _topic,
                                  ),
                                  const DSeparator(),
                                  const Padding(
                                    padding: EdgeInsets.all(20),
                                    child: DText(
                                      'Process Checklist',
                                      variant: DTextVariant.h3,
                                    ),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    child: Text(
                                      'Keep the following sections up to date until the deal is closed.',
                                    ),
                                  ),
                                  const SizedBox(height: 24),
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
