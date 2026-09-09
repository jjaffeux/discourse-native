// Offline native review of the exact Calendar examples and EventCalendar
// adoption. All event data and actions are local to this process.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_calendar.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_calendar_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/styleguide/examples/calendar_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/event_fixtures.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _CalendarReviewApp());
}

class _CalendarReviewApp extends StatefulWidget {
  const _CalendarReviewApp();

  @override
  State<_CalendarReviewApp> createState() => _CalendarReviewAppState();
}

class _CalendarReviewAppState extends State<_CalendarReviewApp> {
  var _theme = StyleguideTheme.light;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _theme.resolve(AppTheme.light),
    builder: (context, child) => DToaster(child: child!),
    home: _CalendarReview(
      theme: _theme,
      onThemeChanged: (value) => setState(() => _theme = value),
    ),
  );
}

class _CalendarReview extends StatefulWidget {
  const _CalendarReview({required this.theme, required this.onThemeChanged});

  final StyleguideTheme theme;
  final ValueChanged<StyleguideTheme> onThemeChanged;

  @override
  State<_CalendarReview> createState() => _CalendarReviewState();
}

class _CalendarReviewState extends State<_CalendarReview> {
  final _ports = EventTestPorts();
  var _example = 0;
  var _eventView = false;
  var _rtl = false;
  var _scale = 1.0;
  var _width = 720.0;
  var _page = EventCalendarPage(
    EventCalendarView.month,
    DateTime.utc(2026, 9, 8),
  );

  late final _events = [
    _event(
      1,
      'Morning call',
      '2026-09-08T09:00:00+02:00',
      '2026-09-08T10:00:00+02:00',
    ),
    _event(2, 'Launch window', '2026-09-14', '2026-09-17', allDay: true),
  ];

  EventCalendarEntry _event(
    int id,
    String name,
    String start,
    String end, {
    bool allDay = false,
  }) => EventCalendarEntry.decode(
    PostEvent.decode({
      'id': id,
      'name': name,
      'starts_at': start,
      'ends_at': end,
      'timezone': 'Europe/Paris',
      'all_day': allDay,
    })!,
    zones: _ports.zones,
    timezone: 'Europe/Paris',
    settings: const EventSettings(),
  )!;

  @override
  void dispose() {
    _ports.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final example = calendarExamples.examples[_example];
    return Scaffold(
      appBar: AppBar(title: const Text('Calendar exact-source review')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<StyleguideTheme>(
                  value: widget.theme,
                  onChanged: (value) {
                    if (value != null) widget.onThemeChanged(value);
                  },
                  items: [
                    for (final theme in StyleguideTheme.values.skip(1))
                      DropdownMenuItem(value: theme, child: Text(theme.label)),
                  ],
                ),
                TextButton(
                  onPressed: () => setState(() => _rtl = !_rtl),
                  child: Text(_rtl ? 'RTL' : 'LTR'),
                ),
                TextButton(
                  onPressed: () => setState(() => _scale = _scale == 1 ? 2 : 1),
                  child: Text('${(_scale * 100).round()}% text'),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _width = _width == 360 ? 720 : 360),
                  child: Text('${_width.round()}px'),
                ),
                TextButton(
                  onPressed: () => setState(() => _eventView = !_eventView),
                  child: Text(
                    _eventView ? 'Calendar examples' : 'EventCalendar',
                  ),
                ),
                if (!_eventView) ...[
                  IconButton(
                    tooltip: 'Previous example',
                    onPressed: () => setState(
                      () => _example =
                          (_example - 1) % calendarExamples.examples.length,
                    ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(example.title),
                  IconButton(
                    tooltip: 'Next example',
                    onPressed: () => setState(
                      () => _example =
                          (_example + 1) % calendarExamples.examples.length,
                    ),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: Center(
                child: SingleChildScrollView(
                  child: MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(_scale)),
                    child: Directionality(
                      textDirection: _rtl
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      child: SizedBox(
                        width: _width,
                        height: _eventView ? 700 : null,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: _eventView
                              ? EventCalendar(
                                  page: _page,
                                  events: _events,
                                  location: _ports.zones.location(
                                    'Europe/Paris',
                                  )!,
                                  onPageChanged: (value) =>
                                      setState(() => _page = value),
                                  onOpen: (_) {},
                                  mine: false,
                                  onMineChanged: (_) {},
                                  actions: const SizedBox.shrink(),
                                  clock: eventTestNow,
                                )
                              : Builder(builder: example.builder),
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
    );
  }
}
