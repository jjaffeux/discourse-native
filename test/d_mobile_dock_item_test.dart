import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      final capsule = find.byKey(const ValueKey('mobile-dock-capsule'));
      expect(tester.getSize(item).width, 72);
      expect(tester.getSize(item).height, 46);
      expect(tester.getSize(capsule), const Size(44, 30));
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
          tester.widget<AnimatedContainer>(capsule).decoration as BoxDecoration;
      expect(decoration.color, isNot(Colors.transparent));

      await pump(selected: true, scale: 2);
      await tester.pumpAndSettle();
      expect(tester.getSize(item).height, greaterThan(48));
      expect(tester.takeException(), isNull);
    });
  }
}
