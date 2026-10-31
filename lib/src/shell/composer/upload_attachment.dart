import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../../data/site_pdf_thumbnail_repository.dart';
import '../../models/composer_upload.dart';
import '../../models/site_config.dart';
import '../../theme/d_icons.dart';
import '../inline_video.dart';
import '../lightbox.dart';
import '../pdf_attachment.dart';
import '../shell_scope.dart';
import '../site_image.dart';
import 'controller.dart';
import 'upload_preview.dart';

class ComposerUploadAttachment extends StatelessWidget {
  const ComposerUploadAttachment({
    super.key,
    required this.composer,
    required this.upload,
  });

  final ComposerController composer;
  final ComposerUploadItem upload;

  @override
  Widget build(BuildContext context) {
    final preview = composer.uploadPreview(upload.id);
    preview?.start();
    return preview == null
        ? _build(context, null)
        : ListenableBuilder(
            listenable: preview,
            builder: (context, _) => _build(context, preview),
          );
  }

  Widget _build(BuildContext context, ComposerUploadPreview? preview) {
    final failed = upload.status == ComposerUploadStatus.failed;
    final completed = upload.status == ComposerUploadStatus.completed;
    final thumbnail = completed ? upload.result : null;
    final isPdf = isPdfAttachment(
      upload.file.name,
      thumbnail?.url ?? 'upload://pending',
    );
    final isImage = SiteConfig.isImageFilename(upload.file.name);
    final retrying = upload.status == ComposerUploadStatus.retrying;
    final processing = upload.status == ComposerUploadStatus.processing;
    final description = failed
        ? upload.error ?? context.l10n.couldnTUploadThisImage
        : completed
        ? context.l10n.uploaded
        : processing
        ? upload.file.isVideo
              ? context.l10n.optimizingVideo
              : isImage
              ? context.l10n.processingImage
              : context.l10n.preparingUpload
        : context.l10n.messageComposeruploadattachment(
            (retrying).toString(),
            ((retrying) ? (context.l10n.retrying) : '').toString(),
            ((upload.progress * 100).round()).toString(),
            ((!(retrying)) ? (context.l10n.uploading) : '').toString(),
          );
    final canPreview =
        (isImage || upload.file.isVideo) &&
        (thumbnail != null || preview?.file != null);
    return DAttachment(
      width: double.infinity,
      state: failed
          ? DAttachmentState.error
          : completed
          ? DAttachmentState.done
          : retrying || processing
          ? DAttachmentState.processing
          : DAttachmentState.uploading,
      liveRegion: !completed,
      children: [
        if (canPreview)
          DAttachmentTrigger(
            semanticLabel: context.l10n.previewOf(upload.file.name),
            onPressed: () => unawaited(_openPreview(context)),
          ),
        DAttachmentMedia(
          variant:
              preview?.file != null ||
                  (thumbnail != null &&
                      (isPdf || isImage || thumbnail.thumbnailUrl != null))
              ? DAttachmentMediaVariant.image
              : DAttachmentMediaVariant.icon,
          child: thumbnail == null && preview?.file != null
              ? _LocalPreview(preview: preview!)
              : thumbnail != null && isPdf && thumbnail.thumbnailUrl == null
              ? PdfThumbnail(
                  url: thumbnail.url,
                  siteUrl: composer.target.siteUrl,
                )
              : thumbnail != null && (isImage || thumbnail.thumbnailUrl != null)
              ? _ComposerUploadThumbnail(
                  siteUrl: composer.target.siteUrl,
                  filename: upload.file.name,
                  uploadId: thumbnail.id,
                  url: thumbnail.previewUrl,
                )
              : failed
              ? const Icon(Icons.error_outline)
              : completed
              ? Icon(isImage ? Icons.image_outlined : Icons.attach_file)
              : const DSpinner(size: 16, semanticLabel: null),
        ),
        DAttachmentContent(
          children: [
            DAttachmentTitle(child: Text(upload.file.name)),
            DAttachmentDescription(
              child: failed
                  ? DTooltip(message: description, child: Text(description))
                  : Text(description),
            ),
          ],
        ),
        DAttachmentActions(
          children: [
            if (failed && upload.retryable)
              DAttachmentAction(
                icon: const Icon(Icons.refresh),
                tooltip: context.l10n.retryUpload,
                onPressed: composer.canUpload
                    ? () => composer.retryUpload(upload.id)
                    : null,
              ),
            DAttachmentAction(
              icon: const Icon(Icons.close),
              tooltip: completed || failed
                  ? context.l10n.removeUpload
                  : processing && upload.file.isVideo
                  ? context.l10n.cancelVideoOptimization
                  : context.l10n.cancelUpload,
              onPressed: completed || failed
                  ? () => composer.removeUpload(upload.id)
                  : () => composer.cancelUpload(upload.id),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openPreview(BuildContext context) async {
    final retired = Completer<void>();
    final lease = ShellScope.maybeIdentityOf(
      context,
    )?.lifecycle.capture(composer.target.siteUrl);
    final stopRetirement = lease?.onRetire(() {
      if (!retired.isCompleted) retired.complete();
    });
    final releases = <VoidCallback>[];
    final images = <LightboxImage>[];
    final ids = <int>[];
    for (final item in composer.uploads) {
      final result = item.result;
      final preview = composer.uploadPreview(item.id);
      final video = item.file.isVideo;
      if (!video && !SiteConfig.isImageFilename(item.file.name)) continue;
      LightboxSource? source;
      if (result != null) {
        if (video) {
          final data = InlineVideoData.fromUpload(
            url: result.url,
            title: item.file.name,
            siteUrl: composer.target.siteUrl,
            posterUrl: result.thumbnailUrl,
          );
          if (data != null) source = LightboxVideo(data);
        } else {
          source = RemoteLightboxImage(result.url);
        }
      } else if (preview?.file case final file?) {
        releases.add(preview!.retain());
        source = video
            ? LightboxVideo(
                InlineVideoData.localFile(file: file, title: item.file.name),
              )
            : LocalLightboxImage(file);
      }
      if (source == null) continue;
      ids.add(item.id);
      images.add(
        LightboxImage(
          source: source,
          thumbnailSrc: result?.thumbnailUrl,
          title: item.file.name,
          description: item.file.name,
          details: null,
          downloadHref: null,
          width: (result?.width ?? preview?.width)?.toDouble(),
          height: (result?.height ?? preview?.height)?.toDouble(),
          heroTag: ('composer-preview', composer, item.id),
        ),
      );
    }
    try {
      final index = ids.indexOf(upload.id);
      if (index < 0) return;
      await showLightboxGallery(
        context,
        images: images,
        initialIndex: index,
        siteUrl: composer.target.siteUrl,
        dismissWhen: Future.any([composer.disposed, retired.future]),
      );
    } finally {
      stopRetirement?.call();
      if (!retired.isCompleted) retired.complete();
      for (final release in releases) {
        release();
      }
    }
  }
}

class _LocalPreview extends StatelessWidget {
  const _LocalPreview({required this.preview});
  final ComposerUploadPreview preview;
  @override
  Widget build(BuildContext context) {
    final poster = preview.poster;
    if (preview.isVideo && poster == null) {
      return const DIcon(DIcons.play);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: preview.isVideo
          ? Image(
              image: ResizeImage(
                MemoryImage(poster!),
                width: 128,
                height: 128,
                policy: ResizeImagePolicy.fit,
              ),
              width: 32,
              height: 32,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const DIcon(DIcons.play),
            )
          : Image(
              image: ResizeImage(
                FileImage(preview.file!),
                width: 128,
                height: 128,
                policy: ResizeImagePolicy.fit,
              ),
              width: 32,
              height: 32,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const DIcon(DIcons.fileLines),
            ),
    );
  }
}

class _ComposerUploadThumbnail extends StatelessWidget {
  const _ComposerUploadThumbnail({
    required this.siteUrl,
    required this.filename,
    required this.uploadId,
    required this.url,
  });

  static const double size = 32;

  final String siteUrl;
  final String filename;
  final int uploadId;
  final String url;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.image_outlined,
      size: 18,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        // The attachment owns the artwork's extent and may stretch it past
        // [size], so the decode covers the size it is drawn at.
        child: LayoutBuilder(
          builder: (context, constraints) => SiteImage(
            key: ValueKey('composer-upload-thumbnail-$uploadId'),
            url: url,
            siteUrl: siteUrl,
            fit: BoxFit.cover,
            width: size,
            height: size,
            coverDecodeSize: constraints.constrain(const Size.square(size)),
            semanticLabel: context.l10n.previewOf((filename).toString()),
            loadingBuilder: (_) => SizedBox.square(
              dimension: size,
              child: Center(child: fallback),
            ),
            errorBuilder: (_, _, _) => SizedBox.square(
              dimension: size,
              child: Center(child: fallback),
            ),
          ),
        ),
      ),
    );
  }
}
