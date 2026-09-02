import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/list_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ContentRoute category identity', () {
    test('reads top-level and nested category feed paths', () {
      expect(ContentRoute.list(ListLink.parse('/c/support/5')!).categoryId, 5);
      expect(
        ContentRoute.list(ListLink.parse('/c/parent/support/12')!).categoryId,
        12,
      );
    });

    test('does not identify tag or ordinary feed routes as categories', () {
      expect(
        ContentRoute.list(ListLink.parse('/tag/support/5')!).categoryId,
        isNull,
      );
      expect(ContentRoute.topicList(TopicListMode.latest).categoryId, isNull);
    });
  });
}
