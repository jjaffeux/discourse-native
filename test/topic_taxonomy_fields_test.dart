import 'package:discourse_native/src/shell/topic_taxonomy_fields.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a long category path wraps instead of ellipsizing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 180,
              child: TopicCategoryValue(
                label: 'Discourse Native App › Bugs',
                color: const Color(0xFFFF6600),
                onNavigate: () {},
                onEdit: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final label = find.text('Discourse Native App › Bugs');
    expect(label, findsOneWidget);
    expect(tester.widget<Text>(label).maxLines, isNull);
    expect(tester.getSize(label).height, greaterThan(20));
    expect(tester.takeException(), isNull);
  });
}
