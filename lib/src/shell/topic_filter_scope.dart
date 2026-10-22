import '../models/topic.dart';
import 'topic_filter_controller.dart';

export '../models/content_route.dart' show topicFilterScopeValue;

/// Extracts feed scope while leaving other server clauses verbatim.
({int? categoryId, List<String> tags, String query}) parseTopicFilterScope(
  String query,
  List<TopicCategory> categories,
) {
  int? categoryId;
  String? tag;
  final conjunctionTags = <String>[];
  final remainder = <String>[];
  for (final clause in splitTopicFilterQuery(query)) {
    final colon = clause.indexOf(':');
    final key = colon < 0 ? '' : clause.substring(0, colon).toLowerCase();
    final value = _unquoteScopeValue(
      colon < 0 ? '' : clause.substring(colon + 1),
    );
    if (key == 'category') {
      final id = int.tryParse(value);
      final category = categories.where((item) {
        if (item.id == id) return true;
        final path = <String>[];
        final visited = <int>{};
        TopicCategory? current = item;
        while (current != null && visited.add(current.id)) {
          path.insert(0, current.slug);
          final parent = current.parentCategoryId;
          current = categories.where((item) => item.id == parent).firstOrNull;
        }
        return path.join(':').toLowerCase() == value.toLowerCase();
      }).firstOrNull;
      if (category != null) {
        categoryId = category.id;
        continue;
      }
    } else if (key == 'tag' &&
        value.isNotEmpty &&
        !value.contains('+') &&
        !value.contains(',')) {
      tag = value;
      continue;
    }
    final match = RegExp(r'^tags?:(.*)$').firstMatch(clause);
    if (match != null) {
      final value = _unquoteScopeValue(match.group(1)!);
      final conjunction = value.split('+');
      if (!value.contains(',') &&
          conjunction.length > 1 &&
          conjunction.every((tag) => tag.trim().isNotEmpty)) {
        conjunctionTags.addAll(conjunction);
        continue;
      }
    }
    remainder.add(clause);
  }
  return (
    categoryId: categoryId,
    tags: List<String>.unmodifiable([?tag, ...conjunctionTags]),
    query: remainder.join(' '),
  );
}

String _unquoteScopeValue(String value) {
  if (value.length > 1 &&
      (value.startsWith('"') && value.endsWith('"') ||
          value.startsWith("'") && value.endsWith("'"))) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

List<String> replaceTopicFilterScopeTokens(Iterable<String> tokens) {
  final result = <String>[];
  for (final token in tokens) {
    final key = topicFilterClauseKey(token)?.toLowerCase();
    if (key == 'category:' || key == 'tag:') {
      result.removeWhere(
        (item) => topicFilterClauseKey(item)?.toLowerCase() == key,
      );
    }
    result.add(token);
  }
  return result;
}
