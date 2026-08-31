import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_category_path.dart';
import 'package:discourse_native/src/shell/topic_taxonomy_fields.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a long category path wraps instead of ellipsizing', (
    tester,
  ) async {
    const parent = TopicCategory(
      id: 5,
      name: 'Discourse Native App',
      color: '0088CC',
    );
    const child = TopicCategory(
      id: 6,
      name: 'Bugs',
      color: 'FF6600',
      parentCategoryId: 5,
    );
    final categoryPath = topicCategoryPathLabel(child, parent: parent);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 180,
              child: TopicCategoryValue(
                label: categoryPath,
                color: const Color(0xFFFF6600),
                onNavigate: () {},
                onEdit: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final label = find.text(categoryPath);
    expect(label, findsOneWidget);
    expect(tester.widget<Text>(label).maxLines, isNull);
    expect(tester.getSize(label).height, greaterThan(20));
    expect(tester.takeException(), isNull);
  });
}
