// Offline fixture using the production event page and Native calendar examples.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_calendar.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_calendar_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/styleguide/examples/calendar_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/event_fixtures.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const MobileEventsReviewApp());
}

class MobileEventsReviewApp extends StatefulWidget {
  const MobileEventsReviewApp({
    super.key,
    this.initialView = EventCalendarView.month,
    this.dark = true,
    this.controls = true,
    this.width = 390,
    this.scale = 1,
  });
  final EventCalendarView initialView;
  final bool dark;
  final bool controls;
  final double width;
  final double scale;

  @override
  State<MobileEventsReviewApp> createState() => _MobileEventsReviewAppState();
}

class _MobileEventsReviewAppState extends State<MobileEventsReviewApp> {
  final _ports = EventTestPorts();
  late var _page = EventCalendarPage(
    widget.initialView,
    DateTime.utc(2026, 9, 23),
  );
  late var _dark = widget.dark;
  late var _width = widget.width;
  late var _scale = widget.scale;
  var _mine = false;
  var _rtl = false;
  var _examples = false;
  String? _opened;

  late final _events = [
    _event(1, 'Launch', 3, end: 8, color: 0xff27ae60, allDay: true),
    _event(2, 'Community call', 3),
    _event(3, 'Community call', 5),
    _event(4, 'Team lunch', 8, color: 0xffefac00),
    _event(5, 'Support escalations', 8),
    _event(6, 'Planning', 10, color: 0xff27ae60),
    _event(7, 'Planning', 11, color: 0xff27ae60),
    _event(8, 'Launch', 14, color: 0xff27ae60),
    _event(9, 'Launch', 15, end: 17, color: 0xff27ae60, allDay: true),
    _event(10, 'Planning', 16, end: 19, color: 0xff27ae60, allDay: true),
    _event(11, 'Conference', 18, end: 21, color: 0xff9b59b6, allDay: true),
    for (var i = 0; i < 5; i++)
      _event(
        12 + i,
        'Team meeting',
        15,
        hour: 10 + i,
        color: i.isEven ? 0xffefac00 : 0xff9b59b6,
      ),
    for (var i = 0; i < 5; i++)
      _event(20 + i, 'Team meeting', 16, hour: 10 + i, color: 0xffefac00),
    for (var i = 0; i < 4; i++)
      _event(30 + i, 'Team meeting', 18, hour: 10 + i),
    _event(
      40,
      'Support escalations',
      23,
      category: 'books',
      author: 'grainydays',
    ),
    _event(
      41,
      'Dev and ops sync',
      24,
      hour: 19,
      minute: 30,
      category: 'hiking',
      author: 'nomadnomad',
      color: 0xff1abc9c,
    ),
    _event(
      42,
      'Asia handover',
      28,
      hour: 7,
      category: 'travel',
      author: 'secondbrain42',
      color: 0xff9b59b6,
    ),
    _event(
      43,
      'Team lunch',
      28,
      hour: 10,
      category: 'wellness',
      author: 'verdant_vera',
      color: 0xffefac00,
    ),
    _event(
      44,
      'Customer roundtable',
      28,
      hour: 14,
      category: 'photography',
      author: 'sobercurious',
      color: 0xff9b59b6,
    ),
    _event(
      45,
      'Customer roundtable',
      28,
      end: 30,
      hour: 15,
      category: 'plants',
      author: 'grindsetgo',
      color: 0xff3498db,
    ),
    _event(
      46,
      'Engineering sync',
      28,
      hour: 16,
      minute: 30,
      category: 'baking',
      author: 'wanderlustwendy',
      color: 0xffefac00,
    ),
    _event(
      47,
      'Mock webinar',
      29,
      hour: 10,
      category: 'photography',
      author: 'wanderlustwendy',
      color: 0xff9b59b6,
    ),
    _event(
      48,
      'Dev and ops sync',
      30,
      hour: 9,
      minute: 30,
      category: 'photography',
      author: 'readingpanda',
      color: 0xff9b59b6,
    ),
    for (var i = 0; i < 4; i++)
      _event(
        50 + i,
        'Asia handover',
        30,
        hour: 10 + i,
        color: i.isEven ? 0xff27ae60 : 0xffefac00,
      ),
  ];

  EventCalendarEntry _event(
    int id,
    String title,
    int day, {
    int? end,
    int hour = 9,
    int minute = 0,
    int color = 0xffe67e22,
    String? category,
    String? author,
    bool allDay = false,
  }) => EventCalendarEntry.decode(
    PostEvent.decode({
      'id': id,
      'name': title,
      'starts_at': DateTime.utc(
        2026,
        9,
        day,
        allDay ? 0 : hour,
        minute,
      ).toIso8601String(),
      'ends_at': DateTime.utc(
        2026,
        9,
        end ?? day,
        allDay ? 0 : hour + 1,
        minute,
      ).toIso8601String(),
      'all_day': allDay,
      if (author != null) 'creator': {'username': author},
      'post': {'id': id, 'category_slug': ?category},
    })!,
    zones: _ports.zones,
    timezone: 'UTC',
    settings: const EventSettings(),
    categoryColor: Color(color),
  )!;

  @override
  void dispose() {
    _ports.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _dark
        ? AppTheme.fromPalette(
            forumThemePresets
                .singleWhere((preset) => preset.id == 'dracula')
                .resolve(Brightness.dark),
          )
        : AppTheme.light;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.copyWith(platform: TargetPlatform.iOS),
      home: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              if (widget.controls)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    spacing: DSpacing.controlGap,
                    runSpacing: 8,
                    children: [
                      DButton(
                        label: Text(_dark ? 'Light palette' : 'Dark palette'),
                        onPressed: () => setState(() => _dark = !_dark),
                      ),
                      DButton(
                        label: Text('${_width.round()} px'),
                        onPressed: () => setState(
                          () => _width = _width == 390
                              ? 320
                              : _width == 320
                              ? 1200
                              : 390,
                        ),
                      ),
                      DButton(
                        label: Text('${_scale * 100}% text'),
                        onPressed: () =>
                            setState(() => _scale = _scale == 1 ? 2 : 1),
                      ),
                      DButton(
                        label: Text(_rtl ? 'RTL' : 'LTR'),
                        onPressed: () => setState(() => _rtl = !_rtl),
                      ),
                      DButton(
                        label: Text(
                          _examples ? 'Event page' : 'Styleguide examples',
                        ),
                        onPressed: () => setState(() => _examples = !_examples),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: _width,
                    child: MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(_scale)),
                      child: Directionality(
                        textDirection: _rtl
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: DPageSurface(
                          child: _examples
                              ? SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      for (final example
                                          in calendarExamples.examples.skip(12))
                                        Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Builder(
                                            builder: example.builder,
                                          ),
                                        ),
                                    ],
                                  ),
                                )
                              : EventCalendar(
                                  page: _page,
                                  events: _events,
                                  location: _ports.zones.location('UTC')!,
                                  onPageChanged: (page) =>
                                      setState(() => _page = page),
                                  onOpen: (event) =>
                                      setState(() => _opened = event.title),
                                  mine: _mine,
                                  onMineChanged: (mine) =>
                                      setState(() => _mine = mine),
                                  actions: const SizedBox.shrink(),
                                  clock: () => DateTime.utc(2026, 9, 23),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_opened != null) Text('Opened $_opened'),
            ],
          ),
        ),
      ),
    );
  }
}
