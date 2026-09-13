import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugin_api/plugin_manifest.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _post = Post(id: 1, postNumber: 1, username: 'author', cooked: 'source');

void main() {
  testWidgets(
    'post transforms compose in order with owned deferred builders and inherited state',
    (tester) async {
      final calls = <String>[];
      final registry = PluginRegistry([
        _Transform('first', calls),
        _Transform('skip', calls, skip: true),
        _Transform('last', calls),
      ]);
      String? displayed;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) => registry.transformPostBody(
              context,
              'https://example.com',
              _post,
              builder: (context, html) {
                displayed = html;
                return Text(html);
              },
            ),
          ),
        ),
      );
      expect(displayed, 'source:first:last');
      expect(calls, [
        'first:entry:first:source',
        'first:builder:first',
        'skip:entry:skip:source:first',
        'last:entry:last:source:first',
        'last:builder:last',
      ]);
      expect(_post.cooked, 'source');
    },
  );

  testWidgets('absent transforms preserve the original renderer and source', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) => PluginRegistry.empty.transformPostBody(
            context,
            'https://example.com',
            _post,
            builder: (_, cooked) => Text(cooked),
          ),
        ),
      ),
    );
    expect(find.text('source'), findsOneWidget);
  });
}

class _Transform implements SitePlugin, PostBodyTransformPlugin {
  _Transform(this.name, this.calls, {this.skip = false});
  @override
  final String name;
  final List<String> calls;
  final bool skip;

  @override
  Widget? transformPostBody(
    PluginPostBodyContext context,
    String cooked,
    PluginPostBodyBuilder builder,
  ) {
    calls.add(
      '$name:entry:${PluginUiScope.ownerOf(context.buildContext).value}:$cooked',
    );
    if (skip) return null;
    if (name == 'last') {
      expect(
        context.buildContext
            .dependOnInheritedWidgetOfExactType<_Marker>()
            ?.name,
        'first',
      );
    }
    return _Marker(
      name: name,
      child: Builder(
        builder: (context) {
          calls.add('$name:builder:${PluginUiScope.ownerOf(context).value}');
          expect(
            () => PluginUiScope.optional(
              context,
              const PluginServiceKey<Object>(
                owner: PluginId('foreign'),
                name: 'private',
              ),
            ),
            throwsStateError,
          );
          return builder(context, '$cooked:$name');
        },
      ),
    );
  }
}

class _Marker extends InheritedWidget {
  const _Marker({required this.name, required super.child});
  final String name;
  @override
  bool updateShouldNotify(_Marker oldWidget) => name != oldWidget.name;
}
