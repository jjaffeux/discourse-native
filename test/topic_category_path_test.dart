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
  const grandchild = TopicCategory(
    id: 7,
    name: 'Mobile',
    color: '663399',
    parentCategoryId: 6,
  );

  test('a top-level category path is its name', () {
    expect(topicCategoryPathLabel(parent), 'Support');
  });

  test('a subcategory path uses the refined visual separator', () {
    expect(topicCategoryPathLabel(child, parent: parent), 'Support › Bugs');
  });

  test('resolves the full path through a subcategory of a subcategory', () {
    final categories = {5: parent, 6: child, 7: grandchild};
    expect(topicCategoryPath(grandchild, categoryFor: (id) => categories[id]), [
      parent,
      child,
      grandchild,
    ]);
    expect(
      topicCategoryPathLabel(grandchild, categoryFor: (id) => categories[id]),
      'Support › Bugs › Mobile',
    );
  });

  test('keeps the available path when an ancestor is missing', () {
    expect(
      topicCategoryPath(
        grandchild,
        categoryFor: (id) => id == 6 ? child : null,
      ),
      [child, grandchild],
    );
  });

  test('terminates without repeating a category when parent data cycles', () {
    const first = TopicCategory(
      id: 1,
      name: 'First',
      color: '663399',
      parentCategoryId: 2,
    );
    const second = TopicCategory(
      id: 2,
      name: 'Second',
      color: '663399',
      parentCategoryId: 1,
    );
    expect(
      topicCategoryPath(first, categoryFor: (id) => id == 1 ? first : second),
      [second, first],
    );
  });
}
