import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_category_path.dart';
import 'package:discourse_native/src/shell/topic_taxonomy_fields.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('editable category row aligns its label, value, and controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              height: 48,
              child: TopicPropertyRow(
                label: 'Category',
                alignLabelToControl: true,
                child: TopicCategoryValue(
                  label: 'Uncategorized',
                  color: const Color(0xFF888888),
                  valueKey: const ValueKey('category-value'),
                  colorKey: const ValueKey('category-color'),
                  editActionKey: const ValueKey('category-edit-action'),
                  editIconKey: const ValueKey('category-edit-icon'),
                  onEdit: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final propertyLabelRect = tester.getRect(find.text('Category'));
    final categoryLabelRect = tester.getRect(find.text('Uncategorized'));
    final categoryValueRect = tester.getRect(
      find.byKey(const ValueKey('category-value')),
    );
    final colorRect = tester.getRect(
      find.byKey(const ValueKey('category-color')),
    );
    final editActionRect = tester.getRect(
      find.byKey(const ValueKey('category-edit-action')),
    );
    final editIconRect = tester.getRect(
      find.byKey(const ValueKey('category-edit-icon')),
    );

    expect(propertyLabelRect.center.dy, categoryLabelRect.center.dy);
    expect(colorRect.top - categoryValueRect.top, 4);
    expect(editActionRect.center.dy, categoryLabelRect.center.dy);
    expect(editIconRect.center.dy, categoryLabelRect.center.dy);
  });

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

  testWidgets('topic tag edit button wraps with the final tag', (tester) async {
    const tags = [
      TopicTag(name: 'data-explorer'),
      TopicTag(name: 'workflows'),
      TopicTag(name: 'ask'),
    ];

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
                onEdit: () {},
                tagKey: (tag) => ValueKey(tag.name),
                addKey: const ValueKey('edit-tags'),
              ),
            ),
          ),
        ),
      ),
    );

    final firstTag = tester.getRect(
      find.byKey(const ValueKey('data-explorer')),
    );
    final finalTag = tester.getRect(find.byKey(const ValueKey('ask')));
    final editButton = tester.getRect(find.byKey(const ValueKey('edit-tags')));

    expect(finalTag.center.dy, editButton.center.dy);
    expect(finalTag.top, greaterThan(firstTag.top));
    expect(tester.takeException(), isNull);
  });
}
