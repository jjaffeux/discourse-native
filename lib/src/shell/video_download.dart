import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart' as selector;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' as sharing;

import '../data/api_credentials.dart';
import '../data/http_transport.dart';
import '../data/site_lifecycle.dart';
import '../foundation/private_file_permissions.dart';
import 'download_filename.dart';

enum VideoDownloadOutcome { saved, shared, cancelled }

abstract interface class VideoDownloadEnvironment {
  Future<String?> chooseSavePath({required String suggestedName});

  Future<Directory> temporaryDirectory();

  Future<VideoDownloadOutcome> shareVideo(
    File file, {
    required String filename,
    required String mimeType,
    Rect? sharePositionOrigin,
  });
}

abstract interface class VideoDownloader {
  Future<VideoDownloadOutcome> download({
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
    VideoDownloadEnvironment? environment,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _platform = platform ?? defaultTargetPlatform,
       _environment = environment ?? const _NativeVideoDownloadEnvironment(),
       _client = client == null ? null : SafeHttpClient.borrowed(client);

  final TargetPlatform _platform;
  final VideoDownloadEnvironment _environment;
  final http.Client? _client;
  final Duration requestTimeout;

  bool get _usesSaveDialog => switch (_platform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
  };

  @override
  Future<VideoDownloadOutcome> download({
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
    final destination = _usesSaveDialog
        ? await _environment.chooseSavePath(suggestedName: filename)
        : null;
    if (_usesSaveDialog && destination == null) {
      return VideoDownloadOutcome.cancelled;
    }
    _requireCurrent(lease);

    final headers = <String, String>{};
    if (siteUrl != null && credentials != null && url.origin == site?.origin) {
      final key = await credentials.apiKeyFor(siteUrl).timeout(requestTimeout);
      _requireCurrent(lease);
      if (key != null) {
        headers['User-Api-Key'] = key;
        final clientId = await credentials.clientId().timeout(requestTimeout);
        _requireCurrent(lease);
        if (clientId.isNotEmpty) headers['User-Api-Client-Id'] = clientId;
      }
    }

    final directory = await (await _environment.temporaryDirectory())
        .createTemp('video-download-');
    final client = _client ?? SafeHttpClient.create();
    try {
      final file = File('${directory.path}/$filename');
      await ensurePrivateFile(file);
      await _fetch(
        client,
        url: url,
        forumOrigin: site?.origin,
        headers: headers,
        lease: lease,
        file: file,
      );
      _requireCurrent(lease);
      if (destination != null) {
        await selector.XFile(file.path).saveTo(destination);
        return VideoDownloadOutcome.saved;
      }
      return await _environment.shareVideo(
        file,
        filename: filename,
        mimeType: _videoMimeType(filename),
        sharePositionOrigin: sharePositionOrigin,
      );
    } finally {
      client.close();
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        // A share target may still hold the file; the private cache is temporary.
      }
    }
  }

  Future<void> _fetch(
    http.Client client, {
    required Uri url,
    required String? forumOrigin,
    required Map<String, String> headers,
    required SiteLease? lease,
    required File file,
  }) async {
    var current = url;
    final abort = Completer<void>();
    try {
      for (var redirects = 0; ; redirects++) {
        _requireCurrent(lease);
        final request = http.AbortableRequest(
          'GET',
          current,
          abortTrigger: abort.future,
        );
        if (current.origin == forumOrigin) request.headers.addAll(headers);
        final pending = client.send(request);
        late final http.StreamedResponse response;
        try {
          response = await pending.timeout(requestTimeout);
        } on TimeoutException {
          // A transport may complete despite the abort signal. Release any
          // late body instead of leaving its connection without a consumer.
          pending
              .then<void>((late) => late.stream.listen(null).cancel())
              .ignore();
          rethrow;
        }
        if (_redirectStatuses.contains(response.statusCode)) {
          await response.stream.listen(null).cancel();
          final location = response.headers['location'];
          if (location == null || redirects >= 5) {
            throw const VideoDownloadException();
          }
          current = resolveSafeHttpRedirect(current, location);
          continue;
        }
        if (response.statusCode != 200 ||
            response.headers['content-type']?.split(';').first.trim() ==
                'text/html') {
          await response.stream.listen(null).cancel();
          throw const VideoDownloadException();
        }

        final output = await file.open(mode: FileMode.write);
        var length = 0;
        try {
          await for (final chunk in response.stream.timeout(requestTimeout)) {
            _requireCurrent(lease);
            await output.writeFrom(chunk);
            length += chunk.length;
          }
        } finally {
          await output.close();
        }
        if (length == 0) throw const VideoDownloadException();
        return;
      }
    } finally {
      abort.complete();
    }
  }
}

void _requireCurrent(SiteLease? lease) {
  if (lease != null && !lease.isCurrent) {
    throw const VideoDownloadException();
  }
}

final class _NativeVideoDownloadEnvironment
    implements VideoDownloadEnvironment {
  const _NativeVideoDownloadEnvironment();

  @override
  Future<String?> chooseSavePath({required String suggestedName}) async =>
      (await selector.getSaveLocation(suggestedName: suggestedName))?.path;

  @override
  Future<Directory> temporaryDirectory() => getTemporaryDirectory();

  @override
  Future<VideoDownloadOutcome> shareVideo(
    File file, {
    required String filename,
    required String mimeType,
    Rect? sharePositionOrigin,
  }) async {
    final result = await sharing.SharePlus.instance.share(
      sharing.ShareParams(
        files: [sharing.XFile(file.path, mimeType: mimeType)],
        fileNameOverrides: [filename],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    return result.status == sharing.ShareResultStatus.dismissed
        ? VideoDownloadOutcome.cancelled
        : VideoDownloadOutcome.shared;
  }
}

final class VideoDownloadException implements Exception {
  const VideoDownloadException();

  @override
  String toString() => 'The video could not be downloaded.';
}

String videoDownloadFilename({required String title, required Uri url}) =>
    downloadFilename(title: title, url: url.toString(), fallback: 'video');

String _videoMimeType(String filename) =>
    switch (filename.split('.').last.toLowerCase()) {
      'mp4' || 'm4v' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      'ogv' || 'ogg' => 'video/ogg',
      'avi' => 'video/x-msvideo',
      'mkv' => 'video/x-matroska',
      _ => 'application/octet-stream',
    };

const _redirectStatuses = {301, 302, 303, 307, 308};
