import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/oneboxes/github/github.dart';
import 'package:discourse_native/src/shell/oneboxes/inline.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// What `InlineOneboxer` leaves in the cooked HTML once it has fetched a
/// title for a link that did not sit alone on its line.
const String prInline =
    '<a class="inline-onebox --gh-status-merged" '
    'href="https://github.com/discourse/discourse/pull/30604">'
    'Add the thing - Pull Request #30604 - discourse/discourse - GitHub</a>';

const String issueInline =
    '<a class="inline-onebox" '
    'href="https://github.com/discourse/discourse/issues/12345">'
    'Bug: the thing breaks - Issue #12345 - discourse/discourse - GitHub</a>';

const String topicInline =
    '<a class="inline-onebox" href="/t/some-topic/123/4">'
    'Some topic - post 4 by martin</a>';

const String genericInline =
    '<a class="inline-onebox" href="https://example.com/page">Example</a>';

dom.Element anchor(String source) => html.parse(source).querySelector('a')!;

void main() {
  group('inlineOneboxWidgetBuilder', () {
    test('claims only a.inline-onebox anchors', () {
      expect(inlineOneboxWidgetBuilder(anchor(prInline)), isNotNull);
      expect(
        inlineOneboxWidgetBuilder(anchor('<a href="/t/x/1">x</a>')),
        isNull,
      );
      expect(
        inlineOneboxWidgetBuilder(anchor('<a class="inline-onebox">x</a>')),
        isNull, // no href
      );
      expect(
        inlineOneboxWidgetBuilder(
          html.parse('<p>text</p>').querySelector('p')!,
        ),
        isNull,
      );
    });

    test('a pull request gets its status glyph, an issue does not', () {
      final pr =
          inlineOneboxWidgetBuilder(anchor(prInline))! as InlineOneboxChip;
      final issue =
          inlineOneboxWidgetBuilder(anchor(issueInline))! as InlineOneboxChip;

      final prSpans = (pr.child as TextSpan).children!;
      expect(prSpans, hasLength(2));
      expect(prSpans.first, isA<WidgetSpan>());
      expect((prSpans.last as TextSpan).text, contains('Add the thing'));

      expect((issue.child as TextSpan).children, isNull);
      expect((issue.child as TextSpan).text, contains('Bug: the thing'));
    });

    test('internal topic links and other domains stay chips and links', () {
      expect(
        inlineOneboxWidgetBuilder(anchor(topicInline)),
        isA<InlineOneboxChip>(),
      );
      // An inline onebox of some other domain is a link with its title —
      // exactly what the default anchor rendering already shows.
      expect(inlineOneboxWidgetBuilder(anchor(genericInline)), isNull);
    });
  });

  group('InlineOneboxChip', () {
    testWidgets('shows the glyph in the status color', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: inlineOneboxWidgetBuilder(anchor(prInline))!),
        ),
      );
      await tester.pump();

      final icon = tester.widget<DIcon>(
        find.byWidgetPredicate(
          (widget) => widget is DIcon && widget.icon == githubPrMergedIcon,
        ),
      );
      expect(icon.color, GithubPrStatus.merged.color);
      expect(
        find.textContaining('Add the thing', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('renders inside a paragraph of cooked HTML', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: CookedHtml(html: '<p>See $prInline for the details.</p>'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(InlineOneboxChip), findsOneWidget);
      expect(
        find.textContaining('for the details', findRichText: true),
        findsOneWidget,
      );
    });
  });
}
