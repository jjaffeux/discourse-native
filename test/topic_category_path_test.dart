import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_category_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parent = TopicCategory(id: 5, name: 'Support', color: '0088CC');
  const child = TopicCategory(
    id: 6,
    name: 'Bugs',
    color: 'FF6600',
    parentCategoryId: 5,
  );

  test('a top-level category path is its name', () {
    expect(topicCategoryPathLabel(parent), 'Support');
  });

  test('a subcategory path uses the refined visual separator', () {
    expect(topicCategoryPathLabel(child, parent: parent), 'Support › Bugs');
  });
}
