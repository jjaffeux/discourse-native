import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/add_instance_sheet.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/discover_sites.dart';

void main() {
  Future<void> openAddSite(WidgetTester tester, TargetPlatform platform) async {
    final source = emptyDiscoverSites();
    addTearDown(source.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: platform),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () =>
                  showAddInstanceSheet(context, discoverSites: source),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('uses a dialog on macOS', (tester) async {
    await openAddSite(tester, TargetPlatform.macOS);

    expect(find.byType(DDialogContent), findsOneWidget);
    expect(find.byType(DDialogTitle), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Add a site'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
  });

  testWidgets('uses the Native drawer on Android', (tester) async {
    await openAddSite(tester, TargetPlatform.android);

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(DDrawerContent), findsOneWidget);
    expect(find.text('Add a site'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
  });
}
