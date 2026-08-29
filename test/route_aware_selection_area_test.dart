import 'package:discourse_native/src/shell/route_aware_selection_area.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('deregisters selection while its route is covered', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    var contentInitializations = 0;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: _SelectionPage(
          onContentInitialized: () => contentInitializations++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea, skipOffstage: false), findsOneWidget);
    expect(contentInitializations, 1);

    navigatorKey.currentState!.push<void>(
      MaterialPageRoute(builder: (context) => const _CoveringPage()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea, skipOffstage: false), findsNothing);
    expect(
      find.text('First selectable paragraph', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Second selectable paragraph', skipOffstage: false),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    expect(contentInitializations, 1);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea, skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(contentInitializations, 1);
  });

  testWidgets('does not register selection on an initially covered route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Navigator(
          pages: const [
            MaterialPage(child: _SelectionPage(onContentInitialized: _noop)),
            MaterialPage(child: _CoveringPage()),
          ],
          onDidRemovePage: (page) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}

class _SelectionPage extends StatelessWidget {
  const _SelectionPage({required this.onContentInitialized});

  final VoidCallback onContentInitialized;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: RouteAwareSelectionArea(
      child: _SelectionContent(onInitialized: onContentInitialized),
    ),
  );
}

class _SelectionContent extends StatefulWidget {
  const _SelectionContent({required this.onInitialized});

  final VoidCallback onInitialized;

  @override
  State<_SelectionContent> createState() => _SelectionContentState();
}

class _SelectionContentState extends State<_SelectionContent> {
  @override
  void initState() {
    super.initState();
    widget.onInitialized();
  }

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      Text('First selectable paragraph'),
      Text('Second selectable paragraph'),
    ],
  );
}

class _CoveringPage extends StatelessWidget {
  const _CoveringPage();

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('Cover'));
}
