import 'dart:async';

import 'package:discourse_native/src/data/composer_geometry_store.dart';
import 'package:discourse_native/src/data/diagnostics_panel_width_store.dart';
import 'package:discourse_native/src/data/sidebar_section_store.dart';
import 'package:discourse_native/src/data/sidebar_width_store.dart';
import 'package:discourse_native/src/data/topic_sidebar_store.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DiagnosticsController diagnostics;
  late DiagnosticsSinkBinding diagnosticsBinding;

  setUp(() async {
    diagnostics = await DiagnosticsController.create(
      persistence: MemoryDiagnosticsPersistence(),
      sessionId: 'ui-preference-write',
    );
    diagnosticsBinding = DiagnosticsSink.install(diagnostics);
  });

  tearDown(() async {
    diagnosticsBinding.close();
    await diagnostics.close();
  });

  test('reports a rejected composer geometry write without failing', () async {
    final persistence = _RejectingComposerGeometryPersistence();
    const geometry = ComposerGeometryPreference(
      width: 760,
      height: 320,
      horizontalPosition: 0.5,
      verticalPosition: 1,
    );

    await ComposerGeometryStore(persistence: persistence).write(geometry);

    expect(persistence.encodedGeometry, isNotNull);
    expect(
      diagnostics.events.whereType<ErrorDiagnosticEvent>().single,
      _isRejectedStorageWrite('composer.writeGeometry'),
    );
  });

  test('reports a rejected diagnostics width write without failing', () async {
    final persistence = _RejectingDiagnosticsPanelWidthPersistence();

    await DiagnosticsPanelWidthStore(persistence: persistence).write(560);

    expect(persistence.width, 560);
    expect(
      diagnostics.events.whereType<ErrorDiagnosticEvent>().single,
      _isRejectedStorageWrite('diagnosticsPanel.writeWidth'),
    );
  });

  test('reports a rejected sidebar width write without failing', () async {
    final persistence = _RejectingSidebarWidthPersistence();

    await SidebarWidthStore(persistence: persistence).write(360);

    expect(persistence.width, 360);
    expect(
      diagnostics.events.whereType<ErrorDiagnosticEvent>().single,
      _isRejectedStorageWrite('sidebar.writeWidth'),
    );
  });

  test('serializes diagnostics width writes in request order', () async {
    final persistence = _ControlledDiagnosticsPanelWidthPersistence();
    final store = DiagnosticsPanelWidthStore(persistence: persistence);

    final firstWrite = store.write(480);
    await persistence.firstWriteStarted.future;
    final secondWrite = store.write(560);
    await Future<void>.delayed(Duration.zero);

    expect(persistence.attemptedWidths, [480]);

    persistence.finishFirstWrite.complete(true);
    await Future.wait([firstWrite, secondWrite]);

    expect(persistence.attemptedWidths, [480, 560]);
    expect(persistence.persistedWidth, 560);
  });

  test('continues queued diagnostics writes after a rejected write', () async {
    final persistence = _ControlledDiagnosticsPanelWidthPersistence();
    final store = DiagnosticsPanelWidthStore(persistence: persistence);

    final firstWrite = store.write(480);
    await persistence.firstWriteStarted.future;
    final secondWrite = store.write(560);
    persistence.finishFirstWrite.complete(false);

    await Future.wait([firstWrite, secondWrite]);

    expect(persistence.attemptedWidths, [480, 560]);
    expect(persistence.persistedWidth, 560);
    final errors = diagnostics.events.whereType<ErrorDiagnosticEvent>();
    expect(errors, hasLength(1));
    expect(
      errors.single,
      _isRejectedStorageWrite('diagnosticsPanel.writeWidth'),
    );
  });

  test('reports a rejected sidebar section write without failing', () async {
    final persistence = _RejectingSidebarSectionPersistence();

    await SidebarSectionStore(persistence: persistence).write(
      siteUrl: 'https://meta.discourse.org',
      sectionId: 'community',
      collapsed: true,
    );

    expect(persistence.write, (
      siteUrl: 'https://meta.discourse.org',
      sectionId: 'community',
      collapsed: true,
    ));
    expect(
      diagnostics.events.whereType<ErrorDiagnosticEvent>().single,
      _isRejectedStorageWrite('sidebarSections.writeCollapsed'),
    );
  });

  test('reports a rejected topic sidebar write without failing', () async {
    final persistence = _RejectingTopicSidebarPersistence();

    await TopicSidebarStore(
      persistence: persistence,
    ).write(siteUrl: 'https://meta.discourse.org', collapsed: true);

    expect(persistence.write, (
      siteUrl: 'https://meta.discourse.org',
      collapsed: true,
    ));
    expect(
      diagnostics.events.whereType<ErrorDiagnosticEvent>().single,
      _isRejectedStorageWrite('topicSidebar.writeCollapsed'),
    );
  });
}

