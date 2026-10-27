import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

import 'api_credentials.dart';
import 'avatar_loader.dart';
import 'avif.dart';
import 'byte_cache.dart';
import 'media_request_coordinator.dart';
import 'site_asset_account.dart';
import 'site_lifecycle.dart';

enum SiteImageMediaType {
  avif('image/avif', ['avif']),
  bmp('image/bmp', ['bmp']),
  gif('image/gif', ['gif']),
  heic('image/heic', ['heic']),
  heif('image/heif', ['heif']),
  jpeg('image/jpeg', ['jpg', 'jpeg']),
  png('image/png', ['png']),
  svg('image/svg+xml', ['svg']),
  tiff('image/tiff', ['tif', 'tiff']),
  webp('image/webp', ['webp']);

  const SiteImageMediaType(this.mimeType, this.extensions);

  final String mimeType;
  final List<String> extensions;

  static SiteImageMediaType? _fromMimeType(String? mimeType) {
    for (final type in values) {
      if (type.mimeType == mimeType) return type;
    }
    return null;
  }
}

final class SiteImageBytes {
  const SiteImageBytes(
    this.bytes, {
    required this.mediaType,
    this.isAnimated = false,
  });

  final Uint8List bytes;
  final SiteImageMediaType? mediaType;
  bool get isSvg => mediaType == SiteImageMediaType.svg;
  final bool isAnimated;
}

/// Loads site-owned images with the account identity that may protect them.
///
/// Discourse intentionally answers an anonymous secure-upload request with a
/// 404. The first hop therefore carries the user API key, but redirects are
/// followed by [ByteCache] one at a time and credentials are added only while
/// the destination remains on the forum origin. A signed object-store or CDN
/// URL never receives them.
///
/// Caches are memory-only and scoped to one [SiteLifecycle] lease. Disconnect
/// and reconnect cannot expose bytes fetched for the previous account.
///
/// Every forum shares one [maxCachedBytes] budget, the most a single forum
/// could retain on its own, so reading several forums costs no more memory
/// than reading one. The forum that just loaded may keep the whole budget;
/// the others give up their least recently used images first.
final class SiteImageRepository {
  SiteImageRepository({
    required this.credentials,
    required this.lifecycle,
    http.Client? client,
    this.maxCachedBytes = 64 * 1024 * 1024,
  }) : assert(maxCachedBytes > 0),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final int maxCachedBytes;
  final http.Client _client;
  final bool _ownsClient;
  final _coordinator = MediaRequestCoordinator();

  /// Ordered from least to most recently used.
  final Map<String, _SiteImageSession> _sessions = {};
  final Map<String, _SiteImageOpening> _opening = {};
  final Set<SiteImageRequest> _requests = {};
  bool _disposed = false;

  Future<SiteImageBytes?> load({
    required String siteUrl,
    required String url,
  }) => request(siteUrl: siteUrl, url: url).result;

  /// Retains one consumer while credentials open and while bytes are loaded.
  SiteImageRequest request({required String siteUrl, required String url}) {
    final account = lifecycle.capture(siteUrl);
    late final SiteImageRequest request;
    request = SiteImageRequest._(siteUrl, () => _requests.remove(request));
    if (_disposed) return request..release();
    _requests.add(request);
    request._removeRetirement = account.onRetire(request.release);
    unawaited(_resolve(request, account, url));
    return request;
  }

  Future<void> _resolve(
    SiteImageRequest request,
    SiteLease account,
    String url,
  ) async {
    try {
      final siteUrl = request._siteUrl;
      final session = await _session(siteUrl);
      if (request._done) return;
      if (_disposed ||
          !account.isCurrent ||
          session == null ||
          !identical(account.session, session.lease.session) ||
          !identical(_sessions[siteUrl], session)) {
        request.release();
        return;
      }
      final owner = session.cache.request(url);
      request._owner = owner;
      request.setVisible(request._visible);
      final bytes = await owner.result;
      if (request._done) return;
      if (_disposed ||
          !account.isCurrent ||
          !identical(_sessions[siteUrl], session)) {
        request.release();
        return;
      }
      _trimOtherSessions(session);
      request._complete(bytes);
    } catch (error, stackTrace) {
      if (request._done) return;
      if (_disposed || !account.isCurrent) {
        request.release();
      } else {
        request._completeError(error, stackTrace);
      }
    }
  }

