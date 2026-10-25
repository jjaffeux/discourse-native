import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/progressive_html_mode.dart';
import 'package:discourse_native/src/shell/search_words.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/parser.dart' as html_parser;

String _large(String label, {int padding = 33 * 1024}) =>
    '<p data-label="$label" data-padding="${'x' * padding}">'
    'needle thread &amp; tail</p>';

void main() {
  test('small and filter-only inputs resolve without starting a worker', () {
    var changes = 0;
    final owner = SearchHtmlPreparation(
      onChanged: () => changes++,
      prepare: (_) => throw StateError('Unexpected worker'),
    );
    addTearDown(owner.dispose);
    expect(
      owner.resolve('<p>needle &amp; thread</p>', 'needle'),
      '<p><mark class="native-search-hit">needle</mark> &amp; thread</p>',
    );
    final large = _large('filter-only');
    expect(owner.resolve(large, 'category:support @sam'), large);
    expect(owner.resolve(large, ''), large);
    expect(changes, 0);
  });

  test('large shared cache hits resolve immediately', () {
    final html = _large('primed-cache');
    final expected = highlightSearchHtml(html, 'needle');
    final owner = SearchHtmlPreparation(
      onChanged: () => fail('Unexpected notification'),
      prepare: (_) => throw StateError('Unexpected worker'),
    );
    addTearDown(owner.dispose);
    expect(owner.resolve(html, 'needle'), expected);
  });

  test(
    'rebuilds share one worker and retain the current oversized result',
    () async {
      final html = _large('retained', padding: 256 * 1024);
      final gate = Completer<String>();
      var calls = 0;
      var changes = 0;
      final owner = SearchHtmlPreparation(
        onChanged: () => changes++,
        prepare: (request) {
          calls++;
          expect(request, (html: html, query: 'needle'));
          return gate.future;
        },
      );
      addTearDown(owner.dispose);
      expect(owner.resolve(html, 'needle'), isNull);
      expect(owner.resolve(html, 'needle'), isNull);
      expect(calls, 1);
      gate.complete('prepared retained');
      await Future<void>.delayed(Duration.zero);
      expect(changes, 1);
      expect(owner.resolve(html, 'needle'), 'prepared retained');
      expect(owner.resolve(html, 'needle'), 'prepared retained');
      expect(calls, 1);

      final nextGate = Completer<String>();
      final next = SearchHtmlPreparation(
        onChanged: () {},
        prepare: (_) => nextGate.future,
      );
      addTearDown(next.dispose);
      expect(next.resolve(html, 'needle'), isNull);
      nextGate.complete('prepared retained');
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'superseded body and query requests coalesce to the newest input',
    () async {
      final requests = <SearchHtmlRequest>[];
      final gates = <Completer<String>>[];
      var changes = 0;
      final owner = SearchHtmlPreparation(
        onChanged: () => changes++,
        prepare: (request) {
          requests.add(request);
          final gate = Completer<String>();
          gates.add(gate);
          return gate.future;
        },
      );
      addTearDown(owner.dispose);
      final first = _large('coalesce-first');
      final latest = _large('coalesce-latest');
      expect(owner.resolve(first, 'needle'), isNull);
      expect(owner.resolve(first, 'thread'), isNull);
      expect(owner.resolve(latest, 'tail'), isNull);
      expect(requests, [(html: first, query: 'needle')]);
      gates.first.complete('obsolete result');
      await Future<void>.delayed(Duration.zero);
      expect(changes, 0);
      expect(requests, [
        (html: first, query: 'needle'),
        (html: latest, query: 'tail'),
      ]);
      expect(owner.resolve(latest, 'tail'), isNull);
      gates.last.complete('latest result');
      await Future<void>.delayed(Duration.zero);
      expect(changes, 1);
      expect(owner.resolve(latest, 'tail'), 'latest result');
    },
  );

  test(
    'small replacement is immediate while an obsolete worker finishes',
    () async {
      final gate = Completer<String>();
      var changes = 0;
      var calls = 0;
      final owner = SearchHtmlPreparation(
        onChanged: () => changes++,
        prepare: (_) {
          calls++;
          return gate.future;
        },
      );
      addTearDown(owner.dispose);
      expect(owner.resolve(_large('replace-small'), 'needle'), isNull);
      const current = '<p>current thread</p>';
      const expected =
          '<p>current <mark class="native-search-hit">thread</mark></p>';
      expect(owner.resolve(current, 'thread'), expected);
      gate.complete('obsolete body');
      await Future<void>.delayed(Duration.zero);
      expect(owner.resolve(current, 'thread'), expected);
      expect(changes, 0);
      expect(calls, 1);
    },
  );

  test(
    'disposed preparations ignore completion and queued replacements',
    () async {
      final gate = Completer<String>();
      var calls = 0;
      final owner = SearchHtmlPreparation(
        onChanged: () => fail('Disposed owner notified'),
        prepare: (_) {
          calls++;
          return gate.future;
        },
      );
      expect(owner.resolve(_large('disposed-first'), 'needle'), isNull);
      expect(owner.resolve(_large('disposed-next'), 'thread'), isNull);
      owner.dispose();
      gate.complete('disposed result');
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
    },
  );

  test(
    'worker failure reports once and resolves to the current safe source',
    () async {
      final oldHandler = FlutterError.onError;
      final errors = <FlutterErrorDetails>[];
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = oldHandler);
      var changes = 0;
      var calls = 0;
      final owner = SearchHtmlPreparation(
        onChanged: () => changes++,
        prepare: (_) {
          calls++;
          return Future<String>.error(StateError('worker failed'));
        },
      );
      addTearDown(owner.dispose);
      final html = _large('failed');
      expect(owner.resolve(html, 'needle'), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(owner.resolve(html, 'needle'), html);
      expect(owner.resolve(html, 'needle'), html);
      expect(calls, 1);
      expect(changes, 1);
      expect(errors.single.exception, isA<StateError>());
    },
  );

  test('obsolete failure starts only the newest pending large input', () async {
    final oldHandler = FlutterError.onError;
    final errors = <FlutterErrorDetails>[];
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = oldHandler);
    final requests = <SearchHtmlRequest>[];
    final gates = <Completer<String>>[];
    var changes = 0;
    final owner = SearchHtmlPreparation(
      onChanged: () => changes++,
      prepare: (request) {
        requests.add(request);
        final gate = Completer<String>();
        gates.add(gate);
        return gate.future;
      },
    );
    addTearDown(owner.dispose);
    final first = _large('failure-first');
    final latest = _large('failure-latest');
    expect(owner.resolve(first, 'needle'), isNull);
    expect(owner.resolve(first, 'thread'), isNull);
    expect(owner.resolve(latest, 'tail'), isNull);
    gates.first.completeError(StateError('obsolete failure'));
    await Future<void>.delayed(Duration.zero);
    expect(requests, [
      (html: first, query: 'needle'),
      (html: latest, query: 'tail'),
    ]);
    expect(changes, 0);
    expect(errors, hasLength(1));
    gates.last.complete('latest after failure');
    await Future<void>.delayed(Duration.zero);
    expect(owner.resolve(latest, 'tail'), 'latest after failure');
    expect(changes, 1);
  });

  test('filter-only replacement never waits for an obsolete worker', () async {
    final gate = Completer<String>();
    var calls = 0;
    var changes = 0;
    final owner = SearchHtmlPreparation(
      onChanged: () => changes++,
      prepare: (_) {
        calls++;
        return gate.future;
      },
    );
    addTearDown(owner.dispose);
    final html = _large('replace-filter');
    expect(owner.resolve(html, 'needle'), isNull);
    expect(owner.resolve(html, 'category:support @sam'), html);
    gate.complete('obsolete marked HTML');
    await Future<void>.delayed(Duration.zero);
    expect(owner.resolve(html, 'category:support @sam'), html);
    expect(changes, 0);
    expect(calls, 1);
  });

  test(
    'expanded worker output exceeding the shared cache limit stays local',
    () async {
      final html = _large('oversized-output');
      final output = 'y' * (256 * 1024);
      final gate = Completer<String>();
      final owner = SearchHtmlPreparation(
        onChanged: () {},
        prepare: (_) => gate.future,
      );
      addTearDown(owner.dispose);
      expect(owner.resolve(html, 'needle'), isNull);
      gate.complete(output);
      await Future<void>.delayed(Duration.zero);
      expect(owner.resolve(html, 'needle'), output);
      var nextCalls = 0;
      final nextGate = Completer<String>();
      final next = SearchHtmlPreparation(
        onChanged: () {},
        prepare: (_) {
          nextCalls++;
          return nextGate.future;
        },
      );
      addTearDown(next.dispose);
      expect(next.resolve(html, 'needle'), isNull);
      expect(nextCalls, 1);
      nextGate.complete(output);
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'production worker returns complete escaped HTML from string input',
    () async {
      final html = _large(
        'real-worker',
        padding: 256 * 1024,
      ).replaceFirst('needle thread', 'needle <code>needle</code> thread');
      final expected = highlightSearchHtml(html, 'needle &');
      final ready = Completer<void>();
      final owner = SearchHtmlPreparation(onChanged: ready.complete);
      addTearDown(owner.dispose);
      expect(owner.resolve(html, 'needle &'), isNull);
      await ready.future;
      final output = owner.resolve(html, 'needle &');
      expect(output, expected);
      final fragment = html_parser.parseFragment(output!);
      expect(fragment.querySelector('code')!.innerHtml, 'needle');
      expect(
        fragment.querySelectorAll('mark.native-search-hit').map((e) => e.text),
        ['needle', '&'],
      );
      expect(
        fragment.querySelector('p')!.attributes['data-label'],
        'real-worker',
      );
    },
  );

  testWidgets(
    'CookedHtml prepares large searched bodies and replaces query marks',
    (tester) async {
      final html = _large('widget', padding: 256 * 1024);
      String? selected;
      final completions = <Future<void>>[];
      final completed = <Future<void>>{};
      Future<void> pump(String source, String query) => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DPageSurface(
            child: NotificationListener<HtmlBodyMountingNotification>(
              onNotification: (notification) {
                expect(notification.layoutPending, isTrue);
                completions.add(notification.completion);
                unawaited(
                  notification.completion.then<void>((_) {
                    completed.add(notification.completion);
                  }),
                );
                return false;
              },
              child: SelectionArea(
                onSelectionChanged: (content) => selected = content?.plainText,
                child: SearchWords(
                  query: query,
                  child: CookedHtml(html: source, buildAsync: false),
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          if (find
              .text('needle thread & tail', findRichText: true)
              .evaluate()
              .isNotEmpty) {
            return;
          }
        }
        fail('Searched body did not finish');
      }

      List<String> marks() => [
        for (final rich in tester.widgetList<RichText>(find.byType(RichText)))
          ..._markedText(rich.text),
      ];

      await pump(html, 'needle');
      expect(completions, hasLength(1));
      expect(completed, isEmpty);
      expect(find.byType(HtmlBodyLoading), findsOneWidget);
      expect(
        find.text('needle thread & tail', findRichText: true),
        findsNothing,
      );
      await settle();
      expect(marks(), ['needle']);
      expect(completed, contains(completions.first));
      await pump(html, 'thread');
      expect(completions, hasLength(2));
      expect(completed, isNot(contains(completions.last)));
      expect(
        find.text('needle thread & tail', findRichText: true),
        findsNothing,
      );
      await settle();
      expect(marks(), ['thread']);
      expect(completed, contains(completions.last));
      tester
          .state<SelectionAreaState>(find.byType(SelectionArea))
          .selectableRegion
          .selectAll(SelectionChangedCause.keyboard);
      await tester.pump();
      expect(selected?.trimRight(), 'needle thread & tail');
      await pump(_large('widget-dispose', padding: 256 * 1024), 'tail');
      expect(completions, hasLength(3));
      final disposedCompletion = completions.last;
      expect(completed, isNot(contains(disposedCompletion)));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(completed, contains(disposedCompletion));
      expect(find.byType(HtmlBodyLoading), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'large searched sliver bodies preserve pending and completed layout',
    (tester) async {
      final html = _large('sliver-widget', padding: 256 * 1024);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DPageSurface(
            child: CustomScrollView(
              slivers: [
                SearchWords(
                  query: 'needle',
                  child: CookedHtml(
                    html: html,
                    buildAsync: false,
                    renderMode: RenderMode.sliverList,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(HtmlBodyLoading, skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (find
            .text('needle thread & tail', findRichText: true)
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      expect(
        find.text('needle thread & tail', findRichText: true),
        findsOneWidget,
      );
      expect(find.byType(HtmlBodyLoading, skipOffstage: false), findsNothing);
      final rich = tester.widget<RichText>(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText() == 'needle thread & tail',
        ),
      );
      expect(_markedText(rich.text), ['needle']);
      expect(tester.takeException(), isNull);
    },
  );
}

Iterable<String> _markedText(InlineSpan span, [bool marked = false]) sync* {
  if (span is! TextSpan) return;
  final active =
      marked ||
      span.style?.backgroundColor != null ||
      span.style?.background != null;
  if (active && span.text != null && span.text!.isNotEmpty) yield span.text!;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _markedText(child, active);
  }
}
