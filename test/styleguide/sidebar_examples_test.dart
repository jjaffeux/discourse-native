import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/sidebar_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'all Sidebar examples render narrow RTL large text and mobile content',
    (tester) async {
      for (final example in sidebarExamples.examples) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                  size: Size(360, 600),
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: SizedBox(
                    width: 360,
                    child: SingleChildScrollView(
                      child: Builder(builder: example.builder),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: example.title);
        if (example.title != 'Documentation') {
          await tester.tap(find.byType(DSidebarTrigger));
          await tester.pump();
          await tester.pump();
          expect(find.byType(DSheetContent), findsOneWidget);
          if (example.title == 'Application sidebar') {
            expect(find.byType(DInput), findsNothing);
          } else {
            expect(find.byType(DInput), findsOneWidget);
          }
          if (example.title != 'Loading and recovery') {
            expect(find.byType(DCollapsible), findsWidgets);
          }
          expect(
            find.byType(DDropdownMenu),
            findsNWidgets(example.title == 'Application sidebar' ? 5 : 2),
          );
          expect(find.byType(DAvatar), findsOneWidget);
          expect(
            tester.takeException(),
            isNull,
            reason: '${example.title} mobile open',
          );
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: '${example.title} removed',
        );
      }
    },
  );

  testWidgets('final owner compositions remain interactive', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(builder: sidebarExamples.examples.first.builder),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Platform'), findsOneWidget);
    expect(find.text('Playground'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Starred'), findsOneWidget);
    expect(find.text('Models'), findsOneWidget);
    expect(find.text('Documentation'), findsOneWidget);
    expect(find.text('m@example.com'), findsOneWidget);
    expect(find.byType(DInput), findsNothing);

    await tester.tap(
      find.bySemanticsLabel('Switch team, Acme Inc, Enterprise'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Acme Corp.'), findsOneWidget);
    await tester.tap(find.text('Acme Corp.'));
    await tester.pumpAndSettle();
    expect(find.text('Acme Corp. team selected'), findsOneWidget);

    final playground = find.bySemanticsLabel('Toggle Playground');
    expect(
      tester.getSemantics(playground).flagsCollection.isExpanded,
      Tristate.isTrue,
    );
    await tester.tap(playground);
    await tester.pumpAndSettle();
    expect(find.text('History'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Open shadcn account menu'));
    await tester.pumpAndSettle();
    expect(find.text('Account'), findsOneWidget);
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(find.text('Account selected'), findsOneWidget);
  });

  testWidgets('project row actions open a dropdown without selecting the row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Builder(builder: sidebarExamples.examples.first.builder),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Toggle Playground'));
    await tester.pumpAndSettle();

    final action = find.byWidgetPredicate(
      (widget) =>
          widget is DSidebarMenuAction &&
          widget.semanticLabel == 'More options for Design Engineering',
    );
    final focus = tester.widget<DSidebarMenuAction>(action).focusNode!;
    double opacity() => tester
        .widget<Opacity>(
          find.descendant(of: action, matching: find.byType(Opacity)),
        )
        .opacity;
    expect(opacity(), 0);
    expect(
      tester.getSemantics(action).flagsCollection.isExpanded,
      Tristate.isFalse,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(action));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('View Project'), findsOneWidget);
    expect(find.text('Share Project'), findsOneWidget);
    expect(find.text('Delete Project'), findsOneWidget);
    expect(find.text('Select a destination'), findsOneWidget);
    expect(
      tester.getSemantics(action).flagsCollection.isExpanded,
      Tristate.isTrue,
    );
    await mouse.moveTo(const Offset(800, 500));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    expect(opacity(), 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(DDropdownMenuContent), findsNothing);
    expect(focus.hasFocus, isTrue);
    expect(
      tester.getSemantics(action).flagsCollection.isExpanded,
      Tristate.isFalse,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Share Project'));
    await tester.pumpAndSettle();
    expect(find.byType(DDropdownMenuContent), findsNothing);
    expect(find.text('Share Design Engineering selected'), findsOneWidget);
    expect(focus.hasFocus, isTrue);

    for (final (project, command) in [
      ('Sales & Marketing', 'View'),
      ('Travel', 'Delete'),
    ]) {
      await tester.tap(find.bySemanticsLabel('More options for $project'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('$command Project'));
      await tester.pumpAndSettle();
      expect(find.text('$command $project selected'), findsOneWidget);
      expect(find.byType(DDropdownMenuContent), findsNothing);
    }

    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(800, 400));
    await tester.pumpAndSettle();
    expect(find.byType(DDropdownMenuContent), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'project dropdown stays inside the mobile sidebar at large RTL text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 640),
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Builder(builder: sidebarExamples.examples.first.builder),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(DSidebarTrigger));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Toggle Playground'));
      await tester.pumpAndSettle();
      final action = find.bySemanticsLabel(
        'More options for Design Engineering',
      );
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      final menu = tester.getRect(find.byType(DDropdownMenuContent));
      expect(menu.left, greaterThanOrEqualTo(0));
      expect(menu.right, lessThanOrEqualTo(360));
      expect(menu.top, greaterThanOrEqualTo(0));
      expect(menu.bottom, lessThanOrEqualTo(640));
      await tester.tap(find.text('Share Project'));
      await tester.pumpAndSettle();
      expect(find.byType(DDropdownMenuContent), findsNothing);
      expect(find.byType(DSheetContent), findsOneWidget);

      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(DDropdownMenuContent), findsNothing);
      expect(find.byType(DSheetContent), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(DSheetContent), findsNothing);
      expect(find.text('Share Design Engineering selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('header and footer menu buttons respond to pointer hover', (
    tester,
  ) async {
    final strategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const hoverColor = Color(0xff123456);
    final theme = ThemeData(platform: TargetPlatform.macOS);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme.copyWith(
          extensions: [DTokens.fromTheme(theme).copyWith(hover: hoverColor)],
        ),
        home: Scaffold(
          body: Builder(builder: sidebarExamples.examples.first.builder),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final team = find.byWidgetPredicate(
      (widget) =>
          widget is DSidebarMenuButton &&
          widget.semanticLabel == 'Switch team, Acme Inc, Enterprise',
    );
    final account = find.byWidgetPredicate(
      (widget) =>
          widget is DSidebarMenuButton &&
          widget.semanticLabel == 'Open shadcn account menu',
    );
    bool usesHoverColor(Finder button) => tester
        .widgetList<Container>(
          find.descendant(of: button, matching: find.byType(Container)),
        )
        .any(
          (container) =>
              container.decoration is BoxDecoration &&
              (container.decoration! as BoxDecoration).color == hoverColor,
        );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(team));
    await tester.pumpAndSettle();
    expect(usesHoverColor(team), isTrue);
    expect(usesHoverColor(account), isFalse);

    await mouse.moveTo(tester.getCenter(account));
    await tester.pump();
    expect(usesHoverColor(team), isFalse);
    expect(usesHoverColor(account), isTrue);
  });

  testWidgets('reference icon collapse hides the Projects group', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Builder(builder: sidebarExamples.examples.first.builder),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Design Engineering'), findsOneWidget);

    await tester.tap(find.byType(DSidebarTrigger));
    await tester.pumpAndSettle();

    expect(find.text('Projects'), findsNothing);
    expect(find.text('Design Engineering'), findsNothing);
    expect(
      find.bySemanticsLabel('Switch team, Acme Inc, Enterprise'),
      findsOne,
    );
    expect(find.bySemanticsLabel('Open shadcn account menu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'icon collapse keeps the account menu usable without hidden focus',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Builder(builder: sidebarExamples.examples[1].builder),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DSidebarTrigger));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DCollapsibleTrigger), findsNothing);
      final account = find.byWidgetPredicate(
        (widget) =>
            widget is DSidebarMenuButton &&
            widget.semanticLabel == 'Open Alex Morgan account menu',
      );
      final accountRect = tester.getRect(account);
      expect(accountRect.size, const Size(32, 32));
      expect(tester.getRect(find.byType(DAvatar)), accountRect);
      final focus = tester.widget<DSidebarMenuButton>(account).focusNode!;
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsNothing);
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile dropdown dismissal stays inside the Sidebar Sheet', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 640),
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Builder(builder: sidebarExamples.examples[4].builder),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(DSidebarTrigger));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(DSheetContent)).right, 360);
    await tester.tap(find.bySemanticsLabel('Switch workspace, Acme Inc'));
    await tester.pumpAndSettle();
    final menu = tester.getRect(find.byType(DDropdownMenuContent));
    expect(menu.left, greaterThanOrEqualTo(0));
    expect(menu.right, lessThanOrEqualTo(360));
    await tester.tap(find.text('Stark Industries'));
    await tester.pumpAndSettle();
    expect(find.byType(DSheetContent), findsOneWidget);
    expect(
      find.bySemanticsLabel('Switch workspace, Stark Industries'),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('Open Alex Morgan account menu'));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsNothing);
    expect(find.byType(DSheetContent), findsOneWidget);
    final account = tester.widget<DSidebarMenuButton>(
      find.byWidgetPredicate(
        (widget) =>
            widget is DSidebarMenuButton &&
            widget.semanticLabel == 'Open Alex Morgan account menu',
      ),
    );
    expect(account.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(DSheetContent), findsNothing);
    expect(find.text('Stark Industries workspace selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
