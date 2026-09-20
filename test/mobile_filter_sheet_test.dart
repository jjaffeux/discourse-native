import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.macOS,
  ]) {
    testWidgets('adaptive dropdown selection and dismissal on $platform', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = DDropdownMenuController();
      addTearDown(controller.dispose);
      var selections = 0;
      final completed = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
            body: Center(
              child: DDropdownMenu(
                controller: controller,
                sheetOnMobile: true,
                onOpenChangeComplete: completed.add,
                content: DDropdownMenuContent(
                  semanticLabel: 'Feeds',
                  children: [
                    DDropdownMenuItem(
                      onPressed: () => selections++,
                      child: const Text('Latest'),
                    ),
                  ],
                ),
                child: DDropdownMenuTrigger.button(label: const Text('Choose')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      expect(
        find.byType(DSheetContent),
        platform == TargetPlatform.macOS ? findsNothing : findsOneWidget,
      );
      if (platform != TargetPlatform.macOS) {
        expect(tester.getRect(find.byType(DSheetContent)).bottom, 844);
        expect(tester.getSize(find.byType(DSheetContent)).width, 390);
      }
      await tester.tap(find.text('Latest'));
      await tester.pumpAndSettle();
      expect(selections, 1);
      expect(completed, [true, false]);
      expect(controller.isOpen, isFalse);
      expect(find.text('Latest'), findsNothing);
      controller.open();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(controller.isOpen, isFalse);
      controller.open();
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(controller.isOpen, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'mobile searchable sheet retains query, multi-selection and keyboard bounds',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = DComboboxController<String>();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: DCombobox<String>.multiple(
              closeOnSelect: false,
              controller: controller,
              options: const [
                DComboboxOption(value: 'one', label: 'One'),
                DComboboxOption(value: 'two', label: 'Two'),
              ],
              anchor: DComboboxTrigger<String>(
                builder: (_, state) => DButton(
                  onPressed: state.toggle,
                  focusNode: state.focusNode,
                  label: const Text('Tags'),
                ),
              ),
              content: const DComboboxContent(
                sheetOnMobile: true,
                semanticLabel: 'Choose tags',
                children: [
                  DComboboxInput<String>(
                    registerAsAnchor: false,
                    showTrigger: false,
                  ),
                  DComboboxList<String>(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Tags'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('One'));
      await tester.pumpAndSettle();
      expect(controller.isOpen, isTrue);
      await tester.enterText(find.byType(EditableText), 'Tw');
      await tester.pumpAndSettle();
      expect(find.text('One'), findsNothing);
      expect(find.text('Two'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Two')).bottom, lessThanOrEqualTo(420));
      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();
      expect(controller.isOpen, isTrue);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(controller.isOpen, isFalse);
      expect(tester.takeException(), isNull);
      controller.open();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
