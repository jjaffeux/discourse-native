import 'package:discourse_native/src/plugins/local_dates/local_date_composer_editor.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_sheet.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    LocalDateEnvironment.instance.ensureDatabase();
    LocalDateEnvironment.instance.setDeviceTimezone('Etc/UTC');
  });

  Future<void> removeSheetWhilePickerIsOpen(
    WidgetTester tester, {
    required String pickerTooltip,
  }) async {
    final hostKey = GlobalKey<_PickerHostState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: _PickerHost(key: hostKey),
      ),
    );

    await tester.tap(find.byTooltip(pickerTooltip));
    await tester.pumpAndSettle();
    expect(find.text('OK'), findsOneWidget);

    hostKey.currentState!.removeSheet();
    await tester.pump();
    expect(find.byType(LocalDateComposerSheet), findsNothing);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('date picker completion ignores a disposed sheet', (
    tester,
  ) async {
    await removeSheetWhilePickerIsOpen(
      tester,
      pickerTooltip: 'Choose Start date',
    );
  });

  testWidgets('time picker completion ignores a disposed sheet', (
    tester,
  ) async {
    await removeSheetWhilePickerIsOpen(
      tester,
      pickerTooltip: 'Choose Start time',
    );
  });

  testWidgets('invalid date is announced from the keyboard action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: SingleChildScrollView(
              child: LocalDateComposerSheet(
                draft: LocalDateComposerDraft.newDate(
                  now: DateTime(2026, 8, 12),
                  timezone: 'Etc/UTC',
                  environment: LocalDateEnvironment.instance,
                ),
                siteFormats: const [],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final startDate = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Start date',
        description: 'Start date field',
      );
      await tester.enterText(startDate, 'not-a-date');

      final apply = find.widgetWithText(FilledButton, 'Apply');
      await tester.ensureVisible(apply);
      await tester.pumpAndSettle();
      expect(tester.getSize(apply).height, greaterThanOrEqualTo(44));

      final focus = _focusButton(tester, apply);
      await tester.pumpAndSettle();
      expect(focus.hasPrimaryFocus, isTrue);
      expect(
        tester.getSemantics(apply),
        isSemantics(
          label: 'Apply',
          isButton: true,
          isFocusable: true,
          isFocused: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final error = find.byKey(const ValueKey('local-date-sheet-error'));
      expect(error, findsOneWidget);
      expect(
        tester.getSemantics(error),
        isSemantics(label: 'Choose a valid start date.', isLiveRegion: true),
      );
      expect(find.byType(LocalDateComposerSheet), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
}

FocusNode _focusButton(WidgetTester tester, Finder button) {
  final inkWell = find.descendant(of: button, matching: find.byType(InkWell));
  expect(inkWell, findsOneWidget);
  final focusChild = find
      .descendant(of: inkWell, matching: find.byType(MouseRegion))
      .first;
  final focus = Focus.of(tester.element(focusChild));
  focus.requestFocus();
  return focus;
}

class _PickerHost extends StatefulWidget {
  const _PickerHost({super.key});

  @override
  State<_PickerHost> createState() => _PickerHostState();
}

class _PickerHostState extends State<_PickerHost> {
  bool _showSheet = true;

  void removeSheet() => setState(() => _showSheet = false);

  @override
  Widget build(BuildContext context) => Scaffold(
    body: _showSheet
        ? SingleChildScrollView(
            child: LocalDateComposerSheet(
              draft: LocalDateComposerDraft.newDate(
                now: DateTime(2026, 8, 12),
                timezone: 'Etc/UTC',
                environment: LocalDateEnvironment.instance,
              ).copyWith(startTime: '09:00:00'),
              siteFormats: const [],
            ),
          )
        : const SizedBox.shrink(),
  );
}
