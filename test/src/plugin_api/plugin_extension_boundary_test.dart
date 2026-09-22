import 'dart:convert';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/shell/global_search_api.dart';
import 'package:discourse_plugin_api/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _section = PreferenceSection.plugin(owner: 'sample', name: 'display');
const _scope = GlobalSearchScope.plugin(
  owner: 'sample',
  name: 'items',
  label: 'Items',
);

void main() {
  group('plugin preference boundary', () {
    test(
      'core ignores optional schemas, including a previous plugin fallback',
      () {
        final preferences = const DiscourseModelCodec.core().userPreferences(
          {
            'user_option': {
              'timezone': 'Europe/Paris',
              'sample_color': 'blue',
              'chat_separate_sidebar_mode': 'always',
            },
          },
          fallback: const UserPreferences(
            pluginValues: {'sample/display': _Values('red')},
          ),
        );
        expect(preferences.timezone, 'Europe/Paris');
        expect(preferences.pluginValues, isEmpty);
        expect(preferences.payloadFor(_section), isEmpty);
      },
    );

    test(
      'installed codecs parse and preserve partial updates in their namespace',
      () {
        final registry = PluginRegistry.validated([_Preferences()]);
        final models = DiscourseModelCodec(extensions: registry);
        final original = models.userPreferences({'sample_color': 'blue'});
        expect(original.payloadFor(_section), {'sample_color': 'blue'});
        final updated = models.userPreferences({
          'user_option': {'timezone': 'UTC'},
        }, fallback: original);
        expect(updated.payloadFor(_section), original.payloadFor(_section));
        expect(updated.timezone, 'UTC');
      },
    );

    test(
      'registration rejects foreign sections and overlapping wire fields',
      () {
        for (final codec in [
          _Codec(section: PreferenceSection.profile),
          _Codec(
            section: const PreferenceSection.plugin(
              owner: 'another',
              name: 'display',
            ),
          ),
          _Codec(fields: {'timezone'}),
          _Codec(fields: {'username'}),
          _Codec(fields: {''}),
        ]) {
          expect(
            () => PluginRegistry.validated([_Preferences(codec: codec)]),
            throwsArgumentError,
          );
        }
        expect(
          () => PluginRegistry.validated([
            _Preferences(),
            _Preferences(
              name: 'other',
              codec: _Codec(
                section: const PreferenceSection.plugin(
                  owner: 'other',
                  name: 'display',
                ),
              ),
            ),
          ]),
          throwsArgumentError,
        );
      },
    );

    test(
      'installation snapshots declarations and rejects undeclared decoded fields',
      () {
        final fields = {'sample_color'};
        final codec = _Codec(fields: fields);
        final plugin = _Preferences(codec: codec);
        final registry = PluginRegistry.validated([plugin]);
        fields.add('timezone');
        plugin.codecs.clear();
        expect(registry.userPreferenceFields, {'sample_color'});
        codec.injectCoreField = true;
        expect(
          () => DiscourseModelCodec(extensions: registry).userPreferences({}),
          throwsStateError,
        );
      },
    );

    test(
      'only installed wire fields may pass the shared account API',
      () async {
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'user': {'sample_color': 'blue'},
            }),
            200,
          );
        });
        final core = DiscourseApi(client: client);
        final registry = PluginRegistry.validated([_Preferences()]);
        final extended = DiscourseApi(
          client: client,
          models: DiscourseModelCodec(extensions: registry),
        );
        Future<UserPreferences> save(DiscourseApi api) =>
            api.updateUserPreferences(
              siteUrl: 'https://example.test',
              apiKey: 'key',
              username: 'mira',
              fallback: const UserPreferences(),
              values: {'sample_color': 'blue'},
            );
        await expectLater(save(core), throwsArgumentError);
        expect(requests, isEmpty);
        expect((await save(extended)).payloadFor(_section), {
          'sample_color': 'blue',
        });
        expect(jsonDecode(requests.single.body), {'sample_color': 'blue'});
      },
    );

    testWidgets('preference editors cannot mutate core or another namespace', (
      tester,
    ) async {
      final plugin = _Preferences();
      final registry = PluginRegistry.validated([plugin]);
      var current = const UserPreferences(
        timezone: 'UTC',
        pluginValues: {
          'sample/display': _Values('red'),
          'other/display': _Values('green'),
        },
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              registry.userPreferenceSections(
                context,
                PluginUserPreferenceContext(
                  siteUrl: 'https://example.test',
                  preferences: current,
                  siteSettings: PluginData.none,
                  currentUserData: PluginData.none,
                  currentUserIsAdmin: false,
                  editable: true,
                  onEdit: (section, change) => current = change(current),
                ),
              );
              return const SizedBox();
            },
          ),
        ),
      );
      plugin.context!.onEdit(
        _section,
        (value) => value.copyWith(
          timezone: 'changed',
          pluginValues: {
            'sample/display': const _Values('blue'),
            'other/display': const _Values('changed'),
          },
        ),
      );
      expect(current.timezone, 'UTC');
      expect(current.pluginValues['other/display']!.payload, {
        'sample_color': 'green',
      });
      expect(current.payloadFor(_section), {'sample_color': 'blue'});
      expect(
        () =>
            plugin.context!.onEdit(PreferenceSection.profile, (value) => value),
        throwsStateError,
      );
      expect(
        _section.keyName,
        isNot(
          const PreferenceSection.plugin(
            owner: 'other',
            name: 'display',
          ).keyName,
        ),
      );
    });
  });

  group('plugin search boundary', () {
    test(
      'core-only cannot dispatch an absent provider or its lookups',
      () async {
        final transport = RecordingPluginTransport();
        final api = GlobalSearchApi(transport: transport);
        await expectLater(
          api.search(
            siteUrl: 'https://example.test',
            apiKey: 'key',
            request: const GlobalSearchRequest(
              scope: _scope,
              query: 'test',
              capabilities: GlobalSearchCapabilities(),
            ),
          ),
          throwsFormatException,
        );
        expect(
          await api.lookupChoices(
            siteUrl: 'https://example.test',
            apiKey: 'key',
            filter: _Search.filter,
            term: 'test',
          ),
          isEmpty,
        );
        expect(transport.requests, isEmpty);
        expect(globalSearchFilter('sampleFilter'), isNull);
      },
    );

    test(
      'arbitrary plugins own availability, endpoints, results and lookups',
      () async {
        final registry = PluginRegistry.validated([_SearchPlugin(_Search())]);
        final transport = RecordingPluginTransport(
          responses: {
            'GET /site/settings.json': {'sample_enabled': true},
            'GET /session/current.json': {'current_user': <String, dynamic>{}},
            'GET /sample/items.json': {'title': 'Plugin result'},
            'GET /sample/choices.json': {'value': 'choice'},
          },
        );
        final api = GlobalSearchApi(transport: transport);
        final caps = await api.capabilities(
          siteUrl: 'https://example.test',
          apiKey: 'key',
          clientId: 'client',
          base: GlobalSearchCapabilities(
            contributions: registry.searchContributions,
            userDirectory: false,
          ),
        );
        expect(caps.scopes, contains(_scope));
        final page = await api.search(
          siteUrl: 'https://example.test',
          apiKey: 'key',
          clientId: 'client',
          request: GlobalSearchRequest(
            scope: _scope,
            query: 'test',
            capabilities: caps,
          ),
        );
        expect(page.results.single.title, 'Plugin result');
        expect(page.results.single.path, '/sample/item/42');
        expect(
          (await api.lookupChoices(
            siteUrl: 'https://example.test',
            apiKey: 'key',
            clientId: 'client',
            filter: _Search.filter,
            term: 'test',
            capabilities: caps,
          )).single.value,
          'choice',
        );
        expect(transport.requests.map((r) => (r.method, r.path)), [
          ('GET', '/site/settings.json'),
          ('GET', '/session/current.json'),
          ('GET', '/sample/items.json'),
          ('GET', '/sample/choices.json'),
        ]);
        expect(transport.requests.map((r) => r.apiKey).toSet(), {'key'});
        expect(transport.requests.map((r) => r.clientId).toSet(), {'client'});
      },
    );

    test(
      'disabled providers add no scopes, filters or network calls',
      () async {
        final source = _Search();
        final caps = GlobalSearchCapabilities(
          contributions: PluginRegistry.validated([
            _SearchPlugin(source),
          ]).searchContributions,
        );
        expect(caps.scopes, isNot(contains(_scope)));
        expect(globalSearchFilterAvailable(_Search.filter, caps), isFalse);
        final transport = RecordingPluginTransport();
        await expectLater(
          GlobalSearchApi(transport: transport).search(
            siteUrl: 'https://example.test',
            apiKey: 'key',
            request: GlobalSearchRequest(
              scope: _scope,
              query: 'test',
              capabilities: caps,
            ),
          ),
          throwsFormatException,
        );
        expect(transport.requests, isEmpty);
      },
    );

    test(
      'schema ownership, duplicate filters and installation snapshots are enforced',
      () {
        final source = _Search();
        final installed = PluginRegistry.validated([_SearchPlugin(source)]);
        source.filters.clear();
        source.scopes.clear();
        expect(installed.searchContributions.single.scopes, [_scope]);
        expect(
          installed.searchContributions.single.filters.single.id,
          'sampleFilter',
        );
        expect(
          () => PluginRegistry.validated([
            _SearchPlugin(_Search()..scopes.add(GlobalSearchScope.forum)),
          ]),
          throwsArgumentError,
        );
        expect(
          () => PluginRegistry.validated([
            _SearchPlugin(_Search()..filters.add(globalSearchFilters.first)),
          ]),
          throwsArgumentError,
        );
        expect(
          () => PluginRegistry.validated([
            _SearchPlugin(_Search(), name: 'foreign'),
          ]),
          throwsArgumentError,
        );
      },
    );
  });
}

