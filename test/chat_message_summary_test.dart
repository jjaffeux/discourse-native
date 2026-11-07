import 'package:discourse_native/src/plugins/chat/chat_message_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'regression fifth: chat summaries never truncate part of a grapheme',
    () {
      expect(
        chatMessageSummary(raw: '${'a' * 239}e\u0301tail'),
        '${'a' * 239}e\u0301…',
      );
      expect(
        chatMessageSummary(raw: '${'a' * 239}👩‍💻tail'),
        '${'a' * 239}👩‍💻…',
      );
      expect(
        chatMessageSummary(cooked: '<!--${'x' * 19992}-->e\u0301tail'),
        isNull,
      );
    },
  );

  test('regression fifth: inbox summaries separate headings and table cells', () {
    expect(
      chatMessageSummary(
        cooked:
            '<h2>Results</h2><table><tr><td>Sam</td><td>2</td></tr></table><p>Done</p>',
      ),
      'Results Sam 2 Done',
    );
  });

  test(
    'turns an excerpt into one line while preserving emoji and entities',
    () {
      expect(
        chatMessageSummary(
          excerpt:
              '<p>Ready &amp; reviewed <img alt=":wave:" src="emoji.png"></p>'
              '<p>Ship it<br>today.</p>',
          cooked: '<p>Older content</p>',
        ),
        'Ready & reviewed :wave: Ship it today.',
      );
    },
  );

  test('uses cooked content, raw text, and attachments when needed', () {
    expect(chatMessageSummary(cooked: '<p><b>Hello</b></p>'), 'Hello');
    expect(chatMessageSummary(raw: 'Hello\n  there'), 'Hello there');
    expect(chatMessageSummary(hasUploads: true), 'Attachment');
    expect(chatMessageSummary(), isNull);
  });

  test('deleted content never appears in a summary', () {
    expect(
      chatMessageSummaryFromJson({
        'excerpt': 'Removed content',
        'message': 'Removed content',
        'deleted_at': '2026-09-08T10:00:00Z',
      }),
      'Message deleted',
    );
  });

  test('bounds long summaries without splitting a Unicode code point', () {
    final summary = chatMessageSummary(raw: '😀' * 500)!;
    expect(summary.runes.length, 241);
    expect(summary, '${'😀' * 240}…');
  });
}
