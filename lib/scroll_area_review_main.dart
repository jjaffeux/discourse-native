import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'discourse_ui.dart';

import 'src/macos_launch_screen.dart';
import 'src/models/topic_feed.dart';
import 'src/plugins/assign/assigned_group.dart';
import 'src/plugins/assign/assigned_group_presentation.dart';
import 'src/plugins/assign/assigned_group_view.dart';
import 'src/plugins/discourse_events/event_calendar.dart';
import 'src/plugins/discourse_events/event_calendar_data.dart';
import 'src/plugins/discourse_events/event_data.dart';
import 'src/plugins/prometheus_alert_receiver/alert_data.dart';
import 'src/plugins/prometheus_alert_receiver/alert_tables.dart';

import 'src/shell/code_block.dart';

import 'src/styleguide/styleguide_page.dart';
import 'src/theme/app_theme.dart';

/// Offline native review of the actual migrated owners. No account services.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const ScrollAreaReviewApp());
}

class ScrollAreaReviewApp extends StatefulWidget {
  const ScrollAreaReviewApp({
    super.key,

    this.themeOverride,
    this.textScale = 1,
  });
  final ThemeData? themeOverride;
  final double textScale;

  @override
  State<ScrollAreaReviewApp> createState() => _ReviewState();
}

class _ReviewState extends State<ScrollAreaReviewApp> {
  int _page = 0;
  bool _dark = false;
  bool _empty = false;
  @override
  Widget build(BuildContext context) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    localeListResolutionCallback: resolveAppLocale,
    debugShowCheckedModeBanner: false,
    themeAnimationDuration: Duration.zero,
    theme: widget.themeOverride ?? (_dark ? AppTheme.dark : AppTheme.light),
    home: Scaffold(
      appBar: AppBar(
        title: const Text('Scroll Area • offline production fixtures'),
        actions: [
          DButton(
            label: const Text('Theme'),
            onPressed: () => setState(() => _dark = !_dark),
          ),
          if (const [1, 2, 3, 5].contains(_page))
            DButton(
              label: const Text('Empty / ready'),
              onPressed: () => setState(() => _empty = !_empty),
            ),
        ],
      ),
      body: Column(
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final (index, label) in [
                'Styleguide',
                'Sidebar',
                'Code',
                'Alerts',
                'Calendar',
                'Assignments',
              ].indexed)
                DButton(
                  label: Text(label),
                  onPressed: () => setState(() => _page = index),
                ),
            ],
          ),
          Expanded(
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(widget.textScale)),
                child: switch (_page) {
                  0 => const ComponentStyleguidePage(),
                  1 => DSidebarProvider(
                    child: DSidebar(
                      collapsible: DSidebarCollapsible.none,
                      child: DSidebarContent(
                        children: [
                          for (var i = 0; i < (_empty ? 0 : 80); i++)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text('Destination $i'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  2 => SingleChildScrollView(
                    child: CodeBlock(
                      data: CodeBlockData(
                        lines: [
                          for (var i = 0; i < (_empty ? 0 : 30); i++)
                            CodeLine(
                              tokens: [
                                CodeToken(
                                  'final entry$i = "${'long local text ' * 12}";',
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  3 => SingleChildScrollView(
                    child: SizedBox(
                      width: 360,
                      child: AlertTables(
                        siteUrl: 'https://example.invalid',
                        data: AlertData.decode({
                          'alert_data': [
                            for (var i = 0; i < (_empty ? 0 : 12); i++)
                              {
                                'status': 'firing',
                                'identifier': 'Local alert $i',
                                'datacenter': 'local',
                                'description':
                                    'Long offline description for horizontal scrolling',
                                'starts_at': '2026-09-09T12:00:00Z',
                              },
                          ],
                        })!,
                      ),
                    ),
                  ),
                  4 => EventCalendar(
                    page: EventCalendarPage(
                      EventCalendarView.month,
                      DateTime(2026, 9, 9),
                    ),
                    events: const [],
                    location: tz.UTC,
                    onPageChanged: (_) {},
                    onOpen: (_) {},
                    mine: false,
                    onMineChanged: (_) {},
                  ),
                  5 => AssignedGroupPresentationView(
                    siteUrl: 'https://example.invalid',
                    state: AssignedGroupPresentationState(
                      groupName: 'local',
                      filter: const AssignedGroupFilter.everyone(),
                      query: const AssignedGroupTopicQuery(),
                      members: AssignedGroupMembersState(
                        loaded: true,
                        members: [
                          for (var i = 0; i < (_empty ? 0 : 80); i++)
                            AssignedGroupMember(
                              id: i + 1,
                              username: 'Member$i',
                              usernameLower: 'member$i',
                              assignmentsCount: i,
                            ),
                        ],
                      ),
                      feed: const TopicFeed(),
                      topics: const [],
                    ),
                    onRefresh: () async {},
                    onSelect: (_) {},
                    onQueryChanged: (_) {},
                    onMemberSearch: (_) {},
                    onLoadMoreMembers: () {},
                    onLoadMoreTopics: () {},
                    onOpenTopic: (_) {},
                  ),
                  _ => const SizedBox.shrink(),
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
