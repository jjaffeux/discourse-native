import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

const _owner = PluginId('feature');
const _host = PluginHostPortKey<String>(owner: _owner, name: 'host');
const _service = PluginServiceKey<String>(owner: _owner, name: 'service');
const _data = PluginDataKey<String>(owner: 'feature', name: 'data');

void main() {
  test('host composition rejects duplicate namespace claims', () {
    expect(
      () => PluginHostBindings(const [
        PluginHostPort<Object>(_host, 'first'),
        PluginHostPort<Object>(_host, 'second'),
      ]),
      throwsA(isA<PluginInstallationException>()),
    );
  });

  test('host composition rejects values inconsistent with the typed key', () {
    expect(
      () => PluginHostBindings(const [PluginHostPort<Object>(_host, 42)]),
      throwsA(isA<PluginInstallationException>()),
    );
  });

  test('consumer scoping rejects a value inconsistent with the typed key', () {
    final bindings = PluginHostBindings([
      PluginHostPort<Object>(_host, 'root', scopeToConsumer: (_) => 42),
    ]);
    expect(
      () => bindings.restrictedTo([_host], consumer: _owner),
      throwsA(isA<PluginInstallationException>()),
    );
    expect(bindings.require(_host), 'root');
  });

  test(
    'service composition rejects erased values and rolls back its owner',
    () async {
      final lifecycle = _Lifecycle();
      final installed = PluginInstaller.install(
        PluginManifest([_BadService(lifecycle)]),
      );
      expect(
        () => installed.openSession(const PluginHostBindings.empty()),
        throwsA(isA<PluginInstallationException>()),
      );
      await installed.close();
      expect(lifecycle.closes, 1);
    },
  );

  for (final typed in [false, true]) {
    test('data admission rejects erased values (generic call=$typed)', () {
      expect(
        () => typed
            ? PluginData.none.withValue<Object>(_data, 42)
            : PluginData.none.withValueFor(_data, 42),
        throwsArgumentError,
      );
      expect(PluginData.none.withValue(_data, 'ready').get(_data), 'ready');
    });
  }

  test('reified keys accept subtype values and permit data removal', () {
    const host = PluginHostPortKey<num>(owner: _owner, name: 'number');
    final bindings = PluginHostBindings(const [
      PluginHostPort<Object>(host, 3),
    ]);
    expect(bindings.require(host), 3);
    const data = PluginDataKey<num>(owner: 'feature', name: 'number');
    final snapshot = PluginData.none.withValueFor(data, 3);
    expect(snapshot.get(data), 3);
    expect(snapshot.withValueFor(data, null).isEmpty, isTrue);
  });

  test('record transformations retain the key type invariant', () {
    const key = PluginDataKey<_BadRecord>(owner: 'feature', name: 'record');
    final data = PluginData.none.withValue(key, const _BadRecord());
    expect(
      () => data.mergeTopicRecordsFrom(PluginData.none),
      throwsArgumentError,
    );
    expect(
      () => data.mergeCategoryRecordsFrom(PluginData.none),
      throwsArgumentError,
    );
  });
}

final class _BadRecord implements TopicRecordValue {
  const _BadRecord();
  @override
  Object mergeTopicRecord(Object? held) => 42;
}

final class _Lifecycle extends PluginSessionLifecycle {
  int closes = 0;
  @override
  void close() => closes++;
}

final class _BadService implements PluginModule {
  const _BadService(this.lifecycle);
  final _Lifecycle lifecycle;
  @override
  PluginDescriptor get descriptor => const PluginDescriptor(id: _owner);
  @override
  void register(PluginRegistrar registrar) {
    registrar.addSession(
      (_, _) => PluginSessionContribution(
        lifecycle: lifecycle,
        services: const [PluginService<Object>(_service, 42)],
      ),
    );
  }
}
