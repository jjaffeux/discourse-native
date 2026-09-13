import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/list_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('search preserves scope and filters, resets pagination and clears', () {
    final source = ContentRoute.list(
      ListLink.parse('/c/design/42?status=open&assigned=nobody&page=3')!,
    );
    final searched = source.withTopicListSearch('  café & layouts  ');
    expect(searched.categoryId, 42);
    expect(searched.topicListSearch, 'café & layouts');
    expect(Uri.parse(searched.feedPath!).queryParameters, {
      'status': 'open',
      'assigned': 'nobody',
      'search': 'café & layouts',
    });
    final tagged = ContentRoute.filteredTopicList(
      TopicListMode.unread,
      categoryId: 42,
      tags: const ['design', 'mobile'],
    ).withTopicListQueryFrom(searched);
    expect(tagged.topicListSearch, searched.topicListSearch);
    expect(tagged.tagNames, ['design', 'mobile']);
    expect(TopicListMode.fromRoute(tagged), TopicListMode.unread);
    expect(ContentRoute.fromJson(tagged.toJson()).topicListSearch, isEmpty);
    expect(tagged.withTopicListSearch('').tagNames, tagged.tagNames);
    expect(tagged.withTopicListSearch('').topicListSearch, isEmpty);
    final latest = ContentRoute.topicList(TopicListMode.latest);
    expect(
      latest.withTopicListSearch('hello').withTopicListSearch('').feedPath,
      '/latest.json',
    );
    expect(
      latest
          .withTopicListSearch('hello')
          .withTopicListSearch('')
          .topicListSearch,
      isEmpty,
    );
    expect(
      latest.withTopicListSearch('one').id,
      isNot(latest.withTopicListSearch('two').id),
    );
  });
}
