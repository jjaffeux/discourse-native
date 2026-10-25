import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/styleguide/examples/thread_writing_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in fonts.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });
  testWidgets('redaction only responds inside its painted bars', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            child: DSpoiler(
              text: 'A full first line of hidden words\nShort',
              showLabel: 'Show spoiler',
              hideLabel: 'Hide spoiler',
              builder: (_) => const Text('Revealed'),
            ),
          ),
        ),
      ),
    );
    final bounds = tester.getRect(find.byType(DSpoiler));
    await tester.tapAt(bounds.bottomRight - const Offset(3, 4));
    await tester.pump();
    expect(find.text('Revealed'), findsNothing);
    await tester.tapAt(bounds.topLeft + const Offset(5, 5));
    await tester.pump();
    expect(find.text('Revealed'), findsOneWidget);
  });
  for (final reduced in [false, true]) {
    testWidgets('welcome fires once on becoming visible; reduced=$reduced', (
      tester,
    ) async {
      var seen = 0;
      Future<void> pump(bool visible) => tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(800, 600),
              disableAnimations: reduced,
            ),
            child: TickerMode(
              enabled: visible,
              child: Center(
                child: DConfetti(
                  onSeen: () => seen++,
                  child: const Text('Welcome'),
                ),
              ),
            ),
          ),
        ),
      );
      await pump(false);
      expect(seen, 0);
      await pump(true);
      expect(seen, 1);
      expect(
        tester.binding.transientCallbackCount,
        reduced ? 0 : greaterThan(0),
      );
      await tester.pumpAndSettle();
      await pump(false);
      await pump(true);
      expect(seen, 1);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
    testWidgets('departing headers lose focus and actions; reduced=$reduced', (
      tester,
    ) async {
      var taps = 0;
      Future<void> pump(bool visible) => tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(800, 600),
              disableAnimations: reduced,
            ),
            child: Center(
              child: DReveal(
                visible: visible,
                child: DButton(
                  label: const Text('Action'),
                  onPressed: () => taps++,
                ),
              ),
            ),
          ),
        ),
      );
      await pump(true);
      final target = tester.getCenter(find.text('Action'));
      await pump(false);
      await tester.tapAt(target);
      expect(taps, 0);
      if (reduced) expect(find.text('Action'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Action'), findsNothing);
    });
  }
  for (final dark in [false, true]) {
    {
      testWidgets('composer wells render in $dark flat', (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final composer = ComposerController(
          const ReplyComposerTarget(
            privateMessageTopic: false,
            siteUrl: 'https://example.test',
            topicId: 1,
            slug: 'topic',
            topicTitle: 'Topic',
          ),
        );
        addTearDown(composer.dispose);
        const source =
            'A code example and its results.\n\n'
            '```dart\nfinal knots = [12, 16, 20];\nprint(knots.reduce((a, b) => a + b));\n```\n\n'
            '| Wind | Speed |\n| :--- | ---: |\n| Moderate | 12 |\n| Fresh | 20 |\n\n'
            'Ready to post.';
        composer.text.value = const TextEditingValue(
          text: source,
          selection: TextSelection.collapsed(offset: source.length),
        );
        const capture = ValueKey('composer-wells-capture');
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.forBrightness(
              dark ? Brightness.dark : Brightness.light,
              fontFamily: 'Lato',
            ),
            home: RepaintBoundary(
              key: capture,
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(32),
                  child: ComposerEditor(
                    composer: composer,
                    hintText: 'Write a reply',
                    textStyle: const TextStyle(fontSize: 16, height: 1.5),
                    hintStyle: null,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (widget) => widget is DCard && widget.variant == DCardVariant.well,
          ),
          findsNWidgets(2),
        );
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          capture,
          'wells-${dark ? 'dark' : 'light'}-flat',
        );
      });
    }
    testWidgets('thread writing renders and switches labels in $dark', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(620, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const capture = ValueKey('thread-components-capture');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.forBrightness(
            dark ? Brightness.dark : Brightness.light,
            fontFamily: 'Lato',
          ),
          home: const RepaintBoundary(
            key: capture,
            child: Scaffold(
              body: Padding(
                padding: EdgeInsets.all(32),
                child: ThreadWritingExample(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Forum'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
      final chatTrigger = find.byWidgetPredicate(
        (widget) => widget is DTabTrigger<String> && widget.value == 'chat',
      );
      expect(
        find.descendant(
          of: chatTrigger,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.selected == false,
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is DTabTrigger<String> && widget.value == 'chat',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Forum'), findsOneWidget);
      expect(find.bySemanticsLabel('Chat'), findsOneWidget);
      expect(
        find.descendant(
          of: chatTrigger,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.selected == true,
          ),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _capture(tester, capture, 'components-${dark ? 'dark' : 'light'}');
      semantics.dispose();
    });
  }
}

Future<void> _capture(WidgetTester tester, Key key, String name) async {
  final path = Platform.environment['THREAD_NOTES_RENDER_DIR'];
  if (path == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(path).create(recursive: true);
    await File('$path/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}
