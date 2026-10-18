import 'dart:async';

import 'package:discourse_native/src/shell/composer/components/emoji.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/media_pipeline.dart';

void main() {
  test(
    'pending artwork completion only notifies the surviving editor',
    () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      var requests = 0;
      final pipeline = installTestMediaPipeline(
        client: MockClient((_) {
          requests++;
          started.complete();
          return response.future;
        }),
      );
      var closedChanges = 0;
      var openChanges = 0;
      final closed = ComposerEmojiArtwork(onChanged: () => closedChanges++);
      final open = ComposerEmojiArtwork(onChanged: () => openChanges++);
      addTearDown(open.dispose);
      const url = 'https://forum.test/emoji/smile.png';
      for (final artwork in [closed, closed, open]) {
        expect(
          artwork.build(
            source: ':smile:',
            range: const TextRange(start: 0, end: 7),
            name: 'smile',
            resolve: (_) => url,
            baseStyle: const TextStyle(),
          ),
          isNull,
        );
      }
      await started.future;
      closed.dispose();
      response.complete(http.Response('missing emoji', 404));
      await pipeline.emoji.load(url);

      expect(requests, 1);
      expect(closedChanges, 0);
      expect(openChanges, 1);
    },
  );
}
