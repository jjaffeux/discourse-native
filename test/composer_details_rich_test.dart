import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_details.dart';
import 'package:discourse_native/src/shell/composer_details_blocks.dart';
import 'package:discourse_native/src/shell/composer_image.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _source =
    'Before\n\n[details="Summary" open future=keep]\n**Bold** and *italic*\n\n![photo|100x80](upload://existing)\n[/details]\n\nAfter';
const _result = ComposerUploadResult(
  id: 1,
  originalFilename: 'new.png',
  shortUrl: 'upload://new',
  url: 'https://example.test/new.png',
  width: 100,
  height: 80,
);
final _file = ComposerUploadFile(
  name: 'new.png',
  length: () async => 3,
  openRead: () => Stream.value([1, 2, 3]),
);

class _Upload {
  final result = Completer<ComposerUploadResult>();
  bool aborted = false;
}

Finder _editable(ComposerController composer) => find.byWidgetPredicate(
  (widget) =>
      widget is EditableText && identical(widget.controller, composer.text),
);
Finder _button(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is DButton && widget.tooltip == tooltip,
);
// Upload offers Files and Photo Library; the fixture stubs only the files.
Future<void> _uploadFiles(WidgetTester tester) async {
  await tester.tap(_button('Upload'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('composer-upload-files')));
  await tester.pump();
}

List<ComposerController> _bodies(WidgetTester tester) => tester
    .widgetList<ComposerRichBodyEditor>(find.byType(ComposerRichBodyEditor))
    .map((widget) => widget.composer)
    .toList();

