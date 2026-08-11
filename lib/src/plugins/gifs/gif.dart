import 'package:flutter/foundation.dart';

import '../../models/json.dart';

/// One featured Klipy category returned by Discourse's GIF proxy.
@immutable
final class GifCategory {
  const GifCategory({
    required this.title,
    required this.imageUrl,
    required this.searchTerm,
  });

  static GifCategory? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final title = jsonText(value['name']);
    final imageUrl = _httpUrl(value['image']);
    final searchTerm = jsonText(value['searchterm']);
    if (title == null || imageUrl == null || searchTerm == null) return null;
    return GifCategory(
      title: title,
      imageUrl: imageUrl,
      searchTerm: searchTerm,
    );
  }

  final String title;
  final String imageUrl;
  final String searchTerm;

  @override
  bool operator ==(Object other) =>
      other is GifCategory &&
      other.title == title &&
      other.imageUrl == imageUrl &&
      other.searchTerm == searchTerm;

  @override
  int get hashCode => Object.hash(title, imageUrl, searchTerm);
}

/// A GIF already reduced to the media format selected by the site.
@immutable
final class GifResult {
  const GifResult({
    required this.title,
    required this.url,
    required this.width,
    required this.height,
  }) : assert(width > 0 && width <= 9999),
       assert(height > 0 && height <= 9999);

  static GifResult? fromJson(Object? value, {required String fileDetail}) {
    if (value is! Map<String, dynamic>) return null;
    final title = _gifTitle(value['title']);
    final formats = jsonObject(value['media_formats']);
    final format = jsonObject(formats[fileDetail]);
    final url = _httpUrl(format['url']);
    final dimensions = jsonArray(format['dims']);
    final width = dimensions.isEmpty ? null : jsonIntOrNull(dimensions[0]);
    final height = dimensions.length < 2 ? null : jsonIntOrNull(dimensions[1]);
    if (url == null ||
        width == null ||
        width <= 0 ||
        width > 9999 ||
        height == null ||
        height <= 0 ||
        height > 9999) {
      return null;
    }
    return GifResult(title: title, url: url, width: width, height: height);
  }

  final String title;
  final String url;
  final int width;
  final int height;

  double get aspectRatio => width / height;

  /// The exact image markdown Discourse's web picker inserts and sends.
  String get markdown =>
      '\n![${_escapeImageAlt(_gifTitle(title))}|${width}x$height]($url)\n';

  @override
  bool operator ==(Object other) =>
      other is GifResult &&
      other.title == title &&
      other.url == url &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(title, url, width, height);
}

/// One cursor page returned by `GET /gifs/search.json`.
@immutable
final class GifSearchPage {
  factory GifSearchPage({
    required List<GifResult> results,
    String? nextPosition,
  }) => GifSearchPage._(
    results: List.unmodifiable(results),
    nextPosition: jsonText(nextPosition),
  );

  const GifSearchPage._({required this.results, this.nextPosition});

  const GifSearchPage.empty() : results = const [], nextPosition = null;

  factory GifSearchPage.fromJson(
    Map<String, dynamic> json, {
    required String fileDetail,
  }) {
    final next = jsonText(json['next']);
    return GifSearchPage(
      results: List.unmodifiable([
        for (final value in jsonArray(json['results']))
          ?GifResult.fromJson(value, fileDetail: fileDetail),
      ]),
      nextPosition: next,
    );
  }

  final List<GifResult> results;

  /// Klipy's opaque continuation cursor, or null when this is the last page.
  final String? nextPosition;

  bool get hasMore => nextPosition?.trim().isNotEmpty == true;

  @override
  bool operator ==(Object other) =>
      other is GifSearchPage &&
      listEquals(other.results, results) &&
      other.nextPosition == nextPosition;

  @override
  int get hashCode => Object.hash(Object.hashAll(results), nextPosition);
}

String? _httpUrl(Object? value) {
  final text = jsonText(value);
  if (text == null) return null;
  final uri = Uri.tryParse(text);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri.toString();
}

String _gifTitle(Object? value) {
  final title = value is String ? value : '';
  final singleLine = title.replaceAll(RegExp(r'[\r\n|]+'), ' ').trim();
  return singleLine.isEmpty ? 'GIF' : singleLine;
}

String _escapeImageAlt(String value) =>
    value.replaceAllMapped(RegExp(r'[\\\[\]`]'), (match) => '\\${match[0]}');
