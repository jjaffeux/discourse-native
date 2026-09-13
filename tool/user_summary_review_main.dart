import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_summary.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_summary.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/fakes.dart';

const _siteUrl = 'https://summary-review.invalid';
const _user = DiscourseUser(id: 7, username: 'alex', name: 'Alex Morgan');
const _categories = [
  TopicCategory(id: 1, name: 'UX', slug: 'ux', color: '8B78B8'),
  TopicCategory(id: 2, name: 'Feature', slug: 'feature', color: '4D8FBD'),
  TopicCategory(id: 3, name: 'Community', slug: 'community', color: '689D7C'),
  TopicCategory(id: 4, name: 'Support', slug: 'support', color: 'C3925D'),
];
final _topics = [
  for (final (index, title) in [
    'A calmer, more focused topic page',
    'Small improvements that make a big difference',
    'Making keyboard navigation feel natural',
    'A better home for your bookmarks',
    'What makes a great community welcome?',
    'Making room for longer conversations',
  ].indexed)
    UserSummaryTopic(
      id: index + 1,
      title: title,
      slug: 'sample-${index + 1}',
      categoryId: index % 3 + 1,
      likeCount: [186, 124, 98, 76, 64, 52][index],
      createdAt: DateTime(2026, 8, 28 - index * 3),
    ),
];
final _replies = [
  for (final (index, title) in [
    'What should we simplify next?',
    'Designing for the conversations in between',
    'Making notifications more useful',
    'A few thoughts on the new composer',
    'Better defaults for growing communities',
    'A more helpful first visit',
  ].indexed)
    UserSummaryReply(
      topic: UserSummaryTopic(
        id: index + 10,
        title: title,
        slug: 'reply-$index',
        categoryId: index % 3 + 1,
      ),
      postNumber: index + 3,
      likeCount: [94, 81, 67, 58, 43, 31][index],
      createdAt: DateTime(2026, 8, 30 - index * 3),
    ),
];
const _people = [
  UserSummaryUser(id: 21, username: 'maya', name: 'Maya Chen', count: 248),
  UserSummaryUser(id: 22, username: 'sam', name: 'Sam Rivera', count: 196),
  UserSummaryUser(id: 23, username: 'jamie', name: 'Jamie Park', count: 154),
  UserSummaryUser(id: 24, username: 'robin', name: 'Robin Lee', count: 121),
];

UserSummary _sample({bool stats = true}) => UserSummary(
  canSeeSummaryStats: stats,
  likesGiven: 1209,
  likesReceived: 2846,
  daysVisited: 312,
  topicCount: 48,
  postCount: 864,
  timeRead: 18 * 86400,
  recentTimeRead: 7 * 3600,
  topicsEntered: 3428,
  postsReadCount: 24680,
  bookmarkCount: 36,
  topics: _topics,
  replies: _replies,
  mostRepliedToUsers: [
    for (final p in _people)
      UserSummaryUser(
        id: p.id,
        username: p.username,
        name: p.name,
        count: p.count ~/ 3,
      ),
  ],
  mostLikedByUsers: _people,
  mostLikedUsers: _people.reversed.toList(),
  topCategories: [
    for (final (index, c) in _categories.indexed)
      UserSummaryCategory(
        id: c.id,
        name: c.name,
        slug: c.slug,
        color: c.color,
        topicCount: [22, 14, 8, 4][index],
        postCount: [318, 246, 174, 126][index],
      ),
  ],
  links: [
    for (final (index, title) in [
      'A guide to welcoming communities',
      'Writing useful feature requests',
      'Designing accessible interfaces',
    ].indexed)
      UserSummaryLink(
        topic: _topics[index],
        url: 'https://example.invalid/resource-$index',
        title: title,
        clicks: [342, 218, 156][index],
        postNumber: 2,
      ),
  ],
  badges: const [
    UserSummaryBadge(
      id: 1,
      name: 'Great Topic',
      description: 'Received 50 likes on a topic.',
      icon: 'certificate',
    ),
    UserSummaryBadge(
      id: 2,
      name: 'Good Reply',
      description: 'Received 25 likes on a reply.',
      icon: 'heart',
      count: 3,
    ),
    UserSummaryBadge(
      id: 3,
      name: 'Enthusiast',
      description: 'Visited on 10 consecutive days.',
      icon: 'calendar',
    ),
  ],
);

