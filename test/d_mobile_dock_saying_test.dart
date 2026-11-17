import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'd_mobile_dock_test.dart' show fixture;

final _surface = find.byKey(const ValueKey('mobile-dock-surface'));
final _peeked = find.byKey(DMobileDock.peekKey);
final _hint = find.text('Swipe up for more');

const _bookmarked = DMobileDockSaying(
  text: 'Bookmarked',
  icon: DIcons.bookmark,
);

void main() {
  double opacityOf(WidgetTester tester, Finder text) => tester
      .widget<Opacity>(
        find.ancestor(of: text, matching: find.byType(Opacity)).first,
      )
      .opacity;

  testWidgets('a bar says what has just happened lifted as for its peek, '
      'where the hint goes, for 2400 ms, then settles', (tester) async {
    final peek = DMobileDockPeek();
    addTearDown(peek.dispose);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(fixture(foot: 34, peek: peek));
    final rest = tester.getRect(_surface);
    expect(peek.say(_bookmarked), isTrue);
    await tester.pump();
    final said = find.text('Bookmarked');
    expect(said, findsOneWidget);
    expect(_hint, findsNothing);
    // The lift is the peek's: 30 and half the foot, on the settle spring.
    await tester.pump(const Duration(milliseconds: 460));
    expect(tester.getRect(_surface).top, closeTo(rest.top - 47, .01));
    expect(tester.getRect(_peeked).bottom, rest.bottom);
    expect(opacityOf(tester, said), 1);

    // The glyph in the accent, the words 13 medium in the strong text
    // colour, on one line.
    final tokens = DTokens.of(tester.element(said));
    final icon = tester.widget<DIcon>(
      find.descendant(
        of: find.byKey(DMobileDock.hintKey),
        matching: find.byType(DIcon),
      ),
    );
    expect(icon.icon, DIcons.bookmark);
    expect(icon.color, tokens.primary);
    expect(tester.getSize(find.byType(DIcon)).height, 12);
    final text = tester.widget<Text>(said);
    expect(text.style!.fontSize, 13);
    expect(text.style!.fontWeight, FontWeight.w500);
    expect(text.style!.color, tokens.foreground);
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    // A reader is told it.
    expect(
      tester.getSemantics(find.byKey(DMobileDock.hintKey)),
      matchesSemantics(label: 'Bookmarked', isLiveRegion: true),
    );

    // Up for 2400 ms from the saying, then down the same way.
    await tester.pump(const Duration(milliseconds: 1939));
    expect(tester.getRect(_surface).top, closeTo(rest.top - 47, .01));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 470));
    expect(tester.getRect(_surface), rest);
    await tester.pump(const Duration(milliseconds: 1));
    expect(said, findsNothing);
    expect(_peeked, findsNothing);

    // The bar lifted to say something has spent its peek on opening.
    await tester.pump(const Duration(seconds: 5));
    expect(_hint, findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('a saying during the peek takes the hint\'s place and holds the '
      'bar up for its own time', (tester) async {
    final peek = DMobileDockPeek();
    addTearDown(peek.dispose);
    await tester.pumpWidget(fixture(foot: 34, peek: peek));
    final rest = tester.getRect(_surface);
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 3000));
    expect(_hint, findsOneWidget);
    peek.say(const DMobileDockSaying(text: 'Saved'));
    await tester.pump();
    expect(_hint, findsNothing);
    expect(find.text('Saved'), findsOneWidget);
    // Already up, it stays up: no fading in again.
    expect(opacityOf(tester, find.text('Saved')), 1);
    await tester.pump(const Duration(milliseconds: 2399));
    expect(tester.getRect(_surface).top, closeTo(rest.top - 47, .01));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 481));
    expect(find.text('Saved'), findsNothing);
    expect(tester.getRect(_surface), rest);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a newer saying while the bar settles lifts it again, and the '
      'settle it cut short does not end it', (tester) async {
    final peek = DMobileDockPeek();
    addTearDown(peek.dispose);
    await tester.pumpWidget(fixture(foot: 34, peek: peek));
    final rest = tester.getRect(_surface);
    peek.say(const DMobileDockSaying(text: 'First'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2400));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getRect(_surface).top, greaterThan(rest.top - 47));
    peek.say(const DMobileDockSaying(text: 'Second'));
    await tester.pump();
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    // Past when the first settle would have ended.
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Second'), findsOneWidget);
    expect(tester.getRect(_surface).top, closeTo(rest.top - 47, .01));
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 481));
    expect(find.text('Second'), findsNothing);
    expect(tester.getRect(_surface), rest);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a bar with nothing to grow into, or none, does not take a '
      'saying', (tester) async {
    final peek = DMobileDockPeek();
    expect(peek.say(_bookmarked), isFalse);
    await tester.pumpWidget(
      fixture(foot: 34, peek: peek, labels: const ['Start', 'Topics']),
    );
    expect(peek.say(_bookmarked), isFalse);
    await tester.pumpWidget(fixture(foot: 34, peek: peek));
    peek.dispose();
    expect(peek.say(_bookmarked), isFalse);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Bookmarked'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('covered, a bar says it once uncovered, tried every 150 ms, and '
      'drops it after 30 tries', (tester) async {
    final peek = DMobileDockPeek();
    addTearDown(peek.dispose);
    await tester.pumpWidget(fixture(foot: 34, peek: peek, covered: true));
    expect(peek.say(_bookmarked), isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Bookmarked'), findsNothing);
    await tester.pumpWidget(fixture(foot: 34, peek: peek));
    await tester.pump(const Duration(milliseconds: 149));
    expect(find.text('Bookmarked'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));

    await tester.pumpWidget(fixture(foot: 34, peek: peek, covered: true));
    peek.say(const DMobileDockSaying(text: 'Late'));
    await tester.pump(const Duration(milliseconds: 30 * 150));
    await tester.pumpWidget(fixture(foot: 34, peek: peek));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Late'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('grown, a bar says it once the panel is back in', (tester) async {
    final peek = DMobileDockPeek();
    addTearDown(peek.dispose);
    await tester.pumpWidget(fixture(foot: 34, peek: peek));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(find.byKey(const ValueKey('Topics')));
    await tester.drag(
      find.byKey(const ValueKey('Topics')),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(DMobileDock.panelKey), findsOneWidget);
    peek.say(_bookmarked);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Bookmarked'), findsNothing);
    await tester.tap(find.byKey(DMobileDock.grabberKey));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.text('Bookmarked'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a bar folded into its circle is brought back to say it', (
    tester,
  ) async {
    final peek = DMobileDockPeek();
    addTearDown(peek.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(bottom: 34)),
          child: Scaffold(
            body: DScrollChrome(
              identity: 'page',
              floatingFooter: true,
              startFolded: true,
              footerBuilder: (hidden) => Builder(
                builder: (context) {
                  final geometry = DMobileDockGeometry.of(context);
                  return Padding(
                    padding: geometry.margin,
                    child: DMobileDock(
                      geometry: geometry,
                      collapsed: hidden,
                      peek: peek,
                      places: [
                        for (final name in [
                          'Start',
                          'Topics',
                          'Chat',
                          'Inbox',
                          'Users',
                          'Events',
                        ])
                          DMobileDockPlace(
                            key: ValueKey(name),
                            icon: const Icon(Icons.forum),
                            label: name,
                            onPressed: () {},
                          ),
                      ],
                      collapsedDestination: DMobileDockItem(
                        key: const ValueKey('reveal'),
                        collapsed: true,
                        icon: const Icon(Icons.forum),
                        label: 'Reveal navigation',
                        onPressed: () {},
                      ),
                    ),
                  );
                },
              ),
              child: ListView(
                children: [
                  for (var row = 0; row < 80; row++)
                    SizedBox(height: 40, child: Text('Row $row')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<DMobileDock>(find.byType(DMobileDock)).collapsed,
      isTrue,
    );
    expect(peek.say(_bookmarked), isTrue);
    await tester.pump();
    expect(find.text('Bookmarked'), findsNothing);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(
      tester.widget<DMobileDock>(find.byType(DMobileDock)).collapsed,
      isFalse,
    );
    expect(find.text('Bookmarked'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('taken out of the tree while it waits or says, a bar is told '
      'nothing more, and its session drops what waits', (tester) async {
    final peek = DMobileDockPeek();
    await tester.pumpWidget(fixture(foot: 34, peek: peek, covered: true));
    peek.say(_bookmarked);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));

    await tester.pumpWidget(fixture(foot: 34, peek: peek));
    peek.say(const DMobileDockSaying(text: 'Saying'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Saying'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    expect(peek.say(_bookmarked), isFalse);
    // Its retries stop with it: no timer outlives the test.
    peek.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('what floats over the bar rises with it on the bar\'s spring, '
      'and comes down as the bar starts down', (tester) async {
    final peek = DMobileDockPeek();
    addTearDown(peek.dispose);
    const floating = ValueKey('floating');
    final lifts = <bool>[];
    peek.lifted.addListener(() => lifts.add(peek.lifted.value));
    await tester.pumpWidget(
      DMobileDockPeek.scope(
        peek: peek,
        child: fixture(
          foot: 34,
          peek: peek,
          page: const Positioned(
            left: 0,
            bottom: 120,
            child: DMobileDockLift(
              child: SizedBox(key: floating, width: 40, height: 40),
            ),
          ),
        ),
      ),
    );
    final rest = tester.getRect(find.byKey(floating));
    peek.say(_bookmarked);
    await tester.pump();
    expect(peek.lifted.value, isTrue);
    // A touch past, as the bar goes, then where the bar stands.
    await tester.pump(const Duration(milliseconds: 230));
    expect(tester.getRect(find.byKey(floating)).top, lessThan(rest.top - 47));
    await tester.pump(const Duration(milliseconds: 230));
    expect(
      tester.getRect(find.byKey(floating)).top,
      closeTo(rest.top - 47, .01),
    );
    await tester.pump(const Duration(milliseconds: 1940));
    expect(peek.lifted.value, isFalse);
    await tester.pump(const Duration(milliseconds: 480));
    expect(tester.getRect(find.byKey(floating)), rest);
    expect(lifts, [true, false]);

    // Taken out of the tree while lifted, the bar leaves it down.
    peek.say(_bookmarked);
    await tester.pump(const Duration(milliseconds: 100));
    expect(peek.lifted.value, isTrue);
    await tester.pumpWidget(
      DMobileDockPeek.scope(peek: peek, child: fixture()),
    );
    await tester.pump();
    expect(peek.lifted.value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pull taking the lift over lets what floats come down', (
    tester,
  ) async {
    final peek = DMobileDockPeek();
    addTearDown(peek.dispose);
    await tester.pumpWidget(fixture(foot: 34, peek: peek));
    peek.say(_bookmarked);
    await tester.pump(const Duration(milliseconds: 500));
    expect(peek.lifted.value, isTrue);
    final gesture = await tester.createGesture();
    await gesture.down(tester.getCenter(find.byKey(const ValueKey('Topics'))));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -12));
    await tester.pump();
    expect(peek.lifted.value, isFalse);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('toasts', () {
    test('a plain toast goes to the teller; anything more stays a card', () {
      final controller = DToastController();
      final told = <String>[];
      controller.teller = (options) {
        told.add(options.description ?? options.title!);
        return true;
      };
      controller.add(const DToastOptions(description: 'Saved'));
      controller.add(
        const DToastOptions(title: 'Copied', type: DToastType.success),
      );
      expect(told, ['Saved', 'Copied']);
      expect(controller.toasts, isEmpty);

      for (final options in [
        DToastOptions(
          description: 'Archived',
          action: DToastAction(label: 'Undo', onPressed: () {}),
        ),
        const DToastOptions(title: 'Push', description: 'Allow it again'),
        const DToastOptions(description: 'Waiting', duration: null),
        const DToastOptions(description: 'Loading', type: DToastType.loading),
        const DToastOptions(description: 'Now', priority: DToastPriority.high),
        DToastOptions(description: 'Closed', onClose: (_) {}),
        DToastOptions(contentBuilder: (context, toast) => const SizedBox()),
      ]) {
        controller.add(options);
      }
      expect(told, ['Saved', 'Copied']);
      expect(controller.toasts, hasLength(3));

      // One the teller does not take is a card.
      controller.teller = (_) => false;
      controller.add(const DToastOptions(description: 'Floated'));
      expect(controller.toasts.last.options.description, 'Floated');
      controller.dispose();
    });

    testWidgets('a toast is said by the bar with its type\'s glyph, and is a '
        'card once no bar can say it', (tester) async {
      final peek = DMobileDockPeek();
      addTearDown(peek.dispose);
      final controller = DToastController()..teller = peek.sayToast;
      addTearDown(controller.dispose);
      expect(
        controller.add(const DToastOptions(description: 'Nothing to say it')),
        isNotNull,
      );
      expect(controller.toasts, hasLength(1));
      controller.close(controller.toasts.single.id);

      await tester.pumpWidget(fixture(foot: 34, peek: peek));
      controller.add(
        const DToastOptions(
          description: 'Could not save',
          type: DToastType.error,
        ),
      );
      expect(controller.toasts, isEmpty);
      await tester.pump();
      final said = find.text('Could not save');
      expect(said, findsOneWidget);
      final icon = tester.widget<DIcon>(
        find.descendant(
          of: find.byKey(DMobileDock.hintKey),
          matching: find.byType(DIcon),
        ),
      );
      expect(icon.color, DTokens.of(tester.element(said)).destructive);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    });
  });
}
