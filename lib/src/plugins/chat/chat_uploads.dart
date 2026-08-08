import 'dart:async';

import 'package:flutter/material.dart';

import '../../foundation/diagnostic_errors.dart';
import '../../shell/image_decode.dart';
import '../../shell/lightbox.dart';
import '../../shell/open_link.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'chat_message.dart';

/// What a message carried besides its words.
///
/// A row of its own rather than something folded into the body, because chat
/// cooks the raw message and not the markdown-with-uploads: unlike a post,
/// where images arrive baked into the HTML with the lightbox markup around
/// them, a chat message's attachments are only ever in the `uploads` array and
/// there is nothing in `cooked` to draw.
class ChatUploads extends StatelessWidget {
  const ChatUploads({super.key, required this.siteUrl, required this.uploads});

  final String siteUrl;
  final List<ChatUpload> uploads;

  /// Never wider than this, however large the image was. Roughly what
  /// Discourse's `max_image_width` gives a chat pane, and it keeps a portrait
  /// photo from taking the whole screen.
  static const double maxWidth = 420;
  static const double maxHeight = 320;

  @override
  Widget build(BuildContext context) {
    if (uploads.isEmpty) return const SizedBox.shrink();

    final images = uploads
        .where((u) => u.kind == ChatUploadKind.image)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final upload in uploads)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: upload.kind == ChatUploadKind.image
                ? _Image(siteUrl: siteUrl, upload: upload, gallery: images)
                : _Attachment(siteUrl: siteUrl, upload: upload),
          ),
      ],
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

  /// Every image on this message, so opening one can be swiped through the
  /// rest — which is what the lightbox does for a post's gallery.
  final List<ChatUpload> gallery;

  /// Six bare hex digits, the same shape a category colour arrives in. Held
  /// behind the picture while it loads so the row does not flash white.
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
    // Shrink to fit, never blow a small image up — Discourse's own rule.
    final width = switch (upload.width) {
      final w? when w > 0 => w.toDouble().clamp(0.0, ChatUploads.maxWidth),
      _ => ChatUploads.maxWidth,
    };

    Widget picture = Image.network(
      absolute(upload.thumbnailUrl ?? upload.url),
      fit: BoxFit.cover,
      width: double.infinity,
      cacheWidth: imagePhysicalPixels(context, width),
      errorBuilder: (context, error, stackTrace) {
        reportImageError(error, stackTrace, operation: 'chat.image');
        return UnavailableImage(color: theme.shell.placeholder);
      },
    );

    if (ratio != null) {
      picture = AspectRatio(aspectRatio: ratio, child: picture);
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: width,
        maxHeight: ChatUploads.maxHeight,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Material(
          color: _placeholder ?? theme.shell.floating,
          child: InkWell(onTap: () => _open(context, absolute), child: picture),
        ),
      ),
    );
  }

  /// Opens the full-size image in the viewer a post's images use.
  ///
  /// The gallery is built here rather than read out of markup, because there is
  /// no markup — `LightboxImage` is a plain value object and `LightboxGallery`
  /// takes a list of them, so nothing about the cooked-HTML path is in the way.
  void _open(BuildContext context, String Function(String) absolute) {
    LightboxImage imageOf(ChatUpload upload) => LightboxImage(
      fullSrc: absolute(upload.url),
      thumbnailSrc: upload.thumbnailUrl == null
          ? null
          : absolute(upload.thumbnailUrl!),
      title: upload.originalFilename,
      details: upload.humanFilesize,
      downloadHref: absolute(upload.url),
      width: upload.width?.toDouble(),
      height: upload.height?.toDouble(),
      // The URL is unique per upload here — unlike a post, where the same
      // image can legitimately appear twice — so it makes a fine identity.
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
              ),
          transitionsBuilder: (context, animation, secondary, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      ),
    );
  }
}

/// Everything that is not an image: a video, a sound, or a file.
///
/// One row rather than three players. Playback is a large amount of machinery
/// for a step that cannot yet post any of it, and a link that hands the file to
/// the system is honest about what it does.
class _Attachment extends StatelessWidget {
  const _Attachment({required this.siteUrl, required this.upload});

  final String siteUrl;
  final ChatUpload upload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => openLink(context, _absoluteUploadUrl(siteUrl, upload.url)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.shell.floating,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DIcon(
              DIcons.paperclip,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                upload.originalFilename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            if (upload.humanFilesize case final size?) ...[
              const SizedBox(width: 8),
              Text(
                size,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _absoluteUploadUrl(String siteUrl, String url) {
  if (url.startsWith('//')) return 'https:$url';

  final parsed = Uri.tryParse(url);
  if (parsed == null || parsed.hasScheme) return url;
  return '$siteUrl${url.startsWith('/') ? '' : '/'}$url';
}
