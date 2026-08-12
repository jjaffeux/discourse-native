import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart' as selector;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' as sharing;

import '../foundation/private_file_permissions.dart';

enum ResenhaReportExportOutcome { shared, saved, cancelled }

abstract interface class ResenhaReportExporter {
  String get actionLabel;

  Future<ResenhaReportExportOutcome> export(
    String report, {
    Rect? sharePositionOrigin,
  });
}

typedef ResenhaReportWriter = FutureOr<void> Function(StringSink output);

/// File-capable exporters can consume a report incrementally, keeping a full
/// 50 MiB capture out of the Dart heap.
abstract interface class StreamingResenhaReportExporter {
  Future<ResenhaReportExportOutcome> exportGenerated(
    ResenhaReportWriter writer, {
    Rect? sharePositionOrigin,
  });
}

/// Exports only the already-redacted JSONL produced by the capture store.
///
/// Apple platforms get the system share sheet. Linux has no native share
/// implementation in share_plus, so it receives an explicit save dialog.
final class NativeResenhaReportExporter
    implements ResenhaReportExporter, StreamingResenhaReportExporter {
  NativeResenhaReportExporter({TargetPlatform? platform})
    : _platform = platform ?? defaultTargetPlatform;

  final TargetPlatform _platform;

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
    final filename = _filename(DateTime.now().toUtc());
    if (_platform == TargetPlatform.linux) {
      final destination = await selector.getSaveLocation(
        suggestedName: filename,
        acceptedTypeGroups: const [
          selector.XTypeGroup(
            label: 'JSON Lines diagnostics',
            extensions: ['jsonl'],
          ),
        ],
      );
      if (destination == null) return ResenhaReportExportOutcome.cancelled;
      final file = File(destination.path);
      await _writePrivateReport(file, writer);
      return ResenhaReportExportOutcome.saved;
    }

    final temporaryDirectory = await getTemporaryDirectory();
    final file = File('${temporaryDirectory.path}/$filename');
    try {
      await _writePrivateReport(file, writer);
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

  static Future<void> _preparePrivateExportFile(File file) async {
    // The save destination belongs to the user. Restrict the report itself,
    // but never change the permissions of a directory they selected.
    if (!await file.exists()) await file.create();
    restrictPrivateFile(file);
  }

  static Future<void> _writePrivateReport(
    File file,
    ResenhaReportWriter writer,
  ) async {
    await _preparePrivateExportFile(file);
    final output = file.openWrite();
    try {
      await writer(output);
      await output.flush();
    } finally {
      await output.close();
    }
  }
}
