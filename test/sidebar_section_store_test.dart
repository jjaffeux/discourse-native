import 'package:discourse_native/src/data/sidebar_section_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
