import 'package:discourse_native/src/shell/theme_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final direction in TextDirection.values) {
    testWidgets(
      'only direction-matched glyphs mirror in ${direction.name} text',
      (tester) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: direction,
            child: const Row(
              children: [
                ThemeIcon(
                  ThemeIcons.darkerSidebar,
                  key: ValueKey('matched'),
                  matchTextDirection: true,
                ),
                ThemeIcon(ThemeIcons.paper, key: ValueKey('fixed')),
              ],
            ),
          ),
        );
        Finder flipIn(String key) => find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Transform),
        );
        expect(
          flipIn('matched'),
          direction == TextDirection.rtl ? findsOneWidget : findsNothing,
        );
        expect(flipIn('fixed'), findsNothing);
      },
    );
  }
}
