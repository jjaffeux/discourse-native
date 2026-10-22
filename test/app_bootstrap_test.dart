import 'package:discourse_native/src/app_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('launches before optional startup operations', () async {
    final host = _BootstrapHost();

    AppBootstrap(host: host).start();

    expect(host.calls, ['binding', 'preferences', 'plugins', 'launch']);
    expect(host.deferred, isNotNull);

    await host.deferred!();
    expect(host.calls.skip(4), ['timezone', 'cache', 'directories']);
  });

  for (final stage in ['timezone', 'cache', 'directories']) {
    test('contains optional $stage failure after launch', () async {
      final host = _BootstrapHost(failAt: stage);
      AppBootstrap(host: host).start();

      await expectLater(host.deferred!(), completes);

      expect(
        host.calls,
        containsAllInOrder(['launch', 'timezone', 'cache', 'directories']),
      );
    });
  }

  for (final stage in ['binding', 'preferences', 'plugins', 'launch']) {
    test('propagates fatal $stage failure', () {
      final host = _BootstrapHost(failAt: stage);

      expect(
        () => AppBootstrap(host: host).start(),
        throwsA(same(host.failure)),
      );

      expect(host.deferred, isNull);
    });
  }
}

final class _BootstrapHost implements AppBootstrapHost {
  _BootstrapHost({this.failAt});

  final String? failAt;
  final failure = StateError('startup failed');
  final calls = <String>[];
  Future<void> Function()? deferred;

  void _call(String stage) {
    calls.add(stage);
    if (failAt == stage) throw failure;
  }

  @override
  void ensureFlutterInitialized() => _call('binding');

  @override
  void installPreferencesStore() => _call('preferences');

  @override
  void initializePlugins() => _call('plugins');

  @override
  void launchApplication() => _call('launch');

  @override
  void scheduleAfterFirstFrame(Future<void> Function() work) => deferred = work;

  @override
  Future<void> initializeTimezoneEnvironment() async => _call('timezone');

  @override
  Future<void> initializePersistentMediaCache() async => _call('cache');

  @override
  Future<void> restrictApplicationDirectories() async => _call('directories');
}
