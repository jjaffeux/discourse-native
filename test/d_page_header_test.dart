import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final reverse in [false, true]) {
    testWidgets(
      'header contract reaches controls, body and chrome (reverse: $reverse)',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        late DPageHeader controlsHeader;
        late DPageHeader bodyHeader;
        DPageHeader? foreground;
        await tester.pumpWidget(
          MaterialApp(
            home: DPageHeaderHost(
              identity: 'directory',
              builder: (_, active, child) => Column(
                children: [
                  ValueListenableBuilder<DPageHeader?>(
                    valueListenable: active,
                    builder: (_, header, _) {
                      foreground = header;
                      return Text(header?.titleText ?? 'No page');
                    },
                  ),
                  Expanded(child: child),
                ],
              ),
              child: DPageSurface.headed(
                title: const Text('Directory'),
                controls: Builder(
                  builder: (context) {
                    controlsHeader = DPageHeaderScope.maybeOf(context)!;
                    return DButton(
                      key: const ValueKey('return'),
                      label: const Text('Return to top'),
                      onPressed: () => unawaited(controlsHeader.scrollToTop()),
                    );
                  },
                ),
                bodyBuilder: (context, geometry) {
                  bodyHeader = DPageHeaderScope.maybeOf(context)!;
                  return CustomScrollView(
                    key: const ValueKey('viewport'),
                    controller: scroll,
                    reverse: reverse,
                    slivers: [
                      SliverToBoxAdapter(child: geometry.spacer),
                      const SliverToBoxAdapter(child: SizedBox(height: 5000)),
                    ],
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(identical(controlsHeader, bodyHeader), isTrue);
        expect(identical(foreground, bodyHeader), isTrue);
        expect(foreground?.titleText, 'Directory');
        scroll.jumpTo(reverse ? scroll.position.maxScrollExtent : 0);
        await tester.pumpAndSettle();
        expect(bodyHeader.value, 0);
        await tester.drag(
          find.byKey(const ValueKey('viewport')),
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();
        expect(bodyHeader.value, 1);
        await tester.tap(find.byKey(const ValueKey('return')));
        await tester.pumpAndSettle();
        expect(scroll.offset, reverse ? scroll.position.maxScrollExtent : 0);
        expect(bodyHeader.value, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'excluded and inactive headers cannot replace the foreground title',
    (tester) async {
      Widget page(String title) => DPageSurface.headed(
        title: Text(title),
        child: ListView(children: const [SizedBox(height: 2000)]),
      );
      DPageHeader? foreground;
      await tester.pumpWidget(
        MaterialApp(
          home: DPageHeaderHost(
            identity: 'foreground',
            builder: (_, active, child) => ValueListenableBuilder<DPageHeader?>(
              valueListenable: active,
              child: child,
              builder: (_, header, child) {
                foreground = header;
                return child!;
              },
            ),
            child: Stack(
              children: [
                page('Foreground page'),
                DPageHeaderHost.exclude(
                  child: Padding(
                    padding: const EdgeInsets.all(1),
                    child: page('Retained underlay'),
                  ),
                ),
                TickerMode(
                  enabled: false,
                  child: Padding(
                    padding: const EdgeInsets.all(1),
                    child: page('Inactive route'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(foreground?.titleText, 'Foreground page');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('a returning sheet previews its own previous visit title', (
    tester,
  ) async {
    Future<void> show(String id, String title, String? previous) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DPageHeaderHost(
            identity: id,
            previousIdentity: previous,
            titlesInBar: true,
            builder: (_, active, child) => Column(
              children: [
                Builder(
                  builder: (context) => Text(
                    DPageHeaderHost.previousTitleOf(context)?.title ??
                        'No previous page',
                    key: const ValueKey('previous-title'),
                  ),
                ),
                Expanded(child: child),
              ],
            ),
            child: DPageSurface.headed(
              key: ValueKey(id),
              title: Text(title),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String previousTitle() =>
        tester.widget<Text>(find.byKey(const ValueKey('previous-title'))).data!;
    await show('list', 'Latest topics', null);
    await show('one', 'First topic', 'list');
    expect(previousTitle(), 'Latest topics');
    await show('two', 'Second topic', 'one');
    expect(previousTitle(), 'First topic');
    await show('one', 'First topic', 'list');
    expect(previousTitle(), 'Latest topics');
    expect(tester.takeException(), isNull);
  });
}
