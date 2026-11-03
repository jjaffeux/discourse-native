import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final reverse in [false, true]) {
    testWidgets(
      'adaptive page title returns its lazy list to the top after resize (reverse: $reverse)',
      (tester) async {
        final scroll = ScrollController();
        final embedded = ScrollController();
        addTearDown(scroll.dispose);
        addTearDown(embedded.dispose);
        late StateSetter resize;
        var height = 450.0;
        Widget row(int index) => index == (reverse ? 35 : 4)
            ? ListView(
                controller: embedded,
                children: [
                  for (var line = 0; line < 20; line++)
                    SizedBox(height: 25, child: Text('Embedded line $line')),
                ],
              )
            : Text('Row $index');
        await tester.pumpWidget(
          MaterialApp(
            home: Align(
              alignment: Alignment.topCenter,
              child: StatefulBuilder(
                builder: (_, setState) {
                  resize = setState;
                  return SizedBox(
                    height: height,
                    child: DPageHeaderHost(
                      identity: 'adaptive-directory',
                      titlesInBar: true,
                      builder: (_, active, child) => Column(
                        children: [
                          ValueListenableBuilder<DPageHeader?>(
                            valueListenable: active,
                            builder: (_, header, _) => DButton(
                              key: const ValueKey('adaptive-return'),
                              label: const Text('Return to top'),
                              onPressed: () => unawaited(header!.scrollToTop()),
                            ),
                          ),
                          Expanded(child: child),
                        ],
                      ),
                      child: DPageSurface.headed(
                        key: const ValueKey('adaptive-page'),
                        title: const Text('Directory'),
                        controls: const SizedBox(height: 40),
                        adaptiveBodyBuilder: (_, lazy) => lazy
                            ? ListView.builder(
                                controller: scroll,
                                reverse: reverse,
                                itemExtent: 50,
                                itemCount: 40,
                                itemBuilder: (_, index) => row(index),
                              )
                            : Column(
                                children: [
                                  for (var index = 0; index < 40; index++)
                                    SizedBox(height: 50, child: row(index)),
                                ],
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        scroll.jumpTo(reverse ? scroll.position.maxScrollExtent - 200 : 200);
        await tester.pumpAndSettle();
        resize(() => height = 500);
        await tester.pumpAndSettle();
        embedded.jumpTo(60);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('adaptive-return')));
        await tester.pumpAndSettle();
        expect(scroll.offset, reverse ? scroll.position.maxScrollExtent : 0);
        expect(embedded.offset, 60);
        resize(() => height = 100);
        await tester.pumpAndSettle();
        final natural = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const ValueKey('adaptive-page')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        natural.position.jumpTo(200);
        await tester.pumpAndSettle();
        embedded.jumpTo(80);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('adaptive-return')));
        await tester.pumpAndSettle();
        expect(natural.position.pixels, 0);
        expect(embedded.offset, 80);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'moving a page title into the phone bar remeasures its spacer in the same frame',
    (tester) async {
      late StateSetter change;
      late DPageHeaderGeometry geometry;
      var inBar = false;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              change = setState;
              return DPageHeaderHost(
                identity: 'page',
                titlesInBar: inBar,
                builder: (_, _, child) => child,
                child: DPageSurface.headed(
                  title: const Text('Latest topics'),
                  controls: const SizedBox(height: 40),
                  bodyBuilder: (_, header) {
                    geometry = header;
                    return CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(child: header.spacer),
                        const SliverToBoxAdapter(child: Text('First topic')),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ),
      );
      final before = tester.getTopLeft(find.text('First topic')).dy;
      change(() => inBar = true);
      await tester.pump();
      final after = tester.getTopLeft(find.text('First topic')).dy;
      expect(after, lessThan(before));
      expect(after, geometry.naturalExtent);
      await tester.pump();
      expect(tester.getTopLeft(find.text('First topic')).dy, after);
      change(() => inBar = false);
      await tester.pump();
      expect(tester.getTopLeft(find.text('First topic')).dy, before);
      expect(tester.takeException(), isNull);
    },
  );

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
  testWidgets('a returning sheet previews its previous title and metadata', (
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
                  builder: (context) {
                    final previous = DPageHeaderHost.previousTitleOf(context);
                    return Column(
                      children: [
                        Text(
                          previous?.title ?? 'No previous page',
                          key: const ValueKey('previous-title'),
                        ),
                        ?previous?.metadata,
                      ],
                    );
                  },
                ),
                Expanded(child: child),
              ],
            ),
            child: DPageSurface.headed(
              key: ValueKey(id),
              title: Text(title),
              titleMetadata: id == 'list' ? null : Text('Metadata for $title'),
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
    expect(find.text('Metadata for First topic'), findsOneWidget);
    await show('one', 'First topic', 'list');
    expect(previousTitle(), 'Latest topics');
    expect(find.text('Metadata for First topic'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'returning headers preserve their presentation until registered',
    (tester) async {
      var previousReturns = 0;
      var currentReturns = 0;
      DPageHeader? painted;
      final previous = DPageHeader(scrollToTop: () async => previousReturns++)
        ..update(
          titleText: 'Latest topics',
          retraction: .6,
          barOpacity: .8,
          layout: DPageHeaderLayout.compact,
          leading: const Text('Marker'),
        );
      final topic = DPageHeader(scrollToTop: () async {})
        ..update(
          titleText: 'Discussion',
          retraction: 1,
          layout: DPageHeaderLayout.standard,
        );
      final current = DPageHeader(scrollToTop: () async => currentReturns++)
        ..update(
          titleText: 'Updated latest topics',
          retraction: 0,
          barOpacity: 1,
          layout: DPageHeaderLayout.standard,
        );
      addTearDown(topic.dispose);
      addTearDown(current.dispose);

      Future<void> show(String identity, DPageHeader? header) =>
          tester.pumpWidget(
            MaterialApp(
              home: DPageHeaderHost(
                identity: identity,
                builder: (_, active, child) =>
                    ValueListenableBuilder<DPageHeader?>(
                      valueListenable: active,
                      child: child,
                      builder: (_, header, child) {
                        painted = header;
                        return Column(
                          children: [
                            Text(header?.titleText ?? 'No title'),
                            Expanded(child: child!),
                          ],
                        );
                      },
                    ),
                child: header == null
                    ? const SizedBox.expand()
                    : DPageHeaderScope(
                        key: ValueKey(identity),
                        header: header,
                        child: const SizedBox.expand(),
                      ),
              ),
            ),
          );

      await show('list', previous);
      await tester.pumpAndSettle();
      await show('topic', topic);
      expect(find.text('No title'), findsOneWidget);
      await tester.pumpAndSettle();
      previous.dispose();
      await show('list', current);
      expect(find.text('Latest topics'), findsOneWidget);
      expect(painted?.barOpacity, .8);
      expect(painted?.value, .6);
      expect(painted?.layout, DPageHeaderLayout.compact);
      expect((painted?.leading as Text).data, 'Marker');
      await painted!.scrollToTop();
      expect(previousReturns, 0);
      expect(currentReturns, 1);
      await tester.pump();
      expect(find.text('Updated latest topics'), findsOneWidget);
      expect(painted, same(current));
      await painted!.scrollToTop();
      expect(currentReturns, 2);

      await show('unknown', null);
      expect(find.text('No title'), findsOneWidget);
      await tester.pumpAndSettle();
      await show('list', null);
      expect(find.text('Updated latest topics'), findsOneWidget);
      await tester.pump();
      expect(find.text('No title'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
