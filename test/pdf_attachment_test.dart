import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/site_pdf_thumbnail_repository.dart';
import 'package:discourse_native/src/data/site_thumbnail_repository.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/composer_upload_attachment.dart';
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

const _target = ComposerTarget(
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
    final lifecycle = SiteLifecycle();
    shell = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      lifecycle: lifecycle,
      pdfThumbnails: SitePdfThumbnailRepository(
        credentials: FakeApiCredentialReader(),
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
