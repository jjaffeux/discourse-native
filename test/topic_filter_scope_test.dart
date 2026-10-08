import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/topic_filter_controller.dart';
import 'package:discourse_native/src/shell/topic_filter_scope.dart';
import 'package:flutter_test/flutter_test.dart';

const categories = [
  TopicCategory(id: 1, name: 'Product', slug: 'product', color: '563A93'),
  TopicCategory(
    id: 2,
    name: 'Design',
    slug: 'design',
    color: '3188CC',
    parentCategoryId: 1,
  ),
  TopicCategory(id: 3, name: 'Support', slug: 'support', color: '3BBF7B'),
];

void main() {
  test(
    'category and a quoted tag round-trip independently of server clauses',
    () {
      expect(
        parseTopicFilterScope(
          'category:product:design tag:"customer feedback" status:open',
          categories,
        ),
        (categoryId: 2, tag: 'customer feedback', query: 'status:open'),
      );
      expect(parseTopicFilterScope('', categories), (
        categoryId: null,
        tag: null,
        query: '',
      ));
    },
  );

  test('the last category and list tag replace the previous scope', () {
    expect(
      parseTopicFilterScope(
        'category:1 tag:old category:2 tag:new',
        categories,
      ),
      (categoryId: 2, tag: 'new', query: ''),
    );
    expect(
      replaceTopicFilterScopeTokens([
        'category:1',
        'status:open',
        'tag:old',
        'category:2',
        'tag:new',
      ]),
      ['status:open', 'category:2', 'tag:new'],
    );
  });

  test('unknown, negative and multi-value clauses remain server filters', () {
    expect(
      parseTopicFilterScope(
        '-category:1 tag:a+b category:missing status:closed',
        categories,
      ),
      (
        categoryId: null,
        tag: null,
        query: '-category:1 tag:a+b category:missing status:closed',
      ),
    );
  });

  TopicFilterSuggestions engine({int? parent}) => TopicFilterSuggestions(
    options: const [
      TopicFilterOption(name: 'category:', type: 'category', priority: 1),
    ],
    categories: categories,
    categoryLookup: (_) async => const [],
    tags: (_) async => const [],
    tagGroups: (_) async => const [],
    users: (_) async => const [],
    groups: (_) async => const [],
    hierarchicalCategories: true,
    categoryParentId: parent,
  );

  test(
    'category browsing offers one level and an explicit enclosing category',
    () async {
      final roots = await engine().suggestions('category:');
      expect(roots.map((item) => item.category?.id), [1, 3]);
      expect(roots.first.hasChildren, isTrue);
      final children = await engine(parent: 1).suggestions('category:');
      expect(children.map((item) => item.category?.id), [1, 2]);
      expect(children.first.categoryUp, isTrue);
      expect(children.last.categoryUp, isFalse);
    },
  );

  test(
    'case-insensitive keys browse scopes while negative categories keep server syntax',
    () async {
      final roots = await engine().suggestions('CATEGORY:');
      expect(roots.map((item) => item.category?.id), [1, 3]);
      final excluded = await engine().suggestions('-category:');
      expect(excluded.map((item) => item.name), [
        '-category:product',
        '-category:product:design',
        '-category:support',
      ]);
    },
  );

  test('search spans the category tree and carries the parent path', () async {
    final matches = await engine(parent: 3).suggestions('category:design');
    expect(matches.single.category?.id, 2);
    expect(matches.single.description, 'Product › Design');
  });
}
