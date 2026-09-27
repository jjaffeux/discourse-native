import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'outlined pills transfer their accent on selection, dark $dark',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
              platform: TargetPlatform.iOS,
            ),
            home: const Scaffold(
              body: DTabs<String>(
                initialValue: 'all',
                children: [
                  DTabList<String>(
                    variant: DTabListVariant.outlinePill,
                    size: DControlSize.small,
                    children: [
                      DTabTrigger(value: 'all', child: Text('Notifications')),
                      DTabTrigger(value: 'replies', child: Text('Replies')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final tabs = find.byType(DTabTrigger<String>);
        final tokens = DTokens.of(tester.element(tabs.first));
        BoxDecoration decoration(int index) =>
            tester
                    .widget<AnimatedContainer>(
                      find.descendant(
                        of: tabs.at(index),
                        matching: find.byType(AnimatedContainer),
                      ),
                    )
                    .decoration!
                as BoxDecoration;
        expect(decoration(0).color, tokens.buttonTheme.primary.background);
        expect(decoration(1).color, Colors.transparent);
        expect(
          (decoration(1).border! as Border).top.color,
          tokens.buttonTheme.outline.border,
        );
        for (var i = 0; i < 2; i++) {
          expect(
            decoration(i).borderRadius,
            BorderRadius.circular(DRadius.pill),
          );
          expect(decoration(i).boxShadow, isNull);
          expect(tester.getSize(tabs.at(i)).height, 40);
        }
        await tester.tap(find.text('Replies'));
        await tester.pump();
        expect(decoration(0).color, Colors.transparent);
        expect(decoration(1).color, tokens.buttonTheme.primary.background);
        expect(
          (decoration(0).border! as Border).top.color,
          tokens.buttonTheme.outline.border,
        );
        expect((decoration(1).border! as Border).top.color, Colors.transparent);
      },
    );
  }
}