// Offline review of the actual production widget, with in-memory APIs/stores.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = _ReviewApi();
  final site = instance('summary-review.invalid').copyWith(
    title: 'Discourse Meta',
    user: _user,
    config: const SiteConfig(badgesEnabled: true),
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
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(_Review(shell: shell, api: api));
}

class _ReviewApi extends FakeDiscourseApi {
  _ReviewApi() : super(user: _user, categoryList: _categories);
  String state = 'Ready';
  Completer<void>? summaryGate;

  @override
  Future<UserSummary> userSummary({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    await summaryGate?.future;
    if (state == 'Error') throw StateError('Fixture refresh failed');
    if (state == 'Empty') return const UserSummary(canSeeSummaryStats: true);
    return _sample(stats: state != 'No stats');
  }
}

class _Review extends StatefulWidget {
  const _Review({required this.shell, required this.api});
  final ShellController shell;
  final _ReviewApi api;
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool _dark = false;
  bool _narrow = false;
  bool _large = false;
  bool _rtl = false;
  final _appearance = SiteAppearance.fromJson(
    jsonDecode(
          const String.fromEnvironment('SUMMARY_PALETTE', defaultValue: '{}'),
        )
        as Map<String, dynamic>,
  );

  void _state(String value) {
    widget.api.state = value;
    widget.api.summaryGate?.complete();
    widget.api.summaryGate = value == 'Loading' ? Completer<void>() : null;
    if (value != 'Error') widget.shell.userSummary.forget(_siteUrl);
    unawaited(
      widget.shell.userSummary.load(
        widget.shell.currentInstance!,
        refresh: true,
      ),
    );
  }

  @override
  void dispose() {
    widget.api.summaryGate?.complete();
    widget.shell.dispose();
    unawaited(widget.shell.plugins.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: widget.shell,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _appearance.isKnown
          ? AppTheme.fromPalette(
              _dark
                  ? _appearance.alternate ?? _appearance.base!
                  : _appearance.base!,
            )
          : _dark
          ? AppTheme.dark
          : AppTheme.light,
      builder: (context, child) => DFocusHighlight(child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DButton(
                        variant: DButtonVariant.outline,
                        label: Text(_dark ? 'Light palette' : 'Dark palette'),
                        onPressed: () => setState(() => _dark = !_dark),
                      ),
                      DButton(
                        variant: DButtonVariant.outline,
                        label: Text(_narrow ? 'Wide pane' : '320px pane'),
                        onPressed: () => setState(() => _narrow = !_narrow),
                      ),
                      DButton(
                        variant: DButtonVariant.outline,
                        label: Text(_large ? '100% text' : '200% text'),
                        onPressed: () => setState(() => _large = !_large),
                      ),
                      DButton(
                        variant: DButtonVariant.outline,
                        label: Text(_rtl ? 'LTR' : 'RTL'),
                        onPressed: () => setState(() => _rtl = !_rtl),
                      ),
                      for (final state in [
                        'Ready',
                        'Empty',
                        'No stats',
                        'Error',
                        'Loading',
                      ])
                        DButton(
                          variant: DButtonVariant.outline,
                          label: Text(state),
                          onPressed: () => _state(state),
                        ),
                      DButton(
                        variant: DButtonVariant.outline,
                        label: const Text('Styleguide'),
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const ComponentStyleguidePage(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const DSeparator(),
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: _narrow ? 320 : double.infinity,
                      height: double.infinity,
                      child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          textScaler: TextScaler.linear(_large ? 2 : 1),
                        ),
                        child: Directionality(
                          textDirection: _rtl
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          child: const UserSummaryView(siteUrl: _siteUrl),
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
