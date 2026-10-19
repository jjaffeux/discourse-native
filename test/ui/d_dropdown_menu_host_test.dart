import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('measured menu returns its typed result and removes its host', (
    tester,
  ) async {
    int? result;
    await _open(tester, onResult: (value) => result = value);
    expect(find.text('Choose seven'), findsOneWidget);
    final bounds = tester.getRect(find.byType(DDropdownMenuContent));
    expect(bounds.left, greaterThanOrEqualTo(60));
    await tester.tap(find.text('Choose seven'));
    await tester.pumpAndSettle();
    expect(result, 7);
    expect(find.byType(DDropdownMenuContent), findsNothing);
    expect(find.text('Open menu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final escape in [false, true]) {
    testWidgets(
      'measured menu completes on ${escape ? 'Escape' : 'outside press'}',
      (tester) async {
        var completed = false;
        await _open(
          tester,
          onResult: (value) {
            expect(value, isNull);
            completed = true;
          },
        );
        if (escape) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        } else {
          await tester.tapAt(const Offset(700, 500));
        }
        await tester.pumpAndSettle();
        expect(completed, isTrue);
        expect(find.byType(DDropdownMenuContent), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('typed menu closure preserves a route opened above it', (
    tester,
  ) async {
    int? result;
    await _open(tester, onResult: (value) => result = value, navigate: true);
    await tester.tap(find.text('Choose seven'));
    await tester.pumpAndSettle();
    expect(result, 7);
    expect(find.text('Destination'), findsOneWidget);
    expect(find.byType(DDropdownMenuContent), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _open(
  WidgetTester tester, {
  required ValueChanged<int?> onResult,
  bool navigate = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.macOS),
      home: Scaffold(
        body: Builder(
          builder: (context) => DButton(
            label: const Text('Open menu'),
            onPressed: () async {
              onResult(
                await showDDropdownMenu<int>(
                  context: context,
                  anchorRect: const Rect.fromLTWH(60, 60, 120, 30),
                  builder: (context) => DDropdownMenuContent(
                    children: [
                      DDropdownMenuItem(
                        child: const Text('Choose seven'),
                        onPressed: () {
                          if (navigate) {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    const Scaffold(body: Text('Destination')),
                              ),
                            );
                          }
                          DDialogClose.close<int>(context, 7);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open menu'));
  await tester.pumpAndSettle();
}
