import 'dart:convert';
import 'dart:typed_data';

import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_uploads.dart';
import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/image_decode.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/media_pipeline.dart';

final Uint8List onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8'
  'BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  testWidgets('decodes memory images at their physical layout bound', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    late ResizeImage provider;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            provider = memoryImageForLayout(
              context,
              Uint8List.fromList([1, 2, 3]),
              logicalSize: const Size(24, 18),
            );
            return const SizedBox();
          },
        ),
      ),
    );

    expect(provider.width, 60);
    expect(provider.height, 45);
    expect(provider.policy, ResizeImagePolicy.fit);
    expect(provider.allowUpscaling, isFalse);
  });

  testWidgets('rounds network decode hints up to physical pixels', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    late int pixels;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pixels = imagePhysicalPixels(context, 16.1);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(pixels, 41);
  });

  testWidgets('chat thumbnails decode no wider than their layout', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: ChatUploads(
              siteUrl: 'https://site.test',
              uploads: [
                ChatUpload(
                  url: '/large.png',
                  originalFilename: 'large.png',
                  kind: ChatUploadKind.image,
                  width: 1200,
                  height: 600,
                ),
                ChatUpload(
                  url: '/small.png',
                  originalFilename: 'small.png',
                  kind: ChatUploadKind.image,
                  width: 100,
                  height: 50,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final providers = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .cast<ResizeImage>()
        .toList();
    expect(providers.map((provider) => provider.width), [600, 200]);
    expect(tester.getSize(find.byType(Image).first).height, 150);
    expect(
      providers.map((provider) => provider.allowUpscaling),
      everyElement(isFalse),
    );
  });

  testWidgets('avatars and emoji share the bounded decode policy', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    const avatarUrl = 'https://site.test/avatar.png';
    const emojiUrl = 'https://site.test/emoji.png';
    final pipeline = installTestMediaPipeline(
      client: MockClient((_) async => http.Response.bytes(onePixelPng, 200)),
    );
    await Future.wait([
      pipeline.avatars.load(avatarUrl),
      pipeline.emoji.load(emojiUrl),
    ]);

    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            AvatarImage(
              url: avatarUrl,
              size: 24,
              fallback: SizedBox.square(dimension: 24),
            ),
            EmojiImage(url: emojiUrl, size: 18, alt: ':wave:'),
          ],
        ),
      ),
    );

    final providers = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .cast<ResizeImage>()
        .toList();
    expect(providers.map((provider) => provider.width), [60, 45]);
    expect(providers.map((provider) => provider.height), [60, 45]);
    expect(
      providers.map((provider) => provider.policy),
      everyElement(ResizeImagePolicy.fit),
    );
  });
}
