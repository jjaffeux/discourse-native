// Local-only production surfaces. All stores and API calls are in-memory fakes.
import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/plugins/poll/poll.dart';
import 'package:discourse_native/src/plugins/poll/poll_card.dart';
import 'package:discourse_native/src/shell/post_flag_editor.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/topic_change_owner.dart';
import 'package:discourse_native/src/shell/topic_move_posts.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/fakes.dart';

const _site = 'https://radio-review.invalid';
const _post = Post(
  id: 1,
  postNumber: 1,
  username: 'author',
  cooked: '<p>Local review post</p>',
);
const _topic = TopicDetail(
  id: 7,
  title: 'Local source topic',
  stream: [1],
  postsCount: 1,
  canMovePosts: true,
  canSplitMergeTopic: true,
);
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = FakeDiscourseApi(
    userSearches: const {
      'review': [
        FoundUser(username: 'alex', name: 'Alex Example'),
        FoundUser(
          username: 'sam',
          name: 'Sam — a long display name that wraps',
        ),
      ],
    },
    searchResults: {
      'review': SearchResults.fromJson(const {
        'topics': [
          {'id': 9, 'title': 'Destination topic', 'slug': 'destination'},
          {
            'id': 10,
            'title': 'Another destination with a longer title',
            'slug': 'another',
          },
        ],
        'posts': [
          {'id': 9, 'topic_id': 9, 'post_number': 1},
          {'id': 10, 'topic_id': 10, 'post_number': 1},
        ],
      }, _site),
    },
  );
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      const DiscourseInstance(
        url: _site,
        title: 'Radio review',
        user: DiscourseUser(
          id: 1,
          username: 'reviewer',
          staff: true,
          canChangePostOwner: true,
        ),
      ),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'local-fixture',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  shell.store.put<TopicDetail>(_site, _topic);
  shell.store.put<Post>(_site, _post);
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(
    MaterialApp(
      theme: AppTheme.light,
      home: _Review(shell: shell),
    ),
  );
}

class _Review extends StatefulWidget {
  const _Review({required this.shell});
  final ShellController shell;
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool _dark = false;
  bool _rtl = false;
  bool _large = false;
  bool _error = false;
  List<String> _selection = [];
  @override
  void dispose() {
    widget.shell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: _dark ? AppTheme.dark : AppTheme.light,
    child: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Radio Group review — local data')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  DButton(
                    label: const Text('Styleguide'),
                    onPressed: () => unawaited(
                      Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const ComponentStyleguidePage(),
                        ),
                      ),
                    ),
                  ),
                  DButton(
                    label: const Text('Light / Dark'),
                    onPressed: () => setState(() => _dark = !_dark),
                  ),
                  DButton(
                    label: const Text('RTL'),
                    onPressed: () => setState(() => _rtl = !_rtl),
                  ),
                  DButton(
                    label: const Text('100 / 200%'),
                    onPressed: () => setState(() => _large = !_large),
                  ),
                  DButton(
                    label: const Text('Toggle save error'),
                    onPressed: () => setState(() => _error = !_error),
                  ),
                  DButton(
                    label: const Text('Move posts'),
                    onPressed: () => unawaited(
                      showTopicMovePosts(
                        context: context,
                        controller: widget.shell,
                        siteUrl: _site,
                        topic: _topic,
                        selectedPosts: const [_post],
                      ),
                    ),
                  ),
                  DButton(
                    label: const Text('Change owner'),
                    onPressed: () => unawaited(
                      showTopicChangeOwner(
                        context: context,
                        controller: widget.shell,
                        siteUrl: _site,
                        topicId: 7,
                        selectedPosts: const [_post],
                      ),
                    ),
                  ),
                ],
              ),
              const Text(
                'Search “review” in either real dialog. Other searches show the empty state. All requests use in-memory fakes.',
              ),
              const SizedBox(height: 24),
              MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(_large ? 2 : 1)),
                child: Directionality(
                  textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
                  child: Column(
                    children: [
                      PostFlagEditor(
                        siteUrl: _site,
                        post: _post,
                        minimumMessageLength: 5,
                        flagTypes: const [
                          PostFlagType(
                            id: 3,
                            nameKey: 'off_topic',
                            name: 'Off-Topic',
                            description:
                                'This post is not relevant to the discussion.',
                          ),
                          PostFlagType(
                            id: 4,
                            nameKey: 'inappropriate',
                            name: 'Inappropriate',
                            description:
                                'Content that does not follow community guidelines.',
                          ),
                          PostFlagType(
                            id: 7,
                            nameKey: 'notify_moderators',
                            name: 'Something Else',
                            description: 'Explain the issue to moderators.',
                            requireMessage: true,
                          ),
                        ],
                        save: (type, {message}) async =>
                            _error ? 'Local simulated save error.' : null,
                        onComplete: () {},
                      ),
                      const SizedBox(height: 24),
                      PollCard(
                        poll: Poll(
                          name: 'review',
                          options: const [
                            PollOption(
                              id: 'a',
                              html: '<strong>Morning</strong>',
                            ),
                            PollOption(id: 'b', html: 'Afternoon'),
                            PollOption(
                              id: 'c',
                              html:
                                  'Evening — a longer choice that should wrap',
                            ),
                          ],
                          selection: PollSelection(optionIds: _selection),
                        ),
                        signedIn: true,
                        archived: false,
                        onVote: (_, values) {
                          if (_error) throw StateError('Local vote error');
                          setState(() => _selection = values);
                        },
                        onRemoveVote: (_) => setState(() => _selection = []),
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
  );
}
