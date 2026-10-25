import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/site_pdf_thumbnail_repository.dart';
import 'package:discourse_native/src/data/site_thumbnail_repository.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/pdf_attachment.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/blank_png.dart';
import 'support/fakes.dart';

const _site = 'https://forum.example';

void main() {
  testWidgets('retained PDF reader generator demand trace', (tester) async {
    final png = blankPng(width: 171, height: 256);
    for (var trial = 0; trial < 5; trial++) {
      final generated = <String>[];
      final lifecycle = SiteLifecycle();
      final shell = ShellController(
        instanceStore: FakeInstanceStore(),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        lifecycle: lifecycle,
        pdfThumbnails: SitePdfThumbnailRepository(
          credentials: FakeApiCredentialReader(),
          lifecycle: lifecycle,
          generator: (source) {
            generated.add(source.path);
            return ThumbnailRequest(SynchronousFuture(png), () {});
          },
        ),
      );
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: ShellScope(
            controller: shell,
            child: Material(
              child: Center(
                child: SizedBox(
                  width: 320,
                  height: 220,
                  child: SingleChildScrollView(
                    controller: scroll,
                    child: CookedHtml(
                      siteUrl: _site,
                      html: [
                        for (var i = 0; i < 20; i++)
                          '<p><a class="attachment" href="/uploads/file-$i.pdf">file-$i.pdf</a></p>',
                      ].join(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _drain(tester);
      expect(find.byType(PdfThumbnail), findsNWidgets(20));
      final retained = tester.element(find.byType(PdfThumbnail).first);
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      List<String> visibleSources() => tester
          .widgetList<PdfThumbnail>(find.byType(PdfThumbnail))
          .where((pdf) => tester.getRect(find.byWidget(pdf)).overlaps(viewport))
          .map((pdf) => Uri.parse(pdf.url!).path)
          .toList();
      final initialVisible = visibleSources();
      expect(initialVisible, isNotEmpty);
      expect(generated.toSet(), containsAll(initialVisible));
      final initial = generated.toList();
      if (!const bool.fromEnvironment('PDF_BASELINE')) {
        expect(initial.toSet(), initialVisible.toSet());
      }
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await _drain(tester);
      expect(tester.element(find.byType(PdfThumbnail).first), same(retained));
      final lastVisible = visibleSources();
      expect(generated.toSet(), containsAll(lastVisible));
      final afterJump = generated.length;
      scroll.jumpTo(0);
      await _drain(tester);
      expect(generated.length, afterJump);
      if (!const bool.fromEnvironment('PDF_BASELINE')) {
        expect(generated.toSet(), {...initialVisible, ...lastVisible});
      }
      bool allVisibleArtwork() =>
          tester
              .widgetList<RawImage>(find.byType(RawImage))
              .where(
                (image) =>
                    tester.getRect(find.byWidget(image)).overlaps(viewport),
              )
              .where((image) => image.image != null)
              .length ==
          initialVisible.length;
      for (var attempt = 0; attempt < 50 && !allVisibleArtwork(); attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(allVisibleArtwork(), isTrue);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      stdout.writeln(
        'PDF_TRACE ${jsonEncode({'trial': trial, 'mounted': 20, 'initialVisible': initialVisible, 'initialGenerated': initial, 'lastVisible': lastVisible, 'totalGenerated': generated, 'errors': 0, 'scheduledIdleFrames': false})}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await _drain(tester);
      scroll.dispose();
      shell.dispose();
    }
  });
}

Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
}
