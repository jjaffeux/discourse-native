import 'dart:io';

import 'package:discourse_native/src/foundation/site_scoped_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Classes that forget a site but are retired by something other than the
/// shell's registry. Each names what retires it.
const _retiredElsewhere = <String, String>{
  'Store': 'registered as one step with the cooking rebind that must follow it',
  'RecentSearchHistory': 'ShellSearchController forgets it',
  'ComposerDraftCoordinator': '_RetainedComposerRegistry forgets it',
  'PreviewRequests': 'PreviewLoadingOwner retires it with the site lease',
};

final _classHeader = RegExp(
  r'^(?:abstract |base |final |sealed |interface |mixin )*class (\w+)([^{]*)\{',
  multiLine: true,
);
final _forgetsSite = RegExp(
  r'^  void (?:forget|forgetSite)\(String siteUrl\)',
  multiLine: true,
);

typedef _Owner = ({String name, bool registrable});

/// Every class in [source] that declares a per-site forget.
List<_Owner> _siteOwners(String source) {
  final headers = _classHeader.allMatches(source).toList();
  return [
    for (final (index, header) in headers.indexed)
      if (_forgetsSite.hasMatch(
        source.substring(
          header.end,
          index + 1 < headers.length ? headers[index + 1].start : source.length,
        ),
      ))
        (name: header[1]!, registrable: header[2]!.contains('ScopedState')),
  ];
}

List<_Owner> _shellSiteOwners() => [
  for (final directory in ['lib/src/shell', 'lib/src/data'])
    for (final entity in Directory(directory).listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart'))
        ..._siteOwners(entity.readAsStringSync()),
];

/// The fields of [source] declared with, or initialized as, one of [types].
Set<String> _fieldsOfType(String source, Set<String> types) => {
  for (final match in RegExp(
    r'^  (?:late )?final (\w+)\??\s+(\w+)\s*[=;]',
    multiLine: true,
  ).allMatches(source))
    if (types.contains(match[1])) match[2]!,
  for (final match in RegExp(
    r'^  (?:late )?final (\w+) =\s+(\w+)[(<.]',
    multiLine: true,
  ).allMatches(source))
    if (types.contains(match[2])) match[1]!,
};

String _methodBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNonNegative, reason: 'missing $signature');
  return source.substring(start, source.indexOf('\n  }\n', start));
}

void main() {
  group('per-site owners', () {
    late List<_Owner> owners;
    setUpAll(() => owners = _shellSiteOwners());

    test('declare the site-scoped capability or name what retires them', () {
      expect(owners, isNotEmpty);
      final undeclared = [
        for (final owner in owners)
          if (!owner.registrable && !_retiredElsewhere.containsKey(owner.name))
            owner.name,
      ];
      expect(
        undeclared,
        isEmpty,
        reason:
            'A class with forget(String siteUrl) implements SiteScopedState '
            '(or mixes in AccountScopedState) and is registered in '
            'ShellController._siteState.',
      );
    });

    test('exemptions name classes that still forget a site', () {
      final names = {for (final owner in owners) owner.name};
      expect(_retiredElsewhere.keys.toSet().difference(names), isEmpty);
      expect([
        for (final owner in owners)
          if (owner.registrable && _retiredElsewhere.containsKey(owner.name))
            owner.name,
      ], isEmpty);
    });

    test('are all registered by the shell that holds them', () {
      final shell = File(
        'lib/src/shell/shell_controller.dart',
      ).readAsStringSync();
      final registrable = {
        for (final owner in owners)
          if (owner.registrable) owner.name,
        // Declared in a library of its own subclasses.
        'SiteVideoThumbnailRepository',
        'SitePdfThumbnailRepository',
      };
      final held = _fieldsOfType(shell, registrable)
        // The injected instances behind siteImages and the two thumbnail
        // repositories, which are the fields that register.
        ..removeWhere((field) => field.startsWith('_provided'));
      expect(held.length, greaterThan(35));
      final start = shell.indexOf('_siteState = SiteStateRegistry()');
      final registry = shell.substring(start, shell.indexOf(';\n\n', start));
      expect(
        [
          for (final field in held)
            if (!registry.contains('..register($field)')) field,
        ],
        isEmpty,
        reason: 'Add `..register(<field>)` to ShellController._siteState.',
      );
    });
  });

  test('chat forgets every collection it keys by site', () {
    final chat = File(
      'lib/src/plugins/chat/chat_controller.dart',
    ).readAsStringSync();
    final start = chat.indexOf(
      RegExp(r'^class ChatController', multiLine: true),
    );
    final body = chat.substring(
      start,
      chat.indexOf(RegExp(r'^}', multiLine: true), start),
    );
    final collections = [
      for (final match in RegExp(
        r'^  final (?:LinkedHashMap|Map|Set)<[^;=]*?\b(_\w+)\s*=',
        multiLine: true,
      ).allMatches(body))
        match[1]!,
    ];
    expect(collections.length, greaterThanOrEqualTo(14));
    final forget = _methodBody(body, '  void forget(String siteUrl) {');
    expect(
      [
        for (final field in collections)
          if (!forget.contains('$field.')) field,
      ],
      isEmpty,
      reason: 'ChatController.forget must retire every per-site collection.',
    );
  });

  group('detection', () {
    test('reports a class that forgets a site without the capability', () {
      expect(
        _siteOwners('''
final class Declared extends Notifier with AccountScopedState {
  @override
  void forget(String siteUrl) {}
}

final class Forgotten {
  void forget(String siteUrl) {}
}

final class Unrelated {
  void forget(int id) {}
}
'''),
        [
          (name: 'Declared', registrable: true),
          (name: 'Forgotten', registrable: false),
        ],
      );
    });

    test('finds held fields by type', () {
      expect(
        _fieldsOfType(
          '''
  final Owner eager;
  late final Owner _lazy = Owner();
  late final Other other = Other();
''',
          {'Owner'},
        ),
        {'eager', '_lazy'},
      );
    });
  });

  group('SiteStateRegistry', () {
    test('retires owners in registration order, lifecycle only on removal', () {
      final log = <String>[];
      final registry = SiteStateRegistry()
        ..register(AccountScopedState.step((site) => log.add('account $site')))
        ..registerRemovalStep((site) => log.add('removal $site'))
        ..register(SiteScopedState.step((site) => log.add('site $site')));

      registry.forget('a', siteRemoved: false);
      expect(log, ['account a', 'site a']);

      log.clear();
      registry.forget('a', siteRemoved: true);
      expect(log, ['account a', 'removal a', 'site a']);
    });

    test('an account change reaches only account-scoped owners and stops '
        'once the publication is no longer owned', () {
      final log = <String>[];
      var owned = true;
      final registry = SiteStateRegistry()
        ..register(AccountScopedState.step((site) => log.add('first')))
        ..register(SiteScopedState.step((site) => log.add('site')))
        ..register(
          AccountScopedState.step((site) {
            log.add('second');
            owned = false;
          }),
        )
        ..register(AccountScopedState.step((site) => log.add('third')));

      expect(registry.accountChanged('a', stillOwned: () => owned), isFalse);
      expect(log, ['first', 'second']);
    });
  });
}
