import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'imperative Popover supplies material for Native editing controls',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => DButton(
                label: const Text('Open search'),
                onPressed: () => showDPopover(
                  context: context,
                  builder: (_) => DPopoverContent(
                    child: DInput(autofocus: true, hintText: 'Search popup'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open search'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.enterText(find.byType(DInput), 'emoji');
      await tester.pump();
      expect(find.text('emoji'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'rectangle Popover stays above and centers after anchor removal',
    (tester) async {
      final presence = ValueNotifier(true);
      final popup = DPopoverController();
      addTearDown(presence.dispose);
      addTearDown(popup.dispose);
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Builder(
              builder: (context) => DButton(
                label: const Text('Open anchored picker'),
                onPressed: () => unawaited(
                  showDPopover(
                    context: context,
                    controller: popup,
                    anchorRect: const Rect.fromLTWH(80, 450, 30, 20),
                    anchorMode: DPopoverAnchorMode.rectangle,
                    anchorPresence: presence,
                    transitionDuration: const Duration(milliseconds: 140),
                    builder: (context) => DPopoverContent(
                      key: const ValueKey('anchored-picker'),
                      width: 180,
                      side: DPopoverSide.top,
                      align: DPopoverAlign.start,
                      sideOffset: 8,
                      collisionPadding: 12,
                      centered: !presence.value,
                      motion: DPopoverMotion.picker,
                      padding: EdgeInsets.zero,
                      scrollable: false,
                      child: const SizedBox(height: 100),
                    ),
                  ).then((_) => completed = true),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open anchored picker'));
      await tester.pumpAndSettle();
      final picker = find.byKey(const ValueKey('anchored-picker'));
      expect(tester.getRect(picker), const Rect.fromLTWH(80, 342, 180, 100));
      presence.value = false;
      await tester.pumpAndSettle();
      expect(tester.getSize(picker), const Size(180, 100));
      expect(tester.getCenter(picker), const Offset(400, 300));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(picker, findsNothing);
      expect(completed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'imperative Popover completes when its own Native surface closes',
    (tester) async {
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Builder(
              builder: (context) => DButton(
                onPressed: () => unawaited(
                  showDPopover(
                    context: context,
                    anchorRect: const Rect.fromLTWH(40, 40, 180, 30),
                    builder: (context) => DPopoverContent(
                      width: 180,
                      child: DPopoverClose(
                        builder: (context, close) => DButton(
                          onPressed: close,
                          label: const Text('Close popup'),
                        ),
                      ),
                    ),
                  ).then((_) => completed = true),
                ),
                label: const Text('Open popup'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open popup'));
      await tester.pumpAndSettle();
      expect(find.text('Close popup'), findsOneWidget);
      expect(completed, isFalse);
      await tester.tap(find.text('Close popup'));
      await tester.pumpAndSettle();
      expect(find.text('Close popup'), findsNothing);
      expect(completed, isTrue);
      expect(find.text('Open popup'), findsOneWidget);
    },
  );

  testWidgets(
    'closing a covered Popover preserves a route opened by its action',
    (tester) async {
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Builder(
              builder: (context) => DButton(
                onPressed: () => unawaited(
                  showDPopover(
                    context: context,
                    builder: (context) => DPopoverContent(
                      child: DPopoverClose(
                        builder: (context, close) => DButton(
                          onPressed: () {
                            unawaited(
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (context) =>
                                      const Scaffold(body: Text('Destination')),
                                ),
                              ),
                            );
                            close();
                          },
                          label: const Text('Open destination'),
                        ),
                      ),
                    ),
                  ).then((_) => completed = true),
                ),
                label: const Text('Open popup'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open popup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open destination'));
      await tester.pumpAndSettle();
      expect(find.text('Destination'), findsOneWidget);
      expect(find.text('Open destination'), findsNothing);
      expect(completed, isTrue);
    },
  );
}
