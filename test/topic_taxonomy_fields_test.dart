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

  testWidgets('topic tags render as compact interactive tokens', (
    tester,
  ) async {
    const tags = [
      TopicTag(name: 'sea2'),
      TopicTag(name: 'blz-prod-eu'),
      TopicTag(name: 'cdck-prod-meta'),
      TopicTag(name: 'dev-alert'),
    ];
    TopicTag? selected;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 220,
              child: TopicTagsValue(
                tags: tags,
                onTagNavigate: (tag) => selected = tag,
                tagKey: (tag) => ValueKey(tag.name),
              ),
            ),
          ),
        ),
      ),
    );

    final wrap = tester.widget<Wrap>(find.byType(Wrap));
    expect(wrap.spacing, 4);
    expect(wrap.runSpacing, 4);

    final firstToken = find.byKey(const ValueKey('sea2'));
    final material = tester.widget<Material>(firstToken);
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(5));
    expect(
      material.color,
      AppTheme.dark.colorScheme.surfaceContainerHigh.withValues(alpha: 0.72),
    );
    expect(
      find.descendant(
        of: firstToken,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Padding &&
              widget.padding ==
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        ),
      ),
      findsOneWidget,
    );

    for (final tag in tags) {
      expect(find.text(tag.name), findsOneWidget);
      expect(
        tester.getSize(find.bySemanticsLabel('Tag: ${tag.name}')).height,
        24,
      );
    }

    await tester.tap(find.bySemanticsLabel('Tag: ${tags.last.name}'));
    expect(selected, tags.last);
  });
}
