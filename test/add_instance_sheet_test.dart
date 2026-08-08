import 'package:discourse_native/src/shell/add_instance_sheet.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> openAddSite(WidgetTester tester, TargetPlatform platform) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: platform),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showAddInstanceSheet(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('uses a modal on desktop', (tester) async {
    await openAddSite(tester, TargetPlatform.macOS);

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Add a site'), findsOneWidget);
  });

  testWidgets('keeps the bottom sheet on touch platforms', (tester) async {
    await openAddSite(tester, TargetPlatform.android);

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Add a site'), findsOneWidget);
  });
}
