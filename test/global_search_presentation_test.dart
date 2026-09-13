import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/plugins/chat/chat_drawer.dart';
import 'package:discourse_native/src/plugins/chat/chat_drawer_preferences_store.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/global_search_models.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/global_search_fixtures.dart';
import 'support/shell_test_harness.dart';

void main() {
  for (final mode in ChatPreferredDisplayMode.values) {
    _testPresentation(
      'chat results from a forum open in the saved ${mode.name} mode',
      (tester) async {
        await const ChatDrawerPreferencesStore().writePreferredDisplayMode(
          mode,
        );
        final shell = await _pumpSearch(tester);
        final chat = shell.pluginSession.require(chatShellService);
        final underlying = shell.currentContent;
        expect(chat.chatActive, isFalse);
        await tester.tap(find.byKey(ForumSearch.inputKey));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('global-search-scope-chat')),
        );
        await tester.enterText(find.byKey(ForumSearch.inputKey), 'design');
        await _finishSearch(tester);
        await tester.tap(
          _panelText('The search design is ready for a keyboard review.'),
        );
        await tester.pumpAndSettle();
        expect(chat.drawerActive, mode == ChatPreferredDisplayMode.drawer);
        expect(chat.currentContent?.id, 'chat-c-2');
        expect(find.byKey(ForumSearch.panelKey), findsNothing);
        expect(
          find.byKey(ChatDrawerOverlay.drawerKey),
          mode == ChatPreferredDisplayMode.drawer
              ? findsOneWidget
              : findsNothing,
        );
        if (mode == ChatPreferredDisplayMode.drawer) {
          expect(shell.currentContent, underlying);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final keyboard in [false, true]) {
    _testPresentation(
      '${keyboard ? 'shortcut' : 'click'} search defaults to the open topic and clears it on a list',
      (tester) async {
        final api = GlobalSearchFixtureApi();
        final shell = await _pumpSearch(tester, api: api);
        shell.pushContent(
          ContentRoute.topic(
            topicId: 1038,
            slug: 'a-calmer-search',
            title: 'A calmer, more useful global search',
          ),
        );
        await tester.pumpAndSettle();

        Future<void> open() async {
          if (keyboard) {
            await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
            await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          } else {
            await tester.tap(find.byKey(ForumSearch.inputKey));
          }
          await tester.pumpAndSettle();
        }

        await open();
        expect(shell.globalSearch.scope, GlobalSearchScope.forum);
        expect(shell.globalSearch.conditions.single.filterId, 'topicId');
        expect(shell.globalSearch.conditions.single.text, '1038');
        await tester.enterText(find.byKey(ForumSearch.inputKey), 'design');
        await _finishSearch(tester);
        expect(
          api.requests
              .lastWhere((r) => r.uri.path == '/search.json')
              .uri
              .queryParameters['q'],
          'design topic:1038',
        );

        shell.globalSearch.clearConditions();
        await _finishSearch(tester);
        await open();
        expect(shell.globalSearch.conditions, isEmpty);
        shell.globalSearch.setScope(GlobalSearchScope.users);
        await _finishSearch(tester);
        await open();
        expect(shell.globalSearch.scope, GlobalSearchScope.users);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        await open();
        expect(shell.globalSearch.scope, GlobalSearchScope.forum);
        expect(shell.globalSearch.conditions.single.text, '1038');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        shell.replaceCurrentContent(
          ContentRoute.topic(
            topicId: 1037,
            slug: 'keyboard-search-focus',
            title: 'Keyboard search focus after switching categories',
          ),
        );
        await tester.pumpAndSettle();
        await open();
        expect(shell.globalSearch.conditions.single.text, '1037');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        shell.handleBack(canReturnToSidebar: false);
        await tester.pumpAndSettle();
        expect(shell.currentContent?.isTopicList, isTrue);
        await open();
        await _finishSearch(tester);
        expect(shell.globalSearch.scope, GlobalSearchScope.forum);
        expect(shell.globalSearch.conditions, isEmpty);
        expect(
          api.requests
              .lastWhere((r) => r.uri.path == '/search.json')
              .uri
              .queryParameters['q'],
          'design',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  _testPresentation(
    'slash opens global search on a topic list and leaves typing to the editor',
    (tester) async {
      final shell = await _pumpSearch(tester);
      expect(find.byKey(const ValueKey('topic-list-search')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
      expect(shell.globalSearch.scope, GlobalSearchScope.forum);
      expect(shell.globalSearch.conditions, isEmpty);
      expect(_editor(tester).focusNode.hasFocus, isTrue);

      shell.globalSearch.setScope(GlobalSearchScope.users);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(ForumSearch.inputKey), 'sam/');
      await _finishSearch(tester);
      expect(shell.globalSearch.query, 'sam/');
      expect(shell.globalSearch.scope, GlobalSearchScope.users);
      expect(tester.takeException(), isNull);
    },
  );

  _testPresentation(
    'Escape from a search control restores the editor without reopening search',
    (tester) async {
      await _pumpSearch(tester);
      await _openAndSearch(tester, 'design');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_editor(tester).focusNode.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.panelKey), findsNothing);
      expect(_editor(tester).focusNode.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  _testPresentation(
    'desktop search replaces the field in place and retains editing state',
    (tester) async {
      final shell = await _pumpSearch(tester);
      final before = tester.getRect(_editorFinder());

      await tester.tap(find.byKey(ForumSearch.inputKey));
      await tester.pumpAndSettle();

      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
      expect(_editorFinder(), findsOneWidget);
      final opened = tester.getRect(_editorFinder());
      expect(opened.topLeft.dx, closeTo(before.topLeft.dx, .5));
      expect(opened.topLeft.dy, closeTo(before.topLeft.dy, .5));
      expect(opened.height, closeTo(before.height, .5));
      expect(_editor(tester).focusNode.hasFocus, isTrue);

      await tester.enterText(find.byKey(ForumSearch.inputKey), 'design');
      await _finishSearch(tester);
      _editor(tester).controller.selection = const TextSelection.collapsed(
        offset: 3,
      );
      await tester.pump();
      final caret = _caretOrigin(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byKey(ForumSearch.panelKey), findsNothing);
      expect(shell.globalSearch.query, 'design');
      expect(_editor(tester).controller.text, 'design');
      expect(_editor(tester).controller.selection.baseOffset, 3);
      final closed = tester.getRect(_editorFinder());
      expect(closed.topLeft.dx, closeTo(before.topLeft.dx, .5));
      expect(closed.topLeft.dy, closeTo(before.topLeft.dy, .5));
      expect(_caretOrigin(tester).dx, closeTo(caret.dx, .5));
      expect(_caretOrigin(tester).dy, closeTo(caret.dy, .5));
      expect(tester.takeException(), isNull);
    },
  );

  _testPresentation(
    'a narrow desktop anchor opens a usable panel without moving or resizing the editor',
    (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final shell = createGlobalSearchFixtureController();
      shell.search.selectSite(globalSearchFixtureSite);
      addTearDown(shell.dispose);
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: 24, top: 32),
                  child: SizedBox(width: 212, child: ForumSearch()),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final groupBefore = tester.getRect(find.byType(DInputGroup));
      final editorBefore = tester.getRect(_editorFinder());
      expect(groupBefore.width, 136);

      await tester.tap(find.byKey(ForumSearch.inputKey));
      await tester.pumpAndSettle();
      final panel = tester.getRect(find.byKey(ForumSearch.panelKey));
      final groupAfter = tester.getRect(find.byType(DInputGroup));
      final editorAfter = tester.getRect(_editorFinder());
      expect(panel.width, greaterThanOrEqualTo(374));
      expect(panel.left, greaterThanOrEqualTo(0));
      expect(panel.right, lessThanOrEqualTo(390));
      expect(groupAfter, groupBefore);
      expect(editorAfter, editorBefore);
      expect(_editor(tester).focusNode.hasFocus, isTrue);
      expect(tester.takeException(), isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(DInputGroup)), groupBefore);
      expect(tester.getRect(_editorFinder()), editorBefore);
      expect(tester.takeException(), isNull);
    },
  );

  _testPresentation(
    'short desktop windows keep the replacement editor on its original baseline',
    (tester) async {
      await _pumpSearch(tester, size: const Size(1000, 420));
      final before = tester.getRect(_editorFinder());
      await tester.tap(find.byKey(ForumSearch.inputKey));
      await tester.pumpAndSettle();
      final after = tester.getRect(_editorFinder());
      final panel = tester.getRect(find.byKey(ForumSearch.panelKey));
      expect(after.topLeft.dx, closeTo(before.topLeft.dx, .5));
      expect(after.topLeft.dy, closeTo(before.topLeft.dy, .5));
      expect(panel.bottom, lessThanOrEqualTo(420));
      expect(_editor(tester).focusNode.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  _testPresentation(
    'composition keeps native keys and initial ArrowUp selects the last result',
    (tester) async {
      final shell = await _pumpSearch(tester);
      await _openAndSearch(tester, 'design');
      final input = _editor(tester).controller;
      input.value = const TextEditingValue(
        text: 'design',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 0, end: 6),
      );
      await tester.pump();
      final selected = find.descendant(
        of: find.byKey(ForumSearch.panelKey),
        matching: find.byWidgetPredicate(
          (widget) => widget is DItem && widget.selected,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(selected, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
      expect(selected, findsNothing);

      input.value = input.value.copyWith(composing: TextRange.empty);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      final last = find.byKey(
        ValueKey('global-search-result-${shell.globalSearch.results.last.id}'),
      );
      expect(tester.widget<DItem>(last).selected, isTrue);
      expect(selected, findsOneWidget);
      expect(_editor(tester).focusNode.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  _testPresentation(
    'the app search shortcut opens and focuses the same search surface',
    (tester) async {
      await _pumpSearch(tester);
      final before = tester.getTopLeft(_editorFinder());
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
      expect(_editor(tester).focusNode.hasFocus, isTrue);
      expect(tester.getTopLeft(_editorFinder()).dx, closeTo(before.dx, .5));
      expect(tester.getTopLeft(_editorFinder()).dy, closeTo(before.dy, .5));
      expect(tester.takeException(), isNull);
    },
  );

  _testPresentation(
    'all results and dedicated scopes use the live query and keep conditions',
    (tester) async {
      final shell = await _pumpSearch(tester);
      await _openAndSearch(tester, 'design');
      await tester.tap(find.byKey(const ValueKey('global-search-scope-all')));
      await _finishSearch(tester);

      expect(_panelText('A calmer, more useful global search'), findsWidgets);
      expect(_panelText('Mira Laurent'), findsWidgets);
      expect(_panelText('Design'), findsWidgets);
      expect(_panelTextContaining('keyboard review'), findsWidgets);

      shell.globalSearch.addCondition(
        const GlobalSearchCondition(filterId: 'author', value: ['mira']),
      );
      await _finishSearch(tester);
      await tester.tap(find.byKey(const ValueKey('global-search-scope-users')));
      await _finishSearch(tester);
      expect(shell.globalSearch.scope, GlobalSearchScope.users);
      expect(shell.globalSearch.query, 'design');
      expect(_editor(tester).controller.text, 'design');
      expect(_panelText('A calmer, more useful global search'), findsNothing);
      expect(_panelText('Mira Laurent'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('global-search-scope-forum')));
      await _finishSearch(tester);
      expect(
        find.byKey(const ValueKey('global-search-condition-0')),
        findsOneWidget,
      );
      expect(_panelText('A calmer, more useful global search'), findsWidgets);
      expect(shell.globalSearch.query, 'design');
      expect(tester.takeException(), isNull);
    },
  );

  _testPresentation(
    'filter menus own Escape and apply visible editable conditions',
    (tester) async {
      final shell = await _pumpSearch(tester);
      await _openAndSearch(tester, 'design');
      final filterTrigger = find.byKey(
        const ValueKey('global-search-filter-trigger'),
      );
      await tester.tap(filterTrigger);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('global-search-filter-author')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('global-search-filter-author')),
        findsNothing,
      );
      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);

      await tester.tap(filterTrigger);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('global-search-filter-author')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('global-search-filter-value')),
        'mira',
      );
      await tester.tap(
        find.byKey(const ValueKey('global-search-filter-apply')),
      );
      await _finishSearch(tester);

      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
      expect(
        find.byKey(const ValueKey('global-search-condition-0')),
        findsOneWidget,
      );
      expect(shell.globalSearch.query, 'design');
      expect(shell.globalSearch.conditions.single.value, ['mira']);
      await tester.tap(find.byKey(const ValueKey('global-search-condition-0')));
      await tester.pumpAndSettle();
      final value = find.descendant(
        of: find.byKey(const ValueKey('global-search-filter-value')),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(value).controller.text, 'mira');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _testPresentation(
    'category conditions show lookup labels and use compact chip widths',
    (tester) async {
      final shell = await _pumpSearch(tester);
      await _openAndSearch(tester, 'design');
      await tester.tap(
        find.byKey(const ValueKey('global-search-filter-trigger')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('global-search-filter-category')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DCommandList<String>),
          matching: find.text('UX'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('global-search-filter-apply')),
      );
      await _finishSearch(tester);

      final chip = find.byKey(const ValueKey('global-search-condition-0'));
      expect(shell.globalSearch.conditions.single.value, ['1']);
      expect(
        find.descendant(of: chip, matching: find.text('UX')),
        findsWidgets,
      );
      expect(find.descendant(of: chip, matching: find.text('1')), findsNothing);
      expect(_panelText('A calmer, more useful global search'), findsOneWidget);
      expect(
        _panelText('Keyboard search focus after switching categories'),
        findsNothing,
      );
      expect(
        tester.getSize(chip).width,
        lessThan(tester.getSize(find.byKey(ForumSearch.panelKey)).width * .9),
      );
      expect(tester.takeException(), isNull);
    },
  );

  _testPresentation(
    'ordering controls keep nested dismissal separate from search',
    (tester) async {
      final shell = await _pumpSearch(tester);
      await _openAndSearch(tester, 'design');
      await tester.tap(find.byKey(const ValueKey('global-search-scope-forum')));
      await _finishSearch(tester);
      await tester.tap(
        find.byKey(const ValueKey('global-search-display-trigger')),
      );
      await tester.pumpAndSettle();
      final order = find.byKey(const ValueKey('global-search-order'));
      await tester.tap(order);
      await tester.pumpAndSettle();
      expect(find.text('Most liked'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(order, findsOneWidget);
      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
      await tester.tap(order);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Most liked'));
      await _finishSearch(tester);
      expect(shell.globalSearch.order, 'likes');
      expect(order, findsOneWidget);
      await tester.tap(find.widgetWithText(DToggle, 'Excerpt'));
      await tester.pumpAndSettle();
      expect(
        shell.globalSearch.properties,
        isNot(contains(GlobalSearchDisplayProperty.excerpt)),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(order, findsNothing);
      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _testPresentation(
    'outside dismissal preserves the query and has no shortcut footer or recent clocks',
    (tester) async {
      final shell = await _pumpSearch(tester);
      await tester.tap(find.byKey(ForumSearch.inputKey));
      await tester.pumpAndSettle();
      final panel = find.byKey(ForumSearch.panelKey);
      final keycaps = find.descendant(
        of: panel,
        matching: find.byType(DShortcutKeycaps),
      );
      for (final element in keycaps.evaluate()) {
        expect(
          tester.getRect(find.byWidget(element.widget)).center.dy,
          lessThan(tester.getRect(_editorFinder()).bottom + 4),
        );
      }
      expect(
        find.descendant(
          of: panel,
          matching: find.byWidgetPredicate(
            (widget) => widget is DIcon && widget.icon.name.contains('clock'),
          ),
        ),
        findsNothing,
      );
      expect(find.textContaining('to navigate'), findsNothing);
      expect(find.textContaining('to select'), findsNothing);

      await tester.enterText(find.byKey(ForumSearch.inputKey), 'keyboard');
      await _finishSearch(tester);
      await tester.tapAt(const Offset(1400, 850));
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.panelKey), findsNothing);
      expect(shell.globalSearch.query, 'keyboard');
      expect(_editor(tester).controller.text, 'keyboard');
      expect(tester.takeException(), isNull);
    },
  );

  _testPresentation(
    'phone presentation stays within its viewport and supports filtering',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await _pumpSearch(tester, size: phone);
      await _openAndSearch(tester, 'design');
      final panel = tester.getRect(find.byKey(ForumSearch.panelKey));
      expect(panel.left, greaterThanOrEqualTo(0));
      expect(panel.right, lessThanOrEqualTo(phone.width));
      expect(panel.top, greaterThanOrEqualTo(0));
      expect(panel.bottom, lessThanOrEqualTo(phone.height));
      expect(_editor(tester).focusNode.hasFocus, isTrue);
      await tester.tap(
        find.byKey(const ValueKey('global-search-filter-trigger')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('global-search-filter-author')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  _testPresentation(
    'changing forums resets search state and removes unavailable chat',
    (tester) async {
      final shell = await _pumpSearch(tester);
      await _openAndSearch(tester, 'design');
      shell.globalSearch.addCondition(
        const GlobalSearchCondition(filterId: 'author', value: ['mira']),
      );
      await _finishSearch(tester);
      expect(
        find.byKey(const ValueKey('global-search-scope-chat')),
        findsOneWidget,
      );

      shell.selectInstance(1);
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.panelKey), findsNothing);
      await tester.tap(find.byKey(ForumSearch.inputKey));
      await tester.pumpAndSettle();
      expect(shell.globalSearch.query, isEmpty);
      expect(shell.globalSearch.conditions, isEmpty);
      expect(
        find.byKey(const ValueKey('global-search-scope-chat')),
        findsNothing,
      );
      await tester.enterText(find.byKey(ForumSearch.inputKey), 'search');
      await _finishSearch(tester);
      expect(_panelText('Community search feedback'), findsWidgets);
      expect(_panelText('A calmer, more useful global search'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<ShellController> _pumpSearch(
  WidgetTester tester, {
  Size size = desktop,
  GlobalSearchFixtureApi? api,
}) async {
  await pumpShell(
    tester,
    size,
    instances: globalSearchFixtureSites,
    api: api ?? GlobalSearchFixtureApi(),
    authenticator: FakeAuthenticator()
      ..keys.addAll({
        globalSearchFixtureSite: 'local-fixture',
        globalSearchFixtureOtherSite: 'local-fixture',
      }),
  );
  return ShellScope.read(tester.element(find.byType(ForumSearch)));
}

Finder _editorFinder() => find.descendant(
  of: find.byKey(ForumSearch.inputKey),
  matching: find.byType(EditableText),
);

EditableText _editor(WidgetTester tester) =>
    tester.widget<EditableText>(_editorFinder());

Offset _caretOrigin(WidgetTester tester) {
  final state = tester.state<EditableTextState>(_editorFinder());
  final render = state.renderEditable;
  final caret = render.getLocalRectForCaret(
    TextPosition(offset: state.widget.controller.selection.extentOffset),
  );
  return render.localToGlobal(caret.topLeft);
}

Future<void> _openAndSearch(WidgetTester tester, String query) async {
  await tester.tap(find.byKey(ForumSearch.inputKey));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(ForumSearch.inputKey), query);
  await _finishSearch(tester);
}

Future<void> _finishSearch(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pumpAndSettle();
}

void _testPresentation(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}

Finder _panelText(String text) => find.descendant(
  of: find.byKey(ForumSearch.panelKey),
  matching: find.text(text),
);

Finder _panelTextContaining(String text) => find.descendant(
  of: find.byKey(ForumSearch.panelKey),
  matching: find.textContaining(text),
);
