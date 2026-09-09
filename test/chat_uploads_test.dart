import 'dart:convert';

import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_uploads.dart';
import 'package:discourse_native/src/shell/lightbox.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

const _imagePath = 'a%20b%2Fc.png?token=a%2Fb%2B%3D&name=a+b';
const _thumbnailPath = 'thumb%20b%2Fc.png?token=b%2Fc%2B%3D&name=b+c';
const _attachmentPath = 'notes%20b%2Fc.pdf?token=c%2Fd%2B%3D&name=c+d';
final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8'
  'BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  const cases = [
    (
      name: 'root-relative URLs on a subfolder forum',
      siteUrl: 'https://example.com/community',
      prefix: '/community/uploads/default/',
      target: 'https://example.com/community/uploads/default/',
    ),
    (
      name: 'root-relative URLs outside the forum directory',
      siteUrl: 'https://example.com/community',
      prefix: '/uploads/default/',
      target: 'https://example.com/uploads/default/',
    ),
    (
      name: 'relative URLs on a subfolder forum',
      siteUrl: 'https://example.com/community',
      prefix: 'uploads/default/',
      target: 'https://example.com/community/uploads/default/',
    ),
    (
      name: 'relative URLs with a trailing forum slash',
      siteUrl: 'https://example.com/community/',
      prefix: 'uploads/default/',
      target: 'https://example.com/community/uploads/default/',
    ),
    (
      name: 'root-relative URLs with an encoded forum path and port',
      siteUrl: 'https://example.com:8443/some%20community',
      prefix: '/some%20community/uploads/default/',
      target: 'https://example.com:8443/some%20community/uploads/default/',
    ),
    (
      name: 'relative URLs with an encoded forum path and port',
      siteUrl: 'https://example.com:8443/some%20community',
      prefix: 'uploads/default/',
      target: 'https://example.com:8443/some%20community/uploads/default/',
    ),
    (
      name: 'root-relative URLs on a root forum',
      siteUrl: 'https://example.com',
      prefix: '/uploads/default/',
      target: 'https://example.com/uploads/default/',
    ),
    (
      name: 'relative URLs on a root forum',
      siteUrl: 'https://example.com/',
      prefix: 'uploads/default/',
      target: 'https://example.com/uploads/default/',
    ),
    (
      name: 'absolute CDN URLs',
      siteUrl: 'https://example.com/community',
      prefix: 'https://cdn.example.com:8443/uploads/',
      target: 'https://cdn.example.com:8443/uploads/',
    ),
    (
      name: 'protocol-relative CDN URLs on an HTTP forum',
      siteUrl: 'http://example.com:3000/community',
      prefix: '//cdn.example.com:8443/uploads/',
      target: 'https://cdn.example.com:8443/uploads/',
    ),
  ];

  for (final input in cases) {
    testWidgets('opens the previewed chat image for ${input.name}', (
      tester,
    ) async {
      final requests = <(String, String)>[];
      await _pumpImage(
        tester,
        siteUrl: input.siteUrl,
        upload: ChatUpload(
          url: '${input.prefix}$_imagePath',
          thumbnailUrl: '${input.prefix}$_thumbnailPath',
          originalFilename: 'a b.png',
          kind: ChatUploadKind.image,
          width: 400,
          height: 200,
        ),
        requests: requests,
      );

      final fullUrl = '${input.target}$_imagePath';
      final thumbnailUrl = '${input.target}$_thumbnailPath';
      expect(requests, [('GET', thumbnailUrl)]);

      await tester.tap(find.bySemanticsLabel('Open image: a b.png'));
      await tester.pumpAndSettle();

      final gallery = tester.widget<LightboxGallery>(
        find.byType(LightboxGallery),
      );
      expect(gallery.siteUrl, input.siteUrl);
      final image = gallery.images.single;
      expect(image.fullSrc, fullUrl);
      expect(image.thumbnailSrc, thumbnailUrl);
      expect(image.downloadHref, fullUrl);
      expect(requests, [('GET', thumbnailUrl), ('GET', fullUrl)]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('launches the chat attachment for ${input.name}', (
      tester,
    ) async {
      const launcher = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final launched = <String>[];
      messenger.setMockMethodCallHandler(launcher, (call) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(launcher, null));

      await tester.pumpWidget(
        _app(
          ChatUploads(
            siteUrl: input.siteUrl,
            uploads: [
              ChatUpload(
                url: '${input.prefix}$_attachmentPath',
                originalFilename: 'notes.pdf',
                kind: ChatUploadKind.attachment,
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Open attachment: notes.pdf'));
      await tester.pumpAndSettle();

      expect(launched, ['${input.target}$_attachmentPath']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('opens the same subfolder image without a separate thumbnail', (
    tester,
  ) async {
    const siteUrl = 'https://example.com/community';
    const fullUrl = '$siteUrl/uploads/default/a.png';
    final requests = <(String, String)>[];
    await _pumpImage(
      tester,
      siteUrl: siteUrl,
      upload: const ChatUpload(
        url: '/community/uploads/default/a.png',
        originalFilename: 'a.png',
        kind: ChatUploadKind.image,
        width: 400,
        height: 200,
      ),
      requests: requests,
    );
    expect(requests, [('GET', fullUrl)]);

    await tester.tap(find.bySemanticsLabel('Open image: a.png'));
    await tester.pumpAndSettle();

    final gallery = tester.widget<LightboxGallery>(
      find.byType(LightboxGallery),
    );
    final image = gallery.images.single;
    expect(image.fullSrc, fullUrl);
    expect(image.thumbnailSrc, isNull);
    expect(image.downloadHref, fullUrl);
    expect(requests, [('GET', fullUrl)]);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: Align(alignment: Alignment.topLeft, child: child),
  ),
);

Future<void> _pumpImage(
  WidgetTester tester, {
  required String siteUrl,
  required ChatUpload upload,
  required List<(String, String)> requests,
}) async {
  final client = MockClient((request) async {
    requests.add((request.method, request.url.toString()));
    return http.Response.bytes(_onePixelPng, 200);
  });
  addTearDown(client.close);
  final repository = SiteImageRepository(
    credentials: FakeApiCredentialReader(),
    lifecycle: SiteLifecycle(),
    client: client,
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
    ShellScope(
      controller: shell,
      child: _app(ChatUploads(siteUrl: siteUrl, uploads: [upload])),
    ),
  );
  await tester.pumpAndSettle();
}
