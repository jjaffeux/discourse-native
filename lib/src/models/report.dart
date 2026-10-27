import 'dashboard.dart';
import 'json.dart';

final class ReportFilter {
  ReportFilter(Map<String, dynamic> json, Map<String, dynamic> site)
    : id = jsonString(json['id']),
      type = jsonString(json['type']),
      value = json['default'],
      disabled = json['disabled'] == true,
      allowAny = json['auto_insert_none_item'] != false,
      choices = Map.unmodifiable({
        for (final choice in jsonObjects(switch (json['type']) {
          'category' || 'category_list' => site['categories'],
          'group' || 'groups' => site['groups'],
          _ => json['choices'],
        }))
          choice['id'].toString(): jsonString(choice['name']),
      });
  final String id;
  final String type;
  final Object? value;
  final bool disabled;
  final bool allowAny;
  final Map<String, String> choices;
  bool get multiple => type == 'category_list' || type == 'groups';
}

final class ReportDetails {
  ReportDetails({
    required this.result,
    this.title = '',
    this.description = '',
    this.datesFiltering = true,
    this.chart = true,
    this.fillMissingDates = false,
    this.filters = const [],
  });

  factory ReportDetails.fromJson(
    Map<String, dynamic> payload, {
    Map<String, dynamic> site = const {},
  }) {
    final data = jsonObject(payload['data']);
    return ReportDetails(
      result: DashboardReportResult.fromJson(payload),
      title: jsonString(data['title']),
      description: jsonHtmlText(data['description']) ?? '',
      datesFiltering: data['dates_filtering'] != false,
      chart:
          data['modes'] is! List ||
          (data['modes'] as List).any(
            (mode) => const {
              'chart',
              'stacked_chart',
              'stacked_line_chart',
            }.contains(mode),
          ),
      fillMissingDates: true,
      filters: List.unmodifiable([
        for (final filter in jsonObjects(data['available_filters']))
          ReportFilter(filter, site),
      ]),
    );
  }

  final DashboardReportResult result;
  final String title;
  final String description;
  final bool datesFiltering;
  final bool chart;
  final bool fillMissingDates;
  final List<ReportFilter> filters;
}
