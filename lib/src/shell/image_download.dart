import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../data/site_image_repository.dart';
import '../foundation/private_file_staging.dart';
import 'download_filename.dart';
import 'media_download_environment.dart';
import 'media_download_result.dart';
import 'site_url.dart';

abstract interface class LightboxImageDownloader {
  Future<MediaDownloadResult> download({
    required String url,
    required String? title,
    required String? siteUrl,
    required SiteImageRepository? repository,
    Rect? sharePositionOrigin,
  });
}

final class NativeLightboxImageDownloader implements LightboxImageDownloader {
  NativeLightboxImageDownloader({
    TargetPlatform? platform,
    MediaDownloadEnvironment? environment,
  }) : _platform = platform ?? defaultTargetPlatform,
       _environment = environment ?? const NativeMediaDownloadEnvironment();

  final TargetPlatform _platform;
  final MediaDownloadEnvironment _environment;

  bool get _usesSaveDialog => switch (_platform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
  };

  @override
  Future<MediaDownloadResult> download({
    required String url,
    required String? title,
    required String? siteUrl,
    required SiteImageRepository? repository,
    Rect? sharePositionOrigin,
  }) async {
    final lease = siteUrl == null
        ? null
        : repository?.lifecycle.capture(siteUrl);
    final suggestedName = imageDownloadFilename(title: title, url: url);
    final destination = _usesSaveDialog
        ? await _environment.chooseSavePath(suggestedName: suggestedName)
        : null;
    if (_usesSaveDialog && destination == null) {
      return const MediaDownloadCancelled();
    }

    if (repository == null ||
        siteUrl == null ||
        lease == null ||
        !lease.isCurrent) {
      throw const ImageDownloadException();
    }
    final absoluteUrl = resolveSiteUrl(url, siteUrl);
    final image = await repository.load(siteUrl: siteUrl, url: absoluteUrl);
    if (image == null || image.bytes.isEmpty || !lease.isCurrent) {
      throw const ImageDownloadException();
    }

    final filename = imageDownloadFilename(
      title: title,
      url: url,
      mediaType: image.mediaType,
    );
    final mimeType = image.mediaType?.mimeType ?? 'application/octet-stream';
    if (destination != null) {
      await _environment.saveBytes(
        image.bytes,
        path: destination,
        filename: filename,
        mimeType: mimeType,
      );
      return MediaDownloadSaved(
        Uri.file(
          destination,
          windows: _platform == TargetPlatform.windows,
        ).pathSegments.last,
      );
    }
    final outcome = await withStagedPrivateFile(
      await _environment.temporaryDirectory(),
      image.bytes,
      prefix: 'image-share-',
      filename: filename,
      use: (file) async {
        // Staging yields, and a retired account must not reach the sheet.
        if (!lease.isCurrent) throw const ImageDownloadException();
        return _environment.shareFile(
          file,
          mimeType: mimeType,
          sharePositionOrigin: sharePositionOrigin,
        );
      },
    );
    return switch (outcome) {
      MediaShareOutcome.shared => const MediaDownloadShared(),
      MediaShareOutcome.cancelled => const MediaDownloadCancelled(),
    };
  }
}

final class ImageDownloadException implements Exception {
  const ImageDownloadException();

  @override
  String toString() => appL10n.theImageCouldNotBeDownloaded;
}

String imageDownloadFilename({
  required String? title,
  required String url,
  SiteImageMediaType? mediaType,
}) => downloadFilename(
  title: title,
  url: url,
  fallback: 'image',
  mediaExtensions: SiteImageMediaType.values.expand((type) => type.extensions),
  preferredExtensions: mediaType?.extensions ?? const [],
);
