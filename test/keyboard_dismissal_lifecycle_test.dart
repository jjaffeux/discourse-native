import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/shell/desktop_navigation.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/global_search_fixtures.dart';
import 'support/shell_test_harness.dart';

void main() {
  testWidgets('compact navigation excludes its hidden sidebar input', (
    tester,
  ) async {
    final shell = createGlobalSearchFixtureController();
    addTearDown(shell.dispose);
    await shell.load();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    late StateSetter update;
    var compact = false;
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return DesktopNavigation(
                  compact: compact,
                  sidebar: SizedBox(
                    width: 240,
                    child: DInput(focusNode: focus),
                  ),
                  child: const SizedBox.expand(),
                );
              },
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    update(() => compact = true);
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    update(() => compact = false);
    await tester.pumpAndSettle();
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final departure in [
      'cancel',
      'back',
      'early back',
      'sidebar',
      'site',
      'replace',
      'topic',
      'home',
      'panel',
    ]) {
      testWidgets('shell search $departure releases keyboard on $platform', (
        tester,
      ) async {
        await pumpShell(
          tester,
          phone,
          instances: globalSearchFixtureSites,
          api: GlobalSearchFixtureApi(),
          authenticator: FakeAuthenticator()
            ..keys[globalSearchFixtureSite] = 'fixture',
        );
        final shell = ShellScope.read(tester.element(find.byType(ForumSearch)));
        await tester.tap(find.byKey(const ValueKey('mobile-search-button')));
        if (departure == 'early back') {
          await tester.pump();
          expect(shell.currentContent?.isGlobalSearch, isTrue);
        } else {
          await tester.pumpAndSettle();
          expect(tester.testTextInput.isVisible, isTrue);
        }
        switch (departure) {
          case 'cancel':
            await tester.tap(find.byKey(const ValueKey('mobile-search-back')));
          case 'back' || 'early back':
            shell.handleBack();
          case 'sidebar':
            shell.toggleMobileSidebar();
          case 'site':
            shell.selectInstance(1);
          case 'replace':
            shell.replaceCurrentContent(ContentRoute.allCategories());
          case 'topic':
            shell.openTopic(globalSearchFixtureTopics.first);
          case 'home':
            shell.openMobileHome();
          case 'panel':
            shell.selectMobilePanel('chat');
        }
        await tester.pumpAndSettle();
        expect(
          tester.testTextInput.isVisible,
          isFalse,
          reason:
              'route=${shell.currentContent?.id}; focus=${FocusManager.instance.primaryFocus}',
        );
        expect(tester.testTextInput.hasAnyClients, isFalse);
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant({platform}));
    }
    testWidgets('search Cancel disconnects the keyboard on $platform', (
      tester,
    ) async {
      final shell = createGlobalSearchFixtureController();
      addTearDown(shell.dispose);
      await shell.load();
      shell.pushContent(ContentRoute.topicList(TopicListMode.latest));
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: platform),
            home: const Scaffold(body: ForumSearch(fullScreen: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mobile-search-button')));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tap(find.byKey(const ValueKey('mobile-search-back')));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.hasAnyClients, isFalse);
    });
  }

  for (final kind in ['dialog', 'sheet', 'drawer', 'popover']) {
    testWidgets('$kind closing content cannot reopen its keyboard', (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final popover = DPopoverController();
      addTearDown(popover.dispose);
      late VoidCallback close;
      Widget body() => SizedBox(
        width: 300,
        height: 200,
        child: DInput(focusNode: focus, autofocus: true),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: Builder(
              builder: (context) => kind == 'popover'
                  ? DPopover(
                      controller: popover,
                      sheetOnMobile: false,
                      restoreFocus: false,
                      content: DPopoverContent(child: body()),
                      child: DPopoverTrigger(
                        builder: (context, toggle) => DButton(
                          onPressed: toggle.toggle,
                          label: const Text('Open'),
                        ),
                      ),
                    )
                  : DButton(
                      label: const Text('Open'),
                      onPressed: () {
                        if (kind == 'dialog') {
                          unawaited(
                            showDDialog<void>(
                              context: context,
                              restoreFocus: false,
                              builder: (_, controller) {
                                close = controller.close;
                                return DDialogContent(children: [body()]);
                              },
                            ),
                          );
                        } else if (kind == 'drawer') {
                          unawaited(
                            showDDrawer<void>(
                              context: context,
                              builder: (_, controller) {
                                close = controller.close;
                                return DDrawerContent(children: [body()]);
                              },
                            ),
                          );
                        } else {
                          unawaited(
                            showDSheet<void>(
                              context: context,
                              builder: (_, controller) {
                                close = controller.close;
                                return DSheetContent(children: [body()]);
                              },
                            ),
                          );
                        }
                      },
                    ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
      if (kind == 'popover') {
        close = popover.close;
      }
      close();
      // A closing surface remains mounted for its reverse animation.
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      focus.requestFocus();
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.hasAnyClients, isFalse);
    });
  }
}
