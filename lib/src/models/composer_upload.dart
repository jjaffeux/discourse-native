import 'dart:async';

import 'package:flutter/foundation.dart';

/// A file the composer can upload without knowing which desktop plugin found it.
@immutable
class ComposerUploadFile {
  const ComposerUploadFile({
    required this.name,
    required this.length,
    required this.openRead,
  });

  final String name;
  final Future<int> Function() length;
  final Stream<List<int>> Function() openRead;
}

@immutable
class ComposerUploadResult {
  const ComposerUploadResult({
    required this.id,
    required this.originalFilename,
    required this.shortUrl,
    required this.url,
    this.width,
    this.height,
    this.thumbnailWidth,
    this.thumbnailHeight,
    this.thumbnailUrl,
  });

  final int id;
  final String originalFilename;
  final String shortUrl;
  final String url;
  final int? width;
  final int? height;
  final int? thumbnailWidth;
  final int? thumbnailHeight;
  final String? thumbnailUrl;

  int? get markdownWidth => thumbnailWidth ?? width;
  int? get markdownHeight => thumbnailHeight ?? height;
  String get previewUrl => thumbnailUrl ?? url;
}

/// The upload security context Discourse applies to a composer attachment.
@immutable
final class ComposerUploadType {
  const ComposerUploadType(this.wireName) : assert(wireName != '');

  static const composer = ComposerUploadType('composer');

  final String wireName;

  @override
  bool operator ==(Object other) =>
      other is ComposerUploadType && other.wireName == wireName;

  @override
  int get hashCode => wireName.hashCode;

  @override
  String toString() => wireName;
}

final class ComposerUploadException implements Exception {
  const ComposerUploadException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ComposerUploadException($statusCode, $message)';
}

enum ComposerUploadStatus { uploading, retrying, completed, failed, cancelled }

/// One visible queue row. Markdown successes are inserted and removed; a
/// target policy may instead retain successes as attachments until submit.
@immutable
class ComposerUploadItem {
  const ComposerUploadItem({
    required this.id,
    required this.file,
    required this.progress,
    required this.status,
    this.error,
    this.result,
  });

  final int id;
  final ComposerUploadFile file;
  final double progress;
  final ComposerUploadStatus status;
  final String? error;
  final ComposerUploadResult? result;

  ComposerUploadItem copyWith({
    double? progress,
    ComposerUploadStatus? status,
    String? error,
    bool clearError = false,
    ComposerUploadResult? result,
    bool clearResult = false,
  }) => ComposerUploadItem(
    id: id,
    file: file,
    progress: progress ?? this.progress,
    status: status ?? this.status,
    error: clearError ? null : error ?? this.error,
    result: clearResult ? null : result ?? this.result,
  );
}

typedef ComposerImageUploader =
    Future<ComposerUploadResult> Function(
      ComposerUploadFile file, {
      required void Function(double progress) onProgress,
      required Future<void> abortTrigger,
    });

typedef ComposerUploadUrlResolver =
    Future<Map<String, String>> Function(Iterable<String> shortUrls);