  bool isCached({required String siteUrl, required String url}) =>
      _use(siteUrl)?.cache.isCached(url) ?? false;

  SiteImageBytes? cached({required String siteUrl, required String url}) =>
      _use(siteUrl)?.cache.cached(url);

  _SiteImageSession? _use(String siteUrl) {
    final session = _sessions[siteUrl];
    if (_disposed || session == null || !session.lease.isCurrent) return null;
    _sessions
      ..remove(siteUrl)
      ..[siteUrl] = session;
    return session;
  }

  /// Brings the retained total back within [maxCachedBytes] at the expense
  /// of every session except [active], least recently used first.
  ///
  /// A trimmed session stays open even once empty: it still owns transfers
  /// that mounted images await and the credentials that authorize them. An
  /// empty session retains only bounded failure records, and there is one per
  /// connected forum until [forget] removes it.
  void _trimOtherSessions(_SiteImageSession active) {
    var retained = 0;
    for (final session in _sessions.values) {
      retained += session.cache.cachedBytes;
    }
    for (final session in _sessions.values.toList(growable: false)) {
      if (retained <= maxCachedBytes) return;
      if (identical(session, active)) continue;
      final before = session.cache.cachedBytes;
      final excess = retained - maxCachedBytes;
      session.cache.trimTo(before > excess ? before - excess : 0);
      retained -= before - session.cache.cachedBytes;
    }
  }

  Future<_SiteImageSession?> _session(String siteUrl) {
    final existing = _use(siteUrl);
    if (existing != null) return SynchronousFuture(existing);

    // A lifecycle change can replace an account without an explicit forget.
    _sessions.remove(siteUrl)?.cache.close();

    final pending = _opening[siteUrl];
    if (pending != null && pending.lease.isCurrent) return pending.result;

    final opening = _SiteImageOpening(lifecycle.capture(siteUrl));
    _opening[siteUrl] = opening;
    return opening.result = _open(siteUrl, opening);
  }

  bool _isCurrentOpening(String siteUrl, _SiteImageOpening opening) =>
      !_disposed &&
      opening.lease.isCurrent &&
      identical(_opening[siteUrl], opening);

  Future<_SiteImageSession?> _open(
    String siteUrl,
    _SiteImageOpening opening,
  ) async {
    try {
      final account = await SiteAssetAccount.open(
        siteUrl: siteUrl,
        credentials: credentials,
        requireCurrent: () {
          if (!_isCurrentOpening(siteUrl, opening)) {
            throw StateError('Image account opening is no longer current.');
          }
        },
      );
      if (!_isCurrentOpening(siteUrl, opening)) return null;

      if (!account.hasOrigin) return null;
      final session = _SiteImageSession(
        lease: opening.lease,
        cache: _AuthenticatedSiteImageCache(
          client: _client,
          maxCachedBytes: maxCachedBytes,
          coordinator: _coordinator,
          account: account,
        ),
      );
      _sessions[siteUrl] = session;
      return session;
    } catch (_) {
      if (_isCurrentOpening(siteUrl, opening)) rethrow;
      return null;
    } finally {
      if (identical(_opening[siteUrl], opening)) {
        final _ = _opening.remove(siteUrl);
      }
    }
  }

  void forget(String siteUrl) {
    for (final request in _requests.toList(growable: false)) {
      if (request._siteUrl == siteUrl) request.release();
    }
    final _ = _opening.remove(siteUrl);
    _sessions.remove(siteUrl)?.cache.close();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final request in _requests.toList(growable: false)) {
      request.release();
    }
    _opening.clear();
    for (final session in _sessions.values) {
      session.cache.close();
    }
    _sessions.clear();
    _coordinator.close();
    if (_ownsClient) _client.close();
  }
}

/// One image consumer. Releasing it leaves other consumers and saves intact.
final class SiteImageRequest {
  SiteImageRequest._(this._siteUrl, this._onDone);

  final String _siteUrl;
  final void Function() _onDone;
  final Completer<SiteImageBytes?> _result = Completer<SiteImageBytes?>();
  ByteCacheRequest<SiteImageBytes>? _owner;
  void Function()? _removeRetirement;
  bool _visible = false;
  bool _done = false;

  Future<SiteImageBytes?> get result => _result.future;

