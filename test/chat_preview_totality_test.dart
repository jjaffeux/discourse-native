import 'dart:convert';
import 'dart:math';

import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugins/chat/chat_preview.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pieces taken from what chat's dialect actually contains, so a generated
/// message is a plausible mangling of one somebody typed rather than arbitrary
/// text the engine would decline on its first check.
const List<String> _pieces = [
  '**',
  '*',
  '_',
  '__',
  '~~',
  '`',
  '``',
  '```',
  '```rb\n',
  '\n```',
  '[',
  ']',
  '(',
  ')',
  '!',
  '#',
  '@',
  ':',
  'a',
  'b',
  ' ',
  '\n',
  '\n\n',
  '<kbd>',
  '</kbd>',
  ':smile:',
  '@sam',
  '#tag',
  'https://e.com',
  '[text](https://e.com)',
  '> ',
  '# ',
  '\r',
  '\t',
  '|',
  '-',
  '\\',
  '\u{1F600}',
  '\u{00e9}',
];

/// Every node kind a raw message can produce. [ChatPreviewImage] is not one of
/// them — it comes only from a trusted GIF seed, which is not raw text.
const List<String> _kinds = [
  'ChatPreviewText',
  'ChatPreviewLineBreak',
  'ChatPreviewSyntax',
  'ChatPreviewCodeBlock',
];

/// The projector is never authoritative — a caller replaces its document with
/// the server's cooked body the moment one arrives — so it answers a message
/// it cannot read with the raw source rather than by throwing. That safety net
/// is also what would hide a defect: a projector that crashed and a projector
/// that recognised nothing produce the same screen.
///
/// `internalFailure` is the reason that separates them. The engine raises it
/// both from its own `catch` and from `_fullyAccountsFor`, which is the
/// document's half of the invariant the composer's own projections hold to:
/// every source character accounted for, exactly once, in order.
void main() {
  test('a message the projector cannot read is declined, never mishandled', () {
    final engine = ChatPreviewEngine();
    final random = Random(90210);
    final declined = <ChatPreviewFallbackReason, String>{};
    final reached = <String>{};
    var projected = 0;

    for (var round = 0; round < 6000; round++) {
      final buffer = StringBuffer();
      for (var piece = 0; piece < random.nextInt(30); piece++) {
        buffer.write(_pieces[random.nextInt(_pieces.length)]);
      }
      final raw = buffer.toString();
      final result = engine.project(
        ChatPreviewRequest(raw: raw, siteConfig: const SiteConfig.unknown()),
      );

      if (result is SourceFallback) {
        declined.putIfAbsent(result.reason, () => raw);
        expect(result.raw, raw, reason: jsonEncode(raw));
        continue;
      }

      projected++;
      final document = (result as ProjectedPreview).document;
      expect(document.source, raw, reason: jsonEncode(raw));

      var previousEnd = 0;
      for (final node in document.nodes) {
        reached.add(node.runtimeType.toString());
        expect(
          node.range.start,
          greaterThanOrEqualTo(previousEnd),
          reason: 'ranges overlap in ${jsonEncode(raw)}',
        );
        expect(
          node.range.end,
          greaterThan(node.range.start),
          reason: 'empty range in ${jsonEncode(raw)}',
        );
        expect(
          node.range.end,
          lessThanOrEqualTo(raw.length),
          reason: 'range past the source in ${jsonEncode(raw)}',
        );
        previousEnd = node.range.end;
      }
    }

    expect(
      declined.keys,
      isNot(contains(ChatPreviewFallbackReason.internalFailure)),
      reason:
          'raised on ${jsonEncode(declined[ChatPreviewFallbackReason.internalFailure])}',
    );
    // A corpus that stopped reaching the projector, or one kind of node in it,
    // would leave this passing while testing nothing. The seed is fixed, so
    // these are not a race.
    expect(projected, greaterThan(1000));
    expect(reached, unorderedEquals(_kinds));
  });
}
