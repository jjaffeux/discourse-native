import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/category_icon.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpIcon(WidgetTester tester, TopicCategory category) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Center(
          child: CategoryIcon(category: category, size: 18, squareSize: 12),
        ),
      ),
    );
  }

  testWidgets('uses the configured category icon and color', (tester) async {
    await pumpIcon(
      tester,
      const TopicCategory(
        id: 1,
        name: 'General',
        color: '3498DB',
        styleType: 'icon',
        icon: 'folder-open',
      ),
    );

    final icon = tester.widget<DIcon>(find.byType(DIcon));
    expect(icon.icon, DIcons.folderOpen);
    expect(icon.color, const Color(0xFF3498DB));
    expect(find.byType(CategorySquare), findsNothing);
  });

  testWidgets('falls back safely when the configured icon is unknown', (
    tester,
  ) async {
    await pumpIcon(
      tester,
      const TopicCategory(
        id: 1,
        name: 'General',
        color: '3498DB',
        styleType: 'icon',
        icon: 'not-a-real-icon',
      ),
    );

    expect(tester.widget<DIcon>(find.byType(DIcon)).icon, DIcons.folder);
  });

  testWidgets('keeps square categories as color swatches', (tester) async {
    await pumpIcon(
      tester,
      const TopicCategory(id: 1, name: 'General', color: '3498DB'),
    );

    expect(find.byType(CategorySquare), findsOneWidget);
    expect(find.byType(DIcon), findsNothing);
    final decoration =
        tester
                .widget<Container>(
                  find.descendant(
                    of: find.byType(CategorySquare),
                    matching: find.byType(Container),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(decoration.color, const Color(0xFF3498DB));
  });
}
