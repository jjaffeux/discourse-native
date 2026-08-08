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
    required this.originalFilename,
    required this.shortUrl,
    required this.url,
    this.width,
    this.height,
    this.thumbnailWidth,
    this.thumbnailHeight,
    this.thumbnailUrl,
  });

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

final class ComposerUploadException implements Exception {
  const ComposerUploadException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ComposerUploadException($statusCode, $message)';
}

enum ComposerUploadStatus { uploading, retrying, failed, cancelled }

/// One visible queue row. Successful uploads are inserted and removed.
@immutable
class ComposerUploadItem {
  const ComposerUploadItem({
    required this.id,
    required this.file,
    required this.progress,
    required this.status,
    this.error,
  });

  final int id;
  final ComposerUploadFile file;
  final double progress;
  final ComposerUploadStatus status;
  final String? error;

  ComposerUploadItem copyWith({
    double? progress,
    ComposerUploadStatus? status,
    String? error,
    bool clearError = false,
  }) => ComposerUploadItem(
    id: id,
    file: file,
    progress: progress ?? this.progress,
    status: status ?? this.status,
    error: clearError ? null : error ?? this.error,
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
