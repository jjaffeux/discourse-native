import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/chat/chat_global_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox.dart';
import 'package:discourse_native/src/plugins/chat/chat_route.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/composer/presentation.dart';
import 'package:discourse_native/src/shell/mobile_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/global_search_fixtures.dart';

void main() {
  setUpAll(() async {
    if (Platform.environment.containsKey('CHAT_SEARCH_CAPTURE_DIR')) {
      await (FontLoader('Lato')
            ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
            ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
          .load();
    }
  });

  for (final source in ['forum', 'channel', 'thread']) {
    testWidgets('$source drawer opens the shared focused phone search', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.reset);
      final wire = GlobalSearchFixtureApi();
      final shell = createGlobalSearchFixtureController(
        api: wire,
        mobileNavigationEnabled: true,
      );
      addTearDown(shell.dispose);
      await shell.load();
      await shell.pluginSession
          .require(chatControllerService)
          .loadChannels(globalSearchFixtureSite);
      if (source != 'forum') {
        shell.pushContent(
          ContentRoute(
            destination: ExtensionDestination(
              (source == 'thread'
                      ? ChatRoute.thread(channelId: 2, threadId: 77)
                      : ChatRoute.channel(2))
                  .routeId,
            ),
            title: 'Design chat',
            icon: DIcons.comment,
          ),
        );
      }
      final boundary = GlobalKey();
      await _mount(tester, shell, boundary);
      final routeBefore = shell.currentContent;
      shell.globalSearch.setQuery('previous words category:support ');
      shell.toggleMobileSidebar();
      expect(shell.mobileNavigation.sidebarOpen, isTrue);

      await tester.tap(find.byKey(const ValueKey('chat-search-entry')));
      await _finishSearch(tester);

      expect(shell.mobileNavigation.sidebarOpen, isFalse);
      expect(shell.currentContent, same(routeBefore));
      expect(find.byType(ForumSearch, skipOffstage: false), findsOneWidget);
      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.byKey(const ValueKey('global-search-footer')), findsNothing);
      expect(_editor(tester).focusNode.hasFocus, isTrue);
      expect(shell.globalSearch.scope, chatSearchScope);
      expect(shell.globalSearch.query, isEmpty);
      if (source == 'forum') {
        expect(shell.globalSearch.conditions, isEmpty);
        expect(
          find.byKey(const ValueKey('global-search-remove-scope')),
          findsOneWidget,
        );
      } else {
        expect(shell.globalSearch.conditions.single.filterId, 'chatChannel');
        expect(shell.globalSearch.conditions.single.text, '2');
        expect(
          find.textContaining('Design chat', findRichText: true),
          findsWidgets,
        );
      }
      expect(tester.getRect(find.byKey(ForumSearch.panelKey)).top, 47);
      expect(tester.getRect(find.byKey(ForumSearch.panelKey)).bottom, 810);

      await tester.enterText(find.byKey(ForumSearch.inputKey), 'search');
      await _finishSearch(tester);
      expect(
        find.textContaining('ready for a keyboard review', findRichText: true),
        findsOneWidget,
      );
      final request = wire.requests.lastWhere(
        (request) => request.uri.path == '/chat/api/search.json',
      );
      expect(request.uri.queryParameters['query'], 'search');
      expect(
        request.uri.queryParameters['channel_id'],
        source == 'forum' ? null : '2',
      );
      expect(request.uri.queryParameters, isNot(contains('thread_id')));
      if (source != 'thread') {
        await _capture(tester, boundary, '$source-scoped-phone');
      }

      // Insets change while the editor and its native keyboard connection stay.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      tester.view.padding = const FakeViewPadding(top: 47);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(ForumSearch.panelKey)).bottom, 544);
      expect(_editor(tester).focusNode.hasFocus, isTrue);
      expect(tester.takeException(), isNull);

      if (source == 'forum') {
        await tester.tap(
          find.byKey(const ValueKey('global-search-remove-scope')),
        );
        await _finishSearch(tester);
        expect(shell.globalSearch.scope, GlobalSearchScope.all);
        expect(shell.globalSearch.query, 'search');
      } else {
        await tester.tap(find.byTooltip('Remove Channel condition'));
        await _finishSearch(tester);
        expect(shell.globalSearch.conditions, isEmpty);
        expect(shell.globalSearch.scope, chatSearchScope);
        expect(shell.globalSearch.query, 'search');
        expect(_editor(tester).focusNode.hasFocus, isTrue);
      }
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.panelKey), findsNothing);
      expect(shell.currentContent, same(routeBefore));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('filter choices retain Chat section and return input focus', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shell = createGlobalSearchFixtureController();
    addTearDown(shell.dispose);
    await shell.load();
    await _mount(tester, shell, GlobalKey());
    await tester.tap(find.byKey(const ValueKey('chat-search-entry')));
    await _finishSearch(tester);
    await tester.enterText(
      find.byKey(ForumSearch.inputKey),
      'search chatThreads:',
    );
    await _finishSearch(tester);
    await tester.tap(find.text('Exclude thread replies'));
    await _finishSearch(tester);
    expect(shell.globalSearch.scope, chatSearchScope);
    expect(shell.globalSearch.conditions.single.filterId, 'chatThreads');
    expect(shell.globalSearch.conditions.single.text, 'exclude');
    expect(shell.globalSearch.wordsQuery.trim(), 'search');
    expect(_editor(tester).focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow phone keeps Cancel and scope removal at 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final shell = createGlobalSearchFixtureController();
    addTearDown(shell.dispose);
    await shell.load();
    await _mount(tester, shell, GlobalKey());
    await tester.tap(find.byKey(const ValueKey('chat-search-entry')));
    await _finishSearch(tester);
    final cancel = tester.getRect(find.text('Cancel'));
    expect(cancel.right, lessThanOrEqualTo(320));
    expect(
      tester.getRect(find.byKey(ForumSearch.inputKey)).width,
      greaterThan(0),
    );
    await tester.tap(find.byKey(const ValueKey('global-search-remove-scope')));
    await _finishSearch(tester);
    expect(shell.globalSearch.scope, GlobalSearchScope.all);
    expect(_editor(tester).focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the phone drawer entry closes the drawer and opens search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shell = createGlobalSearchFixtureController(
      mobileNavigationEnabled: true,
    );
    addTearDown(shell.dispose);
    await shell.load();
    shell.pushContent(
      ContentRoute(
        destination: ExtensionDestination(ChatRoute.channel(2).routeId),
        title: 'Design chat',
        icon: DIcons.comment,
      ),
    );
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
          home: const Scaffold(
            body: SafeArea(
              child: ComposerPresentationHost(
                child: MobileForumRoot(content: SizedBox.expand()),
              ),
            ),
          ),
        ),
      ),
    );
    await _finishSearch(tester);
    await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
    await tester.pumpAndSettle();
    expect(shell.mobileNavigation.sidebarOpen, isTrue);
    expect(find.byKey(const ValueKey('chat-search-entry')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-search-entry')));
    await _finishSearch(tester);
    expect(shell.mobileNavigation.sidebarOpen, isFalse);
    expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
    expect(shell.globalSearch.conditions.single.text, '2');
    expect(_editor(tester).focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search entry retires with the site and disconnected account', (
    tester,
  ) async {
    final shell = createGlobalSearchFixtureController();
    addTearDown(shell.dispose);
    await shell.load();
    await _mount(tester, shell, GlobalKey());
    final chat = shell.pluginSession.require(chatShellService);
    expect(find.byKey(const ValueKey('chat-search-entry')), findsOneWidget);
    shell.selectInstance(1);
    await _finishSearch(tester);
    expect(find.byKey(const ValueKey('chat-search-entry')), findsNothing);
    expect(
      tester.getTopLeft(find.byType(ChatInboxFilterBar)).dy,
      tester.getTopLeft(find.byType(ChatSidebarInboxHeader)).dy,
    );
    chat.openGlobalSearch(globalSearchFixtureSite);
    await tester.pumpAndSettle();
    expect(find.byKey(ForumSearch.panelKey), findsNothing);
    shell.selectInstance(0);
    await _finishSearch(tester);
    expect(find.byKey(const ValueKey('chat-search-entry')), findsOneWidget);
    expect(await shell.disconnectInstance(globalSearchFixtureSite), isTrue);
    await _finishSearch(tester);
    expect(find.byKey(const ValueKey('chat-search-entry')), findsNothing);
    expect(
      tester.getTopLeft(find.byType(ChatInboxFilterBar)).dy,
      tester.getTopLeft(find.byType(ChatSidebarInboxHeader)).dy,
    );
    chat.openGlobalSearch(globalSearchFixtureSite);
    await tester.pumpAndSettle();
    expect(find.byKey(ForumSearch.panelKey), findsNothing);
  });
}

EditableText _editor(WidgetTester tester) => tester.widget<EditableText>(
  find.descendant(
    of: find.byKey(ForumSearch.inputKey),
    matching: find.byType(EditableText),
  ),
);

Future<void> _mount(
  WidgetTester tester,
  ShellController shell,
  GlobalKey key,
) async {
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light.copyWith(
            platform: TargetPlatform.iOS,
            textTheme: AppTheme.light.textTheme.apply(fontFamily: 'Lato'),
          ),
          home: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  const ForumSearch(fullScreen: true),
                  PluginUiScope.own(
                    chatPluginId,
                    const ChatSidebarInboxHeader(
                      siteUrl: globalSearchFixtureSite,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _finishSearch(tester);
}

Future<void> _finishSearch(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['CHAT_SEARCH_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
