import 'package:discourse_native/src/plugins/discourse_events/topic_calendar_data.dart';
import 'package:html/parser.dart' as html;

Map<String, dynamic> calendarPostJson({List<Object?>? details}) => {
  'id': 42,
  'topic_id': 700,
  'post_number': 1,
  'username': 'sam',
  'cooked':
      '<div class="discourse-calendar-wrap">'
      '<div class="calendar" data-calendar-type="dynamic" '
      'data-weekends="true" data-calendar-full-day="true" '
      'data-calendar-show-add-to-calendar="false"></div></div>',
  'calendar_details': details ?? [calendarDetail()],
};

Map<String, Object?> calendarDetail({
  Map<String, Object?> overrides = const {},
}) => {
  'type': 'standalone',
  'post_number': 80,
  'message': 'Team availability',
  'username': 'sam',
  'from': '2026-09-06T22:00:00.000Z',
  'to': '2026-09-09T22:00:00.000Z',
  'timezone': 'Europe/Paris',
  'recurring': null,
  'post_url': '/t/-/700/80',
  ...overrides,
};

TopicCalendarOptions calendarOptions([
  String attributes = 'data-calendar-full-day="true"',
]) => TopicCalendarOptions.fromElement(
  html
      .parseFragment('<div class="calendar" $attributes></div>')
      .children
      .single,
);
