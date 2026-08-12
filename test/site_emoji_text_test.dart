import 'package:discourse_native/src/data/emoji_cache.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/shell/site_emoji_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

void main() {
  setUp(() {
    // Resolving a shortcode must never give this focused rendering test a
    // socket. A miss keeps the fallback deterministic after the first frame.
    EmojiCache.instance = EmojiCache(
      client: MockClient((_) async => http.Response('', 404)),
    );
  });
  tearDown(EmojiCache.instance.clear);

  testWidgets('preserves ordered run styles across many emoji', (tester) async {
    const red = TextStyle(color: Colors.red, fontSize: 10);
    const blue = TextStyle(color: Colors.blue, fontSize: 20);
    final runs = <SiteEmojiTextRun>[];
    for (var index = 0; index < 64; index++) {
      runs.addAll([
        SiteEmojiTextRun('word$index ', style: index.isEven ? red : blue),
        SiteEmojiTextRun(
          index.isEven ? ':sparkles:' : ':wave:t3:',
          style: index.isEven ? red : blue,
        ),
        const SiteEmojiTextRun(' '),
      ]);
    }

    await _pump(tester, runs: runs);

    final emoji = tester
        .widgetList<SiteEmojiImage>(find.byType(SiteEmojiImage))
        .toList(growable: false);
    expect(emoji, hasLength(64));
    expect(
      emoji.map((image) => image.name),
      List.generate(64, (index) => index.isEven ? 'sparkles' : 'wave:t3'),
    );
    expect(emoji[0].style?.color, Colors.red);
    expect(emoji[0].size, 10 * emojiScale);
    expect(emoji[1].style?.color, Colors.blue);
    expect(emoji[1].size, 20 * emojiScale);

    final text = tester.widget<Text>(find.byType(Text).first);
    final styledText = <({String? text, Color? color})>[];
    text.textSpan!.visitChildren((span) {
      if (span is TextSpan && span.text != null) {
        styledText.add((text: span.text, color: span.style?.color));
      }
      return true;
    });
    expect(styledText.take(3), [
      (text: 'word0 ', color: Colors.red),
      (text: ' ', color: null),
      (text: 'word1 ', color: Colors.blue),
    ]);
    expect(
      text.textSpan!.toPlainText(
        includeSemanticsLabels: false,
        includePlaceholders: false,
      ),
      startsWith('word0  word1  word2 '),
    );
    expect(find.bySemanticsLabel(_plainText(runs)), findsOneWidget);
  });

  testWidgets('split shortcode uses the opening colon run style', (
    tester,
  ) async {
    const opening = TextStyle(color: Colors.purple, fontSize: 18);
    const highlighted = TextStyle(
      color: Colors.orange,
      fontWeight: FontWeight.bold,
      fontSize: 30,
    );

    await _pump(
      tester,
      runs: const [
        SiteEmojiTextRun('Before '),
        SiteEmojiTextRun(':', style: opening),
        SiteEmojiTextRun('spar', style: highlighted),
        SiteEmojiTextRun('', style: highlighted),
        SiteEmojiTextRun('kles', style: highlighted),
        SiteEmojiTextRun(': after', style: highlighted),
      ],
    );

    final emoji = tester.widget<SiteEmojiImage>(find.byType(SiteEmojiImage));
    expect(emoji.name, 'sparkles');
    expect(emoji.style?.color, Colors.purple);
    expect(emoji.style?.fontWeight, isNot(FontWeight.bold));
    expect(emoji.size, 18 * emojiScale);

    final text = tester.widget<Text>(find.byType(Text).first);
    final suffix = <TextSpan>[];
    text.textSpan!.visitChildren((span) {
      if (span is TextSpan && span.text == ' after') suffix.add(span);
      return true;
    });
    expect(suffix.single.style, highlighted);
    expect(find.bySemanticsLabel('Before :sparkles: after'), findsOneWidget);
  });

  testWidgets(
    'adjacent emoji and empty boundary runs retain trailing content',
    (tester) async {
      const trailingKey = ValueKey('trailing');
      await _pump(
        tester,
        runs: const [
          SiteEmojiTextRun(''),
          SiteEmojiTextRun(':wave:t2:'),
          SiteEmojiTextRun(''),
          SiteEmojiTextRun(':sparkles:'),
          SiteEmojiTextRun(' done'),
        ],
        trailing: [
          Semantics(
            label: 'Unread',
            child: const SizedBox(key: trailingKey),
          ),
        ],
      );

      expect(
        tester
            .widgetList<SiteEmojiImage>(find.byType(SiteEmojiImage))
            .map((image) => image.name),
        ['wave:t2', 'sparkles'],
      );
      expect(find.byKey(trailingKey), findsOneWidget);

      final text = tester.widget<Text>(find.byType(Text).first);
      expect(
        text.textSpan!.toPlainText(
          includeSemanticsLabels: false,
          includePlaceholders: false,
        ),
        endsWith(' done'),
      );
    },
  );

  testWidgets('styled text without emoji retains runs and trailing content', (
    tester,
  ) async {
    const red = TextStyle(color: Colors.red);
    const blue = TextStyle(color: Colors.blue);
    const trailingKey = ValueKey('plain-trailing');
    await _pump(
      tester,
      runs: const [
        SiteEmojiTextRun('First ', style: red),
        SiteEmojiTextRun(''),
        SiteEmojiTextRun('second', style: blue),
      ],
      trailing: const [SizedBox(key: trailingKey)],
    );

    expect(find.byType(SiteEmojiImage), findsNothing);
    expect(find.byKey(trailingKey), findsOneWidget);
    final text = tester.widget<Text>(find.byType(Text).first);
    final styledText = <({String? text, Color? color})>[];
    text.textSpan!.visitChildren((span) {
      if (span is TextSpan && span.text != null) {
        styledText.add((text: span.text, color: span.style?.color));
      }
      return true;
    });
    expect(styledText, [
      (text: 'First ', color: Colors.red),
      (text: 'second', color: Colors.blue),
    ]);
    expect(
      text.textSpan!.toPlainText(
        includeSemanticsLabels: false,
        includePlaceholders: false,
      ),
      'First second',
    );
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required List<SiteEmojiTextRun> runs,
  List<Widget> trailing = const [],
}) async {
  final controller = ShellController(
    instanceStore: FakeInstanceStore([instance('meta.example')]),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        home: Scaffold(
          body: SiteEmojiText(
            runs,
            siteUrl: 'https://meta.example',
            trailing: trailing,
          ),
        ),
      ),
    ),
  );
}

String _plainText(Iterable<SiteEmojiTextRun> runs) =>
    runs.map((run) => run.text).join();
