import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('expanded tags belong to their page identity', (tester) async {
    final bucket = PageStorageBucket();
    Future<void> show(Object identity) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: PageStorage(
            bucket: bucket,
            child: SizedBox(
              width: 180,
              child: DHeaderTags(
                identity: identity,
                expandSemanticLabel: 'All tags',
                moreKey: const ValueKey('more'),
                tags: [
                  for (var index = 0; index < 10; index++)
                    DHeaderTag(
                      name: 'tag-$index',
                      child: DButton(
                        size: DButtonSize.filter,
                        variant: DButtonVariant.tool,
                        label: Text('# tag-$index'),
                        onPressed: () {},
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final more = find.byKey(const ValueKey('more'));
    await show('first');
    expect(more, findsOneWidget);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(more, findsNothing);
    expect(find.text('# tag-9'), findsOneWidget);
    await show('second');
    expect(more, findsOneWidget);
    expect(find.text('# tag-9'), findsNothing);
    await show('first');
    expect(more, findsNothing);
    expect(find.text('# tag-9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    testWidgets('large tags expand within narrow bounds in $direction', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Directionality(
              textDirection: direction,
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 180,
                    child: DHeaderTags(
                      identity: direction,
                      moreKey: const ValueKey('more'),
                      expandSemanticLabel: 'All tags',
                      tags: [
                        for (final name in ['long-tag-name', 'last-tag'])
                          DHeaderTag(
                            name: name,
                            child: DButton(
                              size: DButtonSize.filter,
                              variant: DButtonVariant.tool,
                              label: Text('# $name'),
                              onPressed: () {},
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final more = find.byKey(const ValueKey('more'));
      expect(find.text('+2'), findsOneWidget);
      expect(tester.getRect(more).left, greaterThanOrEqualTo(0));
      expect(tester.getRect(more).right, lessThanOrEqualTo(180));
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(more, findsNothing);
      for (final name in ['long-tag-name', 'last-tag']) {
        final tag = find.text('# $name');
        expect(tag, findsOneWidget);
        expect(tester.getRect(tag).left, greaterThanOrEqualTo(0));
        expect(tester.getRect(tag).right, lessThanOrEqualTo(180));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
