import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/shell/cooked_details.dart';
import 'package:discourse_native/src/shell/cooked_document.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/cooked_table.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

String tableHtml(int rows) =>
    '<table><tr><th>Name</th><th>Value</th><th>Notes</th></tr>'
    '${List.generate(rows, (i) => '<tr><td>Member $i</td><td>${rows - i}</td><td><strong>Note $i</strong><br><a href="/t/example/12">link $i</a> &amp; <code>code $i</code></td></tr>').join()}</table>';

void main() {
  testWidgets('production cooked projection benchmark', (tester) async {
    final result = <String, Object?>{};
    final source = tableHtml(1000);
    final table = parser.parseFragment(source).querySelector('table')!;
    final document = CookedDocument(source);
    final content = document.bind((_, fragment, style) => Text(fragment.html));
    var checksum = 0;
    double measure(
      Widget? Function() run,
      int iterations, {
      bool cells = false,
    }) {
      final watch = Stopwatch()..start();
      for (var i = 0; i < iterations; i++) {
        final widget = run();
        expect(widget, isNotNull);
        checksum += cells
            ? consumeTableProjection(widget!)
            : widget!.key.hashCode;
      }
      watch.stop();
      return watch.elapsedMicroseconds / iterations;
    }

    for (var i = 0; i < 4; i++) {
      measure(
        () => cookedTableWidgetBuilder(table, content: content),
        4,
        cells: true,
      );
    }
    result['table_adapter_us'] = measure(
      () => cookedTableWidgetBuilder(table, content: content),
      12,
      cells: true,
    );
    result['table_parse_adapter_us'] = measure(
      () => cookedTableWidgetBuilder(
        parser.parseFragment(source).querySelector('table')!,
        content: content,
      ),
      8,
      cells: true,
    );
    final detailsSource =
        '<details><summary>Notes</summary>${List.filled(120, '<p>A <strong>rich</strong> paragraph &amp; <span class="spoiler">secret</span>.</p>').join()}<details><summary>Nested</summary><p>Nested body</p></details></details>';
    final details = parser
        .parseFragment(detailsSource)
        .querySelector('details')!;
    for (var i = 0; i < 4; i++) {
      measure(() => cookedDetailsWidgetBuilder(details, content: content), 10);
    }
    result['closed_details_adapter_us'] = measure(
      () => cookedDetailsWidgetBuilder(details, content: content),
      100,
    );
    result['closed_details_parse_adapter_us'] = measure(
      () => cookedDetailsWidgetBuilder(
        parser.parseFragment(detailsSource).querySelector('details')!,
        content: content,
      ),
      40,
    );

    _TrackedCell.clones = 0;
    _TrackedCell.serializations = 0;
    final tracked = parser.parseFragment(source).querySelector('table')!;
    for (final cell in tracked.querySelectorAll('th, td').toList()) {
      final replacement = _TrackedCell(cell.localName!);
      replacement.attributes.addAll(cell.attributes);
      replacement.nodes.addAll(cell.nodes.toList());
      cell.replaceWith(replacement);
    }
    expect(cookedTableWidgetBuilder(tracked, content: content), isNotNull);
    result['initial_cell_deep_clones'] = _TrackedCell.clones;
    result['initial_cell_html_serializations'] = _TrackedCell.serializations;

    final mountedSource = tableHtml(250);
    Future<void> mount(String html, Key key) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: CookedHtml(
                key: key,
                html: html,
                siteUrl: 'https://example.test',
                buildAsync: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await mount(mountedSource, const ValueKey('warmup'));
    final mountTimes = <int>[];
    for (var i = 0; i < 3; i++) {
      final watch = Stopwatch()..start();
      await mount(mountedSource, ValueKey(i));
      watch.stop();
      expect(find.text('Member 0', findRichText: true), findsOneWidget);
      expect(find.text('Member 249', findRichText: true), findsNothing);
      expect(find.byType(CookedHtml), findsNWidgets(76));
      mountTimes.add(watch.elapsedMicroseconds);
    }
    result['table_mount_us'] = mountTimes;
    final watch = Stopwatch()..start();
    await mount(mountedSource, const ValueKey(2));
    watch.stop();
    result['table_unchanged_rebuild_us'] = watch.elapsedMicroseconds;
    await mount(detailsSource, const ValueKey('details'));
    expect(find.text('Nested body', findRichText: true), findsNothing);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Nested'), findsOneWidget);
    expect(find.text('secret', findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
    result['checksum'] = checksum;
    result['failures'] = 0;
    result['rss_bytes_after'] = ProcessInfo.currentRss;
    final output = Platform.environment['COOKED_PROJECTION_OUTPUT'];
    if (output != null) File(output).writeAsStringSync(jsonEncode(result));
    stdout.writeln('COOKED_PROJECTION ${jsonEncode(result)}');
  }, skip: Platform.environment['COOKED_PROJECTION_OUTPUT'] == null);
}

class _TrackedCell extends dom.Element {
  _TrackedCell(super.localName) : super.tag();
  static int clones = 0;
  static int serializations = 0;
  @override
  dom.Element clone(bool deep) {
    clones++;
    return super.clone(deep);
  }

  @override
  String get innerHtml {
    serializations++;
    return super.innerHtml;
  }
}

int consumeTableProjection(Widget widget) {
  final table = widget as CookedTable;
  var checksum = 2166136261;
  void consume(CookedTableCell cell) {
    for (final value in [cell.text, cell.html, cell.copyText]) {
      for (final unit in value.codeUnits) {
        checksum = ((checksum ^ unit) * 16777619) & 0xffffffff;
      }
    }
  }

  for (final cell in table.headers) {
    consume(cell);
  }
  for (final row in table.rows) {
    for (final cell in row) {
      consume(cell);
    }
  }
  return checksum;
}
