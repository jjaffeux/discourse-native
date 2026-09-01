import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_parser.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_plugin.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _declaredKind = ComposerSyntaxKind(
  owner: PluginId('component'),
  name: 'declared',
);
const _returnedKind = ComposerSyntaxKind(
  owner: PluginId('component'),
  name: 'returned',
);
const _context = ComposerSyntaxPolicyContext(
  siteUrl: 'https://meta.discourse.org',
  isPluginTarget: false,
  isEdit: false,
  initialState: ComposerPluginState(),
  readState: _readEmptyState,
);

ComposerPluginState _readEmptyState() => const ComposerPluginState();

void main() {
  group('component ownership', () {
    test('component kinds must belong to their plugin namespace', () {
      for (final kind in const [
        ComposerSyntaxKind(owner: PluginId('other'), name: 'declared'),
        ComposerSyntaxKind(owner: PluginId('component'), name: ''),
        ComposerSyntaxKind(owner: PluginId('component'), name: 'a/b'),
      ]) {
        expect(
          () => PluginRegistry.validated([
            _ComponentPlugin(
              name: 'component',
              kind: kind,
              registrations: const [],
            ),
          ]),
          throwsArgumentError,
          reason: 'accepted $kind',
        );
      }
    });

    test('two plugins cannot claim the same component kind', () {
      expect(
        () => PluginRegistry.validated(const [
          _ComponentPlugin(
            name: 'component',
            kind: _declaredKind,
            registrations: [],
          ),
          _ComponentPlugin(
            name: 'component',
            kind: _declaredKind,
            registrations: [],
          ),
        ]),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains(_declaredKind.id),
          ),
        ),
      );
    });
  });

  group('component registration', () {
    test('the registered component must match its declared kind', () {
      final target = _CountingRegistrar();
      final registry = PluginRegistry.validated([
        _ComponentPlugin(
          name: 'component',
          kind: _declaredKind,
          registrations: [_stringComponent(_returnedKind)],
        ),
      ]);

      expect(
        () => registry.registerComposerComponents(_context, target),
        throwsA(
          isA<StateError>()
              .having(
                (error) => error.message,
                'message',
                contains(_returnedKind.id),
              )
              .having(
                (error) => error.message,
                'message',
                contains(_declaredKind.id),
              ),
        ),
      );
      expect(target.adds, 0);
    });

    test('a plugin cannot register two components', () {
      final target = _CountingRegistrar();
      final component = _stringComponent(_declaredKind);
      final registry = PluginRegistry.validated([
        _ComponentPlugin(
          name: 'component',
          kind: _declaredKind,
          registrations: [component, component],
        ),
      ]);

      expect(
        () => registry.registerComposerComponents(_context, target),
        throwsStateError,
      );
      expect(target.adds, 0);
    });

    test('a plugin cannot omit its declared component', () {
      final target = _CountingRegistrar();
      final registry = PluginRegistry.validated(const [
        _ComponentPlugin(
          name: 'component',
          kind: _declaredKind,
          registrations: [],
        ),
      ]);

      expect(
        () => registry.registerComposerComponents(_context, target),
        throwsStateError,
      );
      expect(target.adds, 0);
    });
  });

  test(
    'Local Dates reaches a generic registrar with its payload type intact',
    () {
      const syntax = '[date=2026-08-09 timezone=Etc/UTC]';
      const markdown = 'Before $syntax after';
      final environment = LocalDateEnvironment.instance
        ..ensureDatabase()
        ..setDeviceTimezone('Etc/UTC');
      final target = _FindingRegistrar(markdown);
      final registry = PluginRegistry.validated([
        LocalDatesPlugin(environment: environment),
      ]);

      registry.registerComposerComponents(_context, target);

      expect(target.adds, 1);
      expect(target.kind, localDateComposerSyntaxKind);
      expect(target.payloadType, LocalDateComposerBlock);
      expect(target.value, isA<LocalDateComposerBlock>());
      expect(target.range, const TextRange(start: 7, end: 7 + syntax.length));
    },
  );
}

final class _ComponentPlugin implements SitePlugin, ComposerComponentPlugin {
  const _ComponentPlugin({
    required this.name,
    required ComposerSyntaxKind kind,
    required this.registrations,
  }) : composerComponentKind = kind;

  @override
  final String name;

  @override
  final ComposerSyntaxKind composerComponentKind;

  final List<ComposerComponent<String>> registrations;

  @override
  void registerComposerComponent(
    ComposerSyntaxPolicyContext context,
    ComposerComponentRegistrar registrar,
  ) {
    for (final component in registrations) {
      registrar.add<String>(component);
    }
  }
}

final class _CountingRegistrar implements ComposerComponentRegistrar {
  int adds = 0;

  @override
  void add<T extends Object>(ComposerComponent<T> component) {
    adds++;
  }
}

final class _FindingRegistrar implements ComposerComponentRegistrar {
  _FindingRegistrar(this.markdown);

  final String markdown;

  int adds = 0;
  ComposerSyntaxKind? kind;
  Type? payloadType;
  TextRange? range;
  Object? value;

  @override
  void add<T extends Object>(ComposerComponent<T> component) {
    final candidate = component.find(markdown).single;
    _record<T>(component, candidate);
  }

  void _record<T extends Object>(
    ComposerComponent<T> component,
    ComposerComponentCandidate<T> candidate,
  ) {
    adds++;
    kind = component.kind;
    payloadType = T;
    range = candidate.range;
    value = candidate.value;
  }
}

ComposerComponent<String> _stringComponent(ComposerSyntaxKind kind) =>
    ComposerComponent<String>.inline(
      kind: kind,
      find: (_) => const [],
      builder: (context, component) => Text(component.value),
      semanticLabel: (context, component) => component.value,
    );
