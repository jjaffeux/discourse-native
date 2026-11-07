import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/shell/composer/upload_attachment.dart';
import 'package:discourse_native/src/shell/lightbox.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/blank_png.dart';
import 'support/fakes.dart';
import 'support/native_ui_evidence.dart';

const _siteUrl = 'https://forum.example';

void main() {
  for (final width in [390.0, 1100.0]) {
    testWidgets(
      'local attachment gallery closes when its composer is disposed at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await prepareNativeUiEvidence(tester);
        final transfer = Completer<ComposerUploadResult>();
        final composer = ComposerController(
          const ReplyComposerTarget(
            privateMessageTopic: false,
            siteUrl: _siteUrl,
            topicId: 1,
            slug: 'test',
            topicTitle: 'Test',
          ),
          imageUploader: (file, {required onProgress, required abortTrigger}) =>
              transfer.future,
        );
        addTearDown(() {
          if (!composer.isDisposed) composer.dispose();
        });
        await tester.runAsync(() async {
          final asset = await rootBundle.load(
            'packages/discourse_native/src/styleguide/assets/discourse.png',
          );
          final bytes = asset.buffer.asUint8List(
            asset.offsetInBytes,
            asset.lengthInBytes,
          );
          composer.addFiles([
            ComposerUploadFile(
              name: 'Sailing.png',
              length: () async => bytes.length,
              openRead: () => Stream.value(bytes),
            ),
          ], 0);
          await composer.uploadPreview(composer.uploads.single.id)!.ready;
        });
        final file = composer.uploadPreview(composer.uploads.single.id)!.file!;
        await tester.pumpWidget(
          MaterialApp(
            builder: nativeUiEvidenceBuilder,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: ListenableBuilder(
                  listenable: composer,
                  builder: (_, _) => Column(
                    children: [
                      for (final item in composer.uploads)
                        ComposerUploadAttachment(
                          composer: composer,
                          upload: item,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await _captureAttachment(
          tester,
          'composer-local-attachment-${width.toInt()}',
        );
        await tester.tap(find.byType(DAttachmentTrigger));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        final id = composer.uploads.single.id;
        composer.cancelUpload(id);
        await tester.pump();
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          if (tester
              .widgetList<RawImage>(find.byType(RawImage))
              .any((image) => image.image != null)) {
            break;
          }
        }
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<RawImage>(find.byType(RawImage))
              .where((image) => image.image != null),
          isNotEmpty,
        );
        expect(find.byType(LightboxGallery), findsOneWidget);
        await captureNativeUi(
          tester,
          'composer-local-gallery-${width.toInt()}',
        );
        composer.dispose();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.byType(LightboxGallery), findsNothing);
        await tester.runAsync(() async {
          for (var n = 0; n < 100 && await file.exists(); n++) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(await file.exists(), isFalse);
        });
        transfer.complete(
          const ComposerUploadResult(
            id: 1,
            originalFilename: 'Sailing.png',
            shortUrl: 'upload://pending',
            url: 'https://forum.example/pending.png',
          ),
        );
        await tester.pump();
      },
    );
  }

  testWidgets(
    'pending local images open a gallery and survive upload cancellation',
    (tester) async {
      final transfer = Completer<ComposerUploadResult>();
      final composer = ComposerController(
        const ReplyComposerTarget(
          privateMessageTopic: false,
          siteUrl: _siteUrl,
          topicId: 1,
          slug: 'test',
          topicTitle: 'Test',
        ),
        imageUploader: (file, {required onProgress, required abortTrigger}) =>
            transfer.future,
      );
      addTearDown(composer.dispose);
      final bytes = blankPng(width: 120, height: 80);
      await tester.runAsync(() async {
        composer.addFiles([
          ComposerUploadFile(
            name: 'pending.png',
            length: () async => bytes.length,
            openRead: () => Stream.value(bytes),
          ),
        ], 0);
        await composer.uploadPreview(composer.uploads.single.id)!.ready;
      });
      final id = composer.uploads.single.id;
      final file = composer.uploadPreview(id)!.file!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: composer,
              builder: (_, _) => Column(
                children: [
                  for (final item in composer.uploads)
                    ComposerUploadAttachment(composer: composer, upload: item),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.byType(DAttachmentTrigger), findsOneWidget);
      await tester.tap(find.byType(DAttachmentTrigger));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(LightboxGallery), findsOneWidget);
      final gallery = tester.widget<LightboxGallery>(
        find.byType(LightboxGallery),
      );
      expect(gallery.images.single.source, isA<LocalLightboxImage>());
      composer.cancelUpload(id);
      await tester.pump();
      expect(await tester.runAsync(file.exists), isTrue);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (var n = 0; n < 100 && await file.exists(); n++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(await file.exists(), isFalse);
      });
      transfer.complete(
        const ComposerUploadResult(
          id: 1,
          originalFilename: 'pending.png',
          shortUrl: 'upload://pending',
          url: 'https://forum.example/pending.png',
        ),
      );
      await tester.pump();
    },
  );

  testWidgets(
    'video optimization is distinct from uploading and can be cancelled',
    (tester) async {
      final preparation = Completer<PreparedComposerUpload>();
      var aborted = false;
      var uploads = 0;
      var releases = 0;
      final file = ComposerUploadFile(
        name: 'Holiday.MOV',
        length: () async => 10,
        openRead: () => Stream.value([1]),
      );
      final composer = ComposerController(
        const ReplyComposerTarget(
          privateMessageTopic: false,
          siteUrl: _siteUrl,
          topicId: 1,
          slug: 'test',
          topicTitle: 'Test',
        ),
        prepareUpload: (file, {required abortTrigger}) {
          unawaited(abortTrigger.then((_) => aborted = true));
          return preparation.future;
        },
        imageUploader:
            (file, {required onProgress, required abortTrigger}) async {
              uploads++;
              throw StateError('Cancelled videos must not upload');
            },
      );
      addTearDown(composer.dispose);
      composer.addFiles([file], 0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: composer,
              builder: (context, _) => Column(
                children: [
                  for (final upload in composer.uploads)
                    ComposerUploadAttachment(
                      composer: composer,
                      upload: upload,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Optimizing video…'), findsOneWidget);
      expect(find.text('Processing image'), findsNothing);
      expect(find.textContaining('Uploading'), findsNothing);
      expect(composer.hasActiveUploads, isTrue);
      await tester.tap(find.byTooltip('Cancel video upload'));
      await tester.pump();
      expect(aborted, isTrue);
      expect(composer.uploads, isEmpty);
      expect(composer.hasActiveUploads, isFalse);
      preparation.complete(
        PreparedComposerUpload(
          file,
          release: () async {
            releases++;
          },
        ),
      );
      await tester.pump();
      expect(uploads, 0);
      expect(releases, 1);
    },
  );

  testWidgets('video preparation switches to network progress when ready', (
    tester,
  ) async {
    final preparation = Completer<PreparedComposerUpload>();
    final transfer = Completer<ComposerUploadResult>();
    late void Function(double) progress;
    final file = ComposerUploadFile(
      name: 'movie.mov',
      length: () async => 10,
      openRead: () => Stream.value([1]),
    );
    final composer = ComposerController(
      const ReplyComposerTarget(
        privateMessageTopic: false,
        siteUrl: _siteUrl,
        topicId: 1,
        slug: 'test',
        topicTitle: 'Test',
      ),
      prepareUpload: (file, {required abortTrigger}) => preparation.future,
      imageUploader: (file, {required onProgress, required abortTrigger}) {
        progress = onProgress;
        onProgress(.4);
        return transfer.future;
      },
    );
    addTearDown(composer.dispose);
    composer.addFiles([file], 0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ComposerUploadQueue(composer: composer)),
      ),
    );
    expect(find.text('Optimizing video…'), findsOneWidget);
    preparation.complete(PreparedComposerUpload(file));
    await tester.pump();
    expect(find.text('Optimizing video…'), findsNothing);
    expect(find.textContaining('40%'), findsOneWidget);
    expect(find.byTooltip('Cancel upload'), findsOneWidget);
    progress(.7);
    await tester.pump();
    expect(find.textContaining('70%'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel upload'));
    await tester.pump();
    expect(find.byType(DAttachment), findsNothing);
    progress(.9);
    await tester.pump();
    expect(find.byType(DAttachment), findsNothing);
  });

  testWidgets('an uploaded wide image decodes tall enough to cover its '
      'artwork', (tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    PaintingBinding.instance.imageCache.clear();
    addTearDown(PaintingBinding.instance.imageCache.clear);
    final lifecycle = SiteLifecycle();
    final shell = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      lifecycle: lifecycle,
      siteImages: SiteImageRepository(
        credentials: FakeApiCredentialReader(),
        lifecycle: lifecycle,
        client: MockClient(
          (_) async =>
              http.Response.bytes(blankPng(width: 1600, height: 900), 200),
        ),
      ),
    );
    addTearDown(shell.dispose);
    final composer = ComposerController(
      const ReplyComposerTarget(
        privateMessageTopic: false,
        siteUrl: _siteUrl,
        topicId: 1,
        slug: 'test',
        topicTitle: 'Test',
      ),
    );
    addTearDown(composer.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ShellScope(
          controller: shell,
          child: Scaffold(
            body: ComposerUploadAttachment(
              composer: composer,
              upload: ComposerUploadItem(
                id: 1,
                file: ComposerUploadFile(
                  name: 'wide.png',
                  length: () async => 3,
                  openRead: () => Stream.value(const [1, 2, 3]),
                ),
                progress: 1,
                status: ComposerUploadStatus.completed,
                result: const ComposerUploadResult(
                  id: 7,
                  originalFilename: 'wide.png',
                  shortUrl: 'upload://wide',
                  url: '$_siteUrl/uploads/wide.png',
                  width: 1600,
                  height: 900,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    ui.Image? decoded;
    for (var attempt = 0; attempt < 100 && decoded == null; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      final raw = find.byType(RawImage);
      if (raw.evaluate().isNotEmpty) {
        decoded = tester.widget<RawImage>(raw).image;
      }
    }

    // The attachment stretches the artwork past the thumbnail's own size.
    final artwork = tester.getSize(find.byType(RawImage));
    expect(artwork, const Size.square(40));
    expect(tester.widget<RawImage>(find.byType(RawImage)).fit, BoxFit.cover);
    expect(decoded!.height, greaterThanOrEqualTo(artwork.height * 2));
    expect(decoded.width / decoded.height, closeTo(16 / 9, 0.01));
  });
}

Future<void> _captureAttachment(WidgetTester tester, String name) async {
  final directory = Platform.environment['NATIVE_UI_EVIDENCE_DIR'];
  if (directory == null) return;
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (tester
        .widgetList<RawImage>(find.byType(RawImage))
        .any((image) => image.image != null)) {
      break;
    }
  }
  expect(
    tester
        .widgetList<RawImage>(find.byType(RawImage))
        .where((image) => image.image != null),
    isNotEmpty,
  );
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(directory).createSync(recursive: true);
      File(
        '$directory/$name.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
