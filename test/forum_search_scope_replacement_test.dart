import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/global_search_fixtures.dart';

void main() {
  for (final closing in [false, true]) {
    testWidgets(
      'scope replacement synchronizes a different query while mobile search '
      'is ${closing ? 'closing' : 'open'}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final original = createGlobalSearchFixtureController();
        final replacement = createGlobalSearchFixtureController();
        addTearDown(original.dispose);
        addTearDown(replacement.dispose);
        await original.load();
        await replacement.load();
        final selected = ValueNotifier(original);
        addTearDown(selected.dispose);

        await tester.pumpWidget(
          ValueListenableBuilder<ShellController>(
            valueListenable: selected,
            builder: (_, shell, _) => ShellScope(
              controller: shell,
              child: MaterialApp(
                theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
                home: const Scaffold(
                  body: ForumSearch(
                    fullScreen: true,
                    showNavigationControls: false,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final state = tester.state(find.byType(ForumSearch));
        await tester.tap(find.byKey(const ValueKey('mobile-search-button')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(ForumSearch.inputKey), 'design');
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pumpAndSettle();
        expect(original.globalSearch.query, 'design');
        expect(replacement.globalSearch.query, isEmpty);
        if (closing) {
          await tester.tap(find.byKey(const ValueKey('mobile-search-back')));
          await tester.pump();
        }
        expect(find.byKey(ForumSearch.panelKey), findsOneWidget);

        selected.value = replacement;
        await tester.pump();
        expect(
          tester.state(find.byType(ForumSearch, skipOffstage: false)),
          same(state),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        if (closing) {
          await tester.tap(find.byKey(const ValueKey('mobile-search-button')));
          await tester.pumpAndSettle();
        }
        final editor = find.descendant(
          of: find.byKey(ForumSearch.inputKey),
          matching: find.byType(EditableText),
        );
        expect(tester.widget<EditableText>(editor).controller.text, isEmpty);

        await tester.enterText(find.byKey(ForumSearch.inputKey), 'keyboard');
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pumpAndSettle();
        expect(replacement.globalSearch.query, 'keyboard');
        expect(original.globalSearch.query, 'design');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
