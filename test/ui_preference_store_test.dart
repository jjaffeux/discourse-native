import 'package:discourse_native/src/data/composer_layout_store.dart';
import 'package:discourse_native/src/data/sidebar_section_store.dart';
import 'package:discourse_native/src/data/topic_sidebar_store.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {});

  tearDown(() async {});

  test('reports a rejected composer layout write without failing', () async {
    final persistence = _RejectingComposerLayoutPersistence();
    const geometry = ComposerLayoutPreference(sideWidth: 760);

    await ComposerLayoutStore(persistence: persistence).write(geometry);

    expect(persistence.encodedGeometry, isNotNull);
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
  });
}

final class _RejectingComposerLayoutPersistence
    implements ComposerLayoutPersistence {
  String? encodedGeometry;

  @override
  Future<String?> readLayout() async => null;

  @override
  Future<bool> writeLayout(String encoded) async {
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
