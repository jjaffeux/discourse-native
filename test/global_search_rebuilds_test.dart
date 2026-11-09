import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugin_api/global_search_models.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/global_search_fixtures.dart';
import 'support/shell_test_harness.dart';

/// Elements rebuilt by one action, by the part of the search surface they
/// belong to. An element outside every named part counts only in [total].
typedef _Rebuilt = ({
  int total,
  int scope,
  int skeleton,
  int editor,
  int footer,
  int rows,
});

Future<_Rebuilt> _rebuilt(Future<void> Function() action) async {
  final seen = <Element>{};
  var scope = 0, skeleton = 0, editor = 0, footer = 0, rows = 0;
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    previous?.call(element, builtOnce);
    if (!seen.add(element)) return;
    String? part;
    bool visit(Element ancestor) {
      final widget = ancestor.widget;
      if (widget.key == const ValueKey('global-search-footer')) {
        part = 'footer';
      } else if (widget.key case ValueKey<String>(
        :final value,
      ) when value.startsWith('search-row:')) {
        part = 'rows';
      } else if (widget is DToggleGroup<GlobalSearchScope>) {
        part = 'scope';
      } else if (widget is DInputGroup) {
        part = 'editor';
      } else if (widget is DSkeletonRegion) {
        part = 'skeleton';
      }
      return part == null;
    }

    if (visit(element)) element.visitAncestorElements(visit);
    switch (part) {
      case 'footer':
        footer++;
      case 'rows':
        rows++;
      case 'scope':
        scope++;
      case 'editor':
        editor++;
      case 'skeleton':
        skeleton++;
    }
  };
  try {
    await action();
  } finally {
    debugOnRebuildDirtyWidget = previous;
  }
  return (
    total: seen.length,
    scope: scope,
    skeleton: skeleton,
    editor: editor,
    footer: footer,
    rows: rows,
  );
}

/// Holds each source's answer to an All search until the test releases it.
class _GatedSearchApi extends GlobalSearchFixtureApi {
  final gates = {
    for (final source in ['forum', 'messages', 'chat'])
      source: Completer<void>(),
  };

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    final uri = Uri.parse(path);
    final source = switch (uri.path) {
      '/chat/api/search.json' => 'chat',
      '/search/query.json' =>
        uri.queryParameters['type_filter'] == 'private_messages'
            ? 'messages'
            : 'forum',
      _ => null,
    };
    if (source != null) await gates[source]!.future;
    return super.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}

final _mac = TargetPlatformVariant.only(TargetPlatform.macOS);

void _proof(String metric, Object value, {String slug = 'search-panel'}) {
  // ignore: avoid_print
  print('PERF_PROOF $slug $metric=$value');
}

Future<ShellController> _mount(
  WidgetTester tester,
  Size size,
  GlobalSearchFixtureApi api,
) async {
  await pumpShell(
    tester,
    size,
    instances: globalSearchFixtureSites,
    api: api,
    authenticator: FakeAuthenticator()
      ..keys.addAll({
        globalSearchFixtureSite: 'local-fixture',
        globalSearchFixtureOtherSite: 'local-fixture',
      }),
  );
  return ShellScope.read(tester.element(find.byType(ForumSearch).first));
}

Future<void> _open(WidgetTester tester, Size size) async {
  await tester.tap(
    size == phone
        ? find.byKey(const ValueKey('mobile-search-button')).first
        : find.byKey(ForumSearch.inputKey),
  );
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(ForumSearch.inputKey), text);
  await tester.pump();
}

Finder _scopeToggle(GlobalSearchScope scope) => find.ancestor(
  of: find.byKey(ValueKey('global-search-scope-${scope.keyName}')),
  matching: find.byType(DToggle),
);

String _chipText(WidgetTester tester) {
  final chip = find.descendant(
    of: find.byKey(const ValueKey('global-search-condition-0')),
    matching: find.byType(Text),
  );
  return tester.widget<Text>(chip.first).textSpan!.toPlainText();
}

