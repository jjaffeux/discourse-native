import 'dart:ui' as ui;

import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_upload_attachment.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/blank_png.dart';
import 'support/fakes.dart';

const _siteUrl = 'https://forum.example';

void main() {
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
      const ComposerTarget(
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