final class _Values implements UserPreferenceValues {
  const _Values(this.color, {this.injectCoreField = false});
  final String color;
  final bool injectCoreField;
  @override
  Map<String, Object?> get payload => {
    'sample_color': color,
    if (injectCoreField) 'timezone': 'changed',
  };
}

final class _Codec implements UserPreferenceCodec {
  _Codec({this.section = _section, Set<String>? fields})
    : fields = fields ?? {'sample_color'};
  @override
  final PreferenceSection section;
  @override
  final Set<String> fields;
  bool injectCoreField = false;
  @override
  UserPreferenceValues decode(
    Map<String, dynamic> json,
    UserPreferenceValues? fallback,
  ) => _Values(
    json['sample_color'] as String? ?? (fallback as _Values?)?.color ?? 'red',
    injectCoreField: injectCoreField,
  );
}

final class _Preferences
    implements SitePlugin, UserPreferencesPlugin, UserPreferenceSectionPlugin {
  _Preferences({this.name = 'sample', _Codec? codec})
    : codecs = [codec ?? _Codec()];
  @override
  final String name;
  final List<UserPreferenceCodec> codecs;
  PluginUserPreferenceContext? context;
  @override
  List<UserPreferenceCodec> get userPreferenceCodecs => codecs;
  @override
  PluginUserPreferenceSection userPreferenceSection(
    BuildContext context,
    PluginUserPreferenceContext preferences,
  ) {
    this.context = preferences;
    return const PluginUserPreferenceSection(
      section: _section,
      title: 'Sample display',
      icon: DIcons.gear,
      content: SizedBox(),
    );
  }
}