  void setVisible(bool visible) {
    if (_done) return;
    _visible = visible;
    _owner?.priority = visible
        ? MediaRequestPriority.interactive
        : MediaRequestPriority.normal;
  }

  void release() => _complete(null);

  void _finish() {
    _done = true;
    _removeRetirement?.call();
    _removeRetirement = null;
    _owner?.release();
    _owner = null;
    _onDone();
  }

  void _complete(SiteImageBytes? value) {
    if (_done) return;
    _finish();
    _result.complete(value);
  }

  void _completeError(Object error, StackTrace stackTrace) {
    if (_done) return;
    _finish();
    _result.completeError(error, stackTrace);
  }
}

final class _SiteImageOpening {
  _SiteImageOpening(this.lease);

  final SiteLease lease;
  late final Future<_SiteImageSession?> result;
}

final class _SiteImageSession {
  const _SiteImageSession({required this.lease, required this.cache});

  final SiteLease lease;
  final _AuthenticatedSiteImageCache cache;
}

final class _AuthenticatedSiteImageCache extends ByteCache<SiteImageBytes> {
  _AuthenticatedSiteImageCache({
    required super.client,
    required super.maxCachedBytes,
    required super.coordinator,
    required this.account,
  }) : super(
         maxConcurrent: MediaRequestCoordinator.defaultMaxConcurrentPerOrigin,
         maxEntries: 256,
         maxResponseBytes: 32 * 1024 * 1024,
       );

  final SiteAssetAccount account;

  @override
  Map<String, String> requestHeaders(Uri url, Uri original) =>
      account.headersFor(url);

  @override
  SiteImageBytes? decode(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    final mediaType = _imageMediaType(
      response.bodyBytes,
      response.headers['content-type'],
    );
    return SiteImageBytes(
      response.bodyBytes,
      mediaType: mediaType,
      isAnimated: _looksAnimated(
        response.bodyBytes,
        contentType: mediaType?.mimeType,
      ),
    );
  }
}

SiteImageMediaType? _imageMediaType(Uint8List bytes, String? contentType) {
  if (avifKind(bytes) != null) return SiteImageMediaType.avif;
  // An empty path prevents filenames from becoming evidence of a format.
  final normalized = contentType?.split(';').first.trim().toLowerCase();
  final declared = SiteImageMediaType._fromMimeType(normalized);
  final detected = lookupMimeType('', headerBytes: bytes);
  // A generic HEIF container can hold AVIF or HEIC compatible brands.
  if (detected == 'image/heif' &&
      (declared == SiteImageMediaType.avif ||
          declared == SiteImageMediaType.heic)) {
    return declared;
  }
  if (detected != null) return SiteImageMediaType._fromMimeType(detected);
  if (AvatarLoader.looksLikeSvg(bytes)) return SiteImageMediaType.svg;
  return declared;
}

bool _looksAnimated(Uint8List bytes, {String? contentType}) {
  if (avifKind(bytes) == AvifKind.animated) return true;
  if (contentType?.toLowerCase().split(';').first.trim() == 'image/gif') {
    return true;
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38 &&
      (bytes[4] == 0x37 || bytes[4] == 0x39) &&
      bytes[5] == 0x61) {
    return true;
  }
  if (bytes.length < 21 ||
      !_matchesAscii(bytes, 0, 'RIFF') ||
      !_matchesAscii(bytes, 8, 'WEBP')) {
    return false;
  }

  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final chunk = String.fromCharCodes(bytes, offset, offset + 4);
    final size =
        bytes[offset + 4] |
        (bytes[offset + 5] << 8) |
        (bytes[offset + 6] << 16) |
        (bytes[offset + 7] << 24);
    final dataOffset = offset + 8;
    if (chunk == 'ANIM' || chunk == 'ANMF') return true;
    if (chunk == 'VP8X' &&
        dataOffset < bytes.length &&
        bytes[dataOffset] & 0x02 != 0) {
      return true;
    }
    if (size < 0 || dataOffset + size > bytes.length) return false;
    offset = dataOffset + size + (size.isOdd ? 1 : 0);
  }
  return false;
}

bool _matchesAscii(Uint8List bytes, int offset, String expected) {
  if (offset + expected.length > bytes.length) return false;
  for (var index = 0; index < expected.length; index++) {
    if (bytes[offset + index] != expected.codeUnitAt(index)) return false;
  }
  return true;
}
