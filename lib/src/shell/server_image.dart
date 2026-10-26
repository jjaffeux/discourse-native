import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import '../data/byte_cache.dart';
import '../data/http_basic_auth.dart';

final _serverImageBytes = _ServerImageBytes();

Future<Uint8List?> loadServerImageBytes(String url) =>
    _serverImageBytes.load(url);

ImageProvider<Object> serverImageProvider(String url) {
  final destination = Uri.tryParse(url);
  if (destination == null ||
      !destination.hasAuthority ||
      !HttpBasicAuthStore.instance.protects(destination)) {
    return NetworkImage(url);
  }
  return _ServerImage(url, HttpBasicAuthStore.instance.generation);
}

final class _ServerImageBytes extends ByteCache<Uint8List> {
  _ServerImageBytes() : super(maxResponseBytes: 16 * 1024 * 1024);

  @override
  Uint8List? decode(http.Response response) => response.bodyBytes;
}

final class _ServerImage extends ImageProvider<_ServerImage> {
  const _ServerImage(this.url, this.authentication);

  final String url;
  final Object authentication;

  @override
  Future<_ServerImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _ServerImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await loadServerImageBytes(url);
    if (bytes == null ||
        !identical(authentication, HttpBasicAuthStore.instance.generation)) {
      throw StateError('Server image is unavailable.');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is _ServerImage &&
      other.url == url &&
      identical(other.authentication, authentication);

  @override
  int get hashCode => Object.hash(url, identityHashCode(authentication));
}
