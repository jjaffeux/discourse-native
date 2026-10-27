import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sheet named [title], apart from any page a phone shows as a sheet.
Finder phoneSheet(String title) => find.byWidgetPredicate(
  (widget) => widget is DSheetContent && widget.semanticLabel == title,
  description: 'DSheetContent($title)',
);

/// A phone's dialog: a sheet up from the foot under [title], put away by its
/// grabber rather than a close button, and no centred dialog.
void expectPhoneSheet(WidgetTester tester, {required String title}) {
  final sheet = phoneSheet(title);
  expect(sheet, findsOneWidget);
  expect(find.byType(DDialogContent), findsNothing);
  expect(find.byType(DAlertDialogContent), findsNothing);
  expect(
    find.descendant(
      of: sheet,
      matching: find.byKey(const ValueKey('sheet-drag-handle')),
    ),
    findsOneWidget,
  );
  expect(find.descendant(of: sheet, matching: find.text(title)), findsWidgets);
  expect(
    find.descendant(of: sheet, matching: find.byTooltip('Close')),
    findsNothing,
  );
}

/// Raises a keyboard [inset] tall and waits for the phone sheet to settle
/// above it.
Future<void> raiseKeyboard(WidgetTester tester, {double inset = 300}) async {
  tester.view.viewInsets = FakeViewPadding(bottom: inset);
  addTearDown(tester.view.resetViewInsets);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}