Future<({ComposerController root, List<_Upload> uploads})> _pump(
  WidgetTester tester, {
  String source = _source,
  bool panel = false,
  double width = 760,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  ComposerUploadFile? pickedFile,
}) async {
  final uploads = <_Upload>[];
  final root = ComposerController(
    const ComposerTarget(
      siteUrl: 'https://example.test',
      topicId: 1,
      slug: 'topic',
      topicTitle: 'Topic',
    ),
    imageUploader: (file, {required onProgress, required abortTrigger}) {
      final upload = _Upload();
      uploads.add(upload);
      unawaited(abortTrigger.then((_) => upload.aborted = true));
      return upload.result.future;
    },
  );
  root.text.value = TextEditingValue(
    text: source,
    selection: const TextSelection.collapsed(offset: 0),
  );
  addTearDown(root.dispose);
  Widget content = ComposerEditor(
    composer: root,
    hintText: 'Reply',
    textStyle: const TextStyle(fontSize: 16, height: 1.5),
    hintStyle: null,
    showSelectionToolbar: false,
    pickFiles: () async => [pickedFile ?? _file],
    readClipboardFiles: () async => [_file],
  );
  if (panel) {
    final shell = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(shell.dispose);
    await shell.load();
    content = ShellScope(
      controller: shell,
      child: ComposerPanel(
        composer: root,
        height: 570,
        pickFiles: () async => [pickedFile ?? _file],
      ),
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: direction,
            child: Center(
              child: SizedBox(width: width, child: content),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (root: root, uploads: uploads);
}

void main() {
  testWidgets('hidden content paints bold, italic and inline image previews', (
    tester,
  ) async {
    await _pump(tester);
    final body = _bodies(tester).single;
    final field = tester.widget<EditableText>(_editable(body));
    final context = tester.element(_editable(body));
    final span = body.text.buildTextSpan(
      context: context,
      style: field.style,
      withComposing: false,
    );
    final bold = <String>[];
    final italic = <String>[];
    span.visitChildren((span) {
      if (span is TextSpan) {
        if (span.style?.fontWeight == FontWeight.w700) {
          bold.add(span.text ?? '');
        }
        if (span.style?.fontStyle == FontStyle.italic) {
          italic.add(span.text ?? '');
        }
      }
      return true;
    });
    expect(bold.join(), contains('Bold'));
    expect(italic.join(), contains('italic'));
    expect(find.byType(ComposerImagePreview), findsOneWidget);
    expect(body.text.imageBlocks.single.url, 'upload://existing');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the main toolbar formats the focused details body', (
    tester,
  ) async {
    final fixture = await _pump(
      tester,
      panel: true,
      source: _source.replaceFirst('**Bold** and *italic*', 'Words'),
    );
    final body = _bodies(tester).single;
    await tester.showKeyboard(_editable(body));
    body.text.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.pump();
    expect(fixture.root.activeEditor, same(body));
    await tester.tap(_button('Bold').first);
    await tester.pump();
    expect(
      parseComposerDetails(fixture.root.text.text).single.body,
      startsWith('**Words**'),
    );
    expect(
      fixture.root.text.text,
      startsWith('Before\n\n[details="Summary" open future=keep]'),
    );
    expect(fixture.root.draft.reply, fixture.root.text.text);
    expect(_button('Bold'), findsOneWidget);
    expect(_button('Link'), findsOneWidget);
  });

  testWidgets('shared tools follow focus into nested details and back out', (
    tester,
  ) async {
    const source =
        '[details="Outer"]\nOuter words\n\n[details="Inner"]\nInner words\n[/details]\n[/details]\n\nAfter';
    final fixture = await _pump(tester, panel: true, source: source);
    final outer = _bodies(tester).first;
    final inner = _bodies(tester).last;
    outer.requestFocus();
    await tester.pump();
    await tester.pump();
    await tester.showKeyboard(_editable(inner));
    inner.text.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.pump();
    await tester.tap(_button('Bold'));
    await tester.pump();
    expect(inner.text.text, '**Inner** words');
    expect(outer.text.text, startsWith('Outer words'));
    expect(fixture.root.activeEditor, same(inner));

    outer.requestFocus();
    await tester.pump();
    outer.text.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.pump();
    await tester.tap(_button('Italic'));
    await tester.pump();
    expect(outer.text.text, startsWith('*Outer* words'));
    expect(fixture.root.text.text, contains('**Inner** words'));

    fixture.root.requestFocus();
    await tester.pump();
    final start = fixture.root.text.text.indexOf('After');
    fixture.root.text.selection = TextSelection(
      baseOffset: start,
      extentOffset: start + 5,
    );
    await tester.pump();
    await tester.tap(_button('Bold'));
    await tester.pump();
    expect(fixture.root.text.text, endsWith('**After**'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shared link dialog edits selected details content', (
    tester,
  ) async {
    final fixture = await _pump(
      tester,
      panel: true,
      source: 'Before\n\n[details]\nRead this\n[/details]\n\nAfter',
    );
    final body = _bodies(tester).single;
    await tester.showKeyboard(_editable(body));
    body.text.selection = const TextSelection(baseOffset: 0, extentOffset: 9);
    await tester.pump();
    await tester.tap(_button('Link'));
    await tester.pumpAndSettle();
    final url = find.descendant(
      of: find.byKey(const ValueKey('composer-link-url')),
      matching: find.byType(EditableText),
    );
    await tester.enterText(url, 'https://example.test/read');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-link-insert')));
    await tester.pumpAndSettle();
    expect(body.text.text, '[Read this](https://example.test/read)');
    expect(
      fixture.root.raw,
      'Before\n\n[details]\n[Read this](https://example.test/read)\n[/details]\n\nAfter',
    );
    expect(body.focus.hasPrimaryFocus, isTrue);
  });

  testWidgets('the shared upload action inserts video into details content', (
    tester,
  ) async {
    final video = ComposerUploadFile(
      name: 'clip.mp4',
      length: () async => 3,
      openRead: () => Stream.value([1, 2, 3]),
    );
    final fixture = await _pump(
      tester,
      panel: true,
      source: 'Before\n\n[details]\nVideo\n[/details]\n\nAfter',
      pickedFile: video,
    );
    final body = _bodies(tester).single;
    await tester.showKeyboard(_editable(body));
    body.text.selection = TextSelection.collapsed(
      offset: body.text.text.length,
    );
    await tester.pump();
    await _uploadFiles(tester);
    expect(fixture.uploads, hasLength(1));
    fixture.uploads.single.result.complete(
      const ComposerUploadResult(
        id: 2,
        originalFilename: 'clip.mp4',
        shortUrl: 'upload://clip.mp4',
        url: 'https://example.test/clip.mp4',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      parseComposerDetails(fixture.root.raw).single.body,
      'Video\n![clip|video](upload://clip.mp4)',
    );
    expect(fixture.root.raw, startsWith('Before\n\n[details]'));
    expect(fixture.root.raw, endsWith('[/details]\n\nAfter'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the inherited upload picker stores its slot and result inside details',
    (tester) async {
      final fixture = await _pump(tester, panel: true);
      final body = _bodies(tester).single;
      await tester.showKeyboard(_editable(body));
      body.text.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      expect(_button('Upload'), findsOneWidget);
      await _uploadFiles(tester);
      expect(fixture.uploads, hasLength(1));
      expect(fixture.root.hasActiveUploads, isTrue);
      expect(fixture.root.canSubmit, isFalse);
      expect(find.byType(DAttachment), findsOneWidget);
      expect(fixture.root.draft.reply, isNot(contains('upload-')));
      expect(
        parseComposerDetails(fixture.root.text.text).single.body,
        contains(fixture.root.uploadPlaceholders.values.single),
      );
      fixture.uploads.single.result.complete(_result);
      await tester.pumpAndSettle();
      expect(fixture.root.canSubmit, isTrue);
      expect(
        parseComposerDetails(fixture.root.raw).single.body,
        startsWith('![new|100x80](upload://new)'),
      );
      expect(find.byType(ComposerImagePreview), findsNWidgets(2));
      expect(
        body.text.resolvedImageUrl(body.text.imageBlocks.first),
        _result.url,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('clipboard upload is cancelled when its disclosure is removed', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    final body = _bodies(tester).single;
    await tester.showKeyboard(_editable(body));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(fixture.uploads, hasLength(1));
    await tester.longPress(find.byKey(const ValueKey('details-disclosure')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Delete details'));
    await tester.pumpAndSettle();
    expect(fixture.uploads.single.aborted, isTrue);
    expect(fixture.root.hasActiveUploads, isFalse);
    fixture.uploads.single.result.complete(_result);
    await tester.pumpAndSettle();
    expect(fixture.root.raw, 'Before\n\n\n\nAfter');
    expect(fixture.root.activeEditor, same(fixture.root));
  });

  testWidgets('external history restores summary and body together', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    final summary = find.descendant(
      of: find.byKey(const ValueKey('details-summary')),
      matching: find.byType(EditableText),
    );
    await tester.enterText(summary, 'Changed title');
    await tester.enterText(_editable(_bodies(tester).single), 'Changed body');
    fixture.root.text.value = const TextEditingValue(text: _source);
    await tester.pump();
    expect(tester.widget<EditableText>(summary).controller.text, 'Summary');
    expect(_bodies(tester).single.text.text, startsWith('**Bold**'));
  });

  testWidgets('failed hidden uploads can be retried after collapsing details', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    final body = _bodies(tester).single;
    body.addFiles([_file], 0);
    await tester.pump();
    fixture.uploads.single.result.completeError(Exception('Upload failed'));
    await tester.pumpAndSettle();
    expect(body.uploads.single.status, ComposerUploadStatus.failed);
    body.retryUpload(body.uploads.single.id);
    await tester.pump();
    expect(fixture.uploads, hasLength(2));
    await tester.tap(find.byKey(const ValueKey('details-disclosure')));
    await tester.pumpAndSettle();
    fixture.uploads.last.result.complete(_result);
    await tester.pumpAndSettle();
    expect(
      parseComposerDetails(fixture.root.raw).single.body,
      startsWith('![new|'),
    );
    await tester.tap(find.byKey(const ValueKey('details-disclosure')));
    await tester.pumpAndSettle();
    expect(find.byType(ComposerImagePreview), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolled details retain image hit testing and deletion', (
    tester,
  ) async {
    final fixture = await _pump(tester, source: '${'Intro\n' * 14}$_source');
    final body = _bodies(tester).single;
    fixture.root.text.imageScrollController!.jumpTo(70);
    await tester.pump();
    final image = body.text.imageBlocks.single;
    final painted = tester.getRect(find.byType(ComposerImagePreview));
    expect(body.text.collapsedImageGlobalRect(image), painted);
    expect(
      fixture.root.text
          .collapsedSyntaxGlobalRect(fixture.root.text.syntaxBlocks.single)!
          .contains(painted.center),
      isTrue,
    );
    await tester.tapAt(painted.center);
    await tester.pumpAndSettle();
    expect(_button('Delete image'), findsOneWidget);
    await tester.tap(_button('Delete image'));
    await tester.pumpAndSettle();
    expect(
      parseComposerDetails(fixture.root.raw).single.body,
      isNot(contains('upload://existing')),
    );
    expect(tester.takeException(), isNull);
  });

  for (final scenario in [
    (
      name: 'regular',
      dimensions: '200x190',
      width: 760.0,
      scale: 1.0,
      nested: false,
      direction: TextDirection.ltr,
    ),
    (
      name: 'small image',
      dimensions: '80x60',
      width: 760.0,
      scale: 1.0,
      nested: false,
      direction: TextDirection.ltr,
    ),
    (
      name: 'nested and scaled',
      dimensions: '200x190',
      width: 640.0,
      scale: 1.4,
      nested: true,
      direction: TextDirection.ltr,
    ),
    (
      name: 'narrow RTL',
      dimensions: '200x190',
      width: 340.0,
      scale: 1.4,
      nested: false,
      direction: TextDirection.rtl,
    ),
  ]) {
    testWidgets(
      'image controls remain clickable beyond details (${scenario.name})',
      (tester) async {
        final details =
            '[details="Photo"]\n![photo|${scenario.dimensions}](upload://existing)\n[/details]';
        final fixture = await _pump(
          tester,
          source: scenario.nested
              ? '[details="Outer"]\n$details\n[/details]'
              : details,
          width: scenario.width,
          scale: scenario.scale,
          direction: scenario.direction,
        );
        fixture.root.text.imageScrollController!.jumpTo(0);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ComposerImagePreview));
        await tester.pumpAndSettle();

        final description = find.byWidgetPredicate(
          (widget) =>
              widget is DInput && widget.semanticLabel == 'Image description',
        );
        expect(description.hitTestable(), findsOneWidget);
        expect(_button('Save alt text').hitTestable(), findsOneWidget);
        expect(
          MediaQuery.textScalerOf(tester.element(description)).scale(10),
          scenario.scale * 10,
        );
        await tester.tap(description);
        await tester.enterText(description, 'A useful description');
        await tester.tap(_button('Decrease image size'));
        await tester.pumpAndSettle();
        expect(fixture.root.raw, contains('${scenario.dimensions}, 75%'));
        expect(
          tester.widget<DInput>(description).controller!.text,
          'A useful description',
        );
        await tester.tap(_button('Save alt text'));
        await tester.pumpAndSettle();
        expect(
          fixture.root.raw,
          contains('![A useful description|${scenario.dimensions}, 75%]'),
        );
        expect(description, findsNothing);

        await tester.tap(find.byType(ComposerImagePreview));
        await tester.pumpAndSettle();
        await tester.tap(_button('Delete image'));
        await tester.pumpAndSettle();
        expect(fixture.root.raw, isNot(contains('upload://existing')));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('image controls follow outer scrolling and close with details', (
    tester,
  ) async {
    final fixture = await _pump(
      tester,
      source: '${'Intro\n' * 14}$_source\n${'After\n' * 20}',
    );
    final scroll = fixture.root.text.imageScrollController!;
    scroll.jumpTo(120);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ComposerImagePreview));
    await tester.pumpAndSettle();
    final before = tester.getRect(_button('Save alt text'));
    scroll.jumpTo(150);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(_button('Save alt text')).top,
      closeTo(before.top - 30, 1),
    );
    expect(_button('Save alt text').hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('details-disclosure')));
    await tester.pumpAndSettle();
    expect(_button('Save alt text'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('details-disclosure')));
    await tester.pumpAndSettle();
    expect(_button('Save alt text'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing details also removes the shared image popover', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final fixture = await _pump(tester);
      await tester.tap(find.byType(ComposerImagePreview));
      await tester.pumpAndSettle();
      expect(_button('Save alt text').hitTestable(), findsOneWidget);
      final tree = tester
          .binding
          .renderViews
          .first
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!
          .toStringDeep();
      expect(tree, contains('Image controls'));
      expect(tree, contains('Image description'));
      fixture.root.text.value = const TextEditingValue(
        text: 'Replacement draft',
      );
      await tester.pumpAndSettle();
      expect(_button('Save alt text'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('shared image controls follow the selected details body', (
    tester,
  ) async {
    final fixture = await _pump(
      tester,
      source:
          '[details="First"]\n![first|100x80](upload://first)\n[/details]\n\n'
          '[details="Second"]\n![second|100x160](upload://second)\n[/details]',
    );
    await tester.tap(find.byType(ComposerImagePreview).first);
    await tester.pumpAndSettle();
    // Keep enough of the second image exposed below the first image's controls,
    // including when the components use compact paragraph spacing.
    await tester.tapAt(
      tester.getBottomLeft(find.byType(ComposerImagePreview).last) +
          const Offset(12, -12),
    );
    await tester.pumpAndSettle();
    final description = find.byWidgetPredicate(
      (widget) =>
          widget is DInput && widget.semanticLabel == 'Image description',
    );
    expect(description, findsOneWidget);
    await tester.enterText(description, 'Changed second image');
    await tester.tap(_button('Save alt text'));
    await tester.pumpAndSettle();
    expect(fixture.root.raw, contains('![first|100x80](upload://first)'));
    expect(
      fixture.root.raw,
      contains('![Changed second image|100x160](upload://second)'),
    );
    expect(tester.takeException(), isNull);
  });

  for (final scroll in [false, true]) {
    testWidgets(
      'native file drops target the inner editor once (scrolled: $scroll)',
      (tester) async {
        final fixture = await _pump(
          tester,
          source: '${scroll ? 'Intro\n' * 14 : ''}$_source',
        );
        final body = _bodies(tester).single;
        if (scroll) {
          fixture.root.text.imageScrollController!.jumpTo(70);
          await tester.pump();
        }
        final outer = tester
            .widgetList<DropTarget>(find.byType(DropTarget))
            .where((target) => target.enable)
            .single;
        final box = tester.getRect(_editable(body));
        var position = box.topLeft + const Offset(12, 12);
        outer.onDragEntered!(
          DropEventDetails(localPosition: position, globalPosition: position),
        );
        await tester.pump();
        expect(find.byType(DDropIndicator), findsOneWidget);
        // Focusing the nested editor can scroll its parent to reveal the caret.
        position =
            tester.getRect(_editable(body)).topLeft + const Offset(12, 12);
        outer.onDragUpdated!(
          DropEventDetails(localPosition: position, globalPosition: position),
        );
        outer.onDragDone!(
          DropDoneDetails(
            files: [
              DropItemFile(
                '/tmp/new.png',
                bytes: Uint8List.fromList([1, 2, 3]),
              ),
            ],
            localPosition: position,
            globalPosition: position,
          ),
        );
        await tester.pump();
        expect(fixture.uploads, hasLength(1));
        expect(find.byType(DDropIndicator), findsNothing);
        expect(
          parseComposerDetails(fixture.root.text.text).single.body,
          contains(fixture.root.uploadPlaceholders.values.single),
        );
        fixture.uploads.single.result.complete(_result);
        await tester.pumpAndSettle();
        expect(
          parseComposerDetails(fixture.root.raw).single.body,
          contains('upload://new'),
        );
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({TargetPlatform.macOS}),
    );
  }

  testWidgets('collapsed details do not capture file drops in outer prose', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    final body = _bodies(tester).single;
    await tester.showKeyboard(_editable(body));
    await tester.tap(find.byKey(const ValueKey('details-disclosure')));
    await tester.pumpAndSettle();
    expect(fixture.root.activeEditor, same(fixture.root));
    final render = tester
        .state<EditableTextState>(_editable(fixture.root))
        .renderEditable;
    final caret = render.getLocalRectForCaret(
      TextPosition(offset: fixture.root.text.text.length),
    );
    final position = render.localToGlobal(caret.bottomCenter);
    final target = tester
        .widgetList<DropTarget>(find.byType(DropTarget))
        .where((target) => target.enable)
        .single;
    target.onDragDone!(
      DropDoneDetails(
        files: [
          DropItemFile('/tmp/new.png', bytes: Uint8List.fromList([1, 2, 3])),
        ],
        localPosition: position,
        globalPosition: position,
      ),
    );
    await tester.pump();
    fixture.uploads.single.result.complete(_result);
    await tester.pumpAndSettle();
    expect(
      parseComposerDetails(fixture.root.raw).single.body,
      parseComposerDetails(_source).single.body,
    );
    expect(fixture.root.raw, endsWith('After\n![new|100x80](upload://new)'));
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets(
    'nested rich editors keep their edits and uploads in the inner details',
    (tester) async {
      const source =
          'Before\n[details="Outer"]\nOutside inner\n[details="Inner"]\nWords\n[/details]\n[/details]\nAfter';
      final fixture = await _pump(tester, source: source);
      final inner = _bodies(tester).last;
      await tester.enterText(_editable(inner), '**Changed**');
      await tester.pump();
      expect(
        fixture.root.text.text,
        source.replaceFirst('Words', '**Changed**'),
      );
      inner.addFiles([_file], inner.text.text.length);
      await tester.pump();
      expect(fixture.uploads, hasLength(1));
      fixture.uploads.single.result.complete(_result);
      await tester.pumpAndSettle();
      final outerBody = parseComposerDetails(
        fixture.root.text.text,
      ).single.body;
      expect(
        parseComposerDetails(outerBody).single.body,
        contains('upload://new'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'multiple image uploads create and extend a gallery inside details',
    (tester) async {
      final fixture = await _pump(
        tester,
        source: '[details]\nWords\n[/details]',
      );
      final body = _bodies(tester).single;
      body.addFiles([_file, _file, _file], body.text.text.length);
      await tester.pump();
      for (final upload in fixture.uploads) {
        upload.result.complete(_result);
      }
      await tester.pumpAndSettle();
      expect(body.text.galleryBlocks.single.images, hasLength(3));
      body.addImagesToGallery([_file], body.text.galleryBlocks.single);
      await tester.pump();
      expect(fixture.uploads, hasLength(4));
      fixture.uploads.last.result.complete(_result);
      await tester.pumpAndSettle();
      expect(body.text.galleryBlocks.single.images, hasLength(4));
      expect(
        parseComposerDetails(fixture.root.raw).single.body,
        body.text.text.trim(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'uploads promote one-line details without breaking their markup',
    (tester) async {
      final fixture = await _pump(
        tester,
        source: 'Before\n[details="Inline"]Words[/details]\nAfter',
      );
      final body = _bodies(tester).single;
      body.addFiles([_file], 5);
      await tester.pump();
      expect(find.byType(ComposerDetailsEditor), findsOneWidget);
      fixture.uploads.single.result.complete(_result);
      await tester.pumpAndSettle();
      expect(
        parseComposerDetails(fixture.root.raw).single.body,
        startsWith('Words\n![new|'),
      );
    },
  );

  testWidgets(
    'CRLF drafts preserve surrounding source and map local upload offsets',
    (tester) async {
      final fixture = await _pump(
        tester,
        source: 'Before\r\n[details]\r\nOne\r\nTwo\r\n[/details]\r\nAfter',
      );
      final body = _bodies(tester).single;
      await tester.enterText(_editable(body), 'One\n**Two**');
      await tester.pump();
      expect(fixture.root.text.text, contains('One\r\n**Two**\r\n[/details]'));
      body.addFiles([_file], 4);
      await tester.pump();
      fixture.uploads.single.result.complete(_result);
      await tester.pumpAndSettle();
      expect(
        parseComposerDetails(fixture.root.text.text).single.body,
        contains('One\r\n![new|'),
      );
      expect(
        parseComposerDetails(fixture.root.text.text).single.body,
        contains('**Two**'),
      );
      // Map another insertion past both the original CRLF and uploaded LF.
      body.addFiles([_file], body.text.text.indexOf('**Two**'));
      await tester.pump();
      fixture.uploads.last.result.complete(_result);
      await tester.pumpAndSettle();
      expect(
        body.text.text,
        'One\n![new|100x80](upload://new)\n![new|100x80](upload://new)\n**Two**',
      );
      expect(fixture.root.text.text, startsWith('Before\r\n[details]\r\n'));
      expect(fixture.root.text.text, endsWith('\r\n[/details]\r\nAfter'));
    },
  );

  testWidgets(
    'narrow large-text details keep rich content and controls within the viewport',
    (tester) async {
      final fixture = await _pump(tester, width: 320, scale: 2);
      expect(find.byType(ComposerImagePreview), findsOneWidget);
      double caretHeight(ComposerController composer) {
        final editable = tester
            .state<EditableTextState>(_editable(composer))
            .renderEditable;
        final caret = editable.getLocalRectForCaret(
          const TextPosition(offset: 0),
        );
        return (editable.localToGlobal(caret.bottomLeft) -
                editable.localToGlobal(caret.topLeft))
            .dy;
      }

      expect(
        caretHeight(_bodies(tester).single),
        closeTo(caretHeight(fixture.root), 1),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
