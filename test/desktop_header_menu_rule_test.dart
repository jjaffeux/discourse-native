import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/desktop_header_menu.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The header menu's head is its title over a line of chips. Hung from the
/// bar as a dropdown, the head ends on a rule. Filling a phone's sheet, the
/// list runs on under the chips with no rule between.
void main() {
  Widget menu() => DesktopHeaderMenu<String>(
    title: 'Notifications',
    action: 'Dismiss all',
    onAction: () {},
    notificationStyle: true,
    filters: const [
      DesktopHeaderMenuFilter('all', 'All'),
      DesktopHeaderMenuFilter('replies', 'Replies'),
    ],
    value: 'all',
    onChanged: (_) {},
    child: const Text('First notification', key: ValueKey('first-row')),
  );

  Finder rule() => find.descendant(
    of: find.byType(DesktopHeaderMenu<String>),
    matching: find.byType(DSeparator),
  );

  testWidgets('a dropdown keeps the rule under its head', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: DesktopHeaderMenu.width, child: menu()),
          ),
        ),
      ),
    );
    expect(rule(), findsOneWidget);
    final line = tester.getRect(rule());
    expect(line.top, greaterThan(tester.getRect(find.text('Replies')).bottom));
    expect(
      line.bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const ValueKey('first-row'))).top,
      ),
    );
    expect(line.width, DesktopHeaderMenu.width);
  });

  testWidgets('a sheet has no rule under its head', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: DButton(
                label: const Text('Open'),
                onPressed: () => showDSheet<void>(
                  context: context,
                  side: DSheetSide.bottom,
                  variant: DSheetVariant.adaptiveMenu,
                  sizeToContent: false,
                  fillAvailableHeight: true,
                  builder: (context, _) => DSheetContent(
                    side: DSheetSide.bottom,
                    variant: DSheetVariant.adaptiveMenu,
                    sizeToContent: false,
                    fillAvailableHeight: true,
                    semanticLabel: 'Notifications',
                    showCloseButton: false,
                    scrollWholeSheet: false,
                    children: [Expanded(child: menu())],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(DSheetContent), findsOneWidget);
    expect(find.text('Replies'), findsOneWidget);
    expect(find.byKey(const ValueKey('first-row')), findsOneWidget);
    expect(rule(), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
