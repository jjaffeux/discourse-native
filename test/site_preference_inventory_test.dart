import 'dart:io';

import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:discourse_native/src/site_preference_inventory.g.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/site_preference_inventory.dart';

void main() {
  test('every production declaration reaches cold-start retirement', () {
    final inventory = sitePreferenceInventory(Directory('lib/src'));
    for (final entry in inventory.files.entries) {
      expect(
        File('lib/src/${entry.key}').readAsStringSync(),
        entry.value,
        reason: 'Run dart run tool/site_preference_inventory.dart.',
      );
    }
    final plugins = PluginInstaller.install(bundledPluginManifest);
    addTearDown(plugins.close);
    final registered = [
      ...declaredSitePreferenceKeys,
      ...plugins.registry.sitePreferenceKeys,
    ];
    expect(
      registered.map((key) => key.prefix).toSet(),
      inventory.prefixes,
      reason:
          'Each plugin must expose its generated declarations through SitePreferencesPlugin.',
    );
  });

  test('new stores are discovered without editing a cleanup list', () {
    final directory = Directory.systemTemp.createTempSync('preference-owner-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/new_store.dart');
    file.writeAsStringSync('''
class NewStore {
  static const keys = SitePreferenceKey('new.store',
    retirement: SitePreferenceRetirement.storedOnly);
}
''');
    expect(
      sitePreferenceInventory(directory).files.values.join(),
      contains('NewStore.keys'),
    );
    file.writeAsStringSync('''
class NewStore {
  Future<void> write() async => (await SharedPreferences.getInstance()).setBool('hidden', true);
}
''');
    expect(
      () => sitePreferenceInventory(directory),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('without declared ownership'),
        ),
      ),
    );
    file.writeAsStringSync('''
class DeclaredStore {
  static const keys = SitePreferenceKey('declared', retirement: SitePreferenceRetirement.storedOnly);
}
@PreferenceStorage.device('One device setting.')
class DeviceStore {
  Future<void> write() async => SharedPreferences.getInstance();
}
class HiddenStore {
  Future<void> write() async => SharedPreferences.getInstance();
}
''');
    expect(
      () => sitePreferenceInventory(directory),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('HiddenStore'),
        ),
      ),
    );
    file.writeAsStringSync('''
class NewStore {
  static const keys = SitePreferenceKey('new.store', retirement: SitePreferenceRetirement.tracked);
}
''');
    expect(
      () => sitePreferenceInventory(directory),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('must register retirement'),
        ),
      ),
    );
    file.writeAsStringSync('''
class HiddenScalarStore {
  Object write(String site) => ScalarPreferenceRepository(key: site);
}
''');
    expect(
      () => sitePreferenceInventory(directory),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('HiddenScalarStore'),
        ),
      ),
    );
    file.writeAsStringSync('''
class NewStore {
  static const keys = SitePreferenceKey('new.store', retirement: SitePreferenceRetirement.managed);
}
''');
    expect(
      () => sitePreferenceInventory(directory),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('must use OwnedSitePreferences'),
        ),
      ),
    );
    file.writeAsStringSync('''
class NewStore {
  static const keys = SitePreferenceKey('new.store');
}
''');
    expect(
      () => sitePreferenceInventory(directory),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('declare retirement'),
        ),
      ),
    );
  });
}
