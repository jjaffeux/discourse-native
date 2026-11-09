import 'dart:io';

import 'package:discourse_native/src/shell/code_block.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mounts cooked markup the way a post body sits in a topic: selectable and
/// inside a vertical scroll view.
Future<void> _pumpPost(
  WidgetTester tester,
  String html, {
  ThemeData? theme,
  ScrollController? scroll,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(
        body: SelectionArea(
          child: SingleChildScrollView(
            controller: scroll,
            child: CookedHtml(html: html, buildAsync: false),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

({int elements, int renderObjects}) _census() {
  var elements = 0;
  var renderObjects = 0;
  void visit(Element element) {
    elements++;
    if (element is RenderObjectElement) renderObjects++;
    element.visitChildren(visit);
  }

  visit(find.byType(CookedHtml).evaluate().first);
  return (elements: elements, renderObjects: renderObjects);
}

void _proof(String slug, String metric, Object value) =>
    stdout.writeln('PERF_PROOF $slug $metric=$value');

/// What core cooks for `## Title`: an empty link carrying the destination.
String _heading(String slug, String title) =>
    '<h2><a name="$slug" class="anchor" href="#$slug"></a>$title</h2>';

/// What core cooks for a Markdown fence, with its closing newline.
String _fence(List<String> lines) =>
    '<pre data-code-wrap="ruby"><code class="lang-ruby">'
    '${lines.join('\n')}\n</code></pre>';

List<String> _ruby(int count) => [
  for (var index = 0; index < count; index++)
    '  def method_$index(arg) = arg + $index',
];

void main() {
  group('code blocks', () {
    testWidgets('a fence costs one paragraph rather than a row per line, and '
        'still shows and copies every line', (tester) async {
      final messages =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? clipboard;
      messages.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messages.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await _pumpPost(tester, _fence(_ruby(10)));
      final ten = _census();
      final lines = _ruby(30);
      await _pumpPost(tester, _fence(lines));
      final thirty = _census();

      final renderObjects = (thirty.renderObjects - ten.renderObjects) / 20;
      final elements = (thirty.elements - ten.elements) / 20;
      _proof('cooked-code-lines', 'render_objects_per_line', renderObjects);
      _proof('cooked-code-lines', 'elements_per_line', elements);
      _proof(
        'cooked-code-lines',
        'render_objects_30_line_fence',
        thirty.renderObjects,
      );
      expect(renderObjects, 0);

      expect(
        tester.getSize(find.byType(CodeBlock)).height,
        16 + 48 + 4 + 30 * 21 + 12,
      );
      for (final line in lines) {
        expect(
          find.textContaining(line.trimLeft(), findRichText: true),
          findsOneWidget,
        );
      }
      await tester.tap(find.byKey(const ValueKey('code-block-copy')));
      await tester.pump();
      expect(clipboard, lines.join('\n'));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a selection across a fence keeps its line breaks', (
      tester,
    ) async {
      SelectedContent? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SelectionArea(
              onSelectionChanged: (content) => selected = content,
              child: CookedHtml(
                html: _fence(['first', '', '  third']),
                buildAsync: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      tester
          .state<SelectableRegionState>(find.byType(SelectableRegion))
          .selectAll(SelectionChangedCause.keyboard);
      await tester.pump();

      expect(selected?.plainText, 'first\n\n  third');
    });

    testWidgets('blank lines keep their height, also at the end of a fence', (
      tester,
    ) async {
      await _pumpPost(tester, _fence(['first', '', 'third', '']));
      expect(
        tester.getSize(find.byType(CodeBlock)).height,
        16 + 48 + 4 + 4 * 21 + 12,
      );
    });
  });

  group('headings', () {
    testWidgets('an empty heading anchor costs no link machinery, and still '
        'receives navigation', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final fillers = List.filled(40, '<p>Filler paragraph.</p>').join();
      final sections = [
        for (var index = 0; index < 10; index++)
          '${_heading('section-$index', 'Section $index')}$fillers',
      ].join();

      await _pumpPost(
        tester,
        '<p><a href="#section-9">Jump to the end</a></p>$sections',
        scroll: scroll,
      );
      await tester.pumpAndSettle();

      final withHeadings = _census();
      await _pumpPost(
        tester,
        '<p><a href="#section-9">Jump to the end</a></p>'
        '${[for (var index = 0; index < 10; index++) '<h2>Section $index</h2>$fillers'].join()}',
        scroll: scroll,
      );
      await tester.pumpAndSettle();
      final withoutAnchors = _census();

      final perHeading =
          (withHeadings.renderObjects - withoutAnchors.renderObjects) / 10;
      final elementsPerHeading =
          (withHeadings.elements - withoutAnchors.elements) / 10;
      _proof('cooked-heading-anchor', 'render_objects_per_heading', perHeading);
      _proof(
        'cooked-heading-anchor',
        'elements_per_heading',
        elementsPerHeading,
      );
      expect(perHeading, lessThanOrEqualTo(4));

      await _pumpPost(
        tester,
        '<p><a href="#section-9">Jump to the end</a></p>$sections',
        scroll: scroll,
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      final jump = tester.renderObject<RenderParagraph>(
        find.text('Jump to the end', findRichText: true),
      );
      await tester.tapAt(jump.localToGlobal(const Offset(8, 8)));
      await tester.pumpAndSettle();

      expect(scroll.offset, greaterThan(0));
      final section = find.textContaining('Section 9', findRichText: true);
      expect(section, findsOneWidget);
      expect(
        tester.getRect(section).top,
        inInclusiveRange(0, tester.view.physicalSize.height),
      );
    });
  });
}