Matcher _isRejectedStorageWrite(String operation) => isA<ErrorDiagnosticEvent>()
    .having((event) => event.operation, 'operation', operation)
    .having((event) => event.source, 'source', 'storage')
    .having((event) => event.severity, 'severity', DiagnosticSeverity.warning)
    .having((event) => event.errorType, 'error type', 'StateError')
    .having((event) => event.handled, 'handled', isTrue)
    .having((event) => event.degraded, 'degraded', isTrue);

final class _RejectingComposerGeometryPersistence
    implements ComposerGeometryPersistence {
  String? encodedGeometry;

  @override
  Future<String?> readGeometry() async => null;

  @override
  Future<bool> writeGeometry(String encoded) async {
    encodedGeometry = encoded;
    return false;
  }
}

final class _RejectingDiagnosticsPanelWidthPersistence
    implements DiagnosticsPanelWidthPersistence {
  double? width;

  @override
  Future<double?> readWidth() async => null;

  @override
  Future<bool> writeWidth(double width) async {
    this.width = width;
    return false;
  }
}

final class _RejectingSidebarWidthPersistence
    implements SidebarWidthPersistence {
  double? width;

  @override
  Future<double?> readWidth() async => null;

  @override
  Future<bool> writeWidth(double width) async {
    this.width = width;
    return false;
  }
}

final class _ControlledDiagnosticsPanelWidthPersistence
    implements DiagnosticsPanelWidthPersistence {
  final firstWriteStarted = Completer<void>();
  final finishFirstWrite = Completer<bool>();
  final List<double> attemptedWidths = [];
  double? persistedWidth;

  @override
  Future<double?> readWidth() async => persistedWidth;

  @override
  Future<bool> writeWidth(double width) async {
    attemptedWidths.add(width);
    if (attemptedWidths.length == 1) {
      firstWriteStarted.complete();
      final accepted = await finishFirstWrite.future;
      if (accepted) persistedWidth = width;
      return accepted;
    }

    persistedWidth = width;
    return true;
  }
}

final class _RejectingSidebarSectionPersistence
    implements SidebarSectionPersistence {
  ({String siteUrl, String sectionId, bool collapsed})? write;

  @override
  Future<bool?> readCollapsed({
    required String siteUrl,
    required String sectionId,
  }) async => null;

  @override
  Future<bool> writeCollapsed({
    required String siteUrl,
    required String sectionId,
    required bool collapsed,
  }) async {
    write = (siteUrl: siteUrl, sectionId: sectionId, collapsed: collapsed);
    return false;
  }
}

final class _RejectingTopicSidebarPersistence
    implements TopicSidebarPersistence {
  ({String siteUrl, bool collapsed})? write;

  @override
  Future<bool?> readCollapsed({required String siteUrl}) async => null;

  @override
  Future<bool> writeCollapsed({
    required String siteUrl,
    required bool collapsed,
  }) async {
    write = (siteUrl: siteUrl, collapsed: collapsed);
    return false;
  }
}
