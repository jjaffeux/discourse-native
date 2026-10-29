import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
// ignore: implementation_imports
import 'package:flutter_widget_from_html_core/src/internal/core_build_tree.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

class _RecordingFactory extends WidgetFactory {
  final events = <String>[];
  bool disposed = false;
  String owner = 'original';

  @override
  Widget? customWidgetBuilder(dom.Element element) {
    if (disposed) {
      throw StateError('Callback after factory disposal');
    }
    events.add('$owner:visit:${element.localName}:${element.id}');
    if (element.localName == 'test-replacement') {
      return const Text('replacement');
    }
    return super.customWidgetBuilder(element);
  }

  @override
  void parse(BuildTree tree) {
    super.parse(tree);
    events.add('$owner:parse:${tree.element.localName}:${tree.element.id}');
    tree.register(BuildOp(onParsed: (parsed) {
      events.add('$owner:parsed:${tree.element.localName}:${tree.element.id}');
      return parsed;
    }));
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _YieldProbe {
  bool eventRan = false;
  bool? eventRanAtTail;

  Widget? visit(dom.Element element) {
    if (element.id == 'start') {
      Timer.run(() => eventRan = true);
    }
    if (element.id == 'tail') {
      eventRanAtTail = eventRan;
    }
    return null;
  }
}

String _largeBody(String prefix) =>
    '<div>${List.generate(2048, (i) => '<p id="${i == 0 ? 'start' : i == 2047 ? 'tail' : 'item$i'}">$prefix$i</p>').join()}</div>';

CoreBuildTree _tree(WidgetFactory factory) => CoreBuildTree.root(
      inheritanceResolvers: InheritanceResolvers(),
      wf: factory,
    );

Widget _host(Widget child, {ScrollController? controller}) => MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 14, color: Color(0xff000000)),
          child: SizedBox(
            width: 400,
            height: 300,
            child: SingleChildScrollView(controller: controller, child: child),
          ),
        ),
      ),
    );

