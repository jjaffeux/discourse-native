import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/user_directory.dart';
import 'package:discourse_native/src/models/user_summary.dart' as model;
import 'package:discourse_native/src/plugins/poll/poll.dart';
import 'package:discourse_native/src/plugins/poll/poll_card.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_summary.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../../test/support/fakes.dart';

/// Isolated review entrypoint: local data only, mounting real app controls.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  final site = instance(
    'example.com',
  ).copyWith(user: const DiscourseUser(id: 7, username: 'reader'));
  final controller = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: FakeDiscourseApi(
      user: site.user,
      summary: const model.UserSummary(
        canSeeSummaryStats: true,
        canSeeUserActions: true,
        likesGiven: 7,
        likesReceived: 8,
        topicCount: 2,
        postCount: 3,
        bookmarkCount: 1,
        topCategories: [
          model.UserSummaryCategory(
            id: 5,
            name: 'Support',
            slug: 'support',
            color: '0088CC',
            topicCount: 2,
            postCount: 7,
          ),
        ],
      ),
      feeds: const {'/latest.json': []},
    ),
    authenticator: FakeAuthenticator()
      ..keys['https://example.com'] = 'local-review',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await controller.load();
  runApp(ShellScope(controller: controller, child: const ButtonReview()));
}

class ButtonReview extends StatefulWidget {
  const ButtonReview({super.key});
  @override
  State<ButtonReview> createState() => _ButtonReviewState();
}

class _ButtonReviewState extends State<ButtonReview> {
  StyleguideTheme theme = StyleguideTheme.light;
  bool touch = false;
  bool narrow = false;
  bool rtl = false;
  bool large = false;
  String message = 'No application action yet';

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme
        .resolve(AppTheme.light)
        .copyWith(platform: touch ? TargetPlatform.iOS : TargetPlatform.macOS),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(large ? 2 : 1),
        disableAnimations: true,
      ),
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Center(
          child: SizedBox(width: narrow ? 360 : double.infinity, child: child!),
        ),
      ),
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        DButton(
                          label: const Text('Styleguide'),
                          onPressed: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => const ComponentStyleguidePage(),
                            ),
                          ),
                        ),
                        DButton(
                          label: Text(
                            touch ? 'Pointer targets' : 'Touch targets',
                          ),
                          onPressed: () => setState(() => touch = !touch),
                        ),
                        DButton(
                          label: Text(narrow ? 'Wide' : 'Narrow'),
                          onPressed: () => setState(() => narrow = !narrow),
                        ),
                        DButton(
                          label: const Text('Users directory'),
                          onPressed: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => Scaffold(
                                appBar: AppBar(
                                  title: const Text('Users review'),
                                ),
                                body: UsersPage(
                                  siteUrl: 'https://example.com',
                                  data: const UsersPageData(
                                    columns: _columns,
                                    availableColumns: _columns,
                                    canManageColumns: true,
                                    loaded: true,
                                  ),
                                  onPeriodChanged: (value) => setState(
                                    () => message = 'Period ${value.name}',
                                  ),
                                  onManageColumns: (columns) async {
                                    setState(
                                      () => message =
                                          'Column order ${columns.map((c) => c.id).join(', ')}',
                                    );
                                    return true;
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                        DButton(
                          label: const Text('User summary'),
                          onPressed: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => Scaffold(
                                appBar: AppBar(
                                  title: const Text('Summary review'),
                                ),
                                body: const UserSummaryView(
                                  siteUrl: 'https://example.com',
                                ),
                              ),
                            ),
                          ),
                        ),
                        for (final value in StyleguideTheme.values.where(
                          (v) => v != StyleguideTheme.current,
                        ))
                          DButton(
                            label: Text(value.label),
                            variant: DButtonVariant.outline,
                            onPressed: () => setState(() => theme = value),
                          ),
                        DButton(
                          label: Text(rtl ? 'LTR' : 'RTL'),
                          onPressed: () => setState(() => rtl = !rtl),
                        ),
                        DButton(
                          label: Text(large ? '100%' : '200%'),
                          onPressed: () => setState(() => large = !large),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(message),
                    const SizedBox(height: 16),
                    PollCard(
                      poll: const Poll(
                        name: 'multiple',
                        type: PollType.multiple,
                        min: 1,
                        max: 2,
                        options: [
                          PollOption(id: 'a', html: 'Alpha'),
                          PollOption(id: 'b', html: 'Beta'),
                        ],
                      ),
                      signedIn: true,
                      archived: false,
                      onVote: (_, ids) async {
                        await Future<void>.delayed(const Duration(seconds: 2));
                        if (mounted) {
                          setState(() => message = 'Saved ${ids.join(', ')}');
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    PollCard(
                      poll: const Poll(
                        name: 'signed-out',
                        options: [PollOption(id: 'a', html: 'Connect to vote')],
                      ),
                      signedIn: false,
                      archived: false,
                      onConnectAccount: () => setState(
                        () => message = 'Local account connection action',
                      ),
                    ),
                    const SizedBox(height: 16),
                    PollCard(
                      poll: const Poll(
                        name: 'web',
                        type: PollType.rankedChoice,
                        options: [
                          PollOption(id: 'a', html: 'Web voting option'),
                        ],
                      ),
                      signedIn: true,
                      archived: false,
                      onVoteOnWeb: () => setState(
                        () => message = 'Local vote-on-web navigation action',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

const _columns = [
  UserDirectoryColumn(
    id: 1,
    name: 'likes_received',
    type: UserDirectoryColumnType.automatic,
    position: 1,
  ),
  UserDirectoryColumn(
    id: 2,
    name: 'post_count',
    type: UserDirectoryColumnType.automatic,
    position: 2,
  ),
  UserDirectoryColumn(
    id: 3,
    name: 'days_visited',
    type: UserDirectoryColumnType.automatic,
    position: 3,
  ),
];
