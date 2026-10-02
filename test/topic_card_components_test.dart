import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'poster ring preserves 20px images and 7px overlap in both directions',
    (tester) async {
      final semantics = tester.ensureSemantics();

      for (final direction in TextDirection.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Directionality(
              textDirection: direction,
              child: const Center(
                child: DAvatarGroup(
                  overlap: 7,
                  ringWidth: 1.5,
                  children: [
                    DAvatar(
                      dimension: 20,
                      border: false,
                      semanticLabel: 'Sam',
                      fallback: DAvatarFallback(child: Text('S')),
                    ),
                    DAvatar(
                      dimension: 20,
                      border: false,
                      ring: true,
                      ringStyle: DAvatarRingStyle.outside,
                      semanticLabel: 'Alex',
                      ringSemanticLabel: 'Most recent poster',
                      fallback: DAvatarFallback(child: Text('A')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(tester.getSize(find.byType(DAvatarGroup)), const Size(33, 20));
        expect(
          tester.getSize(find.byType(DAvatarFallback).last),
          const Size.square(20),
        );
        final first = tester.getRect(find.byType(DAvatar).first);
        final last = tester.getRect(find.byType(DAvatar).last);
        expect((first.left - last.left).abs(), 13);
        expect(
          direction == TextDirection.ltr
              ? first.left < last.left
              : first.left > last.left,
          isTrue,
        );
        expect(
          find.bySemanticsLabel('Alex, Most recent poster'),
          findsOneWidget,
        );
      }
      semantics.dispose();
    },
  );

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.macOS,
  ]) {
    testWidgets('inline metadata has exactly its visible target on $platform', (
      tester,
    ) async {
      var taps = 0;
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: platform),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Center(
                child: DButton(
                  variant: DButtonVariant.inline,
                  density: DButtonDensity.inlineMetadata,
                  label: const Text('+3'),
                  onPressed: () => taps++,
                ),
              ),
            ),
          ),
        );
        final bounds = tester.getRect(find.byType(DButton));
        expect(bounds.size, tester.getSize(find.text('+3')));
        expect(bounds.height, 18 * scale);
        final before = taps;
        await tester.tapAt(bounds.centerLeft - const Offset(1, 0));
        expect(taps, before);
        await tester.tap(find.byType(DButton));
        expect(taps, before + 1);
      }
    });
  }
}