Future<void> _pumpUntil(WidgetTester tester, bool Function() complete) async {
  for (var i = 0; i < 1000 && !complete(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(complete(), isTrue, reason: 'HTML body did not complete');
}

Future<void> _pumpWithoutTimersUntil(
  WidgetTester tester,
  bool Function() complete,
) async {
  for (var i = 0; i < 1000 && !complete(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump();
  }
  expect(complete(), isTrue);
}

Iterable<Object> _runs(InlineSpan span) sync* {
  if (span is TextSpan) {
    if (span.text != null) {
      yield (
        span.text,
        span.style?.color,
        span.style?.fontWeight,
        span.style?.fontStyle,
        span.style?.fontFamily,
        span.style?.fontSize,
      );
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      yield* _runs(child);
    }
  } else {
    yield span.runtimeType;
  }
}

void main() {
  test('retired conversions never visit the DOM', () async {
    final factory = _RecordingFactory();
    final tree = _tree(factory);
    final complete = await tree.addBitsFromNodesAsync(
      parser.parseFragment('<p>retired</p>').nodes,
      isCurrent: () => false,
    );
    expect(complete, isFalse);
    expect(factory.events, isEmpty);
    expect(tree.children, isEmpty);
    factory.dispose();
  });

  testWidgets(
      'nested retirement leaves the successor factory and root untouched',
      (tester) async {
    final factory = _RecordingFactory();
    await tester.pumpWidget(_host(HtmlWidget(
      '',
      buildAsync: false,
      factoryBuilder: () => factory,
    )));
    await tester.runAsync(() async {
      final original = _tree(factory);
      final source =
          '<div>${List.generate(2048, (i) => '<p id="old$i">old$i</p>').join()}</div>';
      final nodes = parser.parseFragment(source).nodes;
      var current = true;
      late CoreBuildTree successor;
      Timer.run(() {
        expect(factory.events, isNotEmpty);
        current = false;
        factory.owner = 'successor';
        successor = _tree(factory)
          ..addBitsFromNodes(parser.parseFragment('<p id="new">new</p>').nodes);
      });
      final complete = await original.addBitsFromNodesAsync(
        nodes,
        isCurrent: () => current,
      );
      expect(complete, isFalse);
      expect(original.children, isEmpty);
      expect(successor.children, isNotEmpty);
      final successorIndex = factory.events.indexWhere(
        (event) => event.startsWith('successor:'),
      );
      expect(successorIndex, greaterThan(0));
      expect(
        factory.events.skip(successorIndex),
        everyElement(isNot(contains('old'))),
      );
      expect(factory.events, isNot(contains('original:visit:p:old2047')));
      final afterRetirement = List<String>.of(factory.events);
      await Future<void>.delayed(Duration.zero);
      expect(factory.events, afterRetirement);
    });
  });

  testWidgets(
      'async conversion preserves nested CSS, tables, code and callbacks',
      (tester) async {
    const html = '<div style="color: red">'
        '<p id="first">one <b>two <i>three</i></b> four</p>'
        '<test-replacement><b id="hidden">hidden</b></test-replacement>'
        '<table><tr><td>outer<table><tr><td>inner</td></tr></table></td>'
        '<td><span style="font-style: italic">cell</span></td></tr></table>'
        '<pre><code>  first\n second  </code></pre>'
        '<p id="destination"><a href="#first">tail</a></p></div>';
    List<Object>? expectedRuns;
    List<String>? expectedEvents;
    Size? expectedSize;
    for (final async in [false, true]) {
      final factory = _RecordingFactory();
      final key = GlobalKey<HtmlWidgetState>();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_host(HtmlWidget(
        html,
        key: key,
        buildAsync: async,
        factoryBuilder: () => factory,
      )));
      await _pumpUntil(
        tester,
        () => find.text('tail', findRichText: true).evaluate().isNotEmpty,
      );
      final texts = tester.widgetList<RichText>(find.byType(RichText));
      final runs = [for (final text in texts) ..._runs(text.text)];
      final size = tester.getSize(find.byKey(key));
      expect(find.text('replacement'), findsOneWidget);
      expect(factory.events.any((event) => event.contains('hidden')), isFalse);
      expect(texts.map((text) => text.text.toPlainText()).join(),
          contains('inner'));
      if (expectedRuns == null) {
        expectedRuns = runs;
        expectedEvents = List<String>.of(factory.events);
        expectedSize = size;
      } else {
        expect(runs, expectedRuns);
        expect(factory.events, expectedEvents);
        expect(size, expectedSize);
      }
      final anchored = key.currentState!.scrollToAnchor('destination');
      await tester.pumpAndSettle();
      expect(await anchored, isTrue);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('retains a completed body and links during replacement parsing',
      (tester) async {
    final key = GlobalKey<HtmlWidgetState>();
    final urls = <String>[];
    Widget body(String html) => _host(HtmlWidget(
          html,
          key: key,
          buildAsync: true,
          onTapUrl: (url) {
            urls.add(url);
            return true;
          },
          onLoadingBuilder: (context, element, progress) =>
              const SizedBox(key: ValueKey('loading')),
        ));
    await tester.pumpWidget(
        body('<p><a href="https://example.com/old">previous body</a></p>'));
    await _pumpUntil(
      tester,
      () =>
          find.text('previous body', findRichText: true).evaluate().isNotEmpty,
    );
    await tester.tapAt(
        tester.getTopLeft(find.text('previous body', findRichText: true)) +
            const Offset(4, 7));
    expect(urls, ['https://example.com/old']);
    final giant =
        '<div>${List.generate(2048, (i) => '<p>pending$i</p>').join()}</div>';
    await tester.pumpWidget(body(giant));
    expect(find.text('previous body', findRichText: true), findsOneWidget);
    expect(find.byKey(const ValueKey('loading')), findsNothing);
    await tester.pumpWidget(body(
        '<p id="new-anchor"><a href="https://example.com/new">successor body</a></p>'));
    await _pumpUntil(
      tester,
      () =>
          find.text('successor body', findRichText: true).evaluate().isNotEmpty,
    );
    expect(find.text('pending2047', findRichText: true), findsNothing);
    await tester.tapAt(
        tester.getTopLeft(find.text('successor body', findRichText: true)) +
            const Offset(4, 7));
    expect(urls, ['https://example.com/old', 'https://example.com/new']);
    final anchored = key.currentState!.scrollToAnchor('new-anchor');
    await tester.pumpAndSettle();
    expect(await anchored, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposal prevents pending async work from using the factory',
      (tester) async {
    final factory = _RecordingFactory();
    final source =
        '<div>${List.generate(2048, (i) => '<p>pending$i</p>').join()}</div>';
    await tester.pumpWidget(_host(HtmlWidget(
      source,
      buildAsync: true,
      factoryBuilder: () => factory,
    )));
    await tester.pumpWidget(const SizedBox.shrink());
    final events = List<String>.of(factory.events);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(factory.disposed, isTrue);
    expect(factory.events, events);
    expect(tester.takeException(), isNull);
  });
  for (final dispose in [false, true]) {
    testWidgets(
        'retires a State-owned factory during conversion, dispose=$dispose',
        (tester) async {
      final factory = _RecordingFactory();
      final key = GlobalKey<HtmlWidgetState>();
      Widget body(String html) => _host(HtmlWidget(
            html,
            key: key,
            buildAsync: true,
            factoryBuilder: () => factory,
          ));
      final source =
          '<div>${List.generate(2048, (i) => '<p id="old$i">old$i</p>').join()}</div>';
      await tester.pumpWidget(body(source));
      await _pumpWithoutTimersUntil(tester, () => factory.events.isNotEmpty);
      expect(factory.events, contains('original:visit:p:old0'));
      expect(factory.events, isNot(contains('original:visit:p:old2047')));
      if (dispose) {
        await tester.pumpWidget(const SizedBox.shrink());
        expect(factory.disposed, isTrue);
      } else {
        factory.owner = 'successor';
        await tester.pumpWidget(body('<p id="new-anchor">successor</p>'));
        await _pumpWithoutTimersUntil(
          tester,
          () =>
              find.text('successor', findRichText: true).evaluate().isNotEmpty,
        );
        expect(factory.events, contains('successor:visit:p:new-anchor'));
      }
      final afterRetirement = List<String>.of(factory.events);
      await tester.pump(Duration.zero);
      await tester.pumpAndSettle();
      expect(factory.events, afterRetirement);
      expect(find.text('old2047', findRichText: true), findsNothing);
      expect(tester.takeException(), isNull);
      if (!dispose) {
        final anchored = key.currentState!.scrollToAnchor('new-anchor');
        await tester.pumpAndSettle();
        expect(await anchored, isTrue);
      }
    });
  }

  testWidgets('callback errors after a yield reach the error builder',
      (tester) async {
    final key = GlobalKey<HtmlWidgetState>();
    var scheduled = false;
    var eventRan = false;
    Object? caught;
    final source =
        '<div>${List.generate(2048, (i) => '<p id="item$i">item$i</p>').join()}</div>';
    await tester.pumpWidget(_host(HtmlWidget(
      source,
      key: key,
      buildAsync: true,
      customWidgetBuilder: (element) {
        if (!scheduled) {
          scheduled = true;
          Timer.run(() => eventRan = true);
        }
        if (element.id == 'item1536') {
          expect(eventRan, isTrue);
          throw StateError('conversion callback failed');
        }
        return null;
      },
      onErrorBuilder: (_, element, error) {
        caught = error;
        return const Text('conversion failed');
      },
    )));
    await _pumpUntil(
      tester,
      () => find.text('conversion failed').evaluate().isNotEmpty,
    );
    expect(caught, isA<StateError>());
    expect('$caught', contains('conversion callback failed'));
    final recovered = _YieldProbe();
    await tester.pumpWidget(_host(HtmlWidget(
      _largeBody('recovered'),
      key: key,
      buildAsync: true,
      customWidgetBuilder: recovered.visit,
    )));
    await _pumpUntil(
      tester,
      () =>
          find.text('recovered2047', findRichText: true).evaluate().isNotEmpty,
    );
    expect(recovered.eventRanAtTail, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retained async rebuilds preserve scroll extent and offset',
      (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final factory = _RecordingFactory();
    final key = GlobalKey<HtmlWidgetState>();
    final source = List.generate(80, (i) => '<p>paragraph$i</p>').join();
    Widget body(int revision) => _host(
        HtmlWidget(
          source,
          key: key,
          buildAsync: true,
          factoryBuilder: () => factory,
          rebuildTriggers: [revision],
        ),
        controller: scroll);
    await tester.pumpWidget(body(0));
    await _pumpUntil(
      tester,
      () => find.text('paragraph79', findRichText: true).evaluate().isNotEmpty,
    );
    scroll.jumpTo(500);
    await tester.pump();
    final offset = scroll.offset;
    final extent = scroll.position.maxScrollExtent;
    final events = factory.events.length;
    await tester.pumpWidget(body(1));
    expect(scroll.offset, offset);
    expect(scroll.position.maxScrollExtent, extent);
    expect(find.text('paragraph79', findRichText: true), findsOneWidget);
    await _pumpWithoutTimersUntil(tester, () => factory.events.length > events);
    expect(scroll.offset, offset);
    expect(scroll.position.maxScrollExtent, extent);
    expect(tester.takeException(), isNull);
  });
  for (final initialAsync in [false, true]) {
    for (final empty in [false, true]) {
      testWidgets(
          'completed replacements remain atomic, initialAsync=$initialAsync, empty=$empty',
          (tester) async {
        final key = GlobalKey<HtmlWidgetState>();
        final initial = _YieldProbe();
        Widget body(String html, bool async, _YieldProbe probe) =>
            _host(HtmlWidget(
              html,
              key: key,
              buildAsync: async,
              customWidgetBuilder: probe.visit,
            ));
        await tester
            .pumpWidget(body(_largeBody('initial'), initialAsync, initial));
        await _pumpUntil(
            tester,
            () => find
                .text('initial2047', findRichText: true)
                .evaluate()
                .isNotEmpty);
        expect(initial.eventRanAtTail, initialAsync);
        if (empty) {
          await tester.pumpWidget(body('', true, _YieldProbe()));
          await _pumpUntil(
              tester,
              () => find
                  .text('initial2047', findRichText: true)
                  .evaluate()
                  .isEmpty);
        }
        final replacement = _YieldProbe();
        await tester
            .pumpWidget(body(_largeBody('replacement'), true, replacement));
        await _pumpUntil(
            tester,
            () => find
                .text('replacement2047', findRichText: true)
                .evaluate()
                .isNotEmpty);
        expect(replacement.eventRanAtTail, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('an initially empty renderer cooperates on its first body',
      (tester) async {
    final key = GlobalKey<HtmlWidgetState>();
    await tester.pumpWidget(_host(HtmlWidget('', key: key, buildAsync: true)));
    await tester.pumpAndSettle();
    final probe = _YieldProbe();
    await tester.pumpWidget(_host(HtmlWidget(
      _largeBody('first'),
      key: key,
      buildAsync: true,
      customWidgetBuilder: probe.visit,
    )));
    await _pumpUntil(tester,
        () => find.text('first2047', findRichText: true).evaluate().isNotEmpty);
    expect(probe.eventRanAtTail, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short asynchronous body leaves its frame but not the isolate',
      (tester) async {
    await tester.pumpWidget(_host(HtmlWidget(
      '<p>short <b>reply</b></p>',
      buildAsync: true,
    )));
    expect(find.text('short reply', findRichText: true), findsNothing);
    // Only the test clock advances: work sent to another isolate would never
    // come back under it.
    await tester.pump();
    expect(find.text('short reply', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
