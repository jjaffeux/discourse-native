import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart' as selector;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' as sharing;

import '../../foundation/private_file_permissions.dart';

enum ResenhaReportExportOutcome { shared, saved, cancelled }

abstract interface class ResenhaReportExporter {
  String get actionLabel;

  Future<ResenhaReportExportOutcome> export(
    String report, {
    Rect? sharePositionOrigin,
  });
}

typedef ResenhaReportWriter = FutureOr<void> Function(StringSink output);

final class ResenhaClipboardReport {
  const ResenhaClipboardReport(this.text, {required this.truncated});

  final String text;
  final bool truncated;
}

ResenhaClipboardReport boundResenhaReportForClipboard(
  String report, {
  required int byteLimit,
}) {
  if (utf8.encode(report).length <= byteLimit) {
    return ResenhaClipboardReport(report, truncated: false);
  }

  final marker = jsonEncode({
    'kind': 'export_metadata',
    'truncated': true,
    'reason': 'clipboard_limit',
    'fullReportBytes': utf8.encode(report).length,
    'message': 'Recent records only. Use Share/Save for the full report.',
  });
  final retained = <String>[];
  var retainedBytes = utf8.encode('$marker\n').length;
  final lines = const LineSplitter().convert(report);
  for (final line in lines.reversed) {
    final lineBytes = utf8.encode('$line\n').length;
    if (retainedBytes + lineBytes > byteLimit) break;
    retained.add(line);
    retainedBytes += lineBytes;
  }
  return ResenhaClipboardReport(
    '$marker\n${retained.reversed.join('\n')}',
    truncated: true,
  );
}

/// File-capable exporters can consume a report incrementally, keeping a full
/// 50 MiB capture out of the Dart heap.
abstract interface class StreamingResenhaReportExporter {
  Future<ResenhaReportExportOutcome> exportGenerated(
    ResenhaReportWriter writer, {
    Rect? sharePositionOrigin,
  });
}

/// The platform interactions around a report export.
///
/// Keeping them outside [NativeResenhaReportExporter] makes the streaming and
/// file-lifetime rules testable without opening a save panel or share sheet.
abstract interface class ResenhaReportExportEnvironment {
  Future<String?> chooseSavePath({required String suggestedName});

  Future<Directory> temporaryDirectory();

  Future<ResenhaReportExportOutcome> shareReport(
    File file, {
    required String filename,
    Rect? sharePositionOrigin,
  });
}

/// Exports only the already-redacted JSONL produced by the capture store.
///
/// Apple platforms get the system share sheet. Linux has no native share
/// implementation in share_plus, so it receives an explicit save dialog.
final class NativeResenhaReportExporter
    implements ResenhaReportExporter, StreamingResenhaReportExporter {
  NativeResenhaReportExporter({
    TargetPlatform? platform,
    ResenhaReportExportEnvironment? environment,
    DateTime Function()? clock,
  }) : _platform = platform ?? defaultTargetPlatform,
       _environment = environment ?? const _NativeExportEnvironment(),
       _clock = clock ?? DateTime.now;

  final TargetPlatform _platform;
  final ResenhaReportExportEnvironment _environment;
  final DateTime Function() _clock;

  @override
  String get actionLabel =>
      _platform == TargetPlatform.linux ? 'Save report' : 'Share report';

  @override
  Future<ResenhaReportExportOutcome> export(
    String report, {
    Rect? sharePositionOrigin,
  }) => exportGenerated(
    (output) => output.write(report),
    sharePositionOrigin: sharePositionOrigin,
  );

  @override
  Future<ResenhaReportExportOutcome> exportGenerated(
    ResenhaReportWriter writer, {
    Rect? sharePositionOrigin,
  }) async {
    final filename = _filename(_clock().toUtc());
    if (_platform == TargetPlatform.linux) {
      final destination = await _environment.chooseSavePath(
        suggestedName: filename,
      );
      if (destination == null) return ResenhaReportExportOutcome.cancelled;
      final file = File(destination);
      await _writePrivateReport(file, writer);
      return ResenhaReportExportOutcome.saved;
    }

    final temporaryDirectory = await _environment.temporaryDirectory();
    // The display name is supplied separately to the share sheet. Give the
    // physical file a unique name so overlapping exports cannot replace or
    // delete the file another share operation is still consuming.
    final file = File(
      '${temporaryDirectory.path}/resenha-export-${_randomSuffix()}.jsonl',
    );
    try {
      await _writePrivateReport(file, writer);
      return await _environment.shareReport(
        file,
        filename: filename,
        sharePositionOrigin: sharePositionOrigin,
      );
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // The OS may still briefly own the shared file. The app cache remains
        // private and the platform will reclaim it; exporting must still work.
      }
    }
  }

  static String _filename(DateTime timestampUtc) {
    final stamp = timestampUtc
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return 'resenha-diagnostics-$stamp.jsonl';
  }

  static Future<void> _writePrivateReport(
    File file,
    ResenhaReportWriter writer,
  ) async {
    // Stage beside the destination so rename is atomic. A failed generator
    // must not truncate an earlier report the user deliberately selected.
    // The directory belongs to the user, so never change its permissions.
    final temporary = File('${file.path}.${_randomSuffix()}.tmp');
    IOSink? output;
    var ownsTemporary = false;
    try {
      await temporary.create(exclusive: true);
      ownsTemporary = true;
      restrictPrivateFile(temporary);
      output = temporary.openWrite();
      await writer(output);
      await output.flush();
      await output.close();
      output = null;
      await temporary.rename(file.path);
      restrictPrivateFile(file);
    } catch (error, stackTrace) {
      try {
        await output?.close();
      } on FileSystemException {
        // Preserve the generator or rename failure, which explains the export.
      }
      try {
        if (ownsTemporary && await temporary.exists()) {
          await temporary.delete();
        }
      } on FileSystemException {
        // A private orphan is preferable to hiding the export failure.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static String _randomSuffix() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  static final Random _random = Random.secure();
}

final class _NativeExportEnvironment implements ResenhaReportExportEnvironment {
  const _NativeExportEnvironment();

  @override
  Future<String?> chooseSavePath({required String suggestedName}) async {
    final destination = await selector.getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [
        selector.XTypeGroup(
          label: 'JSON Lines diagnostics',
          extensions: ['jsonl'],
        ),
      ],
    );
    return destination?.path;
  }

  @override
  Future<Directory> temporaryDirectory() => getTemporaryDirectory();

  @override
  Future<ResenhaReportExportOutcome> shareReport(
    File file, {
    required String filename,
    Rect? sharePositionOrigin,
  }) async {
    final result = await sharing.SharePlus.instance.share(
      sharing.ShareParams(
        files: [sharing.XFile(file.path, mimeType: 'application/x-ndjson')],
        fileNameOverrides: [filename],
        subject: 'Resenha diagnostics',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    return result.status == sharing.ShareResultStatus.dismissed
        ? ResenhaReportExportOutcome.cancelled
        : ResenhaReportExportOutcome.shared;
  }
}
