import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import 'json.dart';

enum DashboardPeriod {
  last7Days,
  last30Days,
  last3Months,
  last6Months,
  lastYear;

  DashboardRange rangeAt(DateTime now) {
    final end = DateTime(now.year, now.month, now.day);
    final start = switch (this) {
      last7Days => DateTime(end.year, end.month, end.day - 6),
      last30Days => DateTime(end.year, end.month, end.day - 29),
      last3Months => _nextDay(_monthsAgo(end, 3)),
      last6Months => _nextDay(_monthsAgo(end, 6)),
      lastYear => _nextDay(_monthsAgo(end, 12)),
    };
    return DashboardRange(start, end);
  }

  static DateTime _nextDay(DateTime value) =>
      DateTime(value.year, value.month, value.day + 1);

  static DateTime _monthsAgo(DateTime value, int count) {
    final month = DateTime(value.year, value.month - count);
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    return DateTime(month.year, month.month, value.day.clamp(1, lastDay));
  }
}

@immutable
final class DashboardRange {
  const DashboardRange(this.start, this.end);
  final DateTime start;
  final DateTime end;
  Map<String, String> get query => {
    'start_date': _day(start),
    'end_date': _day(end),
  };
  static String _day(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

num? dashboardNumber(Object? value) =>
    value is num && value.isFinite ? value : null;

@immutable
final class DashboardMetric {
  const DashboardMetric(this.type, this.value, {this.change, this.pointChange});
  factory DashboardMetric.fromJson(String type, Map<String, dynamic> json) =>
      DashboardMetric(
        type,
        dashboardNumber(json['value']),
        change: dashboardNumber(json['percent_change']),
        pointChange: dashboardNumber(json['point_change']),
      );
  final String type;
  final num? value;
  final num? change;
  final num? pointChange;
}

@immutable
final class DashboardPoint {
  const DashboardPoint(this.label, this.value);
  factory DashboardPoint.fromJson(Map<String, dynamic> json) =>
      DashboardPoint(jsonString(json['x']), dashboardNumber(json['y']));
  final String label;
  final num? value;
}

@immutable
final class DashboardSeries {
  DashboardSeries(this.id, this.label, Iterable<DashboardPoint> points)
    : points = List.unmodifiable(points);
  factory DashboardSeries.fromJson(Map<String, dynamic> json) =>
      DashboardSeries(
        jsonString(json['req']),
        jsonString(json['label']),
        jsonObjects(json['data']).map(DashboardPoint.fromJson),
      );
  final String id;
  final String label;
  final List<DashboardPoint> points;
  bool get crawler => id == 'page_view_crawler';
}

@immutable
final class DashboardLink {
  const DashboardLink.server(this.value) : origin = DashboardLinkOrigin.server;
  const DashboardLink.app(this.value) : origin = DashboardLinkOrigin.app;

  final String value;
  final DashboardLinkOrigin origin;
}

enum DashboardLinkOrigin { server, app }

@immutable
final class DashboardBreakdownRow {
  const DashboardBreakdownRow({
    required this.label,
    this.count,
    this.share,
    this.change,
    this.topics,
    this.posts,
    this.views,
    this.promoted,
    this.demoted,
    this.status,
    this.link,
  });
  final String label;
  final num? count;
  final num? share;
  final num? change;
  final num? topics;
  final num? posts;
  final num? views;
  final int? promoted;
  final int? demoted;
  final String? status;
  final DashboardLink? link;
}

@immutable
final class DashboardBreakdown {
  DashboardBreakdown(
    this.title,
    Iterable<DashboardBreakdownRow> rows, {
    this.error = false,
  }) : rows = List.unmodifiable(rows);
  final String title;
  final List<DashboardBreakdownRow> rows;
  final bool error;
}

sealed class DashboardSection {
  const DashboardSection(this.id);
  final String id;
  static DashboardSection fromJson(Map<String, dynamic> json) {
    final id = jsonString(json['id']);
    final data = jsonObject(json['data']);
    if (json['error'] == true || json['data'] == null) {
      return DashboardUnavailableSection(id, failed: true);
    }
    return switch (id) {
      'highlights' => DashboardHighlights(_metricsList(data['kpis'])),
      'reports' => DashboardReports(
        jsonObjects(data['items']).map(DashboardReport.fromJson),
      ),
      'traffic' => DashboardTraffic.fromJson(data),
      'engagement' => DashboardEngagement.fromJson(data),
      'search' => DashboardSearch.fromJson(data),
      'system' => DashboardSystem.fromJson(data),
      _ => DashboardUnavailableSection(id),
    };
  }
}

List<DashboardMetric> _metricsList(Object? value) => [
  for (final json in jsonObjects(value))
    DashboardMetric.fromJson(jsonString(json['type']), json),
];
List<DashboardMetric> _metricsMap(Object? value) => [
  for (final entry in jsonObject(value).entries)
    DashboardMetric.fromJson(entry.key, jsonObject(entry.value)),
];

final class DashboardUnavailableSection extends DashboardSection {
  const DashboardUnavailableSection(super.id, {this.failed = false});
  final bool failed;
}

final class DashboardHighlights extends DashboardSection {
  DashboardHighlights(Iterable<DashboardMetric> metrics)
    : metrics = List.unmodifiable(metrics),
      super('highlights');
  final List<DashboardMetric> metrics;
}

@immutable
final class DashboardReport {
  const DashboardReport({
    required this.source,
    required this.identifier,
    required this.title,
    required this.path,
    this.description = '',
    this.rows = 1,
    this.cols = 1,
  });
  factory DashboardReport.fromJson(Map<String, dynamic> json) =>
      DashboardReport(
        source: jsonString(json['source']),
        identifier: jsonString(json['identifier']),
        title: jsonString(json['title']),
        path: jsonString(json['url']),
        description: jsonHtmlText(json['description']) ?? '',
        rows: jsonIntOrNull(json['rows']) ?? 1,
        cols: jsonIntOrNull(json['cols']) ?? 1,
      );
  final String source;
  final String identifier;
  final String title;
  final String description;
  final String path;
  final int rows;
  final int cols;
  String get key => '$source:$identifier';
  Map<String, Object?> toJson() => {
    'source': source,
    'identifier': identifier,
    'rows': rows,
    'cols': cols,
  };
}

final class DashboardReports extends DashboardSection {
  DashboardReports(Iterable<DashboardReport> items)
    : items = List.unmodifiable(items),
      super('reports');
  final List<DashboardReport> items;
}

@immutable
final class DashboardReportResult {
  DashboardReportResult({
    this.error = false,
    this.unsupported = false,
    Iterable<DashboardPoint> points = const [],
    Iterable<String> headings = const [],
    Iterable<List<String>> rows = const [],
    this.total,
    this.average = false,
    this.percent = false,
    Iterable<DashboardSeries> series = const [],
  }) : series = List.unmodifiable(series),
       points = List.unmodifiable(points),
       headings = List.unmodifiable(headings),
       rows = List.unmodifiable(rows.map(List<String>.unmodifiable));
  factory DashboardReportResult.fromJson(Map<String, dynamic> json) {
    final data = jsonObject(json['data']);
    final series = [
      for (final item in jsonObjects(data['data']))
        if (item['data'] is List) DashboardSeries.fromJson(item),
    ];
    final values = jsonObjects(data['data']).toList();
    final labels = jsonObjects(data['labels']).toList();
    final properties = labels.map(_reportProperty).toList();
    final points = values
        .where(
          (row) =>
              row['x'] is String &&
              row.containsKey('y') &&
              (row['y'] == null || dashboardNumber(row['y']) != null),
        )
        .map(DashboardPoint.fromJson)
        .toList();
    return DashboardReportResult(
      error:
          json['error'] == true ||
          data['error'] != null && data['error'] != false,
      unsupported:
          data.isEmpty ||
          series.isEmpty &&
              points.isEmpty &&
              (values.isNotEmpty && labels.isEmpty ||
                  properties.contains(null)),
      points: points,
      series: series,
      average: data['average'] == true,
      percent: data['percent'] == true,
      total: dashboardNumber(data['total']),
      headings: labels.map((label) => jsonString(label['title'])),
      rows: series.isNotEmpty || properties.contains(null)
          ? const []
          : values.map(
              (row) => [
                for (final property in properties) _reportCell(row[property]),
              ],
            ),
    );
  }
  static String? _reportProperty(Map<String, dynamic> label) {
    final property = jsonText(label['property']);
    if (property != null) return property;
    final properties = label['properties'];
    if (properties is List) {
      if (label['type'] == 'link' && properties.length == 2) {
        return jsonText(properties[1]);
      }
      return properties.length == 1 ? jsonText(properties.single) : null;
    }
    final key = switch (label['type']) {
      'user' => 'username',
      'topic' => 'title',
      'post' => 'truncated_raw',
      _ => null,
    };
    return key == null ? null : jsonText(jsonObject(properties)[key]);
  }

  /// Report rows are database text (titles, raw, edit reasons) that the web
  /// escapes cell by cell, so markup in them is content, not formatting.
  static String _reportCell(Object? value) => switch (value) {
    null => '—',
    String() => jsonText(value) ?? '',
    num() => value.toString(),
    bool() => value.toString(),
    _ => '—',
  };
  final bool error;
  final bool unsupported;
  final List<DashboardPoint> points;
  final List<DashboardSeries> series;
  final List<String> headings;
  final List<List<String>> rows;
  final num? total;
  final bool average;
  final bool percent;
  num? get value {
    if (points.isEmpty) return total;
    final observed = points.map((point) => point.value).nonNulls.toList();
    if (observed.isEmpty || !average && observed.length != points.length) {
      return null;
    }
    final sum = observed.fold<num>(0, (sum, value) => sum + value);
    return average ? sum / observed.length : sum;
  }
}

final class DashboardTraffic extends DashboardSection {
  DashboardTraffic({
    required Iterable<DashboardMetric> metrics,
    required Iterable<DashboardSeries> series,
    required Iterable<DashboardBreakdown> rankings,
  }) : metrics = List.unmodifiable(metrics),
       series = List.unmodifiable(series),
       rankings = List.unmodifiable(rankings),
       super('traffic');
  factory DashboardTraffic.fromJson(
    Map<String, dynamic> json,
  ) => DashboardTraffic(
    metrics: _metricsMap(json['kpis']),
    series: jsonObjects(json['pageview_series']).map(DashboardSeries.fromJson),
    rankings: [
      for (final (key, title, property) in [
        ('top_referrers', appL10n.dashboardTopReferrers, 'normalized_referrer'),
        ('top_entry_urls', appL10n.dashboardTopEntryUrls, 'entry_url'),
        ('top_countries', appL10n.dashboardTopCountries, 'country_code'),
      ])
        if (json[key] is Map)
          DashboardBreakdown(title, [
            for (final row in jsonObjects(jsonObject(json[key])['rows']))
              DashboardBreakdownRow(
                label: jsonString(row[property]),
                count: dashboardNumber(row['count']),
                share: dashboardNumber(row['percent']),
                link:
                    key == 'top_entry_urls' &&
                        jsonText(row['entry_url']) != null
                    ? DashboardLink.server(jsonString(row['entry_url']))
                    : null,
              ),
          ], error: jsonObject(json[key])['error'] != null),
    ],
  );
  final List<DashboardMetric> metrics;
  final List<DashboardSeries> series;
  final List<DashboardBreakdown> rankings;
}

final class DashboardEngagement extends DashboardSection {
  DashboardEngagement({
    required Iterable<DashboardMetric> metrics,
    required Iterable<DashboardBreakdown> breakdowns,
  }) : metrics = List.unmodifiable(metrics),
       breakdowns = List.unmodifiable(breakdowns),
       super('engagement');
  factory DashboardEngagement.fromJson(Map<String, dynamic> json) =>
      DashboardEngagement(
        metrics: _metricsList(json['kpis']),
        breakdowns: [
          if (json['trust_level_pipeline'] is Map)
            DashboardBreakdown(appL10n.dashboardTrustPipeline, [
              for (final row in jsonObjects(
                jsonObject(json['trust_level_pipeline'])['rows'],
              ))
                DashboardBreakdownRow(
                  label: jsonString(row['name']),
                  count: dashboardNumber(row['count']),
                  share: dashboardNumber(row['share']),
                  promoted: jsonIntOrNull(row['promoted_in']),
                  demoted: jsonIntOrNull(row['demoted_in']),
                ),
            ]),
          if (json['posters'] is Map)
            DashboardBreakdown(appL10n.dashboardWhosPosting, [
              for (final row in jsonObjects(
                jsonObject(json['posters'])['rows'],
              ))
                DashboardBreakdownRow(
                  label: jsonString(row['name']),
                  count: dashboardNumber(row['count']),
                  share: dashboardNumber(row['share']),
                ),
            ]),
          if (json['activity_by_category'] is Map)
            DashboardBreakdown(appL10n.dashboardCategoryActivity, [
              for (final row in jsonObjects(
                jsonObject(json['activity_by_category'])['rows'],
              ))
                DashboardBreakdownRow(
                  label: jsonString(row['name']),
                  topics: dashboardNumber(row['topics']),
                  posts: dashboardNumber(row['posts']),
                  views: dashboardNumber(row['page_views']),
                  share: dashboardNumber(row['share']),
                  change: dashboardNumber(row['share_change']),
                  link: jsonIntOrNull(row['category_id']) == null
                      ? null
                      : DashboardLink.app('/c/${jsonInt(row['category_id'])}'),
                ),
            ]),
        ],
      );
  final List<DashboardMetric> metrics;
  final List<DashboardBreakdown> breakdowns;
}

final class DashboardSearch extends DashboardSection {
  DashboardSearch({
    required this.loggingEnabled,
    required Iterable<DashboardMetric> metrics,
    required Iterable<DashboardBreakdown> breakdowns,
  }) : metrics = List.unmodifiable(metrics),
       breakdowns = List.unmodifiable(breakdowns),
       super('search');
  factory DashboardSearch.fromJson(Map<String, dynamic> json) =>
      DashboardSearch(
        loggingEnabled: json['logging_enabled'] == true,
        metrics: _metricsMap(json['kpis']),
        breakdowns: [
          for (final (key, title) in [
            ('trending', appL10n.dashboardTrendingSearches),
            ('content_gaps', appL10n.dashboardContentGaps),
          ])
            DashboardBreakdown(title, [
              for (final row in jsonObjects(json[key]))
                DashboardBreakdownRow(
                  label: jsonString(row['term']),
                  count: dashboardNumber(row['searches']),
                  status: jsonText(row['status']),
                  link: DashboardLink.app(
                    Uri(
                      path: '/search',
                      queryParameters: {'q': jsonString(row['term'])},
                    ).toString(),
                  ),
                ),
            ]),
        ],
      );
  final bool loggingEnabled;
  final List<DashboardMetric> metrics;
  final List<DashboardBreakdown> breakdowns;
}

@immutable
final class DashboardStorage {
  const DashboardStorage(
    this.name,
    this.used,
    this.free,
    this.remote,
    this.count,
  );
  factory DashboardStorage.fromJson(String name, Map<String, dynamic> json) =>
      DashboardStorage(
        name,
        dashboardNumber(json['used_bytes']),
        dashboardNumber(json['free_bytes']),
        json['remote'] == true,
        jsonIntOrNull(json['count']),
      );
  final String name;
  final num? used;
  final num? free;
  final bool remote;
  final int? count;
}

final class DashboardSystem extends DashboardSection {
  DashboardSystem({
    required this.version,
    required this.latestVersion,
    required this.commits,
    required this.checkFailed,
    required Iterable<DashboardStorage> storage,
    this.discourseUpdatedAt,
    this.dashboardUpdatedAt,
  }) : storage = List.unmodifiable(storage),
       super('system');
  factory DashboardSystem.fromJson(Map<String, dynamic> json) {
    final version = jsonObject(json['version']);
    return DashboardSystem(
      version:
          jsonText(version['installed_version']) ??
          jsonText(version['installed_describe']),
      latestVersion: jsonText(version['latest_version']),
      commits: jsonText(version['installed_sha']),
      checkFailed:
          version['updated_at'] == null || version['stale_data'] == true,
      storage: [
        for (final entry in jsonObject(json['storage']).entries)
          if (entry.value is Map)
            DashboardStorage.fromJson(entry.key, jsonObject(entry.value)),
      ],
      discourseUpdatedAt: jsonDate(json['discourse_updated_at']),
      dashboardUpdatedAt: jsonDate(json['dashboard_updated_at']),
    );
  }
  final String? version;
  final String? latestVersion;
  final String? commits;
  final bool checkFailed;
  final List<DashboardStorage> storage;
  final DateTime? discourseUpdatedAt;
  final DateTime? dashboardUpdatedAt;
}

@immutable
final class DashboardProblem {
  const DashboardProblem(this.id, this.message, this.priority);
  factory DashboardProblem.fromJson(Map<String, dynamic> json) =>
      DashboardProblem(
        jsonInt(json['id']),
        jsonHtmlText(json['message']) ?? '',
        jsonString(json['priority']),
      );
  final int id;
  final String message;
  final String priority;
}

@immutable
final class DashboardConfiguration {
  const DashboardConfiguration(this.id, this.visible);
  factory DashboardConfiguration.fromJson(Map<String, dynamic> json) =>
      DashboardConfiguration(jsonString(json['id']), json['visible'] == true);
  final String id;
  final bool visible;
  Map<String, Object?> toJson() => {'id': id, 'visible': visible};
}

@immutable
final class DashboardSnapshot {
  DashboardSnapshot({
    required this.supported,
    Iterable<DashboardSection> sections = const [],
    Iterable<DashboardProblem> problems = const [],
    Iterable<DashboardConfiguration>? configuration,
  }) : sections = List.unmodifiable(sections),
       problems = List.unmodifiable(problems),
       configuration = configuration == null
           ? null
           : List.unmodifiable(configuration);
  factory DashboardSnapshot.fromJson(Map<String, dynamic> json) =>
      DashboardSnapshot(
        supported: json['sections'] is List,
        sections: jsonObjects(json['sections']).map(DashboardSection.fromJson),
        problems: jsonObjects(json['problems']).map(DashboardProblem.fromJson),
        configuration: jsonObject(json['configuration'])['sections'] is List
            ? jsonObjects(
                jsonObject(json['configuration'])['sections'],
              ).map(DashboardConfiguration.fromJson)
            : null,
      );
  final bool supported;
  final List<DashboardSection> sections;
  final List<DashboardProblem> problems;
  final List<DashboardConfiguration>? configuration;
  DashboardSnapshot withProblems(Iterable<DashboardProblem> value) =>
      DashboardSnapshot(
        supported: supported,
        sections: sections,
        problems: value,
        configuration: configuration,
      );
}
