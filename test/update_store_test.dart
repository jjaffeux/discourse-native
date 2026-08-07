import 'package:discourse_native/src/data/update_store.dart';
import 'package:discourse_native/src/data/updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = UpdateStore();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('the channel', () {
    test('reads as no preference when nothing was stored', () async {
      expect(await store.readChannel(), isNull);
    });

    test('survives a round trip', () async {
      await store.writeChannel(UpdateChannel.canary);
      expect(await store.readChannel(), UpdateChannel.canary);

      await store.writeChannel(UpdateChannel.stable);
      expect(await store.readChannel(), UpdateChannel.stable);
    });

    test('reads as no preference when the name is no longer a channel',
        () async {
      // A preference written by an older build must not stop this one from
      // launching.
      SharedPreferences.setMockInitialValues({
        'discourse_native.update_channel': 'beta',
      });
      expect(await store.readChannel(), isNull);
    });
  });

  group('the last check', () {
    test('reads as never when nothing was stored', () async {
      expect(await store.readLastChecked(), isNull);
    });

    test('survives a round trip', () async {
      final at = DateTime.fromMillisecondsSinceEpoch(1720000000000);
      await store.writeLastChecked(at);

      expect(await store.readLastChecked(), at);
    });

    test('keeps the two facts apart', () async {
      await store.writeChannel(UpdateChannel.canary);
      final at = DateTime.fromMillisecondsSinceEpoch(1720000000000);
      await store.writeLastChecked(at);

      expect(await store.readChannel(), UpdateChannel.canary);
      expect(await store.readLastChecked(), at);
    });
  });
}
