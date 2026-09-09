import 'package:flutter/material.dart';

import 'discourse_ui.dart';
import 'src/data/user_directory_column_width_store.dart';
import 'src/macos_launch_screen.dart';
import 'src/models/user_directory.dart';
import 'src/plugins/poll/poll.dart';
import 'src/plugins/poll/poll_card.dart';
import 'src/shell/users_page.dart';
import 'src/styleguide/examples/chart_examples.dart';
import 'src/styleguide/styleguide_page.dart';
import 'src/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const ChartReviewFixture(),
    ),
  );
}

/// Offline fixture mounting actual production PollCards. No stores or accounts.
class ChartReviewFixture extends StatefulWidget {
  const ChartReviewFixture({super.key});
  @override
  State<ChartReviewFixture> createState() => _ChartReviewFixtureState();
}

class _ChartReviewFixtureState extends State<ChartReviewFixture> {
  final _widthStore = UserDirectoryColumnWidthStore(
    persistence: _MemoryWidths(),
  );
  var _directoryState = 'ready';
  var _dark = false;
  var _rtl = false;
  var _large = false;
  var _pending = false;
  var _error = false;
  var _status = 'Local ready';
  @override
  Widget build(BuildContext context) => Theme(
    data: _dark ? AppTheme.dark : AppTheme.light,
    child: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Chart review · offline')),
        body: Directionality(
          textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(_large ? 2 : 1)),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DButton(
                      label: const Text('Styleguide'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ComponentStyleguidePage(),
                        ),
                      ),
                    ),
                    DButton(
                      label: Text(_dark ? 'Light' : 'Dark'),
                      onPressed: () => setState(() => _dark = !_dark),
                    ),
                    DButton(
                      label: const Text('RTL'),
                      onPressed: () => setState(() => _rtl = !_rtl),
                    ),
                    DButton(
                      label: const Text('200% text'),
                      onPressed: () => setState(() => _large = !_large),
                    ),
                    DButton(
                      label: const Text('Pending'),
                      onPressed: () => setState(() => _pending = !_pending),
                    ),
                    DButton(
                      label: const Text('Fail next vote'),
                      onPressed: () => setState(() => _error = true),
                    ),
                  ],
                ),
                Text(_status),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final state in ['ready', 'loading', 'empty', 'error'])
                      DButton(
                        label: Text('Directory $state'),
                        onPressed: () =>
                            setState(() => _directoryState = state),
                      ),
                  ],
                ),
                SizedBox(
                  height: 450,
                  child: UsersPage(
                    siteUrl: 'https://chart-review.invalid',
                    columnWidthStore: _widthStore,
                    data: UsersPageData(
                      loaded: _directoryState != 'loading',
                      loading: _directoryState == 'loading',
                      error: _directoryState == 'error'
                          ? 'Offline simulated failure'
                          : null,
                      columns: const [
                        UserDirectoryColumn(
                          id: 1,
                          name: 'likes_received',
                          type: UserDirectoryColumnType.automatic,
                          position: 1,
                        ),
                      ],
                      items: _directoryState != 'ready'
                          ? const []
                          : const [
                              UserDirectoryItem(
                                id: 1,
                                user: UserDirectoryUser(
                                  id: 1,
                                  username: 'local_alpha',
                                ),
                                values: {'likes_received': 290},
                              ),
                              UserDirectoryItem(
                                id: 2,
                                user: UserDirectoryUser(
                                  id: 2,
                                  username: 'local_beta',
                                ),
                                values: {'likes_received': 145},
                              ),
                            ],
                      totalRows: _directoryState == 'ready' ? 2 : 0,
                    ),
                    onRefresh: () async =>
                        setState(() => _directoryState = 'ready'),
                  ),
                ),
                const SizedBox(height: 16),
                const ChartInteractiveExample(),
                const SizedBox(height: 24),
                const Text('Actual PollCard: visible quantitative results'),
                PollCard(
                  poll: const Poll(
                    name: 'ready',
                    title: 'Which device?',
                    voters: 10,
                    options: [
                      PollOption(id: 'desktop', html: 'Desktop', votes: 7),
                      PollOption(id: 'mobile', html: 'Mobile', votes: 3),
                    ],
                  ),
                  signedIn: true,
                  archived: false,
                  pending: _pending,
                  onVote: (_, ids) async {
                    if (_error) {
                      setState(() => _error = false);
                      throw StateError('Offline simulated failure');
                    }
                    setState(
                      () => _status = 'Accepted local vote: ${ids.join(', ')}',
                    );
                  },
                  onVoteError: (_) => setState(
                    () => _status = 'Vote failed locally; retry is available',
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Actual PollCard: multiple-choice quantitative results',
                ),
                PollCard(
                  poll: const Poll(
                    name: 'multiple',
                    title: 'Which platforms do you use?',
                    type: PollType.multiple,
                    min: 1,
                    max: 2,
                    voters: 10,
                    options: [
                      PollOption(id: 'macos', html: 'macOS', votes: 8),
                      PollOption(id: 'ios', html: 'iOS', votes: 6),
                    ],
                  ),
                  signedIn: true,
                  archived: false,
                  pending: _pending,
                  onVote: (_, ids) async {
                    if (_error) {
                      setState(() => _error = false);
                      throw StateError('Offline simulated failure');
                    }
                    setState(
                      () => _status =
                          'Accepted local multiple vote: ${ids.join(', ')}',
                    );
                  },
                  onVoteError: (_) => setState(
                    () => _status =
                        'Multiple vote failed locally; retry is available',
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Confidential results remain confidential'),
                const PollCard(
                  poll: Poll(
                    name: 'confidential',
                    results: PollResults.onVote,
                    options: [
                      PollOption(id: 'a', html: 'Alpha'),
                      PollOption(id: 'b', html: 'Beta'),
                    ],
                  ),
                  signedIn: false,
                  archived: false,
                ),
                const SizedBox(height: 24),
                const Text('Closed poll with no votes'),
                const PollCard(
                  poll: Poll(
                    name: 'empty',
                    status: PollStatus.closed,
                    options: [
                      PollOption(id: 'a', html: 'Alpha', votes: 0),
                      PollOption(id: 'b', html: 'Beta', votes: 0),
                    ],
                  ),
                  signedIn: true,
                  archived: false,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _MemoryWidths implements UserDirectoryColumnWidthPersistence {
  final _values = <String, String>{};
  @override
  Future<String?> readWidths({required String siteUrl}) async =>
      _values[siteUrl];
  @override
  Future<bool> writeWidths({
    required String siteUrl,
    required String encoded,
  }) async {
    _values[siteUrl] = encoded;
    return true;
  }
}
