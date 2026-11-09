import 'package:discourse_native/src/plugin_api/plugin_contracts.dart';
import 'package:discourse_native/src/plugin_api/plugin_ui_scope.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _owner = PluginId('owner');
const _key = PluginServiceKey<String>(owner: _owner, name: 'value');
const _foreignKey = PluginServiceKey<String>(
  owner: PluginId('foreign'),
  name: 'value',
);

final class _Directory implements PluginServiceDirectory {
  const _Directory(this.value);

  final String value;

  @override
  PluginOwnedServices servicesFor(PluginId owner) =>
      PluginOwnedServices(owner, {_key: value});
}

Widget _owned(WidgetBuilder builder) => Directionality(
  textDirection: TextDirection.ltr,
  child: PluginUiScope.own(_owner, Builder(builder: builder)),
);

void main() {
  testWidgets('a directory alone serves a contribution its own services', (
    tester,
  ) async {
    String? value;
    await tester.pumpWidget(
      PluginServicesScope(
        directory: const _Directory('first'),
        child: _owned((context) {
          value = PluginUiScope.require(context, _key);
          return const SizedBox();
        }),
      ),
    );

    expect(value, 'first');
  });

  testWidgets('a retained owner stamp reads only its own directory view', (
    tester,
  ) async {
    late BuildContext stamped;
    await tester.pumpWidget(
      PluginServicesScope(
        directory: const _Directory('first'),
        child: Builder(
          builder: (context) {
            stamped = PluginUiScope.contextFor(context, _owner);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(PluginUiScope.ownerOf(stamped), _owner);
    expect(PluginUiScope.require(stamped, _key), 'first');
    expect(() => PluginUiScope.maybe(stamped, _foreignKey), throwsStateError);
  });

  testWidgets('replacing the directory republishes to owned descendants', (
    tester,
  ) async {
    final seen = <String?>[];
    final child = _owned((context) {
      seen.add(PluginUiScope.optional(context, _key));
      return const SizedBox();
    });

    await tester.pumpWidget(
      PluginServicesScope(directory: const _Directory('first'), child: child),
    );
    await tester.pumpWidget(
      PluginServicesScope(directory: const _Directory('second'), child: child),
    );

    expect(seen, ['first', 'second']);
  });

  testWidgets('outside any directory an owner resolves nothing', (
    tester,
  ) async {
    String? value = 'unset';
    await tester.pumpWidget(
      _owned((context) {
        value = PluginUiScope.optional(context, _key);
        return const SizedBox();
      }),
    );

    expect(value, isNull);
  });
}
