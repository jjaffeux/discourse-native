import 'dart:async';

import 'package:flutter/foundation.dart';

import '../foundation/count_label.dart';

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

/// The size ceiling the site's upload validator holds one file to.
@immutable
final class ComposerUploadSizeLimit {
  const ComposerUploadSizeLimit(this.maxBytes, {required this.enforced});

  final int maxBytes;

  /// Whether the validator refuses a larger file, which it does only once the
  /// whole body has arrived. It downsizes an image instead, and skips staff in
  /// a private message; a proxy's own body limit can still refuse either.
  final bool enforced;

  @override
  bool operator ==(Object other) =>
      other is ComposerUploadSizeLimit &&
      other.maxBytes == maxBytes &&
      other.enforced == enforced;

  @override
  int get hashCode => Object.hash(maxBytes, enforced);

  @override
  String toString() =>
      'ComposerUploadSizeLimit($maxBytes, enforced: $enforced)';
}

final class ComposerUploadException implements Exception {
  const ComposerUploadException(
    this.message, {
    this.statusCode,
    this.retryAfter,
    this.retryable = true,
  });

  /// Sending the same file again is refused the same way, so it is final.
  ComposerUploadException.tooLarge(
    String filename, {
    int? maxBytes,
    int? statusCode,
  }) : this(
         maxBytes == null
             ? '$filename is too large to upload.'
             : '$filename is too large (maximum size is '
                   '${_humanFileSize(maxBytes)}).',
         statusCode: statusCode,
         retryable: false,
       );

  final String message;
  final int? statusCode;
  final Duration? retryAfter;
  final bool retryable;

  String get displayMessage {
    if (statusCode != 429) return message;
    final wait = retryAfter;
    if (wait == null) return 'Too many uploads. Please wait and retry.';
    final seconds = (wait.inMilliseconds / 1000).ceil();
    return 'Too many uploads. Try again in ${countLabel(seconds, 'second')}.';
  }

  @override
  String toString() => 'ComposerUploadException($statusCode, $message)';
}

/// The web client's `I18n.toHumanSize`, so a limit reads as it does there.
String _humanFileSize(int bytes) {
  const units = ['bytes', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final whole = unit == 0 || size == size.truncateToDouble();
  return '${size.toStringAsFixed(whole ? 0 : 1)} ${units[unit]}';
}

enum ComposerUploadStatus { uploading, retrying, completed, failed, cancelled }

@immutable
class ComposerUploadItem {
  const ComposerUploadItem({
    required this.id,
    required this.file,
    required this.progress,
    required this.status,
    this.error,
    this.retryable = true,
    this.result,
  });

  final int id;
  final ComposerUploadFile file;
  final double progress;
  final ComposerUploadStatus status;
  final String? error;

  /// False once the site has refused this file in a way a retry repeats.
  final bool retryable;
  final ComposerUploadResult? result;

  ComposerUploadItem copyWith({
    double? progress,
    ComposerUploadStatus? status,
    String? error,
    bool clearError = false,
    bool? retryable,
    ComposerUploadResult? result,
    bool clearResult = false,
  }) => ComposerUploadItem(
    id: id,
    file: file,
    progress: progress ?? this.progress,
    status: status ?? this.status,
    error: clearError ? null : error ?? this.error,
    retryable: retryable ?? this.retryable,
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
