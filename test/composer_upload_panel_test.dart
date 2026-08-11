import 'dart:async';

import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_image.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('the panel shows progress and failed upload actions', (
    tester,
  ) async {
    final calls = <_PanelUploadCall>[];
    final composer = ComposerController(
      _target,
      imageUploader: (file, {required onProgress, required abortTrigger}) {
        final call = _PanelUploadCall(onProgress);
        calls.add(call);
        return call.result.future;
      },
    );
    final shell = await _shell();
    addTearDown(composer.dispose);
    addTearDown(shell.dispose);
    await _pumpPanel(tester, shell, composer);

    expect(find.text('Write a reply…'), findsOneWidget);
    composer.text.text = 'body';
    composer.addDroppedImages([_file], 4);
    calls.single.onProgress(0.37);
    await tester.pump();

    expect(find.text('Write a reply…'), findsNothing);
    expect(find.text('photo.png'), findsOneWidget);
    expect(find.text('37%'), findsOneWidget);
    expect(find.byTooltip('Cancel upload'), findsOneWidget);
    calls.single.result.completeError(
      const ComposerUploadException('The image is too large.'),
    );
    await tester.pump();

    expect(find.text('The image is too large.'), findsOneWidget);
    expect(find.byTooltip('Retry upload'), findsOneWidget);
    expect(find.byTooltip('Remove upload'), findsOneWidget);

    await tester.tap(find.byTooltip('Retry upload'));
    await tester.pump();
    expect(calls, hasLength(2));
    expect(find.text('0%'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel upload'));
    await tester.pump();
    expect(find.text('photo.png'), findsNothing);
  });

  testWidgets('click edits a projected image and backspace removes it', (
    tester,
  ) async {
    final composer = ComposerController(
      _target,
      resolveUploadUrls: (_) async => const {},
    );
    final shell = await _shell();
    addTearDown(composer.dispose);
    addTearDown(shell.dispose);
    composer.text.text = '![old|640x480](upload://photo)';
    await _pumpPanel(tester, shell, composer);

    expect(find.byType(ComposerImagePreview), findsOneWidget);
    final previewRect = tester.getRect(find.byType(ComposerImagePreview));
    final editorRect = tester.getRect(find.byType(EditableText));
    expect(previewRect.top, greaterThanOrEqualTo(editorRect.top));
    Future<void> tapPreview({bool redrawBeforeUp = false}) async {
      final position =
          tester.getTopLeft(find.byType(ComposerImagePreview)) +
          const Offset(8, 8);
      final gesture = await tester.startGesture(position);
      if (redrawBeforeUp) {
        final image = composer.text.imageBlocks.single;
        composer.text.selection = TextSelection.collapsed(
          offset: image.start + 1,
        );
        await tester.pump();
        expect(find.byType(ComposerImagePreview), findsOneWidget);
      }
      await gesture.up();
    }

    await tapPreview(redrawBeforeUp: true);
    await tester.pump();
    await tester.pump();

    expect(find.byTooltip('Decrease image size'), findsOneWidget);
    expect(find.byTooltip('Increase image size'), findsOneWidget);
    expect(find.byTooltip('Remove image'), findsNothing);
    expect(find.byTooltip('Save alt text'), findsOneWidget);
    final image = composer.text.imageBlocks.single;
    composer.text.selection = TextSelection.collapsed(offset: image.end - 1);
    await tester.pump();
    expect(find.byType(ComposerImagePreview), findsOneWidget);

    await tester.tap(find.byTooltip('Decrease image size'));
    await tester.pump();
    expect(composer.text.text, '![old|640x480, 75%](upload://photo)');

    await tapPreview();
    await tester.pump();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Add image description',
      ),
      'new [alt]',
    );
    tester
        .widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('Save alt text'),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed!();
    await tester.pump();
    expect(composer.text.text, r'![new \[alt\]|640x480, 75%](upload://photo)');

    composer.focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(composer.text.text, isEmpty);
  });

  testWidgets('an image taller than the editor scrolls inside it', (
    tester,
  ) async {
    final composer = ComposerController(
      _target,
      resolveUploadUrls: (_) async => const {},
    );
    final shell = await _shell();
    addTearDown(composer.dispose);
    addTearDown(shell.dispose);
    composer.text.text = '![tall|640x480](upload://photo)';
    await _pumpPanel(tester, shell, composer);
    await tester.pumpAndSettle();

    final editor = find.byType(EditableText);
    final scrollable = find.descendant(
      of: editor,
      matching: find.byType(Scrollable),
    );
    final scrollState = tester.state<ScrollableState>(scrollable);
    expect(scrollState.position.maxScrollExtent, greaterThan(0));
    scrollState.position.jumpTo(0);
    await tester.pump();

    final preview = find.byType(ComposerImagePreview);
    final oldTop = tester.getTopLeft(preview).dy;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getRect(find.byType(TextField)).center,
        scrollDelta: const Offset(0, 80),
      ),
    );
    await tester.pumpAndSettle();

    expect(scrollState.position.pixels, greaterThan(0));
    expect(tester.getTopLeft(preview).dy, lessThan(oldTop));
  });
}

Future<ShellController> _shell() async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore(),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  return shell;
}

Future<void> _pumpPanel(
  WidgetTester tester,
  ShellController shell,
  ComposerController composer,
) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.dark,
    home: ShellScope(
      controller: shell,
      child: Scaffold(body: ComposerPanel(composer: composer)),
    ),
  ),
);

const _target = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 7,
  slug: 'a-topic',
  topicTitle: 'A topic',
);

final _file = ComposerUploadFile(
  name: 'photo.png',
  length: () => Future.value(3),
  openRead: () => Stream.value([1, 2, 3]),
);

class _PanelUploadCall {
  _PanelUploadCall(this.onProgress);

  final void Function(double) onProgress;
  final Completer<ComposerUploadResult> result = Completer();
}
