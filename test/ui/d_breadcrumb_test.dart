import 'dart:ui' show Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpBreadcrumb(
  WidgetTester tester,
  Widget child, {
  double width = 360,
  double scale = 1,
  bool rtl = false,
  bool reducedMotion = false,
  TargetPlatform platform = TargetPlatform.macOS,
  ThemeData? theme,
}) => tester.pumpWidget(
  MaterialApp(
    theme: (theme ?? AppTheme.light).copyWith(platform: platform),
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reducedMotion,
        ),
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  ),
);

Widget basicBreadcrumb({
  VoidCallback? onHome,
  VoidCallback? onComponents,
}) => DBreadcrumb(
  child: DBreadcrumbList(
    children: [
      DBreadcrumbItem(
        child: DBreadcrumbLink(onPressed: onHome, child: const Text('Home')),
      ),
      const DBreadcrumbSeparator(),
      DBreadcrumbItem(
        child: DBreadcrumbLink(
          onPressed: onComponents,
          child: const Text('Components'),
        ),
      ),
      const DBreadcrumbSeparator(),
      const DBreadcrumbItem(child: DBreadcrumbPage(child: Text('Breadcrumb'))),
    ],
  ),
);

void main() {
  testWidgets('matches base-nova type, gaps, and artwork geometry', (
    tester,
  ) async {
    await pumpBreadcrumb(
      tester,
      basicBreadcrumb(onHome: () {}, onComponents: () {}),
    );

    final homeStyle = tester.widget<DefaultTextStyle>(
      find
          .ancestor(
            of: find.text('Home'),
            matching: find.byType(DefaultTextStyle),
          )
          .first,
    );
    expect(homeStyle.style.fontSize, 14);
    expect(homeStyle.style.height, 20 / 14);
    for (final separator in find.byType(DBreadcrumbSeparator).evaluate()) {
      expect(
        tester.getSize(find.byElementPredicate((e) => e == separator)),
        const Size(14, 14),
      );
    }

    final home = tester.getRect(find.text('Home'));
    final firstSeparator = tester.getRect(
      find.byType(DBreadcrumbSeparator).first,
    );
    expect(firstSeparator.left - home.right, closeTo(6, .01));
  });

  testWidgets(
    'links support pointer, keyboard, disabled state, and borrowed focus',
    (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      var calls = 0;
      await pumpBreadcrumb(
        tester,
        DBreadcrumb(
          child: DBreadcrumbList(
            children: [
              DBreadcrumbItem(
                child: DBreadcrumbLink(
                  focusNode: focusNode,
                  onPressed: () => calls++,
                  child: const Text('Enabled'),
                ),
              ),
              const DBreadcrumbSeparator(),
              const DBreadcrumbItem(
                child: DBreadcrumbLink(
                  onPressed: null,
                  child: Text('Disabled'),
                ),
              ),
            ],
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.tap(find.text('Enabled'));
      expect(calls, 3);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(focusNode.hasFocus, isTrue, reason: 'disabled link is skipped');
      await tester.tap(find.text('Disabled'));
      expect(calls, 3);

      await pumpBreadcrumb(tester, const Text('Removed'));
      focusNode.requestFocus();
    },
  );

  testWidgets('typed route callback and adapter preserve destination type', (
    tester,
  ) async {
    var destination = -1;
    var adapted = -1;
    await pumpBreadcrumb(
      tester,
      DBreadcrumbLink.route<int>(
        destination: 42,
        onNavigate: (value) => destination = value,
        adapter: (context, value, child) {
          adapted = value;
          return KeyedSubtree(key: ValueKey(value), child: child);
        },
        child: const Text('Topic'),
      ),
    );
    expect(adapted, 42);
    await tester.tap(find.text('Topic'));
    expect(destination, 42);
  });

  testWidgets('touch links retain 48 pixel activation bounds', (tester) async {
    await pumpBreadcrumb(
      tester,
      const DBreadcrumbLink(onPressed: _noop, child: Text('Home')),
      platform: TargetPlatform.iOS,
    );
    expect(tester.getSize(find.byType(DBreadcrumbLink)).height, 48);

    await pumpBreadcrumb(
      tester,
      const DBreadcrumbLink(onPressed: _noop, child: Text('Home')),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DBreadcrumbLink)).height, 20);
  });

  testWidgets('landmark and current page expose useful semantics only', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpBreadcrumb(
      tester,
      const DBreadcrumb(
        semanticLabel: 'Resource path',
        child: DBreadcrumbList(
          children: [
            DBreadcrumbItem(
              child: DBreadcrumbLink(
                onPressed: _noop,
                semanticLabel: 'Home route',
                child: Text('Home'),
              ),
            ),
            DBreadcrumbSeparator(),
            DBreadcrumbItem(child: DBreadcrumbEllipsis()),
            DBreadcrumbSeparator(),
            DBreadcrumbItem(
              child: DBreadcrumbPage(
                semanticLabel: 'Breadcrumb, current page',
                child: Text('Breadcrumb'),
              ),
            ),
          ],
        ),
      ),
    );

    expect(find.bySemanticsLabel('Resource path'), findsOneWidget);
    final link = tester.getSemantics(find.bySemanticsLabel('Home route'));
    expect(link.flagsCollection.isLink, isTrue);
    expect(link.flagsCollection.isEnabled, Tristate.isTrue);
    final page = tester.getSemantics(
      find.bySemanticsLabel('Breadcrumb, current page'),
    );
    expect(page.flagsCollection.isLink, isTrue);
    expect(page.flagsCollection.isEnabled, Tristate.isFalse);
    expect(page.flagsCollection.isSelected, Tristate.isTrue);
    expect(find.bySemanticsLabel('More'), findsNothing);
    handle.dispose();
  });

  testWidgets('default separator flips with reading direction', (tester) async {
    Future<double> horizontalScale(bool rtl) async {
      await pumpBreadcrumb(tester, const DBreadcrumbSeparator(), rtl: rtl);
      return tester
          .widget<Transform>(
            find.descendant(
              of: find.byType(DBreadcrumbSeparator),
              matching: find.byType(Transform),
            ),
          )
          .transform
          .entry(0, 0);
    }

    expect(await horizontalScale(false), 1);
    expect(await horizontalScale(true), -1);
  });

  testWidgets('wrap and scroll remain usable at narrow 200 percent text', (
    tester,
  ) async {
    await pumpBreadcrumb(
      tester,
      basicBreadcrumb(onHome: () {}, onComponents: () {}),
      width: 120,
      scale: 2,
      reducedMotion: true,
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.text('Breadcrumb')).dy,
      greaterThan(tester.getTopLeft(find.text('Home')).dy),
    );

    final lastFocus = FocusNode();
    addTearDown(lastFocus.dispose);
    await pumpBreadcrumb(
      tester,
      DBreadcrumbList(
        overflow: DBreadcrumbOverflow.scroll,
        children: [
          const DBreadcrumbItem(
            child: DBreadcrumbLink(onPressed: _noop, child: Text('Workspace')),
          ),
          const DBreadcrumbSeparator(),
          const DBreadcrumbItem(
            child: DBreadcrumbLink(
              onPressed: _noop,
              child: Text('Documentation'),
            ),
          ),
          const DBreadcrumbSeparator(),
          DBreadcrumbItem(
            child: DBreadcrumbLink(
              focusNode: lastFocus,
              onPressed: _noop,
              child: const Text('Current section'),
            ),
          ),
        ],
      ),
      width: 120,
      scale: 2,
      reducedMotion: true,
    );
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    lastFocus.requestFocus();
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'collapsed menu supports keyboard selection and focus restoration',
    (tester) async {
      final triggerFocus = FocusNode();
      addTearDown(triggerFocus.dispose);
      var selected = '';
      await pumpBreadcrumb(
        tester,
        DBreadcrumb(
          child: DBreadcrumbList(
            children: [
              const DBreadcrumbItem(
                child: DBreadcrumbLink(onPressed: _noop, child: Text('Home')),
              ),
              const DBreadcrumbSeparator(),
              DBreadcrumbItem(
                child: DDropdownMenu(
                  content: DDropdownMenuContent(
                    semanticLabel: 'Hidden pages',
                    children: [
                      DDropdownMenuItem(
                        onPressed: () => selected = 'Documentation',
                        child: const Text('Documentation'),
                      ),
                      DDropdownMenuItem(
                        onPressed: () => selected = 'Themes',
                        child: const Text('Themes'),
                      ),
                    ],
                  ),
                  child: DDropdownMenuTrigger(
                    focusNode: triggerFocus,
                    builder: (context, state) => DButton.iconOnly(
                      icon: const DBreadcrumbEllipsis(),
                      tooltip: 'More pages',
                      size: DButtonSize.small,
                      variant: DButtonVariant.ghost,
                      hasPopup: true,
                      expanded: state.open,
                      focusNode: state.focusNode,
                      onPressed: state.toggle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      triggerFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Documentation'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, 'Themes');
      expect(triggerFocus.hasFocus, isTrue);
    },
  );
}

void _noop() {}