final class _SearchPlugin implements SitePlugin, GlobalSearchPlugin {
  _SearchPlugin(_Search source, {this.name = 'sample'})
    : searchContributions = [source];
  @override
  final String name;
  @override
  final List<GlobalSearchContribution> searchContributions;
}

final class _Search extends GlobalSearchContribution {
  _Search() : super('sample');
  static const filter = GlobalSearchFilter(
    id: 'sampleFilter',
    label: 'Sample',
    scope: _scope,
    kind: GlobalSearchFilterKind.text,
    token: 'sample',
    lookup: GlobalSearchLookup.contributed,
  );
  @override
  final List<GlobalSearchScope> scopes = [_scope];
  @override
  final List<GlobalSearchFilter> filters = [filter];
  @override
  bool available(
    Map<String, dynamic> settings,
    Map<String, dynamic> user,
    bool authenticated,
  ) => settings['sample_enabled'] == true;
  @override
  List<GlobalSearchOrder> orders(GlobalSearchScope scope) => scope == _scope
      ? const [GlobalSearchOrder('relevance', 'Relevance')]
      : const [];
  @override
  Future<GlobalSearchPage> search(
    GlobalSearchReadContext context,
    GlobalSearchRequest request,
  ) async {
    final body = await context.get('/sample/items.json');
    return GlobalSearchPage(
      sections: [
        GlobalSearchSection(
          scope: _scope,
          results: [
            GlobalSearchResult(
              id: 'sample:42',
              scope: _scope,
              title: body['title'] as String,
              path: '/sample/item/42',
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<List<GlobalSearchFilterChoice>> lookup(
    GlobalSearchReadContext context,
    GlobalSearchFilter filter,
    String term,
  ) async => [
    GlobalSearchFilterChoice(
      value: (await context.get('/sample/choices.json'))['value'] as String,
      label: 'Choice',
    ),
  ];
}
