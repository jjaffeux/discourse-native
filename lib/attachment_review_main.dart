import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'src/models/composer_upload.dart';
import 'src/plugins/chat/chat_message.dart';
import 'src/plugins/chat/chat_uploads.dart';
import 'src/shell/composer_controller.dart';
import 'src/shell/composer_panel.dart';
import 'src/styleguide/examples/attachment_examples.dart';
import 'src/theme/app_theme.dart';

void main() => runApp(const AttachmentReviewApp());

class AttachmentReviewApp extends StatefulWidget {
  const AttachmentReviewApp({super.key});

  @override
  State<AttachmentReviewApp> createState() => _AttachmentReviewAppState();
}

class _AttachmentReviewAppState extends State<AttachmentReviewApp> {
  var dark = false;
  var customPalette = false;
  var rtl = false;
  var largeText = false;
  var reducedMotion = false;
  var narrow = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _reviewTheme(Brightness.light, customPalette: customPalette),
    darkTheme: _reviewTheme(Brightness.dark, customPalette: customPalette),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(largeText ? 2 : 1),
            disableAnimations: reducedMotion,
          ),
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Attachment source review'),
              actions: [
                DButton.iconOnly(
                  onPressed: () => setState(() => dark = !dark),
                  variant: DButtonVariant.ghost,
                  tooltip: dark ? 'Use light theme' : 'Use dark theme',
                  icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
                ),
                DButton.iconOnly(
                  onPressed: () =>
                      setState(() => customPalette = !customPalette),
                  variant: DButtonVariant.ghost,
                  tooltip: customPalette
                      ? 'Use default palette'
                      : 'Use custom palette and radius',
                  icon: const Icon(Icons.palette_outlined),
                ),
                DButton.iconOnly(
                  onPressed: () => setState(() => rtl = !rtl),
                  variant: DButtonVariant.ghost,
                  tooltip: rtl ? 'Use left-to-right' : 'Use right-to-left',
                  icon: const Icon(Icons.format_textdirection_r_to_l),
                ),
                DButton.iconOnly(
                  onPressed: () => setState(() => largeText = !largeText),
                  variant: DButtonVariant.ghost,
                  tooltip: largeText ? 'Use 100% text' : 'Use 200% text',
                  icon: const Icon(Icons.text_increase),
                ),
                DButton.iconOnly(
                  onPressed: () =>
                      setState(() => reducedMotion = !reducedMotion),
                  variant: DButtonVariant.ghost,
                  tooltip: reducedMotion
                      ? 'Use standard motion'
                      : 'Use reduced motion',
                  icon: const Icon(Icons.motion_photos_off_outlined),
                ),
                DButton.iconOnly(
                  onPressed: () => setState(() => narrow = !narrow),
                  variant: DButtonVariant.ghost,
                  tooltip: narrow ? 'Use wide canvas' : 'Use narrow canvas',
                  icon: const Icon(Icons.width_normal),
                ),
              ],
            ),
            body: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: narrow ? 420 : double.infinity,
                ),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Text(
                      'Production adapters',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const _ProductionUploadFixture(),
                    const SizedBox(height: 16),
                    const ChatUploads(
                      siteUrl: 'https://meta.discourse.org',
                      uploads: [
                        ChatUpload(
                          id: 71,
                          url: '/uploads/attachment-review.pdf',
                          originalFilename: 'attachment-review.pdf',
                          kind: ChatUploadKind.attachment,
                          humanFilesize: '2.4 MB',
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Frozen documented examples',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final example in attachmentExamples.examples) ...[
                      Text(
                        example.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(example.description),
                      const SizedBox(height: 12),
                      Builder(builder: example.builder),
                      const SizedBox(height: 32),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

ThemeData _reviewTheme(Brightness brightness, {required bool customPalette}) {
  final base = brightness == Brightness.dark ? AppTheme.dark : AppTheme.light;
  if (!customPalette) return base;

  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xFF7C3AED),
    brightness: brightness,
  );
  final themed = base.copyWith(colorScheme: colors);
  return themed.copyWith(
    extensions: [
      ...base.extensions.values.where((extension) => extension is! DTokens),
      DTokens.fromTheme(themed).copyWith(radius: 14),
    ],
  );
}

class _ProductionUploadFixture extends StatefulWidget {
  const _ProductionUploadFixture();

  @override
  State<_ProductionUploadFixture> createState() =>
      _ProductionUploadFixtureState();
}

class _ProductionUploadFixtureState extends State<_ProductionUploadFixture> {
  late final ComposerController composer;
  final calls = <_UploadCall>[];

  @override
  void initState() {
    super.initState();
    composer = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://meta.discourse.org',
        topicId: 7,
        slug: 'attachment-review',
        topicTitle: 'Attachment review',
      ),
      imageUploader: (file, {required onProgress, required abortTrigger}) {
        final call = _UploadCall(onProgress);
        calls.add(call);
        return call.result.future;
      },
    )..addListener(_changed);
    _newUpload();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && calls.isNotEmpty) calls.last.onProgress(.64);
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _newUpload() {
    composer.addImages([
      ComposerUploadFile(
        name: 'sales-dashboard.pdf',
        length: () async => 2048,
        openRead: () => Stream.value(const [1, 2, 3]),
      ),
    ], 0);
  }

  @override
  void dispose() {
    composer
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (composer.uploads.isNotEmpty) ComposerUploadQueue(composer: composer),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          DButton(
            onPressed: composer.uploads.isEmpty ? _newUpload : null,
            variant: DButtonVariant.outline,
            label: const Text('New local upload'),
          ),
          DButton(
            onPressed: calls.isNotEmpty && !calls.last.result.isCompleted
                ? () => calls.last.onProgress(.64)
                : null,
            variant: DButtonVariant.outline,
            label: const Text('64% progress'),
          ),
          DButton(
            onPressed: calls.isNotEmpty && !calls.last.result.isCompleted
                ? () => calls.last.result.completeError(
                    const ComposerUploadException('Upload failed. Try again.'),
                  )
                : null,
            variant: DButtonVariant.outline,
            label: const Text('Fail upload'),
          ),
          DButton(
            onPressed: calls.isNotEmpty && !calls.last.result.isCompleted
                ? () => calls.last.result.complete(
                    const ComposerUploadResult(
                      id: 73,
                      originalFilename: 'sales-dashboard.pdf',
                      shortUrl: 'upload://sales-dashboard.pdf',
                      url: '/uploads/sales-dashboard.pdf',
                    ),
                  )
                : null,
            variant: DButtonVariant.outline,
            label: const Text('Complete upload'),
          ),
        ],
      ),
    ],
  );
}

class _UploadCall {
  _UploadCall(this.onProgress);
  final void Function(double) onProgress;
  final result = Completer<ComposerUploadResult>();
}
