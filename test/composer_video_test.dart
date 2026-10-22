import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugin_api/composer_syntax.dart';
import 'package:discourse_native/src/shell/composer/components/image_source.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/shell/inline_video.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _target = ReplyComposerTarget(
  privateMessageTopic: false,
  siteUrl: 'https://example.test',
  topicId: 1,
  slug: 'topic',
  topicTitle: 'Topic',
);
const _video = '![My clip|video](https://example.test/clip.mp4)';

ComposerController _composer(String source) {
  final composer = ComposerController(_target);
  composer.text.value = TextEditingValue(
    text: source,
    selection: TextSelection.collapsed(offset: source.length),
  );
  addTearDown(composer.dispose);
  return composer;
}

Future<void> _pump(WidgetTester tester, ComposerController composer) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SizedBox(
          width: 760,
          child: ComposerEditor(
            composer: composer,
            hintText: 'Write a reply',
            textStyle: const TextStyle(fontSize: 16, height: 1.5),
            hintStyle: null,
          ),
        ),
      ),
    ),
  );
  composer.requestFocus();
  await tester.pump();
}

void main() {
  test('retains exact video source and offsets with escaped caption text', () {
    const video =
        r'![A \[screen\] \\ take|video|640x360, 75%](upload://clip "Title")';
    const source = 'Before\r\n$video\r\nAfter';
    final block = parseComposerVideos(source).single;
    expect(block.start, 8);
    expect(block.end, 8 + video.length);
    expect(block.source, video);
    expect(block.title, r'A [screen] \ take');
    expect(block.url, 'upload://clip');
    expect(parseComposerImages(source), isEmpty);
  });

  test('uses core media suffix ordering and leaves audio to its owner', () {
    for (final label in [
      'clip|video',
      'clip|video|thumbnail',
      'clip|video|320x180',
      'clip|video|320x180, x75',
      'clip|video|data-name=value',
      'clip|unknown|video',
    ]) {
      final videos = parseComposerVideos('![$label](upload://clip)');
      expect(videos, hasLength(1), reason: label);
      expect(
        videos.single.title,
        label == 'clip|unknown|video' ? 'clip|unknown' : 'clip',
      );
      expect(parseComposerImages('![$label](upload://clip)'), isEmpty);
    }
    for (final label in [
      'clip|audio',
      'clip|audio|video',
      'clip|thumbnail|video',
      'clip|320x180|video',
      'clip|video|unknown',
      'clip|Video',
      'clip',
    ]) {
      expect(
        parseComposerVideos('![$label](upload://clip)'),
        isEmpty,
        reason: label,
      );
    }
  });

  test('ignores escaped openers and inline or fenced code', () {
    const source =
        '\\$_video\n'
        '`$_video`\n\n'
        '```md\n$_video\n```\n\n'
        '$_video\n'
        '\\\\$_video';
    final videos = parseComposerVideos(source);
    expect(videos, hasLength(2));
    expect(videos.first.start, source.lastIndexOf('$_video\n'));
    expect(videos.last.start, source.lastIndexOf(_video));
  });

  test(
    'video projection exposes only whole source selection and IME escape',
    () {
      final composer = _composer('Before\n\n$_video\nAfter');
      final projection = composer.text.syntaxBlocks.single.projection;
      expect(projection, isA<ComposerAtomicSelectionProjection>());
      expect(projection.source, _video);
      expect(projection.caretAfter(composer.text.text), 8 + _video.length + 1);
      expect(
        projection.needsRawSource(
          composer.value.copyWith(
            composing: const TextRange(start: 10, end: 12),
          ),
          suppressCollapsedCaret: false,
        ),
        isTrue,
      );
      composer.text.selection = const TextSelection(
        baseOffset: 9,
        extentOffset: 12,
      );
      expect(
        composer.text.selection,
        const TextSelection(baseOffset: 8, extentOffset: 8 + _video.length),
      );
    },
  );

  testWidgets('rich videos keep source and raw mode displays exact markdown', (
    tester,
  ) async {
    const source = 'Before\n\n$_video\n\nAfter';
    final composer = _composer(source);
    await _pump(tester, composer);
    final player = tester.widget<InlineVideo>(find.byType(InlineVideo));
    expect(player.data.source.toString(), 'https://example.test/clip.mp4');
    expect(player.data.title, 'My clip');
    expect(find.byKey(const ValueKey('inline-video-play')), findsOneWidget);
    final projection = composer.text.collapsedSyntaxGlobalRect(
      composer.text.syntaxBlocks.single,
    )!;
    final playerBounds = tester.getRect(
      find.descendant(
        of: find.byType(InlineVideo),
        matching: find.byType(DAspectRatio),
      ),
    );
    expect(projection.width, closeTo(playerBounds.width, 0.01));
    expect(projection.left, closeTo(playerBounds.left, 0.01));
    expect(
      composer.text.collapsedSyntaxAtGlobalPosition(
        Offset(playerBounds.right + 20, playerBounds.center.dy),
      ),
      isNull,
    );
    await tester.tapAt(Offset(playerBounds.right + 20, playerBounds.center.dy));
    await tester.pump();
    expect(
      composer.text.selection,
      TextSelection.collapsed(offset: source.indexOf('After')),
    );
    expect(composer.raw, source);
    composer.text.rawMarkdown = true;
    await tester.pump();
    expect(find.byType(InlineVideo), findsNothing);
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.renderEditable.text!.toPlainText(), source);
    composer.text.rawMarkdown = false;
    await tester.pump();
    expect(find.byType(InlineVideo), findsOneWidget);
    expect(composer.raw, source);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'restored upload resolves to the rich player without editing source',
    (tester) async {
      const source = '![Restored|video](upload://restored.mp4)';
      final result = Completer<Map<String, String>>();
      final requested = <Set<String>>[];
      final composer = ComposerController(
        _target,
        resolveUploadUrls: (urls) {
          requested.add(urls.toSet());
          return result.future;
        },
      );
      addTearDown(composer.dispose);
      composer.text.text = source;
      await _pump(tester, composer);
      expect(requested, [
        <String>{'upload://restored.mp4'},
      ]);
      expect(find.byType(InlineVideo), findsNothing);
      expect(find.byType(DSkeletonRegion), findsOneWidget);
      expect(find.byType(DSpinner), findsNothing);
      expect(tester.getSize(find.byType(DSkeleton)).height, 190);
      expect(find.textContaining('Loading'), findsNothing);
      result.complete({
        'upload://restored.mp4': 'https://example.test/restored.mp4',
      });
      await tester.pump();
      await tester.pump();
      expect(find.byType(InlineVideo), findsOneWidget);
      expect(
        tester
            .widget<InlineVideo>(find.byType(InlineVideo))
            .data
            .source
            .toString(),
        'https://example.test/restored.mp4',
      );
      expect(composer.raw, source);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'partial native edits are rejected and backspace undo restores video',
    (tester) async {
      const source = 'Before\n\n$_video\n\nAfter';
      final composer = _composer(source);
      await _pump(tester, composer);
      composer.text.selection = const TextSelection.collapsed(
        offset: 8 + _video.length,
      );
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: source.replaceRange(10, 12, 'x'),
          selection: const TextSelection.collapsed(offset: 11),
        ),
      );
      await tester.pump();
      expect(composer.raw, source);
      composer.text.selection = const TextSelection.collapsed(offset: 8);
      await tester.pump();
      expect(
        composer.text.selection,
        const TextSelection(baseOffset: 8, extentOffset: 8 + _video.length),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(composer.raw, 'Before\n\n\n\nAfter');
      expect(find.byType(InlineVideo), findsNothing);
      composer.history.undo();
      await tester.pump();
      expect(composer.raw, source);
      expect(find.byType(InlineVideo), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('play button receives clicks without selecting hidden markdown', (
    tester,
  ) async {
    final composer = _composer('Before\n\n$_video\n\nAfter');
    await _pump(tester, composer);
    final selection = composer.text.selection;
    await tester.tap(find.byKey(const ValueKey('inline-video-play')));
    await tester.pump();
    expect(find.byType(InlineVideoPlaybackSurface), findsOneWidget);
    expect(composer.text.selection, selection);
    expect(composer.raw, 'Before\n\n$_video\n\nAfter');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
