import 'package:discourse_native/discourse_ui.dart';
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
  testWidgets(
    'search hints use keycaps, stay outside input state and fit scaled narrow layouts',
    (tester) async {
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
      for (final width in [220.0, 360.0, 600.0]) {
        await tester.pumpWidget(
          ShellScope(
            controller: controller,
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: MediaQuery(
                  data: const MediaQueryData(
                    size: Size(800, 600),
                    textScaler: TextScaler.linear(2),
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(width: width, child: const ForumSearch()),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final hint = find.byType(DShortcutKeycaps);
        if (width >= 560) {
          expect(hint, findsOneWidget);
          final caps = tester.widget<DShortcutKeycaps>(hint);
          expect(caps.shortcut[0].trigger, LogicalKeyboardKey.keyF);
          expect(caps.shortcut[0].control, isTrue);
          expect(caps.listenToKeyboard, isFalse);
        } else {
          expect(hint, findsNothing);
        }
        expect(
          tester.takeException(),
          isNull,
          reason: 'At width $width and 200% text',
        );
      }
      await tester.enterText(find.byKey(ForumSearch.inputKey), 'community');
      await tester.pump();
      expect(controller.globalSearch.query, 'community');
      expect(find.byType(DShortcutKeycaps), findsNothing);
      await tester.tap(find.byKey(const ValueKey('forum-search-clear')));
      await tester.pump();
      expect(controller.globalSearch.query, isEmpty);
      expect(find.byType(DShortcutKeycaps), findsOneWidget);
      expect(
        tester.widget<EditableText>(_editableInput()).focusNode.hasFocus,
        isTrue,
      );
    },
  );

  testWidgets(
    'clear search uses kit geometry with padding and independent keyboard semantics',
    (tester) async {
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
        expect(
          tester.widget<DInputGroupButton>(clear).size,
          DControlSize.extraSmall,
        );
        expect(tester.getSize(clear), const Size.square(24));
        expect(tester.getSize(find.byType(ForumSearch)).height, 32);
        final groupRect = tester.getRect(find.byType(DInputGroup));
        final clearRect = tester.getRect(clear);
        expect(clearRect.right, lessThan(groupRect.right));
        expect(clearRect.top - groupRect.top, closeTo(4, .5));
        expect(groupRect.bottom - clearRect.bottom, closeTo(4, .5));
        expect(
          tester.getSemantics(clear),
          isSemantics(
            label: 'Clear search',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );

        final input = tester.widget<EditableText>(_editableInput()).focusNode;
        expect(input.hasFocus, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(clear),
          isSemantics(isFocusable: true, isFocused: true),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(controller.globalSearch.query, isEmpty);
        expect(
          tester.widget<EditableText>(_editableInput()).controller.text,
          isEmpty,
        );
      } finally {
        semantics.dispose();
      }
    },
  );
}

Finder _editableInput() => find.descendant(
  of: find.byKey(ForumSearch.inputKey),
  matching: find.byType(EditableText),
);
