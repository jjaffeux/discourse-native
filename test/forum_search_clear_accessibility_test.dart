import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';

void main() {
  testWidgets('clear search is a compact 44-pixel keyboard target', (
    tester,
  ) async {
    final controller = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    controller.search.selectSite(_siteUrl);
    addTearDown(controller.dispose);

    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: const Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: 320, child: ForumSearch()),
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.byKey(ForumSearch.inputKey), 'ab');
      await tester.pumpAndSettle();

      final clear = find.byKey(const ValueKey('forum-search-clear'));
      expect(clear, findsOneWidget);
      expect(tester.getSize(clear), const Size.square(44));
      // The one-pixel field border sits outside the 44px button on each edge.
      expect(tester.getSize(find.byType(ForumSearch)).height, 46);
      expect(
        tester.getSemantics(clear),
        isSemantics(
          tooltip: 'Clear search',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );

      final input = tester
          .widget<EditableText>(find.byKey(ForumSearch.inputKey))
          .focusNode;
      expect(input.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(clear),
        isSemantics(isFocusable: true, isFocused: true),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(controller.search.query, isEmpty);
      expect(
        tester
            .widget<EditableText>(find.byKey(ForumSearch.inputKey))
            .controller
            .text,
        isEmpty,
      );
    } finally {
      semantics.dispose();
    }
  });
}
