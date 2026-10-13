import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('dock actions and destinations scale together on $platform', (
      tester,
    ) async {
      var presses = 0;
      for (final scale in [1.0, 17 / 14, 2.0, 3.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: platform),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Row(
                  children: [
                    DMobileDockItem(
                      icon: const DIcon(DIcons.comment),
                      label: 'Chat',
                      onPressed: () {},
                    ),
                    DButton.iconOnly(
                      key: const ValueKey('action'),
                      density: DButtonDensity.mobileDockAction,
                      shape: DButtonShape.pill,
                      icon: const DIcon(DIcons.plus),
                      tooltip: 'New chat',
                      onPressed: () => presses++,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final action = find.byKey(const ValueKey('action'));
        final actionIcon = find.descendant(
          of: action,
          matching: find.byType(DIcon),
        );
        final destinationIcon = find.descendant(
          of: find.byType(DMobileDockItem),
          matching: find.byType(DIcon),
        );
        expect(
          tester.getSize(actionIcon).height,
          tester.getSize(destinationIcon).height,
        );
        expect(
          tester.getSize(actionIcon).height,
          scale == 1 ? 20 : greaterThan(20),
        );
        expect(tester.getCenter(actionIcon), tester.getCenter(action));
        final surface = find.descendant(
          of: action,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is AnimatedContainer &&
                widget.decoration is DButtonDecoration,
          ),
        );
        expect(tester.getRect(action), tester.getRect(surface));
        expect(tester.getSize(action).width, tester.getSize(action).height);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(presses, 4);
    });
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets('dock item keeps one target and an inline count on $platform', (
      tester,
    ) async {
      var presses = 0;
      Future<void> pump({bool selected = false, double scale = 1}) =>
          tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light.copyWith(platform: platform),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 72,
                      child: DMobileDockItem(
                        icon: const Icon(Icons.chat_bubble),
                        label: 'Chat',
                        selected: selected,
                        badge: const DBadge.overlay(child: Text('32')),
                        onPressed: () => presses++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

      await pump();
      final item = find.byType(DMobileDockItem);
      final label = find.text('Chat');
      final count = find.text('32');
      final capsule = find.descendant(
        of: item,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is AnimatedContainer &&
              widget.decoration is DButtonDecoration,
        ),
      );
      expect(tester.getSize(item).width, 72);
      expect(tester.getSize(item).height, 50);
      expect(tester.getRect(capsule), tester.getRect(item));
      expect(
        tester.getRect(count).left,
        greaterThan(tester.getRect(label).right),
      );
      expect(
        tester.getRect(count).center.dy,
        closeTo(tester.getRect(label).center.dy, 1),
      );
      await tester.tapAt(tester.getCenter(count));
      await tester.pump();
      expect(presses, 1);

      await pump(selected: true);
      await tester.pumpAndSettle();
      final decoration =
          tester.widget<AnimatedContainer>(capsule).decoration
              as DButtonDecoration;
      expect(decoration.color, isNot(Colors.transparent));

      await pump(selected: true, scale: 2);
      await tester.pumpAndSettle();
      expect(tester.getSize(item).height, greaterThan(48));
      expect(tester.takeException(), isNull);
    });
  }
}
