import 'package:discourse_native/src/data/composer_geometry_store.dart';
import 'package:discourse_native/src/data/sidebar_section_store.dart';
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
