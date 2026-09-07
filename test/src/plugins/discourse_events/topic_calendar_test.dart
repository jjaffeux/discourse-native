import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugins/discourse_events/discourse_events_module.dart';
import 'package:discourse_native/src/plugins/discourse_events/topic_calendar.dart';
import 'package:discourse_native/src/plugins/discourse_events/topic_calendar_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/topic_calendar_plugin.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:kalender/kalender.dart' as kalender;

import '../../../support/event_fixtures.dart';
import '../../../support/topic_calendar_fixtures.dart';

void main() {
  late EventTestPorts ports;
  setUp(() => ports = EventTestPorts());
  tearDown(() => ports.close());

  Widget calendar({
    List<Object?>? details,
    String options = 'data-calendar-full-day="true"',
    double width = 800,
    double scale = 1,
    Brightness brightness = Brightness.light,
    ValueChanged<int>? openReply,
    VoidCallback? openWeb,
    TopicCalendarSettings settings = const TopicCalendarSettings(),
  }) => MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: TopicCalendar(
              data: TopicCalendarData.decode(
                calendarPostJson(details: details),
              )!,
              options: calendarOptions(options),
              settings: settings,
              zones: ports.zones,
              now: DateTime.utc(2026, 9, 7, 12),
              onOpenReply: openReply ?? (_) {},
              onOpenWeb: openWeb ?? () {},
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> chooseView(WidgetTester tester, String view) async {
    await tester.tap(find.byTooltip('Calendar view'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(view).last);
    await tester.pumpAndSettle();
  }

  testWidgets('month navigation, today and reply links use server details', (
    tester,
  ) async {
    int? postNumber;
    await tester.pumpWidget(
      calendar(openReply: (number) => postNumber = number),
    );
    await tester.pumpAndSettle();
    expect(find.byType(kalender.KalenderView), findsOneWidget);
    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('Team availability'), findsOneWidget);
    await tester.tap(find.text('Team availability'));
    expect(postNumber, 80);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('Team availability'), findsNothing);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('September 2026'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('August 2026'), findsOneWidget);
  });

  testWidgets(
    'a busy narrow calendar exposes every hidden event in its day list',
    (tester) async {
      final details = [
        for (var i = 0; i < 8; i++)
          calendarDetail(
            overrides: {
              'from': '2026-09-07',
              'to': null,
              'message': 'Person $i',
              'post_number': 10 + i,
            },
          ),
      ];
      int? opened;
      await tester.pumpWidget(
        calendar(
          width: 320,
          details: details,
          openReply: (number) => opened = number,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('+5'), findsOneWidget);
      expect(find.text('Person 7'), findsNothing);
      await tester.tap(find.text('+5'));
      await tester.pumpAndSettle();
      expect(find.text('Person 7'), findsOneWidget);
      final reply = find.text('View reply #17');
      await tester.ensureVisible(reply);
      await tester.tap(reply);
      await tester.pumpAndSettle();
      expect(opened, 17);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'a changed post updates Kalender without resetting the current month',
    (tester) async {
      const options = 'data-weekends="true" data-calendar-full-day="true"';
      await tester.pumpWidget(calendar(options: options));
      await tester.pumpAndSettle();
      expect(find.text('Sat'), findsOneWidget);
      expect(find.text('Sun'), findsOneWidget);
      expect(find.text('Mon'), findsOneWidget);
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        calendar(
          options: options,
          details: [
            calendarDetail(
              overrides: {
                'from': '2026-10-05',
                'to': null,
                'message': 'New reply',
              },
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('New reply'), findsOneWidget);
      await tester.pumpWidget(
        calendar(
          details: [
            calendarDetail(
              overrides: {
                'from': '2026-10-05',
                'to': null,
                'message': 'Edited reply',
              },
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('New reply'), findsNothing);
      expect(find.text('Edited reply'), findsOneWidget);
    },
  );

  testWidgets(
    'timezone selection changes timed entries without changing account settings',
    (tester) async {
      await tester.pumpWidget(
        calendar(
          options: '',
          details: [
            calendarDetail(
              overrides: {
                'from': '2026-09-08T01:00:00Z',
                'to': '2026-09-08T02:00:00Z',
              },
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('01:00 Team availability'), findsOneWidget);
      await tester.tap(find.text('Etc/UTC'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Los Angeles');
      await tester.pumpAndSettle();
      await tester.tap(find.text('America/Los Angeles'));
      await tester.pumpAndSettle();
      expect(find.text('18:00 Team availability'), findsOneWidget);
      expect(ports.zones.readerTimezone(), 'Etc/UTC');
    },
  );

  testWidgets('Kalender clips a range into adjoining week rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      calendar(
        details: [
          calendarDetail(
            overrides: {
              'from': '2026-09-11',
              'to': '2026-09-15',
              'message': 'Long weekend',
            },
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final bars = find.byWidgetPredicate(
      (widget) =>
          widget is Tooltip &&
          (widget.message?.startsWith('Long weekend,') ?? false),
    );
    expect(bars, findsNWidgets(2));
    final first = tester.getRect(bars.first);
    final second = tester.getRect(bars.last);
    expect(first.width / second.width, closeTo(1.5, 0.05));
    expect(first.top, lessThan(second.top));
    expect(second.left, lessThan(first.left));
  });

  testWidgets(
    'week, day and agenda views keep the focused date and reply data',
    (tester) async {
      await tester.pumpWidget(calendar(width: 320));
      await tester.pumpAndSettle();
      await chooseView(tester, 'Week');
      expect(find.byType(kalender.MultiDayBody), findsOneWidget);
      expect(find.text('Sep 7 – Sep 13, 2026'), findsOneWidget);
      expect(find.text('Team availability'), findsOneWidget);
      await tester.tap(find.byTooltip('Next week'));
      await tester.pumpAndSettle();
      expect(find.text('Sep 14 – Sep 20, 2026'), findsOneWidget);
      expect(find.text('Team availability'), findsNothing);
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      await chooseView(tester, 'Day');
      expect(find.text('Sep 7, 2026'), findsOneWidget);
      expect(find.text('Team availability'), findsOneWidget);
      await chooseView(tester, 'Agenda');
      expect(find.byType(kalender.ScheduleBody), findsOneWidget);
      expect(find.text('Team availability'), findsWidgets);
      await chooseView(tester, 'Month');
      expect(find.text('September 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('all views fit a narrow post with large text', (tester) async {
    await tester.pumpWidget(calendar(width: 320, scale: 2));
    await tester.pumpAndSettle();
    for (final view in ['Week', 'Day', 'Agenda', 'Month']) {
      await chooseView(tester, view);
      expect(tester.takeException(), isNull, reason: view);
    }
  });

  testWidgets(
    'swiping to later months loads recurring dates beyond the initial window',
    (tester) async {
      await tester.pumpWidget(
        calendar(
          details: [
            calendarDetail(
              overrides: {
                'from': '2026-09-07',
                'to': null,
                'recurring': '1.weeks',
              },
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        final body = tester.getRect(find.byType(kalender.MonthBody));
        await tester.dragFrom(
          Offset(body.right - 30, body.top + 70),
          const Offset(-650, 0),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('February 2027'), findsOneWidget);
      expect(find.text('Team availability'), findsWidgets);
      final view = tester.widget<kalender.KalenderView>(
        find.byType(kalender.KalenderView),
      );
      expect(view.eventsController.events.length, lessThan(25));
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      await chooseView(tester, 'Day');
      expect(find.text('Sep 7, 2026'), findsOneWidget);
    },
  );

  testWidgets('site week starts are translated into Kalender weekdays', (
    tester,
  ) async {
    await tester.pumpWidget(
      calendar(settings: const TopicCalendarSettings(firstDay: 0)),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.text('Sun')).dx,
      lessThan(tester.getCenter(find.text('Mon')).dx),
    );
    await chooseView(tester, 'Week');
    expect(find.text('Sep 6 – Sep 12, 2026'), findsOneWidget);
  });

  testWidgets('timezone changes preserve the browsed month and all-day dates', (
    tester,
  ) async {
    await tester.pumpWidget(
      calendar(
        details: [
          calendarDetail(overrides: {'from': '2026-10-25', 'to': null}),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Etc/UTC'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Los Angeles');
    await tester.pumpAndSettle();
    await tester.tap(find.text('America/Los Angeles'));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    final text = tester.widget<Text>(find.text('Team availability'));
    expect(text.semanticsLabel, contains('Oct 25, 2026 · All day'));
  });

  testWidgets('hidden weekdays offer a working web fallback', (tester) async {
    var opened = false;
    for (final options in ['data-weekends="false"', 'data-hidden-days="2"']) {
      await tester.pumpWidget(
        calendar(options: options, openWeb: () => opened = true),
      );
      await tester.pumpAndSettle();
      expect(find.byType(kalender.KalenderView), findsNothing);
      expect(
        find.text('Open the web calendar to view its configured weekdays.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Open web calendar'));
      expect(opened, isTrue);
      opened = false;
    }
  });

  testWidgets('empty and all-hidden calendars have readable states', (
    tester,
  ) async {
    await tester.pumpWidget(calendar(details: []));
    expect(find.text('No calendar entries this month.'), findsOneWidget);
    await tester.pumpWidget(
      calendar(options: 'data-hidden-days="0,1,2,3,4,5,6"'),
    );
    expect(
      find.text('All weekdays are hidden in this calendar.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('320px calendar supports large text in $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        calendar(width: 320, scale: 2, brightness: brightness),
      );
      await tester.pumpAndSettle();
      expect(find.text('Team availability'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final label = tester.widget<Text>(find.text('Team availability'));
      expect(label.semanticsLabel, contains('Sep 7, 2026 – Sep 10, 2026'));
    });
  }

  test(
    'standalone installation owns calendar data and settings; core stays unaware',
    () async {
      final plugins = PluginInstaller.install(
        const PluginManifest([discourseEventsModule]),
      );
      addTearDown(plugins.close);
      expect(
        plugins.models
            .post(calendarPostJson(), eventSite)
            .plugins
            .get(topicCalendarKey),
        isNotNull,
      );
      expect(
        const DiscourseModelCodec.core()
            .post(calendarPostJson(), eventSite)
            .plugins
            .get(topicCalendarKey),
        isNull,
      );
      expect(plugins.descriptors.single.dependencies, isEmpty);
    },
  );

  testWidgets(
    'real cooked wrapper renders once and opens an unloaded reply on a subfolder site',
    (tester) async {
      const site = '$eventSite/forum';
      final plugins = PluginInstaller.install(
        const PluginManifest([discourseEventsModule]),
      );
      addTearDown(plugins.close);
      final host = await PluginHostHarness.open(
        transport: RecordingPluginTransport(),
        manifest: const PluginManifest([discourseEventsModule]),
        sites: const [PluginHostSite(url: site, apiKey: 'key')],
      );
      addTearDown(host.close);
      final now = DateTime.now().toUtc();
      final json = calendarPostJson(
        details: [
          calendarDetail(
            overrides: {
              'from': DateTime.utc(
                now.year,
                now.month,
                now.day,
                12,
              ).toIso8601String(),
              'to': null,
              'timezone': 'Etc/UTC',
            },
          ),
        ],
      );
      json['cooked'] = (json['cooked'] as String).replaceFirst(
        '<div class="calendar"',
        '<div class="discourse-calendar-header"><select class="discourse-calendar-timezone-picker"></select></div><div class="calendar"',
      );
      final post = plugins.models.post(json, site);
      await tester.pumpWidget(
        host.scope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: CookedHtml(
                  html: post.cooked,
                  post: post,
                  siteUrl: site,
                  registry: plugins.registry,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TopicCalendar), findsOneWidget);
      expect(find.text('Team availability'), findsOneWidget);
      await tester.ensureVisible(find.text('Team availability'));
      await tester.tap(find.text('Team availability'));
      await tester.pumpAndSettle();
      expect(host.currentContent!.topicId, 700);
      expect(host.currentContent!.postNumber, 80);
      await tester.pumpWidget(const SizedBox.shrink());
      await host.close();
    },
  );

  testWidgets(
    'quoted, static and missing-data calendars keep a readable fallback',
    (tester) async {
      const plugin = TopicCalendarPlugin();
      final plugins = PluginInstaller.install(
        const PluginManifest([discourseEventsModule]),
      );
      addTearDown(plugins.close);
      final post = plugins.models.post(calendarPostJson(), eventSite);
      for (final markup in [
        '<blockquote><div class="calendar">Quoted dates</div></blockquote>',
        '<div class="calendar" data-calendar-type="static">Static dates</div>',
      ]) {
        final element = html.parseFragment(markup).querySelector('.calendar')!;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: plugin.postBodyElement(
                  PluginPostBodyContext(
                    buildContext: context,
                    siteUrl: eventSite,
                    post: post,
                  ),
                  element,
                ),
              ),
            ),
          ),
        );
        expect(find.byType(TopicCalendarFallback), findsOneWidget);
        expect(find.text(element.text), findsOneWidget);
        expect(find.byType(TopicCalendar), findsNothing);
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: plugin.cookedElement(
              eventSite,
              html
                  .parseFragment('<div class="calendar"></div>')
                  .children
                  .single,
            ),
          ),
        ),
      );
      expect(find.text('Topic calendar'), findsOneWidget);
      expect(
        find.text('Open the original topic to view this calendar.'),
        findsOneWidget,
      );
    },
  );
}
