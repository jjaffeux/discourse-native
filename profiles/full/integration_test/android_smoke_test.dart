import 'dart:io';

import 'package:discourse_native/discourse_bundled.dart';
import 'package:discourse_native/src/data/draft_store.dart';
import 'package:discourse_native/src/data/private_storage.dart';
import 'package:discourse_native_full/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android persists credentials and drafts and starts the app', (
    tester,
  ) async {
    expect(Platform.isAndroid, isTrue);
    expect(Directory.systemTemp.parent.path, endsWith('/org.discourse.native'));
    const key = 'android_smoke_test';
    final credentials = platformCredentialStorage;
    addTearDown(() => credentials.delete(key));

    await credentials.write(key, 'android-smoke-secret-unique-value');
    expect(
      await AndroidKeystoreStorage().read(key),
      'android-smoke-secret-unique-value',
    );
    final preferences = File(
      '${Directory.systemTemp.parent.path}/shared_prefs/credentials.xml',
    );
    final storedBytes = await preferences.readAsString();
    expect(storedBytes, contains(key));
    expect(storedBytes, isNot(contains('android-smoke-secret-unique-value')));
    await credentials.write(key, 'replacement credential');
    expect(await credentials.read(key), 'replacement credential');
    await credentials.delete(key);
    expect(await credentials.read(key), isNull);

    const site = 'https://android-smoke.invalid';
    final drafts = DraftStore();
    addTearDown(() => drafts.clear(site, key));
    await drafts.write(site, key, 'An unfinished Android reply');
    expect(await DraftStore().read(site, key), 'An unfinished Android reply');
    await drafts.clear(site, key);
    expect(await DraftStore().read(site, key), isNull);

    app.main();
    await tester.pumpAndSettle();
    expect(find.byType(DiscourseApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
