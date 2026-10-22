import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/plugin_api/global_search.dart';
import 'package:discourse_native/src/shell/global_search_api.dart';
import 'package:discourse_native/src/shell/global_search_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'support/fakes.dart';

void main() {
  late GlobalSearchController search;

  setUp(() {
    search = GlobalSearchController(
      api: GlobalSearchApi(transport: FakeDiscourseApi()),
      credentials: FakeApiCredentialReader(),
      lifecycle: SiteLifecycle(),
    );
    search.configure(capabilities: const GlobalSearchCapabilities());
  });

  tearDown(() => search.dispose());

  test(
    'filter labels follow the resolved localization in each locale zone',
    () {
      for (final locale in [
        'en',
        'fr',
        ...AppLocalizations.supportedLocales.map(
          (value) => value.toLanguageTag(),
        ),
        'en',
      ]) {
        Intl.withLocale(locale, () {
          final category = search.availableFilters.firstWhere(
            (filter) => filter.id == 'category',
          );
          expect(category.label, appL10n.category);
          expect(category.placeholder, appL10n.chooseCategories);
          expect(
            search.availableFilters
                .firstWhere((filter) => filter.id == 'order')
                .label,
            appL10n.ordering,
          );
        });
      }
    },
  );

  test('staging observes replacement schemas from a raw contribution', () {
    final contribution = _MutableContribution([
      _filter('widgetFilter', 'Widget', token: 'widget'),
    ]);
    search.configure(
      capabilities: GlobalSearchCapabilities(
        contributions: [contribution],
        enabledContributions: const {'mutable'},
      ),
    );
    search.setQuery('widget:value');
    expect(search.stagedFilter?.label, 'Widget');
    expect(search.stagedTerm, 'value');
    expect(search.stagedOperator, 'is');

    contribution.definitions = [
      _filter(
        'widgetFilter',
        'Revised widget',
        token: 'widget',
        operators: const [
          GlobalSearchFilterOperator('excludes', 'Excludes'),
          GlobalSearchFilterOperator('is', 'Is'),
        ],
      ),
    ];
    expect(search.stagedFilter?.label, 'Revised widget');
    expect(search.stagedOperator, 'excludes');
    expect(
      search.availableFilters
          .firstWhere((filter) => filter.id == 'widgetFilter')
          .label,
      'Revised widget',
    );

    contribution.definitions = [
      _filter('gadgetFilter', 'Gadget', token: 'gadget'),
    ];
    expect(search.stagedFilter, isNull);
    expect(search.stagedTerm, isEmpty);
    expect(search.wordsQuery, 'widget:value');
    search.setQuery('gad');
    expect(search.hintedFilters.map((filter) => filter.id), ['gadgetFilter']);
  });

  test('availability follows mutable contribution enablement', () {
    final enabled = {'mutable'};
    final contribution = _MutableContribution([
      _filter('widgetFilter', 'Widget', token: 'widget'),
    ]);
    search.configure(
      capabilities: GlobalSearchCapabilities(
        contributions: [contribution],
        enabledContributions: enabled,
      ),
    );
    search.setQuery('widget:value');
    expect(search.stagedFilter?.id, 'widgetFilter');
    enabled.clear();
    expect(search.stagedFilter, isNull);
    expect(
      search.availableFilters.any((filter) => filter.id == 'widgetFilter'),
      isFalse,
    );
    enabled.add('mutable');
    expect(search.stagedFilter?.id, 'widgetFilter');
  });

  test('scope and capability changes refresh available and staged filters', () {
    search.configure(
      capabilities: const GlobalSearchCapabilities(authenticated: true),
    );
    search.setScope(GlobalSearchScope.forum);
    search.setQuery('tags:blue');
    expect(search.stagedFilter?.id, 'tags');
    search.setScope(GlobalSearchScope.messages);
    expect(search.stagedFilter, isNull);
    expect(
      search.availableFilters.every(
        (filter) => filter.scope == GlobalSearchScope.messages,
      ),
      isTrue,
    );
    search.setQuery('after:2026-01-01');
    expect(search.stagedFilter?.id, 'messagePostDate');
    search.setScope(GlobalSearchScope.forum);
    expect(search.stagedFilter?.id, 'postDate');
    search.setQuery('tags:blue');
    search.configure(
      capabilities: const GlobalSearchCapabilities(
        authenticated: true,
        tagging: false,
      ),
    );
    expect(search.stagedFilter, isNull);
    expect(
      search.availableFilters.any((filter) => filter.id == 'tags'),
      isFalse,
    );
    search.configure(
      capabilities: const GlobalSearchCapabilities(authenticated: true),
    );
    expect(search.stagedFilter?.id, 'tags');
  });

  test(
    'condition ordering follows mutation and current contributed labels',
    () {
      final contribution = _MutableContribution([
        _filter('first', 'Zulu', token: 'first'),
        _filter('second', 'Alpha', token: 'second'),
      ]);
      search.configure(
        capabilities: GlobalSearchCapabilities(
          contributions: [contribution],
          enabledContributions: const {'mutable'},
        ),
      );
      search.addCondition(
        const GlobalSearchCondition(filterId: 'first', value: ['one']),
      );
      search.addCondition(
        const GlobalSearchCondition(filterId: 'second', value: ['two']),
      );
      expect(search.orderedConditionIndices, [1, 0]);
      contribution.definitions = [
        _filter('first', 'Alpha', token: 'first'),
        _filter('second', 'Zulu', token: 'second'),
      ];
      expect(search.orderedConditionIndices, [0, 1]);
      search.removeCondition(0);
      expect(search.orderedConditionIndices, [0]);
      search.addCondition(
        const GlobalSearchCondition(filterId: 'first', value: ['three']),
      );
      expect(search.orderedConditionIndices, [1, 0]);
      contribution.definitions = [
        _filter('first', 'same', token: 'first'),
        _filter('second', 'SAME', token: 'second'),
      ];
      expect(search.orderedConditionIndices, [0, 1]);
    },
  );

  test('staging keeps aliases, original case and colons in values', () {
    search.setQuery('words TAG:one:two');
    expect(search.stagedFilter?.id, 'tags');
    expect(search.stagedTerm, 'one:two');
    expect(search.wordsQuery, 'words');
    search.setQuery('-tag:blue');
    expect(search.stagedFilter?.id, 'tags');
    expect(search.stagedOperator, 'none');
    search.setQuery('user:mira');
    expect(search.stagedFilter?.id, 'author');
    search.setQuery('before:2026-01-01');
    expect(search.stagedFilter?.id, 'postDate');
    expect(search.stagedOperator, 'before');
    search.setQuery('BEFORE:2026-01-01');
    expect(search.stagedFilter?.id, 'postDate');
    expect(search.stagedOperator, 'after');
  });

  test(
    'hints and words preserve short tails, whitespace and unknown tokens',
    () {
      search.setQuery('words ta');
      expect(search.hintedFilters.map((filter) => filter.id), contains('tags'));
      expect(search.wordsQuery, 'words');
      search.setQuery('words t');
      expect(search.hintedFilters, isEmpty);
      expect(search.wordsQuery, 'words t');
      for (final whitespace in [' ', '\t', '\n']) {
        search.setQuery('words ta$whitespace');
        expect(search.stagedFilter, isNull);
        expect(search.hintedFilters, isEmpty);
        expect(search.wordsQuery, 'words ta$whitespace');
      }
      search.setQuery('words\tunknown:value');
      expect(search.stagedFilter, isNull);
      expect(search.wordsQuery, 'words\tunknown:value');
      search.setQuery('words\ttags:blue');
      expect(search.stagedTerm, 'blue');
      expect(search.wordsQuery, 'words');
    },
  );

  test(
    'staged operator fallback follows condition changes without query edits',
    () {
      search.addCondition(
        const GlobalSearchCondition(
          filterId: 'postDate',
          operator: 'before',
          value: ['2026-01-01'],
        ),
      );
      search.setQuery('postDate:2026-02-02');
      expect(search.stagedOperator, 'before');
      search.updateCondition(
        0,
        const GlobalSearchCondition(
          filterId: 'postDate',
          operator: 'after',
          value: ['2026-01-01'],
        ),
      );
      expect(search.stagedOperator, 'after');
      search.removeCondition(0);
      expect(search.stagedOperator, 'after');
      expect(search.stagedTerm, '2026-02-02');
    },
  );
}

GlobalSearchFilter _filter(
  String id,
  String label, {
  required String token,
  List<GlobalSearchFilterOperator> operators = const [
    GlobalSearchFilterOperator('is', 'Is'),
    GlobalSearchFilterOperator('excludes', 'Excludes'),
  ],
}) => GlobalSearchFilter(
  id: id,
  label: label,
  scope: GlobalSearchScope.forum,
  kind: GlobalSearchFilterKind.text,
  token: token,
  operators: operators,
);

class _MutableContribution extends GlobalSearchContribution {
  _MutableContribution(this.definitions) : super('mutable');

  List<GlobalSearchFilter> definitions;

  @override
  List<GlobalSearchFilter> get filters => definitions;

  @override
  bool available(
    Map<String, dynamic> settings,
    Map<String, dynamic> user,
    bool authenticated,
  ) => true;
}
