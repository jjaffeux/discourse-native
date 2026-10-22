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
  void expectScope(
    String input, {
    int? categoryId,
    List<String> tags = const [],
    String query = '',
  }) {
    final scope = parseTopicFilterScope(input, categories);
    expect(scope.categoryId, categoryId, reason: input);
    expect(scope.tags, tags, reason: input);
    expect(scope.query, query, reason: input);
  }

  test('category and a quoted tag round-trip beside server clauses', () {
    expectScope(
      'category:product:design tag:"customer feedback" status:open',
      categoryId: 2,
      tags: ['customer feedback'],
      query: 'status:open',
    );
    expectScope('');
  });

  test('the last category and singular tag replace the previous scope', () {
    expectScope(
      'category:1 tag:old category:2 tag:new',
      categoryId: 2,
      tags: ['new'],
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

  test('singular tag precedes ordered conjunctions without normalization', () {
    expectScope(
      'tags:b+a tag:old tag:new tag:" a + b " tag:new+new status:open',
      tags: ['new', 'b', 'a', ' a ', ' b ', 'new', 'new'],
      query: 'status:open',
    );
    expectScope(
      'tag:"customer feedback+123+中文+café"',
      tags: ['customer feedback', '123', '中文', 'café'],
    );
  });

  test('unknown and negative clauses and disjunctions stay server filters', () {
    const query =
        '-category:1 category:missing -tag:a+b tag:a,b '
        'tags:one TAG:a+b future:"Keep  spacing"';
    expectScope(query, query: query);
    expectScope(
      'category:1 category:missing CATEGORY:product:design TAG:中文',
      categoryId: 2,
      tags: ['中文'],
      query: 'category:missing',
    );
  });

  test('malformed clauses retain existing server and extraction behavior', () {
    const query = 'tag:a+ tag:+b tags:a++b tag:"a+ +b" tag:""';
    expectScope(query, query: query);
    expectScope(
      'status:open tag:"unfinished',
      tags: ['"unfinished'],
      query: 'status:open',
    );
    expectScope('tag:"a+\nb"', query: 'tag:"a+\nb"');
    expectScope(
      'tag:"customer feedback"+urgent',
      tags: ['"customer feedback"', 'urgent'],
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
