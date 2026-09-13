import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';

import '../test/support/fakes.dart';

// Offline review of the production Messages workspace; no account data is used.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const user = DiscourseUser(
    id: 7,
    username: 'sam',
    canSendPrivateMessages: true,
    messageGroupNames: ['team'],
  );
  final site = instance('messages-review.invalid').copyWith(user: user);
  const titles = [
    'Planning our next community workshop',
    'A few ideas for the September meetup',
    'Welcome to the team',
    'Notes from our design discussion',
    'Thanks for your help with the release',
    'Following up on the onboarding feedback',
  ];
  final rows = [
    for (final (i, title) in titles.indexed)
      Topic(
        id: i + 1,
        title: title,
        slug: 'message-${i + 1}',
        privateMessage: true,
        postsCount: 2,
        replyCount: 1,
        lastPosterUsername: 'alex',
        excerpt: 'Let’s compare notes and decide on the next steps together.',
        bumpedAt: DateTime.now().subtract(Duration(days: i + 1)),
      ),
  ];
  final shell = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: FakeDiscourseApi(
      user: user,
      feeds: {
        '/latest.json': const [],
        '/topics/private-messages/sam.json': rows,
        '/topics/private-messages-unread/sam.json': [rows[1], rows[2]],
        '/topics/private-messages-sent/sam.json': [rows[3]],
        '/topics/private-messages-archive/sam.json': const [],
        '/topics/private-messages-group/sam/team.json': rows.reversed.toList(),
        '/topics/private-messages-group/sam/team/unread.json': [rows[4]],
        '/topics/private-messages-group/sam/team/archive.json': const [],
      },
      topics: {
        for (final row in rows)
          row.id: (
            detail: TopicDetail(
              id: row.id,
              title: row.title,
              stream: [row.id * 100, row.id * 100 + 1],
              privateMessage: true,
              postsCount: 2,
              replyCount: 1,
              canCreatePost: true,
              participants: const [
                TopicParticipant(id: 7, username: 'sam'),
                TopicParticipant(id: 8, username: 'alex'),
              ],
            ),
            posts: [
              Post(
                id: row.id * 100,
                postNumber: 1,
                userId: 8,
                username: 'alex',
                cooked:
                    '<p>Hi Sam,</p><p>${row.title}</p><p>I have put together a few ideas for us to discuss. Let me know what you think, and we can work out the details together.</p>',
              ),
              Post(
                id: row.id * 100 + 1,
                postNumber: 2,
                userId: 7,
                username: 'sam',
                cooked:
                    '<p>Thanks Alex! I will take a look and share my thoughts.</p>',
              ),
            ],
          ),
      },
    ),
    authenticator: FakeAuthenticator()..keys[site.url] = 'local-fixture',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    forumTabsEnabled: false,
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  shell.selectDestination(
    const SidebarDestination(
      id: 'messages',
      label: 'Messages',
      icon: DIcons.inbox,
    ),
  );
  await shell.loadFeed('messages');
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(_Review(shell: shell));
}

class _Review extends StatefulWidget {
  const _Review({required this.shell});
  final ShellController shell;
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool _dark = true;
  bool _narrow = false;
  bool _large = false;

  @override
  void dispose() {
    widget.shell.dispose();
    unawaited(widget.shell.plugins.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: widget.shell,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _dark ? AppTheme.dark : AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 8,
                  children: [
                    DButton(
                      label: Text(_narrow ? 'Wide pane' : '390px pane'),
                      onPressed: () => setState(() => _narrow = !_narrow),
                    ),
                    DButton(
                      label: Text(_dark ? 'Light theme' : 'Dark theme'),
                      onPressed: () => setState(() => _dark = !_dark),
                    ),
                    DButton(
                      label: Text(_large ? '100% text' : '200% text'),
                      onPressed: () => setState(() => _large = !_large),
                    ),
                    DButton(
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
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: _narrow ? 390 : 1200,
                    child: MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(_large ? 2 : 1)),
                      child: const MainContent(layout: ShellLayout.expanded),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