Finder _row(String id) => find.byKey(ValueKey('global-search-result-$id'));

bool _selected(WidgetTester tester, String id) =>
    tester.widget<DItem>(_row(id)).selected;

/// Opens the desktop search and starts an All search whose three sources
/// answer only when [_GatedSearchApi.gates] are released.
Future<(ShellController, _GatedSearchApi)> _searchAll(
  WidgetTester tester,
) async {
  final api = _GatedSearchApi();
  final shell = await _mount(tester, desktop, api);
  await _open(tester, desktop);
  await _type(tester, 'keyboard');
  await tester.pump(const Duration(milliseconds: 450));
  return (shell, api);
}

Future<_Rebuilt> _deliver(
  WidgetTester tester,
  _GatedSearchApi api,
  String source,
) => _rebuilt(() async {
  api.gates[source]!.complete();
  await tester.pump();
  await tester.pump();
});

void main() {
  for (final (name, size) in [('desktop', desktop), ('phone', phone)]) {
    testWidgets('a $name keystroke while loading redraws only the field', (
      tester,
    ) async {
      final api = GlobalSearchFixtureApi()..responseGate = Completer<void>();
      await _mount(tester, size, api);
      await _open(tester, size);
      await _type(tester, 'keyb');
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.byType(DSkeletonRegion), findsOneWidget);

      final rebuilt = await _rebuilt(() => _type(tester, 'keybo'));
      expect(find.byType(DSkeletonRegion), findsOneWidget);

      _proof('${name}_keystroke_elements', rebuilt.total);
      _proof('${name}_keystroke_scope_elements', rebuilt.scope);
      _proof('${name}_keystroke_skeleton_elements', rebuilt.skeleton);
      _proof('${name}_keystroke_editor_elements', rebuilt.editor);
      _proof('${name}_keystroke_footer_elements', rebuilt.footer);
      expect(rebuilt.scope, 0);
      expect(rebuilt.skeleton, 0);
      expect(rebuilt.footer, 0);
      expect(rebuilt.total, lessThanOrEqualTo(size == phone ? 72 : 66));
      api.responseGate!.complete();
      await tester.pumpAndSettle();
    }, variant: size == phone ? const DefaultTestVariant() : _mac);
  }

  testWidgets('a chip label that arrives after its condition is drawn', (
    tester,
  ) async {
    final shell = await _mount(tester, desktop, GlobalSearchFixtureApi());
    await _open(tester, desktop);
    final search = shell.globalSearch;
    search.addCondition(
      const GlobalSearchCondition(
        filterId: 'category',
        operator: 'any',
        value: ['6'],
      ),
    );
    await tester.pumpAndSettle();
    expect(_chipText(tester), endsWith(' 6'));

    search.rememberCategorySelection(const [
      GlobalSearchFilterChoice(value: '6', label: 'Bug reports'),
    ]);
    await tester.pump();

    expect(_chipText(tester), endsWith(' Bug reports'));
    expect(tester.takeException(), isNull);
  }, variant: _mac);

  testWidgets('the scope bar shows arriving counts and follows the scope', (
    tester,
  ) async {
    final shell = await _mount(tester, desktop, GlobalSearchFixtureApi());
    await _open(tester, desktop);
    final search = shell.globalSearch;
    await _type(tester, 'keyboard');
    expect(
      find.descendant(
        of: _scopeToggle(GlobalSearchScope.forum),
        matching: find.text('2'),
      ),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: _scopeToggle(GlobalSearchScope.forum),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<DToggle>(_scopeToggle(GlobalSearchScope.all)).pressed,
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(search.scope, isNot(GlobalSearchScope.all));
    expect(
      tester.widget<DToggle>(_scopeToggle(GlobalSearchScope.all)).pressed,
      isFalse,
    );
    expect(tester.widget<DToggle>(_scopeToggle(search.scope)).pressed, isTrue);
    expect(tester.takeException(), isNull);
  }, variant: _mac);

  testWidgets('the skeleton gains avatar circles for a people scope', (
    tester,
  ) async {
    final api = GlobalSearchFixtureApi()..responseGate = Completer<void>();
    final shell = await _mount(tester, desktop, api);
    await _open(tester, desktop);
    await _type(tester, 'keyboard');
    await tester.pump(const Duration(milliseconds: 450));
    final bars = tester.widgetList(find.byType(DSkeleton)).length;
    expect(bars, greaterThan(0));

    shell.globalSearch.setScope(GlobalSearchScope.users);
    await tester.pump();

    expect(find.byType(DSkeletonRegion), findsOneWidget);
    expect(tester.widgetList(find.byType(DSkeleton)).length, bars + 8);
    api.responseGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: _mac);

  testWidgets('a later source answer leaves settled result rows alone', (
    tester,
  ) async {
    final (_, api) = await _searchAll(tester);
    final first = await _deliver(tester, api, 'forum');
    expect(_row('forum:2037'), findsOneWidget);
    final second = await _deliver(tester, api, 'chat');
    expect(_row('chat:3001'), findsOneWidget);
    final last = await _deliver(tester, api, 'messages');
    expect(_row('forum:2037'), findsOneWidget);
    expect(_row('chat:3001'), findsOneWidget);

    _proof('first_delivery_elements', first.total, slug: 'search-panel-rows');
    _proof('second_delivery_elements', second.total, slug: 'search-panel-rows');
    _proof(
      'second_delivery_row_elements',
      second.rows,
      slug: 'search-panel-rows',
    );
    _proof('last_delivery_elements', last.total, slug: 'search-panel-rows');
    _proof('last_delivery_row_elements', last.rows, slug: 'search-panel-rows');
    expect(last.rows, 0);
    expect(last.total, lessThanOrEqualTo(192));
    expect(second.rows, lessThanOrEqualTo(70));
    await tester.pumpAndSettle();
  }, variant: _mac);

  testWidgets('rows from a later source appear below the settled rows', (
    tester,
  ) async {
    final (_, api) = await _searchAll(tester);
    await _deliver(tester, api, 'forum');
    expect(_row('forum:2037'), findsOneWidget);
    expect(_row('chat:3001'), findsNothing);

    await _deliver(tester, api, 'chat');

    expect(_row('forum:2037'), findsOneWidget);
    expect(_row('chat:3001'), findsOneWidget);
    expect(
      tester.getTopLeft(_row('chat:3001')).dy,
      greaterThan(tester.getTopLeft(_row('forum:2037')).dy),
    );
    api.gates['messages']!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: _mac);

  testWidgets('a keyboard-selected row stays selected across a later answer', (
    tester,
  ) async {
    final (_, api) = await _searchAll(tester);
    await _deliver(tester, api, 'forum');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_selected(tester, 'forum:2038'), isTrue);
    expect(_selected(tester, 'forum:2037'), isFalse);

    await _deliver(tester, api, 'chat');

    expect(_selected(tester, 'forum:2038'), isTrue);
    expect(_selected(tester, 'forum:2037'), isFalse);
    expect(_selected(tester, 'chat:3001'), isFalse);
    api.gates['messages']!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: _mac);

  testWidgets('hiding the excerpt property redraws settled rows', (
    tester,
  ) async {
    final (shell, api) = await _searchAll(tester);
    for (final source in ['forum', 'chat', 'messages']) {
      await _deliver(tester, api, source);
    }
    final excerpt = find.descendant(
      of: _row('forum:2037'),
      matching: find.byType(DItemDescription),
    );
    expect(excerpt, findsOneWidget);

    shell.globalSearch.setDisplayProperty(
      GlobalSearchDisplayProperty.excerpt,
      false,
    );
    await tester.pump();

    expect(excerpt, findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: _mac);
}
