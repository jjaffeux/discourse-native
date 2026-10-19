import 'dart:ui' as ui;

import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'support/native_ui_evidence.dart';

void main() {
  testWidgets('post image delivery retains rendered content', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(720, 600);
    addTearDown(tester.view.reset);
    await prepareNativeUiEvidence(tester);
    final bytes = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 120, 60),
        Paint()..color = const Color(0xFF2563EB),
      );
      canvas.drawRect(
        const Rect.fromLTWH(60, 0, 60, 60),
        Paint()..color = const Color(0xFF38BDF8),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(120, 60);
      picture.dispose();
      try {
        return (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }))!;
    const site = 'https://forum.example';
    final repository = SiteImageRepository(
      credentials: FakeApiCredentialReader(),
      lifecycle: SiteLifecycle(),
      client: MockClient((_) async => http.Response.bytes(bytes, 200)),
    );
    final shell = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      siteImages: repository,
    );
    addTearDown(shell.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: nativeUiEvidenceBuilder,
        home: ShellScope(
          controller: shell,
          child: const SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: 400,
                child: CookedHtml(
                  siteUrl: site,
                  html:
                      '<p>Images in a post</p>'
                      '<p><img src="$site/plain.png" width="240" height="120"></p>'
                      '<div class="lightbox-wrapper"><a class="lightbox" '
                      'href="$site/full.png" data-download-href="$site/full.png">'
                      '<img src="$site/thumb.png" width="240" height="120">'
                      '<div class="meta"><span class="filename">Sailing.png</span>'
                      '<span class="informations">120 x 60</span></div>'
                      '</a></div>',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var index = 0; index < 100; index++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      final images = tester.widgetList<RawImage>(find.byType(RawImage));
      if (images.length == 2 && images.every((image) => image.image != null)) {
        break;
      }
    }
    await tester.pumpAndSettle();
    final rendered = tester.widgetList<RawImage>(find.byType(RawImage));
    expect(rendered.where((image) => image.image != null), hasLength(2));
    expect(tester.takeException(), isNull);
    await captureNativeUi(tester, 'post-images');
  });
}
