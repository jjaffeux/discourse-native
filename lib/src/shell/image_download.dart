import 'package:file_selector/file_selector.dart' as selector;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart' as sharing;

import '../data/site_image_repository.dart';
import 'download_filename.dart';
import 'site_url.dart';

enum ImageDownloadOutcome { saved, shared, cancelled }

abstract interface class ImageDownloadEnvironment {
  Future<String?> chooseSavePath({required String suggestedName});

  Future<void> saveImage(
    Uint8List bytes, {
    required String path,
    required String filename,
    required String mimeType,
  });

  Future<ImageDownloadOutcome> shareImage(
    Uint8List bytes, {
    required String filename,
    required String mimeType,
    Rect? sharePositionOrigin,
  });
}

abstract interface class LightboxImageDownloader {
  Future<ImageDownloadOutcome> download({
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
    ImageDownloadEnvironment? environment,
  }) : _platform = platform ?? defaultTargetPlatform,
       _environment = environment ?? const _NativeImageDownloadEnvironment();

  final TargetPlatform _platform;
  final ImageDownloadEnvironment _environment;

  bool get _usesSaveDialog => switch (_platform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
  };

  @override
  Future<ImageDownloadOutcome> download({
    required String url,
    required String? title,
    required String? siteUrl,
    required SiteImageRepository? repository,
    Rect? sharePositionOrigin,
  }) async {
    final lease = siteUrl == null
        ? null
        : repository?.lifecycle.capture(siteUrl);
    final filename = imageDownloadFilename(title: title, url: url);
    final destination = _usesSaveDialog
        ? await _environment.chooseSavePath(suggestedName: filename)
        : null;
    if (_usesSaveDialog && destination == null) {
      return ImageDownloadOutcome.cancelled;
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

    final mimeType = imageMimeType(filename, isSvg: image.isSvg);
    if (destination != null) {
      await _environment.saveImage(
        image.bytes,
        path: destination,
        filename: filename,
        mimeType: mimeType,
      );
      return ImageDownloadOutcome.saved;
    }
    return _environment.shareImage(
      image.bytes,
      filename: filename,
      mimeType: mimeType,
      sharePositionOrigin: sharePositionOrigin,
    );
  }
}

final class _NativeImageDownloadEnvironment
    implements ImageDownloadEnvironment {
  const _NativeImageDownloadEnvironment();

  @override
  Future<String?> chooseSavePath({required String suggestedName}) async {
    final destination = await selector.getSaveLocation(
      suggestedName: suggestedName,
    );
    return destination?.path;
  }

  @override
  Future<void> saveImage(
    Uint8List bytes, {
    required String path,
    required String filename,
    required String mimeType,
  }) => selector.XFile.fromData(
    bytes,
    name: filename,
    mimeType: mimeType,
  ).saveTo(path);

  @override
  Future<ImageDownloadOutcome> shareImage(
    Uint8List bytes, {
    required String filename,
    required String mimeType,
    Rect? sharePositionOrigin,
  }) async {
    final result = await sharing.SharePlus.instance.share(
      sharing.ShareParams(
        files: [
          sharing.XFile.fromData(bytes, name: filename, mimeType: mimeType),
        ],
        fileNameOverrides: [filename],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    return result.status == sharing.ShareResultStatus.dismissed
        ? ImageDownloadOutcome.cancelled
        : ImageDownloadOutcome.shared;
  }
}

final class ImageDownloadException implements Exception {
  const ImageDownloadException();

  @override
  String toString() => 'The image could not be downloaded.';
}

String imageDownloadFilename({required String? title, required String url}) =>
    downloadFilename(title: title, url: url, fallback: 'image');

String imageMimeType(String filename, {required bool isSvg}) {
  if (isSvg) return 'image/svg+xml';
  return switch (_extension(filename)) {
    'avif' => 'image/avif',
    'bmp' => 'image/bmp',
    'gif' => 'image/gif',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'svg' => 'image/svg+xml',
    'tif' || 'tiff' => 'image/tiff',
    'webp' => 'image/webp',
    _ => 'application/octet-stream',
  };
}

String? _extension(String filename) {
  final match = RegExp(r'\.([A-Za-z0-9]{1,10})$').firstMatch(filename);
  return match?.group(1)?.toLowerCase();
}
