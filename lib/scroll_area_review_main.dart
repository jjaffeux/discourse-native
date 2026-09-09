import 'dart:async';

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'discourse_ui.dart';
import 'src/diagnostics/diagnostics.dart';
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
import 'src/plugins/voice/voice_diagnostics_view.dart';
import 'src/plugins/voice/voice_report_exporter.dart';
import 'src/shell/code_block.dart';
import 'src/shell/diagnostics_panel.dart';
import 'src/shell/syntax.dart';
import 'src/styleguide/styleguide_page.dart';
import 'src/theme/app_theme.dart';

/// Offline native review of the actual migrated owners. No account services.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final diagnostics = await DiagnosticsController.create(
    persistence: MemoryDiagnosticsPersistence(),
    sessionId: 'scroll-area-review',
  );
  for (var i = 0; i < 80; i++) {
    diagnostics.recordLog(
      name: 'Local event $i',
      message: 'Scroll fixture event $i',
    );
  }
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(_Review(diagnostics: diagnostics));
}

class _Review extends StatefulWidget {
  const _Review({required this.diagnostics});
  final DiagnosticsController diagnostics;
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  final _voice = ChangeNotifier();
  int _page = 0;
  bool _dark = false;
  bool _empty = false;
  @override
  void dispose() {
    _voice.dispose();
    unawaited(widget.diagnostics.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: _dark ? AppTheme.dark : AppTheme.light,
    home: Scaffold(
      appBar: AppBar(
        title: const Text('Scroll Area • offline production fixtures'),
        actions: [
          DButton(
            label: const Text('Theme'),
            onPressed: () => setState(() => _dark = !_dark),
          ),
          if (const [1, 2, 3, 5, 7].contains(_page))
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
                'Diagnostics',
                'Voice',
              ].indexed)
                DButton(
                  label: Text(label),
                  onPressed: () => setState(() => _page = index),
                ),
            ],
          ),
          Expanded(
            child: switch (_page) {
              0 => const ComponentStyleguidePage(),
              1 => DSidebarProvider(
                child: DSidebar(
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
                actions: const SizedBox(),
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
              6 => DiagnosticsPanel(
                controller: widget.diagnostics,
                onClose: () {},
              ),
              _ => VoiceDiagnosticsView(
                stateListenable: _voice,
                eventsListenable: _voice,
                readState: () => const VoiceDiagnosticsUiState(
                  enabled: false,
                  retainedBytes: 0,
                  droppedRecords: 0,
                  truncated: false,
                ),
                readEvents: () => [
                  for (var i = 0; i < (_empty ? 0 : 80); i++)
                    {
                      'sequence': i,
                      'timestampUtc': DateTime.utc(
                        2026,
                        9,
                        9,
                        12,
                        0,
                        i,
                      ).toIso8601String(),
                      'event': 'Local event',
                      'component': 'fixture',
                      'severity': 'info',
                      'message': 'Local event $i',
                      'data': <String, Object?>{},
                    },
                ],
                startCapture: () async {},
                stopCapture: () async {},
                clear: () async => setState(() => _empty = true),
                buildJsonReport: () async => '{}',
                exporter: _LocalExporter(),
              ),
            },
          ),
        ],
      ),
    ),
  );
}

class _LocalExporter implements VoiceReportExporter {
  @override
  String get actionLabel => 'Local export';
  @override
  Future<VoiceReportExportOutcome> export(
    String report, {
    Rect? sharePositionOrigin,
  }) async => VoiceReportExportOutcome.cancelled;
}
