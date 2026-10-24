import 'package:flutter_test/flutter_test.dart';

import 'support/owner_dependency_graph.dart';

const _owner = 'lib/src/owner.dart';
const _shell = 'lib/src/shell_controller.dart';
const _scope = 'lib/src/shell_scope.dart';

List<String> _check(Map<String, String> sources) => OwnerDependencyGraph({
  _shell: 'class ShellController {}',
  _scope: 'class ShellScope {}',
  ...sources,
}).violations(owners: [_owner], forbidden: {_shell, _scope});

void _expectForbidden(Map<String, String> sources, List<String> path) {
  final violations = _check(sources);
  expect(violations, isNotEmpty);
  final diagnostic = violations.join('\n');
  var cursor = 0;
  for (final step in path) {
    final index = diagnostic.indexOf(step, cursor);
    expect(index, greaterThanOrEqualTo(0), reason: diagnostic);
    cursor = index + step.length;
  }
  expect(diagnostic, contains('Forbidden shell authority'));
  expect(diagnostic, contains('Pass a narrow typed capability instead'));
  expect(diagnostic, contains('keep the owner library outside'));
}

void main() {
  group('standalone owner library authority', () {
    for (final directive in [
      "import 'shell_controller.dart';",
      "import 'package:discourse_native/src/shell_controller.dart' "
          'deferred as shell show ShellController;',
      "import './nested/../shell_controller.dart' as shell hide Unused;",
      "import '%73hell_controller.dart';",
      "import '%2e/temporary/%2e%2e/shell_controller.dart';",
      "import 'package:discourse_native/src/%73hell_controller.dart' as shell;",
      "import 'package:discourse_native/src/temporary/%2e%2e/shell_controller.dart';",
      "export 'shell_controller.dart' show ShellController;",
    ]) {
      test('rejects $directive', () {
        _expectForbidden({_owner: directive}, [_owner, _shell]);
      });
    }

    test('reports full aliased barrel path and directive location', () {
      final sources = {
        _owner: "import 'barrel.dart' as api;",
        'lib/src/barrel.dart': "export 'nested/contracts.dart' hide Unused;",
        'lib/src/nested/contracts.dart':
            "export 'package:discourse_native/src/shell_scope.dart';",
      };
      _expectForbidden(sources, [
        _owner,
        '--import at $_owner:1',
        'lib/src/barrel.dart',
        '--export at lib/src/barrel.dart:1',
        'lib/src/nested/contracts.dart',
        _scope,
      ]);
    });

    for (final kind in ['import', 'export']) {
      test('checks every conditional $kind branch', () {
        for (final shellBranch in [0, 1, 2]) {
          final choices = List.filled(3, 'safe.dart');
          choices[shellBranch] = 'shell_controller.dart';
          _expectForbidden(
            {
              _owner:
                  "$kind '${choices[0]}' if (dart.library.io) '${choices[1]}' "
                  "if (dart.library.html) '${choices[2]}';",
              'lib/src/safe.dart': 'class Safe {}',
            },
            [_owner, _shell],
          );
        }
      });
    }

    test('checks imports from the owning library of a URI part', () {
      _expectForbidden(
        {
          _owner: "part of 'parent.dart';",
          'lib/src/parent.dart':
              "import 'shell_controller.dart'; part 'owner.dart';",
        },
        [_owner, 'lib/src/parent.dart', _shell],
      );
    });

    test('checks imports from a named owning library', () {
      _expectForbidden(
        {
          _owner: 'part of feature.owner;',
          'lib/src/parent.dart':
              "library feature.owner; import 'shell_scope.dart'; part 'owner.dart';",
        },
        [_owner, 'lib/src/parent.dart', _scope],
      );
    });

    test('rejects a protected owner becoming a shell part', () {
      for (final named in [false, true]) {
        _expectForbidden(
          {
            _owner: named
                ? 'part of shell;'
                : "part of 'shell_controller.dart';",
            _shell:
                "${named ? 'library shell;' : ''} "
                "part 'owner.dart'; class ShellController {}",
          },
          [_owner, _shell],
        );
      }
    });

    test('rejects reciprocal membership without a part-of declaration', () {
      _expectForbidden(
        {
          _owner: 'class Owner {}',
          _shell: "part 'owner.dart'; class ShellController {}",
        },
        [_owner, _shell],
      );
    });

    test('checks authority introduced through an owner part', () {
      _expectForbidden(
        {
          _owner: "part 'implementation.dart';",
          'lib/src/implementation.dart': "part of 'shell_controller.dart';",
        },
        [_owner, 'lib/src/implementation.dart', _shell],
      );
    });

    test('rejects attempted authority recovery by importing a barrel part', () {
      _expectForbidden(
        {
          _owner: "import 'barrel_part.dart';",
          'lib/src/barrel_part.dart': "part of 'barrel.dart';",
          'lib/src/barrel.dart':
              "export 'shell_scope.dart'; part 'barrel_part.dart';",
        },
        [_owner, 'lib/src/barrel_part.dart', 'lib/src/barrel.dart', _scope],
      );
    });

    test('accepts typed dependencies without following private imports', () {
      expect(
        _check({
          _owner:
              "import 'store.dart'; import 'topic_data_session.dart'; "
              "import 'account_activity_controller.dart'; "
              "import 'plugin_contract.dart'; "
              "import 'package:flutter/foundation.dart'; "
              "import 'package:flutter/widgets.dart'; "
              'class Owner { Store? store; TopicDataSession? topics; '
              'AccountActivityController? activity; PluginContract? plugin; }',
          'lib/src/store.dart':
              "import 'shell_controller.dart'; class Store {}",
          'lib/src/topic_data_session.dart':
              "import 'shell_scope.dart'; class TopicDataSession {}",
          'lib/src/account_activity_controller.dart':
              "import 'shell_controller.dart'; class AccountActivityController {}",
          'lib/src/plugin_contract.dart':
              "export 'typed_contract.dart'; import 'shell_scope.dart';",
          'lib/src/typed_contract.dart': 'abstract class PluginContract {}',
        }),
        isEmpty,
      );
    });

    for (final named in [false, true]) {
      test('accepts valid ${named ? 'named' : 'URI'} library parts', () {
        expect(
          _check({
            _owner: named ? 'part of preview;' : "part of 'preview.dart';",
            'lib/src/preview.dart':
                "${named ? 'library preview;' : ''} "
                "import 'typed.dart'; part 'owner.dart'; part 'other.dart';",
            'lib/src/other.dart': named
                ? 'part of preview;'
                : "part of 'preview.dart';",
            'lib/src/typed.dart': 'class TypedCapability {}',
          }),
          isEmpty,
        );
      });
    }

    test('does not inherit private imports from an imported part library', () {
      expect(
        _check({
          _owner: "import 'typed.dart';",
          'lib/src/typed_part.dart': "part of 'typed.dart'; class Typed {}",
          'lib/src/typed.dart':
              "import 'shell_controller.dart'; part 'typed_part.dart';",
        }),
        isEmpty,
      );
    });

    test('terminates export cycles and reports deterministically', () {
      final sources = {
        _owner: "import 'a.dart';",
        'lib/src/a.dart': "export 'b.dart';",
        'lib/src/b.dart': "export 'a.dart'; export 'shell_controller.dart';",
      };
      _expectForbidden(sources, [
        _owner,
        'lib/src/a.dart',
        'lib/src/b.dart',
        _shell,
      ]);
      expect(
        _check(sources),
        _check(Map.fromEntries(sources.entries.toList().reversed)),
      );
      expect(
        _check({...sources, 'lib/src/b.dart': "export 'a.dart';"}),
        isEmpty,
      );
    });

    test('ignores comments and strings that resemble directives', () {
      expect(
        _check({
          _owner: '''
// import 'shell_controller.dart';
/* export 'shell_scope.dart'; */
const example = "import 'shell_controller.dart';";
''',
        }),
        isEmpty,
      );
    });

    for (final sources in <Map<String, String>>[
      {},
      {_owner: "import 'missing.dart';"},
      {_owner: "export 'missing.dart';"},
      {_owner: "part of 'missing.dart';"},
      {_owner: "part 'missing.dart';"},
    ]) {
      test('fails explicitly for missing expected source $sources', () {
        final diagnostic = _check(sources).join('\n');
        expect(diagnostic, contains(_owner));
        expect(diagnostic, contains('Missing expected local source'));
        expect(diagnostic, contains('Restore the source or update'));
      });
    }

    test(
      'fails when a declared shell authority source moves or disappears',
      () {
        final violations = OwnerDependencyGraph({
          _owner: 'class Owner {}',
        }).violations(owners: [_owner], forbidden: {_shell});
        expect(violations, hasLength(1));
        expect(violations.single, contains(_shell));
        expect(
          violations.single,
          contains('Missing declared shell authority source'),
        );
        expect(violations.single, contains('Update the boundary declaration'));
      },
    );

    test('fails explicitly for malformed reachable sources', () {
      for (final sources in [
        {_owner: 'class {'},
        {_owner: 'part of ;'},
        {_owner: 'import ;'},
        {_owner: "import 'unterminated"},
        {_owner: "import 'broken.dart';", 'lib/src/broken.dart': 'class {'},
      ]) {
        final diagnostic = _check(sources).join('\n');
        expect(diagnostic, contains(_owner));
        expect(diagnostic, contains('malformed Dart source'));
        expect(diagnostic, contains('Repair the source'));
      }
    });

    test('accepts platform source paths before resolving declarations', () {
      final graph = OwnerDependencyGraph({
        r'lib\src\owner.dart': "import 'typed.dart';",
        r'lib\src\typed.dart': 'class TypedCapability {}',
        r'lib\src\shell_controller.dart': 'class ShellController {}',
        r'lib\src\shell_scope.dart': 'class ShellScope {}',
      });
      expect(
        graph.violations(owners: [_owner], forbidden: {_shell, _scope}),
        isEmpty,
      );
    });

    test('rejects shell recovery from platform source paths', () {
      _expectForbidden(
        {r'lib\src\owner.dart': "import 'shell_controller.dart';"},
        [_owner, _shell],
      );
    });

    test('decodes percent escapes exactly once', () {
      expect(
        _check({
          _owner: "import '%2573hell_controller.dart';",
          'lib/src/%73hell_controller.dart': 'class TypedCapability {}',
        }),
        isEmpty,
      );
    });

    test('fails explicitly for invalid reachable directive URIs', () {
      for (final uri in [
        'http://[',
        '../../../escape.dart',
        'file:///outside.dart',
      ]) {
        final diagnostic = _check({_owner: "import '$uri';"}).join('\n');
        expect(diagnostic, contains('$_owner:1'));
        expect(diagnostic, contains('invalid local directive'));
        expect(diagnostic, contains('Repair the source'));
      }
    });

    test('binds named parts by declared membership, not a global name', () {
      expect(
        _check({
          _owner: 'part of feature;',
          'lib/src/parent.dart': "library feature; part 'owner.dart';",
          'lib/src/unrelated.dart': 'library feature; class Unrelated {}',
        }),
        isEmpty,
      );
    });

    test('fails for unresolved or ambiguous named library membership', () {
      for (final parents in [
        <String, String>{},
        {'lib/src/unrelated.dart': 'library duplicate; class Unrelated {}'},
        {
          'lib/src/a.dart': "library duplicate; part 'owner.dart';",
          'lib/src/b.dart': "library duplicate; part 'owner.dart';",
        },
      ]) {
        final diagnostic = _check({
          _owner: 'part of duplicate;',
          ...parents,
        }).join('\n');
        expect(diagnostic, contains(_owner));
        expect(
          diagnostic,
          contains('named part-of duplicate must resolve to one'),
        );
        expect(diagnostic, contains('Repair the source'));
      }
    });
  });
}
