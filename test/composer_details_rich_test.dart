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
    pickFiles: () async => [_file],
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
        pickFiles: () async => [_file],
      ),
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Center(
            child: SizedBox(width: width, child: content),
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
  });

  testWidgets(
    'the inherited upload picker stores its slot and result inside details',
    (tester) async {
      final fixture = await _pump(tester);
      final body = _bodies(tester).single;
      body.text.selection = const TextSelection.collapsed(offset: 0);
      await tester.tap(_button('Upload'));
      await tester.pump();
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
    await tester.tap(_button('Remove details'));
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
    await tester.tap(find.text('Summary').first);
    await tester.pumpAndSettle();
    fixture.uploads.last.result.complete(_result);
    await tester.pumpAndSettle();
    expect(
      parseComposerDetails(fixture.root.raw).single.body,
      startsWith('![new|'),
    );
    await tester.tap(find.text('Summary').first);
    await tester.pumpAndSettle();
    expect(find.byType(ComposerImagePreview), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolled details retain image hit testing and deletion', (
    tester,
  ) async {
    final fixture = await _pump(tester, source: '${'Intro\n' * 6}$_source');
    final body = _bodies(tester).single;
    fixture.root.text.imageScrollController!.jumpTo(70);
    await tester.pump();
    final image = body.text.imageBlocks.single;
    final painted = tester
        .getRect(find.byType(ComposerImagePreview))
        .shift(const Offset(0, -70));
    expect(body.text.collapsedImageGlobalRect(image), painted);
    await tester.tapAt(painted.center);
    await tester.pumpAndSettle();
    expect(_button('Delete image'), findsOneWidget);
    final remove = tester.widget<DButton>(_button('Delete image'));
    remove.onPressed!();
    await tester.pumpAndSettle();
    expect(
      parseComposerDetails(fixture.root.raw).single.body,
      isNot(contains('upload://existing')),
    );
    expect(tester.takeException(), isNull);
  });

  for (final scroll in [false, true]) {
    testWidgets(
      'native file drops target the inner editor once (scrolled: $scroll)',
      (tester) async {
        final fixture = await _pump(
          tester,
          source: '${scroll ? 'Intro\n' * 6 : ''}$_source',
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
        final position = box.topLeft + Offset(12, 12 - (scroll ? 70 : 0));
        outer.onDragEntered!(
          DropEventDetails(localPosition: position, globalPosition: position),
        );
        await tester.pump();
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
      await _pump(tester, width: 320, scale: 2);
      expect(find.byType(ComposerImagePreview), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
