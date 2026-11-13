import 'dart:async';
import 'dart:io';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

import '../data/api_credentials.dart';
import '../data/http_transport.dart';
import '../data/http_url_safety.dart';
import '../data/site_asset_account.dart';
import '../data/site_lifecycle.dart';
import '../foundation/media_download_environment.dart';
import '../foundation/native_media_download_environment.dart';
import '../foundation/private_file_staging.dart';
import 'download_filename.dart';
import 'media_download_result.dart';

abstract interface class VideoDownloader {
  Future<MediaDownloadResult> download({
    required Uri url,
    required String title,
    required String? siteUrl,
    required ApiCredentialReader? credentials,
    required SiteLifecycle? lifecycle,
    Rect? sharePositionOrigin,
  });
}

final class NativeVideoDownloader implements VideoDownloader {
  NativeVideoDownloader({
    TargetPlatform? platform,
    MediaDownloadEnvironment? environment,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _platform = platform ?? defaultTargetPlatform,
       _environment = environment ?? const NativeMediaDownloadEnvironment(),
       _client = client == null ? null : SafeHttpClient.borrowed(client);

  final TargetPlatform _platform;
  final MediaDownloadEnvironment _environment;
  final http.Client? _client;
  final Duration requestTimeout;

  @override
  Future<MediaDownloadResult> download({
    required Uri url,
    required String title,
    required String? siteUrl,
    required ApiCredentialReader? credentials,
    required SiteLifecycle? lifecycle,
    Rect? sharePositionOrigin,
  }) async {
    requireSafeHttpUrl(url);
    final site = siteUrl == null
        ? null
        : requireSafeHttpUrl(Uri.parse(siteUrl));
    final lease = siteUrl == null ? null : lifecycle?.capture(siteUrl);
    final filename = videoDownloadFilename(title: title, url: url);
    final usesSaveDialog = usesMediaSaveDialog(_platform);
    final destination = usesSaveDialog
        ? await _environment.chooseSavePath(suggestedName: filename)
        : null;
    if (usesSaveDialog && destination == null) {
      return const MediaDownloadCancelled();
    }
    _requireCurrent(lease);

    final account =
        siteUrl != null && credentials != null && url.origin == site?.origin
        ? await SiteAssetAccount.open(
            siteUrl: siteUrl,
            credentials: credentials,
            requireCurrent: () => _requireCurrent(lease),
            waitForCredential: <T>(Future<T> operation) =>
                _waitForCredential(operation, lease),
          )
        : null;

    return withPrivateStagingPath(
      await _environment.temporaryDirectory(),
      prefix: 'video-download-',
      filename: filename,
      createFile: true,
      use: (file) async {
        final client = _client ?? SafeHttpClient.create();
        try {
          final mediaType = await _fetch(
            client,
            url: url,
            account: account,
            lease: lease,
            file: file,
          );
          _requireCurrent(lease);
          if (destination != null) {
            await _environment.saveFile(file, destination);
            return MediaDownloadResult.savedTo(
              destination,
              windows: _platform == TargetPlatform.windows,
            );
          }
          final shareFilename = downloadFilename(
            title: title,
            url: url.toString(),
            fallback: 'video',
            mediaExtensions: _VideoMediaType.values.expand(
              (type) => type.extensions,
            ),
            preferredExtensions: mediaType?.extensions ?? const [],
          );
          final shareFile = shareFilename == filename
              ? file
              : await file.rename('${file.parent.path}/$shareFilename');
          _requireCurrent(lease);
          final outcome = await _environment.shareFile(
            shareFile,
            filename: shareFilename,
            mimeType: mediaType?.mimeType ?? 'application/octet-stream',
            sharePositionOrigin: sharePositionOrigin,
          );
          return MediaDownloadResult.fromShare(outcome);
        } finally {
          client.close();
        }
      },
    );
  }

  Future<T> _waitForCredential<T>(Future<T> operation, SiteLease? lease) async {
    if (lease == null) return operation.timeout(requestTimeout);

    final retired = Completer<Never>();
    final removeRetirement = lease.onRetire(() {
      retired.completeError(const VideoDownloadException());
    });
    try {
      return await Future.any<T>([
        retired.future,
        operation,
      ]).timeout(requestTimeout);
    } finally {
      removeRetirement();
    }
  }

  Future<_VideoMediaType?> _fetch(
    http.Client client, {
    required Uri url,
    required SiteAssetAccount? account,
    required SiteLease? lease,
    required File file,
  }) async {
    var current = url;
    final abort = Completer<void>();
    final retired = Completer<Never>();
    retired.future.ignore();
    StreamIterator<List<int>>? body;
    Future<void>? bodyCancellation;
    final removeRetirement = lease?.onRetire(() {
      retired.completeError(const VideoDownloadException());
      if (!abort.isCompleted) abort.complete();
      bodyCancellation = body?.cancel();
      bodyCancellation?.ignore();
    });
    try {
      for (var redirects = 0; ; redirects++) {
        _requireCurrent(lease);
        final request = http.AbortableRequest(
          'GET',
          current,
          abortTrigger: abort.future,
        );
        request.headers.addAll(account?.headersFor(current) ?? const {});
        final pending = client.send(request);
        late final http.StreamedResponse response;
        try {
          response = await Future.any([
            pending,
            retired.future,
          ]).timeout(requestTimeout);
        } on Object {
          // A transport may complete despite the abort signal. Release any
          // late body instead of leaving its connection without a consumer.
          cancelLateHttpResponse(pending);
          rethrow;
        }
        if (isHttpRedirectStatus(response.statusCode)) {
          await cancelUnreadHttpBody(response.stream);
          final location = response.headers['location'];
          if (location == null || redirects >= 5) {
            throw const VideoDownloadException();
          }
          current = resolveSafeHttpRedirect(current, location);
          continue;
        }
        if (response.statusCode != 200 ||
            response.headers['content-type']
                    ?.split(';')
                    .first
                    .trim()
                    .toLowerCase() ==
                'text/html') {
          await cancelUnreadHttpBody(response.stream);
          throw const VideoDownloadException();
        }

        RandomAccessFile? output;
        var length = 0;
        final prefix = <int>[];
        try {
          _requireCurrent(lease);
          output = await file.open(mode: FileMode.write);
          _requireCurrent(lease);
          final iterator = body = StreamIterator(response.stream);
          while (await iterator.moveNext().timeout(requestTimeout)) {
            _requireCurrent(lease);
            final chunk = iterator.current;
            await output.writeFrom(chunk);
            prefix.addAll(chunk.take(32 - prefix.length));
            length += chunk.length;
          }
          _requireCurrent(lease);
        } finally {
          try {
            if (body == null) {
              cancelUnreadHttpBody(response.stream).ignore();
            } else {
              await (bodyCancellation ?? body.cancel());
            }
          } finally {
            await output?.close();
          }
        }
        if (length == 0) throw const VideoDownloadException();
        return _videoMediaType(prefix, response.headers['content-type']);
      }
    } finally {
      removeRetirement?.call();
      if (!abort.isCompleted) abort.complete();
    }
  }
}

void _requireCurrent(SiteLease? lease) {
  if (lease != null && !lease.isCurrent) {
    throw const VideoDownloadException();
  }
}

final class VideoDownloadException implements Exception {
  const VideoDownloadException();

  @override
  String toString() => appL10n.theVideoCouldNotBeDownloaded;
}

String videoDownloadFilename({required String title, required Uri url}) =>
    downloadFilename(
      title: title,
      url: url.toString(),
      fallback: 'video',
      mediaExtensions: _VideoMediaType.values.expand((type) => type.extensions),
    );

_VideoMediaType? _videoMediaType(List<int> prefix, String? contentType) {
  final normalized = contentType?.split(';').first.trim().toLowerCase();
  final declared = _VideoMediaType.fromMimeType(normalized);
  final detected = lookupMimeType('', headerBytes: prefix);
  // The mime package labels every EBML header as audio/weba, including
  // WebM video and Matroska. Only their declared type resolves that ambiguity.
  if (detected == 'audio/weba') {
    return switch (declared) {
      _VideoMediaType.webm || _VideoMediaType.matroska => declared,
      _ => null,
    };
  }
  if (detected != null) return _VideoMediaType.fromMimeType(detected);
  return declared;
}

enum _VideoMediaType {
  mp4('video/mp4', ['mp4', 'm4v']),
  quicktime('video/quicktime', ['mov']),
  webm('video/webm', ['webm']),
  ogg('video/ogg', ['ogv', 'ogg']),
  avi('video/x-msvideo', ['avi']),
  matroska('video/x-matroska', ['mkv']);

  const _VideoMediaType(this.mimeType, this.extensions);

  final String mimeType;
  final List<String> extensions;

  static _VideoMediaType? fromMimeType(String? mimeType) {
    if (mimeType == 'video/x-m4v') return mp4;
    for (final type in values) {
      if (type.mimeType == mimeType) return type;
    }
    return null;
  }
}
