import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/diagnostics/resenha_report_exporter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'resenha-report-exporter-',
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('a cancelled save does not generate or touch a report', () async {
    final environment = _FakeExportEnvironment(directory: directory);
    var generated = false;
    final exporter = NativeResenhaReportExporter(
      platform: TargetPlatform.linux,
      environment: environment,
      clock: _fixedClock,
    );

    final outcome = await exporter.exportGenerated((_) {
      generated = true;
    });

    expect(outcome, ResenhaReportExportOutcome.cancelled);
    expect(generated, isFalse);
    expect(environment.suggestedName, _expectedFilename);
    expect(exporter.actionLabel, 'Save report');
    expect(await directory.list().toList(), isEmpty);
  });

  test('a completed save atomically replaces the selected file', () async {
    final destination = File('${directory.path}/existing.jsonl');
    await destination.writeAsString('old report');
    final environment = _FakeExportEnvironment(
      directory: directory,
      savePath: destination.path,
    );
    final exporter = NativeResenhaReportExporter(
      platform: TargetPlatform.linux,
      environment: environment,
      clock: _fixedClock,
    );

    final outcome = await exporter.exportGenerated((output) async {
      output.write('first\n');
      await Future<void>.delayed(Duration.zero);
      output.write('second\n');
    });

    expect(outcome, ResenhaReportExportOutcome.saved);
    expect(await destination.readAsString(), 'first\nsecond\n');
    if (!Platform.isWindows) {
      expect((await destination.stat()).mode & 0x1ff, 0x180); // 0600
    }
    expect(await _stagedFilesFor(destination), isEmpty);
  });

  test('a failed generator preserves the previous selected file', () async {
    final destination = File('${directory.path}/existing.jsonl');
    await destination.writeAsString('old report');
    final exporter = NativeResenhaReportExporter(
      platform: TargetPlatform.linux,
      environment: _FakeExportEnvironment(
        directory: directory,
        savePath: destination.path,
      ),
    );

    await expectLater(
      exporter.exportGenerated((output) {
        output.write('partial replacement');
        throw StateError('capture failed');
      }),
      throwsA(isA<StateError>()),
    );

    expect(await destination.readAsString(), 'old report');
    expect(await _stagedFilesFor(destination), isEmpty);
  });

  test('a shared report exists only for the share operation', () async {
    const origin = Rect.fromLTWH(12, 24, 36, 48);
    final environment = _FakeExportEnvironment(
      directory: directory,
      shareOutcome: ResenhaReportExportOutcome.shared,
    );
    final exporter = NativeResenhaReportExporter(
      platform: TargetPlatform.iOS,
      environment: environment,
      clock: _fixedClock,
    );

    final outcome = await exporter.export(
      '{"safe":true}\n',
      sharePositionOrigin: origin,
    );

    expect(outcome, ResenhaReportExportOutcome.shared);
    expect(exporter.actionLabel, 'Share report');
    expect(environment.sharedFilename, _expectedFilename);
    expect(environment.sharedContents, '{"safe":true}\n');
    expect(environment.sharedOrigin, origin);
    expect(environment.sharedFileExisted, isTrue);
    expect(environment.sharedFilePath, isNotNull);
    expect(await File(environment.sharedFilePath!).exists(), isFalse);
  });

  test('overlapping shares own distinct temporary files', () async {
    final environment = _GatedShareEnvironment(directory);
    final exporter = NativeResenhaReportExporter(
      platform: TargetPlatform.iOS,
      environment: environment,
      clock: _fixedClock,
    );

    final first = exporter.export('first report');
    final second = exporter.export('second report');
    await environment.bothStarted.future;

    final firstFile = environment.files['first report']!;
    final secondFile = environment.files['second report']!;
    expect(firstFile.path, isNot(secondFile.path));
    expect(await firstFile.exists(), isTrue);
    expect(await secondFile.exists(), isTrue);

    environment.release['first report']!.complete();
    expect(await first, ResenhaReportExportOutcome.shared);
    expect(await firstFile.exists(), isFalse);
    expect(await secondFile.exists(), isTrue);

    environment.release['second report']!.complete();
    expect(await second, ResenhaReportExportOutcome.shared);
    expect(await secondFile.exists(), isFalse);
  });
}

const _expectedFilename =
    'resenha-diagnostics-2026-08-24T10-11-12-123456Z.jsonl';

DateTime _fixedClock() => DateTime.utc(2026, 8, 24, 10, 11, 12, 123, 456);

Future<List<FileSystemEntity>> _stagedFilesFor(File destination) async =>
    destination.parent
        .list()
        .where(
          (entry) =>
              entry.path.startsWith('${destination.path}.') &&
              entry.path.endsWith('.tmp'),
        )
        .toList();

final class _FakeExportEnvironment implements ResenhaReportExportEnvironment {
  _FakeExportEnvironment({
    required this.directory,
    this.savePath,
    this.shareOutcome = ResenhaReportExportOutcome.cancelled,
  });

  final Directory directory;
  final String? savePath;
  final ResenhaReportExportOutcome shareOutcome;

  String? suggestedName;
  String? sharedFilename;
  String? sharedContents;
  String? sharedFilePath;
  Rect? sharedOrigin;
  bool sharedFileExisted = false;

  @override
  Future<String?> chooseSavePath({required String suggestedName}) async {
    this.suggestedName = suggestedName;
    return savePath;
  }

  @override
  Future<ResenhaReportExportOutcome> shareReport(
    File file, {
    required String filename,
    Rect? sharePositionOrigin,
  }) async {
    sharedFilename = filename;
    sharedFilePath = file.path;
    sharedOrigin = sharePositionOrigin;
    sharedFileExisted = await file.exists();
    sharedContents = await file.readAsString();
    return shareOutcome;
  }

  @override
  Future<Directory> temporaryDirectory() async => directory;
}

final class _GatedShareEnvironment implements ResenhaReportExportEnvironment {
  _GatedShareEnvironment(this.directory);

  final Directory directory;
  final Map<String, File> files = {};
  final Map<String, Completer<void>> release = {};
  final Completer<void> bothStarted = Completer<void>();

  @override
  Future<String?> chooseSavePath({required String suggestedName}) async => null;

  @override
  Future<ResenhaReportExportOutcome> shareReport(
    File file, {
    required String filename,
    Rect? sharePositionOrigin,
  }) async {
    final report = await file.readAsString();
    files[report] = file;
    final gate = release[report] = Completer<void>();
    if (files.length == 2 && !bothStarted.isCompleted) bothStarted.complete();
    await gate.future;
    return ResenhaReportExportOutcome.shared;
  }

  @override
  Future<Directory> temporaryDirectory() async => directory;
}
