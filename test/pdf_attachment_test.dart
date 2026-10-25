import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/site_pdf_thumbnail_repository.dart';
import 'package:discourse_native/src/data/site_thumbnail_repository.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/shell/composer/upload_attachment.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/pdf_attachment.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/blank_png.dart';
import 'support/fakes.dart';

const _site = 'https://forum.example';

void main() {
  test('recognizes PDF destinations and Discourse short URLs', () {
    expect(isPdfAttachment('notes.PDF|attachment', 'upload://abc'), isTrue);
    expect(isPdfAttachment('Notes', '/uploads/notes.PDF?download=1'), isTrue);
    expect(isPdfAttachment('notes.pdf', 'https://example.com/page'), isFalse);
    expect(isPdfAttachment('notes.pdf.exe', 'upload://abc'), isFalse);
  });

  for (final dark in [false, true]) {
    testWidgets('post PDF preview fits a narrow lane (dark: $dark)', (
      tester,
    ) async {
      final harness = _Harness();
      await tester.pumpWidget(
        harness.app(
          const CookedHtml(
            html:
                '<p><a class="attachment" href="/uploads/notes.PDF?download=1">'
                'notes.PDF</a> (1.2 MB)</p><p>Following paragraph</p>',
            siteUrl: _site,
          ),
          dark: dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(harness.jobs, hasLength(1));
      expect(
        harness.jobs.single.url.toString(),
        '$_site/uploads/notes.PDF?download=1',
      );
      expect(find.byType(DAttachmentTrigger), findsOneWidget);
      expect(
        find.text('Following paragraph', findRichText: true),
        findsOneWidget,
      );
      harness.jobs.single.result.complete(blankPng(width: 171, height: 256));
      await _waitForImage(tester);
      expect(
        tester.widget<RawImage>(find.byType(RawImage)).fit,
        BoxFit.contain,
      );
      expect(tester.getSize(find.byType(RawImage)), const Size.square(40));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ordinary links and non-PDF attachments keep their rendering', (
    tester,
  ) async {
    final harness = _Harness();
    await tester.pumpWidget(
      harness.app(
        const CookedHtml(
          html:
              '<p><a href="/uploads/notes.pdf">Read the guide</a></p>'
              '<p><a class="attachment" href="/uploads/notes.zip">notes.zip</a></p>'
              '<p><a class="attachment" href="javascript:notes.pdf">Bad link</a></p>',
          siteUrl: _site,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PdfThumbnail), findsNothing);
    expect(harness.jobs, isEmpty);
  });

  testWidgets(
    'failed and replaced previews keep the file icon and discard stale images',
    (tester) async {
      final harness = _Harness();
      Widget preview(String name) => PdfAttachment(
        filename: '$name.pdf',
        url: '/uploads/$name.pdf',
        siteUrl: _site,
      );
      await tester.pumpWidget(harness.app(preview('one')));
      await tester.pump();
      await tester.pumpWidget(harness.app(preview('two')));
      await tester.pump();
      expect(harness.jobs.first.cancelled, isTrue);
      harness.jobs.first.result.complete(blankPng(width: 171, height: 256));
      harness.jobs.last.result.complete(null);
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsNothing);
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
      expect(find.text('two.pdf'), findsOneWidget);
    },
  );

  testWidgets('hidden panes release pending PDF work', (tester) async {
    final harness = _Harness();
    const preview = PdfAttachment(
      filename: 'notes.pdf',
      url: '/uploads/notes.pdf',
      siteUrl: _site,
    );
    await tester.pumpWidget(harness.app(preview));
    await tester.pump();
    await tester.pumpWidget(harness.app(preview, enabled: false));
    await tester.pump();
    expect(harness.jobs.single.cancelled, isTrue);
    harness.jobs.single.result.complete(blankPng(width: 171, height: 256));
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);
  });

  testWidgets(
    'offscreen PDFs admit on entry and cancel unfinished work on exit',
    (tester) async {
      final harness = _Harness();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        harness.app(
          SingleChildScrollView(
            controller: scroll,
            child: const Column(
              children: [
                SizedBox(height: 450),
                SizedBox(
                  height: 40,
                  child: PdfThumbnail(
                    url: '/uploads/notes.pdf',
                    siteUrl: _site,
                  ),
                ),
                SizedBox(height: 450),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(harness.jobs, isEmpty);
      final retained = tester.element(find.byType(PdfThumbnail));
      scroll.jumpTo(300);
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(PdfThumbnail)), same(retained));
      expect(harness.jobs, hasLength(1));
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(harness.jobs.single.cancelled, isTrue);
      scroll.jumpTo(300);
      await tester.pumpAndSettle();
      expect(harness.jobs, hasLength(2));
      harness.jobs.first.result.complete(blankPng(width: 171, height: 256));
      await tester.pump();
      expect(find.byType(RawImage), findsNothing);
      harness.jobs.last.result.complete(blankPng(width: 171, height: 256));
      await _waitForImage(tester);
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      scroll.jumpTo(300);
      await tester.pumpAndSettle();
      expect(harness.jobs, hasLength(2));
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets('ancestor clips and Offstage defer retained PDF previews', (
    tester,
  ) async {
    final harness = _Harness();
    final top = ValueNotifier<double>(150);
    final hidden = ValueNotifier<bool>(true);
    addTearDown(top.dispose);
    addTearDown(hidden.dispose);
    await tester.pumpWidget(
      harness.app(
        Column(
          children: [
            SizedBox(
              height: 100,
              child: ValueListenableBuilder<double>(
                valueListenable: top,
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: PdfThumbnail(
                    url: '/uploads/clipped.pdf',
                    siteUrl: _site,
                  ),
                ),
                builder: (_, offset, child) => ClipRect(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [Positioned(top: offset, child: child!)],
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: hidden,
              child: const SizedBox(
                width: 40,
                height: 40,
                child: PdfThumbnail(url: '/uploads/hidden.pdf', siteUrl: _site),
              ),
              builder: (_, offstage, child) =>
                  Offstage(offstage: offstage, child: child),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.jobs, isEmpty);
    top.value = 20;
    await tester.pumpAndSettle();
    expect(harness.jobs.single.url.path, '/uploads/clipped.pdf');
    hidden.value = false;
    await tester.pumpAndSettle();
    expect(harness.jobs, hasLength(2));
    top.value = 150;
    await tester.pumpAndSettle();
    expect(harness.jobs.first.cancelled, isTrue);
    expect(harness.jobs.last.cancelled, isFalse);
  });

  testWidgets('visible duplicate PDFs retain shared work until both leave', (
    tester,
  ) async {
    final harness = _Harness();
    final firstHidden = ValueNotifier<bool>(false);
    final secondHidden = ValueNotifier<bool>(false);
    addTearDown(firstHidden.dispose);
    addTearDown(secondHidden.dispose);
    Widget preview(ValueNotifier<bool> hidden) => ValueListenableBuilder<bool>(
      valueListenable: hidden,
      child: const SizedBox(
        width: 40,
        height: 40,
        child: PdfThumbnail(url: '/uploads/shared.pdf', siteUrl: _site),
      ),
      builder: (_, offstage, child) =>
          Offstage(offstage: offstage, child: child),
    );
    await tester.pumpWidget(
      harness.app(
        Column(children: [preview(firstHidden), preview(secondHidden)]),
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.jobs, hasLength(1));
    firstHidden.value = true;
    await tester.pumpAndSettle();
    expect(harness.jobs.single.cancelled, isFalse);
    secondHidden.value = true;
    await tester.pumpAndSettle();
    expect(harness.jobs.single.cancelled, isTrue);
  });

  testWidgets('deferred PDF admission cannot acquire under a successor lease', (
    tester,
  ) async {
    final harness = _Harness();
    final hidden = ValueNotifier<bool>(true);
    addTearDown(hidden.dispose);
    await tester.pumpWidget(
      harness.app(
        ValueListenableBuilder<bool>(
          valueListenable: hidden,
          child: const SizedBox(
            width: 40,
            height: 40,
            child: PdfThumbnail(url: '/uploads/notes.pdf', siteUrl: _site),
          ),
          builder: (_, offstage, child) =>
              Offstage(offstage: offstage, child: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.jobs, isEmpty);
    harness.lifecycle.invalidate(_site);
    harness.lifecycle.capture(_site);
    hidden.value = false;
    await tester.pumpAndSettle();
    expect(harness.jobs, isEmpty);
    expect(find.byType(RawImage), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
    'failed PDF previews honor cooldown when leaving and reentering',
    (tester) async {
      final harness = _Harness();
      final hidden = ValueNotifier<bool>(false);
      addTearDown(hidden.dispose);
      await tester.pumpWidget(
        harness.app(
          ValueListenableBuilder<bool>(
            valueListenable: hidden,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: PdfThumbnail(url: '/uploads/failed.pdf', siteUrl: _site),
            ),
            builder: (_, offstage, child) =>
                Offstage(offstage: offstage, child: child),
          ),
        ),
      );
      await tester.pumpAndSettle();
      harness.jobs.single.result.complete(null);
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }
      expect(harness.jobs, hasLength(1));
      expect(tester.binding.hasScheduledFrame, isFalse);
      hidden.value = true;
      await tester.pumpAndSettle();
      hidden.value = false;
      await tester.pumpAndSettle();
      expect(harness.jobs, hasLength(1));
      hidden.value = true;
      await tester.pumpAndSettle();
      harness.now = harness.now.add(const Duration(seconds: 31));
      hidden.value = false;
      await tester.pumpAndSettle();
      expect(harness.jobs, hasLength(2));
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    },
  );

  testWidgets(
    'retained composer PDFs share post thumbnails and keep remove actions',
    (tester) async {
      final harness = _Harness();
      final composer = _composer();
      await tester.pumpWidget(
        harness.app(
          ComposerUploadAttachment(
            composer: composer,
            upload: ComposerUploadItem(
              id: 1,
              file: _file,
              progress: 1,
              status: ComposerUploadStatus.completed,
              result: _result,
            ),
          ),
        ),
      );
      await tester.pump();
      harness.jobs.single.result.complete(blankPng(width: 171, height: 256));
      await _waitForImage(tester);
      expect(find.byType(DAttachmentAction), findsOneWidget);
      await tester.pumpWidget(
        harness.app(
          const PdfAttachment(
            filename: 'notes.pdf',
            url: '/uploads/notes.pdf',
            siteUrl: _site,
          ),
        ),
      );
      await _waitForImage(tester);
      expect(harness.jobs, hasLength(1));
    },
  );

  testWidgets(
    'uploaded PDF renders in the rich composer without changing its Markdown',
    (tester) async {
      final harness = _Harness();
      final composer = _composer(uploader: true);
      await tester.pumpWidget(
        harness.app(
          ComposerEditor(
            composer: composer,
            hintText: 'Write a reply',
            textStyle: const TextStyle(fontSize: 14),
            hintStyle: const TextStyle(fontSize: 14),
          ),
        ),
      );
      composer.addFiles([_file], 0);
      await tester.pumpAndSettle();
      expect(composer.raw, contains('[notes.pdf](upload://notes)'));
      expect(find.byType(PdfThumbnail), findsOneWidget);
      expect(harness.jobs, hasLength(1));
      expect(harness.jobs.single.url.toString(), _result.url);
      final original = composer.raw;
      harness.jobs.single.result.complete(blankPng(width: 171, height: 256));
      await _waitForImage(tester);
      expect(composer.raw, original);
      composer.text.rawMarkdown = true;
      await tester.pumpAndSettle();
      expect(find.byType(PdfThumbnail), findsNothing);
      expect(composer.raw, original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('existing draft PDF short URLs resolve before previewing', (
    tester,
  ) async {
    final harness = _Harness();
    final composer = ComposerController(
      _target,
      resolveUploadUrls: (urls) async => {
        for (final url in urls) url: _result.url,
      },
    );
    addTearDown(composer.dispose);
    composer.text.text = '[notes.pdf](upload://notes)';
    await tester.pumpWidget(
      harness.app(
        ComposerEditor(
          composer: composer,
          hintText: 'Write a reply',
          textStyle: const TextStyle(fontSize: 14),
          hintStyle: const TextStyle(fontSize: 14),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.jobs, hasLength(1));
    expect(harness.jobs.single.url.toString(), _result.url);
    expect(composer.raw, '[notes.pdf](upload://notes)');
  });
}

const _target = ReplyComposerTarget(
  privateMessageTopic: false,
  siteUrl: _site,
  topicId: 1,
  slug: 'test',
  topicTitle: 'Test',
);
const _result = ComposerUploadResult(
  id: 7,
  originalFilename: 'notes.pdf',
  shortUrl: 'upload://notes',
  url: '$_site/uploads/notes.pdf',
);
final _file = ComposerUploadFile(
  name: 'notes.pdf',
  length: () async => 3,
  openRead: () => Stream.value([1, 2, 3]),
);

ComposerController _composer({bool uploader = false}) {
  final composer = ComposerController(
    _target,
    imageUploader: uploader
        ? (file, {required onProgress, required abortTrigger}) async => _result
        : null,
  );
  addTearDown(composer.dispose);
  return composer;
}

Future<void> _waitForImage(WidgetTester tester) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (find.byType(RawImage).evaluate().isNotEmpty &&
        tester.widget<RawImage>(find.byType(RawImage)).image != null) {
      return;
    }
  }
  fail('PDF thumbnail did not render');
}

final class _Harness {
  _Harness() {
    lifecycle = SiteLifecycle();
    shell = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      lifecycle: lifecycle,
      pdfThumbnails: SitePdfThumbnailRepository(
        credentials: FakeApiCredentialReader(),
        clock: () => now,
        lifecycle: lifecycle,
        generator: (url) {
          final job = _Job(url);
          jobs.add(job);
          return ThumbnailRequest(
            job.result.future,
            () => job.cancelled = true,
          );
        },
      ),
    );
    addTearDown(shell.dispose);
  }
  DateTime now = DateTime(2026);
  late final SiteLifecycle lifecycle;
  late final ShellController shell;
  final jobs = <_Job>[];
  Widget app(Widget child, {bool dark = false, bool enabled = true}) =>
      MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: ShellScope(
          controller: shell,
          child: TickerMode(
            enabled: enabled,
            child: Scaffold(
              body: Center(
                child: SizedBox(width: 280, height: 400, child: child),
              ),
            ),
          ),
        ),
      );
}

final class _Job {
  _Job(this.url);
  final Uri url;
  final result = Completer<Uint8List?>();
  bool cancelled = false;
}
