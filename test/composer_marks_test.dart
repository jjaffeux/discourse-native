import 'package:discourse_native/src/shell/composer_marks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

/// What the composer actually has to guarantee: markdown in, the same markdown
/// out. The field's text is the payload, so anything else silently rewrites
/// what someone wrote.
void expectRoundTrip(String markdown) {
  expect(
    discourseDocumentToMarkdown(discourseMarkdownToDocument(markdown)),
    markdown,
    reason: 'round trip changed the source',
  );
  expect(richModeAvailable(markdown), isTrue);
}

/// Writes a selection as `text` with the selected part between brackets, so a
/// failure reads as what someone would see rather than as a pair of offsets.
String showSelection(TextEditingValue value) {
  final s = value.selection;
  if (!s.isValid) return value.text;
  return '${value.text.substring(0, s.start)}[${value.text.substring(s.start, s.end)}]'
      '${value.text.substring(s.end)}';
}

TextEditingValue selected(String annotated) {
  final start = annotated.indexOf('[');
  final end = annotated.indexOf(']') - 1;
  final text = annotated.replaceAll('[', '').replaceAll(']', '');
  return TextEditingValue(
    text: text,
    selection: TextSelection(baseOffset: start, extentOffset: end),
  );
}

void main() {
  group('toggleMarkdownMark', () {
    void expectToggle(String before, String marker, String after) {
      expect(
        showSelection(toggleMarkdownMark(selected(before), marker)),
        after,
        reason: '$before + "$marker"',
      );
    }

    test('wraps a selection, keeping the selection on the text', () {
      // Markers land outside the selection so a second mark composes onto the
      // same words rather than onto the first mark's asterisks.
      expectToggle('say [hello] there', '**', 'say **[hello]** there');
      expectToggle('say [hello] there', '*', 'say *[hello]* there');
    });

    test('unwraps when the markers are inside the selection', () {
      expectToggle('say [**hello**] there', '**', 'say [hello] there');
    });

    test(
      'unwraps when the markers are outside it, as a double-click gives',
      () {
        expectToggle('say **[hello]** there', '**', 'say [hello] there');
      },
    );

    test('puts the caret between the markers when nothing is selected', () {
      final result = toggleMarkdownMark(
        const TextEditingValue(
          text: 'say ',
          selection: TextSelection.collapsed(offset: 4),
        ),
        '**',
      );
      expect(result.text, 'say ****');
      expect(result.selection.baseOffset, 6);
      expect(result.selection.isCollapsed, isTrue);
    });

    test('does not mistake bold for a pair of italics', () {
      // Pressing italic on bold text adds a mark; it does not peel one off.
      expectToggle('say [**hello**] there', '*', 'say *[**hello**]* there');
      // Which is what makes bold-then-italic reach ***hello***.
      expectToggle('say **[hello]** there', '*', 'say ***[hello]*** there');
    });

    test('appends at the end when there is no selection at all', () {
      final result = toggleMarkdownMark(
        const TextEditingValue(text: 'say'),
        '**',
      );
      expect(result.text, 'say****');
    });

    test('is its own inverse', () {
      for (final marker in ['**', '*']) {
        const start = 'say [hello] there';
        final once = toggleMarkdownMark(selected(start), marker);
        expect(showSelection(toggleMarkdownMark(once, marker)), start);
      }
    });
  });

  group('inline HTML', () {
    test('keeps the tags Discourse keeps', () {
      for (final tag in allowedInlineTags) {
        expectRoundTrip('press <$tag>x</$tag> now');
      }
    });

    test('carries the tag as an attribution rather than as text', () {
      final doc = discourseMarkdownToDocument('press <kbd>Esc</kbd> now');
      final node = doc.first as TextNode;

      // The markup is gone from the text — that is the whole point of rich
      // mode — but recoverable from the attribution.
      expect(node.text.toPlainText(), 'press Esc now');
      expect(
        node.text
            .getAllAttributionsAt(6)
            .whereType<HtmlInlineAttribution>()
            .single
            .tag,
        'kbd',
      );
    });

    test('nests, which one attribution per tag is what allows', () {
      expectRoundTrip('<mark>look <kbd>here</kbd></mark>');
    });
  });

  group('mentions', () {
    test('round-trip, because the text is left as written', () {
      expectRoundTrip('hey @sam and @martin.j');
    });

    test('are recognised as people', () {
      final doc = discourseMarkdownToDocument('hey @sam');
      final node = doc.first as TextNode;

      expect(node.text.toPlainText(), 'hey @sam');
      expect(
        node.text
            .getAllAttributionsAt(5)
            .whereType<MentionAttribution>()
            .single
            .username,
        'sam',
      );
    });
  });

  group('ordinary markdown', () {
    test('survives the constructs a reply is mostly made of', () {
      expectRoundTrip('**bold** and *italic* and `code`');
      expectRoundTrip('~~struck~~');
      expectRoundTrip('# A heading');
      expectRoundTrip('> quoted');
      expectRoundTrip('plain text with no marks at all');
    });

    test('marks close in the order they opened', () {
      expectRoundTrip('**bold with *italic* inside**');
    });
  });

  group('richModeAvailable', () {
    test('is true for an empty composer', () {
      expect(richModeAvailable(''), isTrue);
      expect(richModeAvailable('   '), isTrue);
    });

    test('is false for markdown the model would rewrite', () {
      // A table has no representation here yet, so rich mode must decline it
      // rather than quietly reformat someone's post.
      const table = '| a | b |\n| - | - |\n| 1 | 2 |';
      expect(
        richModeAvailable(table) &&
            discourseDocumentToMarkdown(discourseMarkdownToDocument(table)) !=
                table,
        isFalse,
        reason: 'either it round-trips, or rich mode declines it',
      );
    });

    test('never claims a post is safe when the round trip changed it', () {
      // The guard and the round trip are the same question, so they cannot
      // disagree — this is what makes the toggle safe to offer.
      for (final source in [
        'press <kbd>Esc</kbd>',
        '| a |\n| - |',
        '```ruby\nputs 1\n```',
        '* one\n* two',
        'hey @sam',
      ]) {
        final unchanged =
            discourseDocumentToMarkdown(discourseMarkdownToDocument(source)) ==
            source;
        expect(richModeAvailable(source), unchanged, reason: source);
      }
    });
  });
}
