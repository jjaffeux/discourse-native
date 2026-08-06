import 'dart:convert';

import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('encode', () {
    test('uses the web composer field names, so a draft is portable', () {
      final json =
          jsonDecode(
                const ComposerDraft(
                  reply: 'Half a thought',
                  replyToPostNumber: 4,
                  replyToUsername: 'sam',
                  typingTime: Duration(seconds: 9),
                  composerTime: Duration(seconds: 30),
                ).encode(),
              )
              as Map<String, dynamic>;

      expect(json['reply'], 'Half a thought');
      expect(json['action'], 'reply');
      expect(json['archetypeId'], 'regular');
      expect(json['reply_to_post_number'], 4);
      expect(json['reply_to_user'], {'username': 'sam'});
      // Milliseconds, which is what the create call reports too.
      expect(json['typingTime'], 9000);
      expect(json['composerTime'], 30000);
    });
  });

  group('decode', () {
    test('reads a blob back, which is a JSON string and not an object', () {
      final draft = ComposerDraft.decode(
        const ComposerDraft(
          reply: 'Round trip',
          replyToPostNumber: 2,
          replyToUsername: 'sam',
        ).encode(),
      );

      expect(draft?.reply, 'Round trip');
      expect(draft?.replyToPostNumber, 2);
      expect(draft?.replyToUsername, 'sam');
    });

    test('accepts a bare username, which is how some payloads write it', () {
      final draft = ComposerDraft.decode(
        jsonEncode({'reply': 'Hi', 'reply_to_user': 'sam'}),
      );

      expect(draft?.replyToUsername, 'sam');
    });

    test('treats an empty reply as no draft at all', () {
      expect(ComposerDraft.decode(jsonEncode({'reply': '   '})), isNull);
      expect(ComposerDraft.decode(jsonEncode({})), isNull);
    });

    test('treats nothing, and nonsense, as no draft', () {
      // An unreadable draft is not worth failing a composer open over.
      expect(ComposerDraft.decode(null), isNull);
      expect(ComposerDraft.decode(''), isNull);
      expect(ComposerDraft.decode('not json'), isNull);
      expect(ComposerDraft.decode('[1,2,3]'), isNull);
      // The API sends a string; an object is not what it sends.
      expect(ComposerDraft.decode(const {'reply': 'Hi'}), isNull);
    });
  });
}
