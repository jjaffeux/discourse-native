import 'dart:async';

import 'package:discourse_native/src/data/sidebar_section_store.dart';
import 'package:discourse_native/src/data/site_preference_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SidebarSectionStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = SidebarSectionStore();
  });

  test('sections are expanded until a collapsed choice is saved', () async {
    expect(
      await store.read(
        siteUrl: 'https://meta.discourse.org',
        sectionId: 'community',
      ),
      isFalse,
    );

    await store.write(
      siteUrl: 'https://meta.discourse.org',
      sectionId: 'community',
      collapsed: true,
    );

    expect(
      await store.read(
        siteUrl: 'https://meta.discourse.org',
        sectionId: 'community',
      ),
      isTrue,
    );
  });

  test('choices are independent by forum and section', () async {
    await store.write(
      siteUrl: 'https://meta.discourse.org',
      sectionId: 'community',
      collapsed: true,
    );

    expect(
      await store.read(
        siteUrl: 'https://team.discourse.org',
        sectionId: 'community',
      ),
      isFalse,
    );
    expect(
      await store.read(
        siteUrl: 'https://meta.discourse.org',
        sectionId: 'chat',
      ),
      isFalse,
    );
  });

  test('dotted forum and section names keep opposite choices', () async {
    await store.write(
      siteUrl: 'https://a.b',
      sectionId: 'c.d',
      collapsed: true,
    );
    await store.write(
      siteUrl: 'https://a.b.c',
      sectionId: 'd',
      collapsed: false,
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final restored = SidebarSectionStore();
    expect(
      await restored.read(siteUrl: 'https://a.b', sectionId: 'c.d'),
      isTrue,
    );
    expect(
      await restored.read(siteUrl: 'https://a.b.c', sectionId: 'd'),
      isFalse,
    );
  });

  test('legacy choices migrate without replacing an exact false', () async {
    final legacy =
        '${SharedPreferencesSidebarSectionPersistence.keys.of('https://a.b')}.c.d';
    SharedPreferences.setMockInitialValues({legacy: true});
    for (var repeat = 0; repeat < 2; repeat++) {
      expect(
        await store.read(siteUrl: 'https://a.b', sectionId: 'c.d'),
        isTrue,
      );
    }
    await store.write(
      siteUrl: 'https://a.b',
      sectionId: 'c.d',
      collapsed: false,
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    for (var repeat = 0; repeat < 2; repeat++) {
      expect(
        await store.read(siteUrl: 'https://a.b', sectionId: 'c.d'),
        isFalse,
      );
    }
    expect(preferences.getBool(legacy), isTrue);
  });

  test('retirement removes exact choices and keeps ambiguous legacy', () async {
    final legacy =
        '${SharedPreferencesSidebarSectionPersistence.keys.of('https://a.b')}.c.d';
    SharedPreferences.setMockInitialValues({legacy: true});
    expect(
      await store.ensure(siteUrl: 'https://a.b', sectionId: 'c.d'),
      isTrue,
    );
    await store.write(
      siteUrl: 'https://a.b.c',
      sectionId: 'd',
      collapsed: false,
    );
    await forgetSitePreferences([
      SharedPreferencesSidebarSectionPersistence.keys,
    ], () => ForgottenSites.removed('https://a.b', keeping: ['https://a.b.c']));
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    expect(
      store.collapsedFor(siteUrl: 'https://a.b', sectionId: 'c.d'),
      isNull,
    );
    expect(
      preferences.containsKey(
        SharedPreferencesSidebarSectionPersistence.preferences.keyFor(
          const SitePreferenceIdentity.namedItem('https://a.b', 'c.d'),
        ),
      ),
      isFalse,
    );
    expect(preferences.getBool(legacy), isTrue);
    expect(await store.read(siteUrl: 'https://a.b.c', sectionId: 'd'), isFalse);
    await forgetSitePreferences([
      SharedPreferencesSidebarSectionPersistence.keys,
    ], () => ForgottenSites.removed('https://a.b.c', keeping: []));
    expect(preferences.containsKey(legacy), isFalse);
  });

  for (final freshWrite in [false, true]) {
    test(
      'retirement fences queued reads and snapshots with re-add $freshWrite',
      () async {
        const site = 'https://a.b';
        const neighbor = 'https://a.b.c';
        const section = 'c.d';
        final legacy =
            '${SharedPreferencesSidebarSectionPersistence.keys.of(site)}.$section';
        final backend = _HeldPreferences({'flutter.$legacy': true});
        SharedPreferencesStorePlatform.instance = backend;
        addTearDown(() {
          if (!backend.release.isCompleted) backend.release.complete();
        });
        final reader = SidebarSectionStore();
        final admitted = store.write(
          siteUrl: site,
          sectionId: section,
          collapsed: true,
        );
        await backend.started.future;
        final queued = store.read(siteUrl: site, sectionId: section);
        final snapshot = reader.ensure(siteUrl: site, sectionId: section);
        final retired = Completer<void>();
        final removal = forgetSitePreferences([
          SharedPreferencesSidebarSectionPersistence.keys,
          SitePreferenceKey(
            'test.sidebar.section.retirement',
            onForget: (_) => retired.complete(),
          ),
        ], () => ForgottenSites.removed(site, keeping: [neighbor]));
        await retired.future;
        expect(store.collapsedFor(siteUrl: site, sectionId: section), isNull);
        expect(reader.collapsedFor(siteUrl: site, sectionId: section), isNull);
        final fresh = freshWrite
            ? reader.write(siteUrl: site, sectionId: section, collapsed: false)
            : Future<void>.value();
        backend.release.complete();
        await Future.wait([admitted, removal, fresh]);
        expect(await queued, isFalse);
        expect(await snapshot, isFalse);
        expect(store.collapsedFor(siteUrl: site, sectionId: section), isNull);
        expect(
          reader.collapsedFor(siteUrl: site, sectionId: section),
          freshWrite ? isFalse : isNull,
        );
        final preferences = await SharedPreferences.getInstance();
        await preferences.reload();
        final exact = SharedPreferencesSidebarSectionPersistence.preferences
            .keyFor(const SitePreferenceIdentity.namedItem(site, section));
        expect(preferences.getBool(legacy), isTrue);
        expect(preferences.getBool(exact), freshWrite ? isFalse : isNull);
        expect(backend.values, freshWrite ? [true, false] : [true]);
        if (freshWrite) {
          expect(
            await SidebarSectionStore().read(siteUrl: site, sectionId: section),
            isFalse,
          );
        }
      },
    );
  }
}

final class _HeldPreferences extends InMemorySharedPreferencesStore {
  _HeldPreferences(super.data) : super.withData();

  final started = Completer<void>();
  final release = Completer<void>();
  final values = <Object>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    values.add(value);
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    return super.setValue(valueType, key, value);
  }
}
