import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lazy groups share one viewport and preserve its end boundary', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final built = <int>{};
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: SizedBox(
            width: 260,
            height: 400,
            child: DSidebarProvider(
              child: DSidebar(
                collapsible: DSidebarCollapsible.none,
                header: const DSidebarHeader(child: Text('Fixed header')),
                footer: const DSidebarFooter(child: Text('Fixed footer')),
                child: DSidebarContent.slivers(
                  controller: scroll,
                  slivers: [
                    DSidebarGroup.sliver(
                      label: const DSidebarGroupLabel(child: Text('Channels')),
                      sliver: DSidebarMenu.sliverBuilder(
                        itemCount: 400,
                        itemExtent: 32,
                        itemBuilder: (context, index) {
                          built.add(index);
                          return DSidebarMenuItem(
                            key: ValueKey(index),
                            child: DSidebarMenuButton(
                              onPressed: () {},
                              child: Text('Channel $index'),
                            ),
                          );
                        },
                      ),
                    ),
                    DSidebarGroup.sliver(
                      label: const DSidebarGroupLabel(child: Text('People')),
                      sliver: DSidebarMenuSub.sliverBuilder(
                        itemCount: 3,
                        itemExtent: 28,
                        itemBuilder: (context, index) => DSidebarMenuSubButton(
                          onPressed: () {},
                          child: Text('Person $index'),
                        ),
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
    expect(find.byType(Scrollable), findsOneWidget);
    expect(built.length, lessThan(40));
    expect(find.text('Channel 399'), findsNothing);
    final header = tester.getRect(find.text('Fixed header'));
    final footer = tester.getRect(find.text('Fixed footer'));
    final end = scroll.position.maxScrollExtent;
    scroll.jumpTo(end);
    await tester.pumpAndSettle();
    expect(scroll.position.maxScrollExtent, closeTo(end, .001));
    expect(find.text('Person 2'), findsOneWidget);
    expect(built.length, lessThan(80));
    expect(tester.getRect(find.text('Fixed header')), header);
    expect(tester.getRect(find.text('Fixed footer')), footer);
    await tester.pumpWidget(const SizedBox());
    // The content borrows this controller and must not dispose it.
    scroll.addListener(() {});
    expect(tester.takeException(), isNull);
  });

  for (final retained in [false, true]) {
    testWidgets(
      'sliver disclosure restores focus and hides content (retained=$retained)',
      (tester) async {
        final trigger = FocusNode();
        final row = FocusNode();
        addTearDown(trigger.dispose);
        addTearDown(row.dispose);
        var open = true;
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.macOS),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return DSidebarContent.slivers(
                    slivers: [
                      DCollapsible(
                        open: open,
                        onOpenChange: (value) => setState(() => open = value),
                        child: DSidebarGroup.sliver(
                          label: DCollapsibleTrigger(
                            focusNode: trigger,
                            child: const DSidebarGroupLabel(
                              child: Text('Toggle channels'),
                            ),
                          ),
                          sliver: DCollapsibleContent.sliver(
                            keepMounted: retained,
                            sliver: DSidebarMenu.sliverBuilder(
                              itemCount: 200,
                              itemExtent: 32,
                              itemBuilder: (context, index) =>
                                  DSidebarMenuButton(
                                    focusNode: index == 0 ? row : null,
                                    onPressed: () {},
                                    child: Text('Destination $index'),
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
        row.requestFocus();
        await tester.pump();
        update(() => open = false);
        await tester.pumpAndSettle();
        expect(find.text('Destination 0'), findsNothing);
        expect(trigger.hasPrimaryFocus, isTrue);
        expect(row.canRequestFocus, retained ? isFalse : isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(find.text('Destination 0'), findsOneWidget);
        expect(find.text('Destination 199'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('wide sidebar badges reserve their actual width', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                child: DSidebarMenuItem(
                  badge: const DSidebarMenuBadge(child: Text('1234')),
                  action: DSidebarMenuAction(
                    semanticLabel: 'Channel actions',
                    onPressed: () {},
                    child: const Icon(Icons.more_horiz),
                  ),
                  child: DSidebarMenuButton(
                    onPressed: () {},
                    child: const Text('A long channel name'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final label = tester.getRect(find.text('A long channel name'));
    final badge = tester.getRect(find.byType(DSidebarMenuBadge));
    expect(label.right, lessThanOrEqualTo(badge.left));
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    testWidgets('changing counts keep actions independent in $direction', (
      tester,
    ) async {
      var count = '1';
      var navigations = 0;
      var actions = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Directionality(
                textDirection: direction,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 200,
                    child: StatefulBuilder(
                      builder: (context, setState) {
                        update = setState;
                        return DSidebarMenuItem(
                          badge: DSidebarMenuBadge(child: Text(count)),
                          action: DSidebarMenuAction(
                            semanticLabel: 'Actions',
                            showOnHover: true,
                            onPressed: () => actions++,
                            child: const Icon(Icons.more_horiz),
                          ),
                          child: DSidebarMenuButton(
                            icon: const Icon(Icons.tag),
                            onPressed: () => navigations++,
                            child: const Text('Long channel name'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final initial = tester.getRect(find.text('Long channel name'));
      update(() => count = '1234');
      await tester.pump();
      final label = tester.getRect(find.text('Long channel name'));
      final badge = tester.getRect(find.byType(DSidebarMenuBadge));
      final action = tester.getRect(find.byType(DSidebarMenuAction));
      expect(label.width, lessThan(initial.width));
      expect(label.width, greaterThanOrEqualTo(28));
      if (direction == TextDirection.ltr) {
        expect(label.right + 4, lessThanOrEqualTo(badge.left));
        expect(badge.right, lessThanOrEqualTo(action.left));
      } else {
        expect(label.left - 4, greaterThanOrEqualTo(badge.right));
        expect(badge.left, greaterThanOrEqualTo(action.right));
      }
      expect(badge.center.dy, closeTo(action.center.dy, .001));
      expect(action.height, greaterThanOrEqualTo(48));
      await tester.tap(find.byType(DSidebarMenuAction));
      await tester.pump();
      expect(actions, 1);
      expect(navigations, 0);
      await tester.tap(find.text('Long channel name'));
      await tester.pump();
      expect(navigations, 1);
      expect(actions, 1);
      update(() => count = '1');
      await tester.pump();
      expect(tester.getRect(find.text('Long channel name')), initial);
      expect(tester.takeException(), isNull);
    });
  }
}
