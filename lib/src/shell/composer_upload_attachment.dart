import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/composer_upload.dart';
import '../models/site_config.dart';
import 'composer_controller.dart';
import 'image_decode.dart';
import 'site_image.dart';

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
    final failed = upload.status == ComposerUploadStatus.failed;
    final completed = upload.status == ComposerUploadStatus.completed;
    final thumbnail = completed ? upload.result : null;
    final isImage = SiteConfig.isImageFilename(upload.file.name);
    final retrying = upload.status == ComposerUploadStatus.retrying;
    final description = failed
        ? upload.error ?? "Couldn't upload this image."
        : completed
        ? 'Uploaded'
        : '${retrying ? 'Retrying' : 'Uploading'} · ${(upload.progress * 100).round()}%';
    return DAttachment(
      width: double.infinity,
      state: failed
          ? DAttachmentState.error
          : completed
          ? DAttachmentState.done
          : retrying
          ? DAttachmentState.processing
          : DAttachmentState.uploading,
      liveRegion: !completed,
      children: [
        DAttachmentMedia(
          variant:
              thumbnail != null && (isImage || thumbnail.thumbnailUrl != null)
              ? DAttachmentMediaVariant.image
              : DAttachmentMediaVariant.icon,
          child:
              thumbnail != null && (isImage || thumbnail.thumbnailUrl != null)
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
                tooltip: 'Retry upload',
                onPressed: composer.canUpload
                    ? () => composer.retryUpload(upload.id)
                    : null,
              ),
            DAttachmentAction(
              icon: const Icon(Icons.close),
              tooltip: completed || failed ? 'Remove upload' : 'Cancel upload',
              onPressed: completed || failed
                  ? () => composer.removeUpload(upload.id)
                  : () => composer.cancelUpload(upload.id),
            ),
          ],
        ),
      ],
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
        child: SiteImage(
          key: ValueKey('composer-upload-thumbnail-$uploadId'),
          url: url,
          siteUrl: siteUrl,
          fit: BoxFit.cover,
          width: size,
          height: size,
          cacheWidth: imagePhysicalPixels(context, size),
          cacheHeight: imagePhysicalPixels(context, size),
          semanticLabel: 'Preview of $filename',
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
    );
  }
}
