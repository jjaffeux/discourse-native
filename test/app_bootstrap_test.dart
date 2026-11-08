import 'package:discourse_native/src/app_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('startup admits one launch even when reentered by a host callback', () {
    final host = _BootstrapHost();
    final bootstrap = AppBootstrap(host: host);
    var reentered = false;
    host.onStage = (stage) {
      if (stage == 'plugins' && !reentered) {
        reentered = true;
        bootstrap.start();
      }
    };
    bootstrap.start();
    bootstrap.start();
    expect(host.calls, [
      'binding',
      'preferences',
      'preload',
      'plugins',
      'launch',
    ]);
    expect(host.schedules, 1);
  });

  test('a fatal startup attempt cannot repeat partial initialization', () {
    final host = _BootstrapHost(failAt: 'plugins');
    final bootstrap = AppBootstrap(host: host);
    Object? first;
    StackTrace? firstStack;
    try {
      bootstrap.start();
    } catch (error, stack) {
      first = error;
      firstStack = stack;
    }
    Object? second;
    StackTrace? secondStack;
    try {
      bootstrap.start();
    } catch (error, stack) {
      second = error;
      secondStack = stack;
    }
    expect(first, same(host.failure));
    expect(second, same(first));
    expect(secondStack.toString(), firstStack.toString());
    expect(host.calls, ['binding', 'preferences', 'preload', 'plugins']);
    expect(host.schedules, 0);
  });

  test('launches before optional startup operations', () async {
    final host = _BootstrapHost();

    AppBootstrap(host: host).start();

    expect(host.calls, [
      'binding',
      'preferences',
      'preload',
      'plugins',
      'launch',
    ]);
    expect(host.deferred, isNotNull);

    await host.deferred!();
    expect(host.calls.skip(5), ['timezone', 'cache', 'directories']);
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

  test('starts local reads after preferences install and before launch', () {
    final host = _BootstrapHost();

    AppBootstrap(host: host).start();

    expect(
      host.calls.indexOf('preload'),
      greaterThan(host.calls.indexOf('preferences')),
    );
    expect(
      host.calls.indexOf('preload'),
      lessThan(host.calls.indexOf('launch')),
    );
  });

  for (final stage in [
    'binding',
    'preferences',
    'preload',
    'plugins',
    'launch',
  ]) {
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
  void Function(String)? onStage;
  int schedules = 0;
  Future<void> Function()? deferred;

  void _call(String stage) {
    calls.add(stage);
    onStage?.call(stage);
    if (failAt == stage) throw failure;
  }

  @override
  void ensureFlutterInitialized() => _call('binding');

  @override
  void installPreferencesStore() => _call('preferences');

  @override
  void preloadLocalState() => _call('preload');

  @override
  void initializePlugins() => _call('plugins');

  @override
  void launchApplication() => _call('launch');

  @override
  void scheduleAfterFirstFrame(Future<void> Function() work) {
    schedules++;
    deferred = work;
  }

  @override
  Future<void> initializeTimezoneEnvironment() async => _call('timezone');

  @override
  Future<void> initializePersistentMediaCache() async => _call('cache');

  @override
  Future<void> restrictApplicationDirectories() async => _call('directories');
}
