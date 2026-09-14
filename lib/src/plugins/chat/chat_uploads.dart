import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../foundation/diagnostic_errors.dart';
import '../../shell/image_decode.dart';
import '../../shell/inline_video.dart';
import '../../shell/lightbox.dart';
import '../../shell/open_link.dart';
import '../../shell/site_image.dart';
import '../../shell/site_url.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icons.dart';
import 'chat_message.dart';

/// Chat attachments exist only in the `uploads` array, not cooked HTML.
class ChatUploads extends StatelessWidget {
  const ChatUploads({
    super.key,
    required this.siteUrl,
    required this.uploads,
    this.alignment = CrossAxisAlignment.start,
  });

  final String siteUrl;
  final List<ChatUpload> uploads;

  /// Horizontal placement within the available message width.
  final CrossAxisAlignment alignment;

  /// Core's chat-specific width ceiling; images are capped at 150px high.
  static const double maxWidth = 420;
  static const double maxHeight = 150;

  @override
  Widget build(BuildContext context) {
    if (uploads.isEmpty) return const SizedBox.shrink();

    final images = uploads
        .where((u) => u.kind == ChatUploadKind.image)
        .toList();

    return Column(
      crossAxisAlignment: alignment,
      children: [
        for (final upload in uploads)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: upload.kind == ChatUploadKind.image
                ? _Image(siteUrl: siteUrl, upload: upload, gallery: images)
                : upload.kind == ChatUploadKind.video
                ? _Video(siteUrl: siteUrl, upload: upload)
                : _Attachment(siteUrl: siteUrl, upload: upload),
          ),
      ],
    );
  }
}

class _Video extends StatelessWidget {
  const _Video({required this.siteUrl, required this.upload});

  final String siteUrl;
  final ChatUpload upload;

  @override
  Widget build(BuildContext context) {
    final data = InlineVideoData.fromUpload(
      url: upload.url,
      title: upload.originalFilename,
      siteUrl: siteUrl,
      posterUrl: upload.thumbnailUrl,
      aspectRatio: upload.aspectRatio,
    );
    if (data == null) {
      return _Attachment(siteUrl: siteUrl, upload: upload);
    }
    return InlineVideo(
      data: data,
      siteUrl: siteUrl,
      maximumWidth: ChatUploads.maxWidth,
      maximumHeight: 240,
      padding: EdgeInsets.zero,
    );
  }
}

class _Image extends StatelessWidget {
  const _Image({
    required this.siteUrl,
    required this.upload,
    required this.gallery,
  });

  final String siteUrl;
  final ChatUpload upload;

  final List<ChatUpload> gallery;

  Color? get _placeholder {
    final value = upload.dominantColor;
    if (value == null || value.length != 6) return null;
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? null : Color(0xFF000000 | parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String absolute(String url) => _absoluteUploadUrl(siteUrl, url);

    final ratio = upload.aspectRatio;
    // Discourse shrinks oversized chat images but never upscales them.
    final sourceWidth = switch (upload.width) {
      final w? when w > 0 => w.toDouble().clamp(0.0, ChatUploads.maxWidth),
      _ => ChatUploads.maxWidth,
    };
    final width = ratio == null
        ? sourceWidth
        : math.min(sourceWidth, ChatUploads.maxHeight * ratio);
    void open() => _open(context, absolute);

    Widget picture = SiteImage(
      url: absolute(upload.thumbnailUrl ?? upload.url),
      siteUrl: siteUrl,
      fit: BoxFit.contain,
      width: double.infinity,
      cacheWidth: imagePhysicalPixels(context, width),
      gifPlaybackControls: true,
      gifPlaybackControlsAtTop: true,
      errorBuilder: (context, error, stackTrace) {
        reportImageError(error, stackTrace, operation: 'chat.image');
        return UnavailableImage(color: theme.shell.placeholder);
      },
    );

    if (ratio != null) {
      picture = DAspectRatio(ratio: ratio, child: picture);
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: width,
        maxHeight: ChatUploads.maxHeight,
      ),
      child: DImagePreview(
        semanticLabel: 'Open image: ${upload.originalFilename}',
        filename: upload.originalFilename,
        details: [
          if (upload.width case final width? when width > 0)
            if (upload.height case final height? when height > 0)
              '$width×$height',
          if (upload.humanFilesize case final size? when size.isNotEmpty) size,
        ].join(' '),
        onPressed: open,
        child: ColoredBox(
          color: _placeholder ?? theme.shell.floating,
          child: picture,
        ),
      ),
    );
  }

  void _open(BuildContext context, String Function(String) absolute) {
    LightboxImage imageOf(ChatUpload upload) => LightboxImage(
      fullSrc: absolute(upload.url),
      thumbnailSrc: upload.thumbnailUrl == null
          ? null
          : absolute(upload.thumbnailUrl!),
      title: upload.originalFilename,
      description: upload.originalFilename,
      details: upload.humanFilesize,
      downloadHref: absolute(upload.url),
      width: upload.width?.toDouble(),
      height: upload.height?.toDouble(),
      heroTag: 'chat-upload-${upload.url}',
    );

    final images = [for (final u in gallery) imageOf(u)];
    final index = gallery.indexOf(upload);

    unawaited(
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<void>(
          opaque: false,
          barrierColor: Colors.black.withValues(alpha: 0.92),
          barrierDismissible: true,
          barrierLabel: MaterialLocalizations.of(
            context,
          ).modalBarrierDismissLabel,
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (context, animation, secondaryAnimation) =>
              LightboxGallery(
                images: images,
                initialIndex: index < 0 ? 0 : index,
                siteUrl: siteUrl,
              ),
          transitionsBuilder: (context, animation, secondary, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      ),
    );
  }
}

class _Attachment extends StatelessWidget {
  const _Attachment({required this.siteUrl, required this.upload});

  final String siteUrl;
  final ChatUpload upload;

  @override
  Widget build(BuildContext context) {
    final filesize = upload.humanFilesize?.trim();
    final label = filesize == null || filesize.isEmpty
        ? 'Open attachment: ${upload.originalFilename}'
        : 'Open attachment: ${upload.originalFilename}, $filesize';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: ChatUploads.maxWidth),
      child: DAttachment(
        size: DAttachmentSize.extraSmall,
        // The attachment border sits outside the trigger's content box. Keep
        // the link itself at the established 44 logical-pixel hit target.
        constraints: const BoxConstraints(minWidth: 160, minHeight: 46),
        children: [
          const DAttachmentMedia(child: DIcon(DIcons.paperclip, size: 16)),
          DAttachmentContent(
            children: [
              DAttachmentTitle(child: Text(upload.originalFilename)),
              if (filesize case final size?)
                DAttachmentDescription(child: Text(size)),
            ],
          ),
          DAttachmentTrigger(
            semanticLabel: label,
            isLink: true,
            onPressed: () =>
                openLink(context, _absoluteUploadUrl(siteUrl, upload.url)),
          ),
        ],
      ),
    );
  }
}

String _absoluteUploadUrl(String siteUrl, String url) {
  if (url.startsWith('//')) return 'https:$url';

  final parsed = Uri.tryParse(url);
  if (parsed == null || parsed.hasScheme) return url;
  return resolveSitePath(siteUrl, url);
}
