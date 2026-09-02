import 'dart:ui' show Tristate;

import 'package:discourse_native/discourse_plugin_test.dart'
    show PluginTestRequestHost;
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_feed.dart';
import 'package:discourse_native/src/plugins/assign/assigned_group.dart';
import 'package:discourse_native/src/plugins/assign/assigned_group_api.dart';
import 'package:discourse_native/src/plugins/assign/assigned_group_controller.dart';
import 'package:discourse_native/src/plugins/assign/assigned_group_presentation.dart';
import 'package:discourse_native/src/plugins/assign/assigned_group_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _siteUrl = 'https://forum.example.com';
const _topic = Topic(
  id: 42,
  title: 'Investigate the deploy',
  slug: 'investigate-the-deploy',
  postsCount: 3,
  views: 91,
);

void main() {
  group('AssignedGroupPresentationController', () {
    test('projects domain state and delegates route actions', () async {
      final api = _RecordingAssignedGroupApi();
      final domain = AssignedGroupController(
        api: api,
        requests: PluginTestRequestHost(apiKeys: const {_siteUrl: 'api-key'}),
      );
      addTearDown(domain.dispose);
      final selected = <(String, AssignedGroupFilter)>[];
      final opened = <Topic>[];
      final presentation = AssignedGroupPresentationController(
        siteUrl: _siteUrl,
        groupName: 'support',
        subsection: 'Sam',
        controller: domain,
        onSelectFilter: (groupName, filter) {
          selected.add((groupName, filter));
        },
        onOpenTopic: opened.add,
      );
      addTearDown(presentation.dispose);

      await presentation.load();
      presentation.selectFilter(const AssignedGroupFilter.directGroup());
      presentation.openTopic(_topic);

      expect(presentation.state.filter, AssignedGroupFilter.member('sam'));
      expect(presentation.state.members.members.single.username, 'Sam');
      expect(presentation.state.topics, [_topic]);
      expect(selected, [('support', const AssignedGroupFilter.directGroup())]);
      expect(opened, [_topic]);
      expect(api.memberCalls.single.search, '');
      expect(api.topicCalls.single.filter, AssignedGroupFilter.member('sam'));
    });

    test('coordinates query, member search, and pagination', () async {
      final api = _RecordingAssignedGroupApi();
      final domain = AssignedGroupController(
        api: api,
        requests: PluginTestRequestHost(apiKeys: const {_siteUrl: 'api-key'}),
      );
      addTearDown(domain.dispose);
      final presentation = AssignedGroupPresentationController(
        siteUrl: _siteUrl,
        groupName: 'support',
        subsection: 'everyone',
        controller: domain,
        onSelectFilter: (_, _) {},
        onOpenTopic: (_) {},
      );
      addTearDown(presentation.dispose);

      await presentation.load();
      presentation.replaceQuery(
        const AssignedGroupTopicQuery(
          order: AssignedGroupOrder.views,
          ascending: true,
          search: 'deploy',
        ),
      );
      presentation.searchMembers('  sam  ');
      await pumpEventQueue();
      presentation.loadMoreMembers();
      presentation.loadMoreTopics();
      await pumpEventQueue();

      expect(presentation.state.query.search, 'deploy');
      expect(api.memberCalls.map((call) => call.search), ['', 'sam', 'sam']);
      expect(api.memberCalls.map((call) => call.offset), [0, 0, 50]);
      expect(api.topicCalls.map((call) => call.query.search), ['', 'deploy']);
      expect(api.pageCalls, ['/assignments.json?page=2']);
      presentation.dispose();
    });
  });

  group('AssignedGroupView', () {
    testWidgets('renders initial loading and in-place refreshing states', (
      tester,
    ) async {
      final presentation = _FakeAssignedGroupPresentation(
        _state(feed: const TopicFeed.loading()),
      );
      await _pumpView(tester, presentation);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.text('No active assignments match this filter.'),
        findsNothing,
      );
      expect(presentation.loads, [false]);

      presentation.show(
        _state(
          feed: const TopicFeed(topicIds: [42], loading: true, loaded: true),
          topics: const [_topic],
        ),
      );
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text(_topic.title), findsOneWidget);
    });

    testWidgets('renders an error and retries through the presentation', (
      tester,
    ) async {
      final presentation = _FakeAssignedGroupPresentation(
        _state(feed: const TopicFeed.failed('Assignments unavailable.')),
      );
      await _pumpView(tester, presentation);

      expect(find.text('Assignments unavailable.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pump();

      expect(presentation.loads, [false, true]);
    });

    testWidgets('renders the empty state only after a successful empty load', (
      tester,
    ) async {
      final presentation = _FakeAssignedGroupPresentation(
        _state(feed: const TopicFeed(loaded: true)),
      );
      await _pumpView(tester, presentation);

      expect(
        find.text('No active assignments match this filter.'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('exposes member filters, search, pagination, and semantics', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final presentation = _FakeAssignedGroupPresentation(
        _state(
          filter: AssignedGroupFilter.member('sam'),
          members: const AssignedGroupMembersState(
            members: [
              AssignedGroupMember(
                id: 7,
                username: 'Sam',
                usernameLower: 'sam',
                assignmentsCount: 4,
              ),
            ],
            assignmentCount: 8,
            groupAssignmentCount: 2,
            hasMore: true,
            loaded: true,
          ),
          feed: const TopicFeed(loaded: true),
        ),
      );
      await _pumpView(tester, presentation);

      final memberFinder = find.widgetWithText(ChoiceChip, '@Sam (4)');
      final memberChip = tester.widget<ChoiceChip>(memberFinder);
      expect(memberChip.selected, isTrue);
      expect(
        tester
            .getSemantics(memberFinder)
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(find.byTooltip('Ascending'), findsOneWidget);

      await tester.tap(find.text('@support (2)'));
      await tester.tap(find.text('@Sam (4)'));
      await tester.tap(find.text('More people'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Find assigned person'),
        ' Alex ',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);

      expect(presentation.selectedFilters, [
        const AssignedGroupFilter.directGroup(),
        AssignedGroupFilter.member('sam'),
      ]);
      expect(presentation.loadMoreMemberCalls, 1);
      expect(presentation.memberSearches, [' Alex ']);
      semantics.dispose();
    });

    testWidgets('forwards topic query controls without losing query fields', (
      tester,
    ) async {
      final presentation = _FakeAssignedGroupPresentation(
        _state(
          query: const AssignedGroupTopicQuery(
            order: AssignedGroupOrder.posts,
            ascending: true,
          ),
          feed: const TopicFeed(loaded: true),
        ),
      );
      await _pumpView(tester, presentation);

      await tester.enterText(
        find.widgetWithText(TextField, 'Search assignments'),
        ' incident ',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.tap(find.byTooltip('Descending'));

      expect(presentation.queries, [
        const AssignedGroupTopicQuery(
          order: AssignedGroupOrder.posts,
          ascending: true,
          search: 'incident',
        ),
        const AssignedGroupTopicQuery(
          order: AssignedGroupOrder.posts,
          ascending: false,
        ),
      ]);
    });

    testWidgets('opens topics and requests the next assignment page', (
      tester,
    ) async {
      final presentation = _FakeAssignedGroupPresentation(
        _state(
          feed: const TopicFeed(
            topicIds: [42],
            loaded: true,
            nextPagePath: '/assignments?page=2',
          ),
          topics: const [_topic],
        ),
      );
      await _pumpView(tester, presentation);

      expect(find.text('3 posts · 91 views'), findsOneWidget);
      await tester.tap(find.text(_topic.title));
      await tester.scrollUntilVisible(
        find.text('Load more assignments'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Load more assignments'));

      expect(presentation.openedTopics, [_topic]);
      expect(presentation.loadMoreTopicCalls, 1);

      presentation.show(
        _state(
          feed: const TopicFeed(
            topicIds: [42],
            loaded: true,
            loadingMore: true,
          ),
          topics: const [_topic],
        ),
      );
      await tester.pump();

      final loadMore = tester.widget<DButton>(find.byType(DButton));
      expect(loadMore.loading, isTrue);
      expect(loadMore.onPressed, isNull);
    });

    testWidgets('disposes presentations when the route changes and unmounts', (
      tester,
    ) async {
      final presentations = <_FakeAssignedGroupPresentation>[];
      AssignedGroupPresentation factory(
        String siteUrl,
        String groupName,
        String? subsection,
      ) {
        final presentation = _FakeAssignedGroupPresentation(
          _state(groupName: groupName, feed: const TopicFeed(loaded: true)),
        );
        presentations.add(presentation);
        return presentation;
      }

      await _pumpFactoryView(tester, factory, groupName: 'support');
      await _pumpFactoryView(tester, factory, groupName: 'engineering');

      expect(presentations, hasLength(2));
      expect(presentations.first.disposeCalls, 1);
      expect(presentations.first.loads, [false]);
      expect(presentations.last.loads, [false]);

      await tester.pumpWidget(const SizedBox.shrink());

      expect(presentations.last.disposeCalls, 1);
    });
  });
}

AssignedGroupPresentationState _state({
  String groupName = 'support',
  AssignedGroupFilter filter = const AssignedGroupFilter.everyone(),
  AssignedGroupTopicQuery query = const AssignedGroupTopicQuery(),
  AssignedGroupMembersState members = const AssignedGroupMembersState(),
  TopicFeed feed = const TopicFeed(),
  List<Topic> topics = const [],
}) => AssignedGroupPresentationState(
  groupName: groupName,
  filter: filter,
  query: query,
  members: members,
  feed: feed,
  topics: topics,
);

Future<void> _pumpView(
  WidgetTester tester,
  _FakeAssignedGroupPresentation presentation,
) => _pumpFactoryView(tester, (_, _, _) => presentation);

Future<void> _pumpFactoryView(
  WidgetTester tester,
  AssignedGroupPresentationFactory factory, {
  String groupName = 'support',
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: AssignedGroupView(
          siteUrl: _siteUrl,
          groupName: groupName,
          subsection: 'everyone',
          presentationFactory: factory,
        ),
      ),
    ),
  );
  await tester.pump();
}

final class _FakeAssignedGroupPresentation extends ChangeNotifier
    implements AssignedGroupPresentation {
  _FakeAssignedGroupPresentation(this._state);

  AssignedGroupPresentationState _state;
  final List<bool> loads = [];
  final List<AssignedGroupFilter> selectedFilters = [];
  final List<AssignedGroupTopicQuery> queries = [];
  final List<String> memberSearches = [];
  final List<Topic> openedTopics = [];
  int loadMoreMemberCalls = 0;
  int loadMoreTopicCalls = 0;
  int disposeCalls = 0;

  @override
  AssignedGroupPresentationState get state => _state;

  void show(AssignedGroupPresentationState state) {
    _state = state;
    notifyListeners();
  }

  @override
  Future<void> load({bool refresh = false}) async {
    loads.add(refresh);
  }

  @override
  void selectFilter(AssignedGroupFilter filter) {
    selectedFilters.add(filter);
  }

  @override
  void replaceQuery(AssignedGroupTopicQuery query) {
    queries.add(query);
  }

  @override
  void searchMembers(String value) {
    memberSearches.add(value);
  }

  @override
  void loadMoreMembers() {
    loadMoreMemberCalls += 1;
  }

  @override
  void loadMoreTopics() {
    loadMoreTopicCalls += 1;
  }

  @override
  void openTopic(Topic topic) {
    openedTopics.add(topic);
  }

  @override
  void dispose() {
    disposeCalls += 1;
    super.dispose();
  }
}

final class _RecordingAssignedGroupApi implements AssignedGroupApi {
  final List<({String search, int offset})> memberCalls = [];
  final List<({AssignedGroupFilter filter, AssignedGroupTopicQuery query})>
  topicCalls = [];
  final List<String> pageCalls = [];

  @override
  Future<AssignedGroupMembersPage> members({
    required String siteUrl,
    required String apiKey,
    required String groupName,
    String search = '',
    int offset = 0,
    int limit = AssignedGroupApiClient.memberPageSize,
    String? clientId,
  }) async {
    memberCalls.add((search: search, offset: offset));
    return AssignedGroupMembersPage(
      members: const [
        AssignedGroupMember(id: 7, username: 'Sam', usernameLower: 'sam'),
      ],
      assignmentCount: 8,
      groupAssignmentCount: 2,
      offset: offset,
      limit: limit,
      hasMore: offset == 0,
    );
  }

  @override
  Future<TopicList> topics({
    required String siteUrl,
    required String apiKey,
    required String groupName,
    required AssignedGroupFilter filter,
    AssignedGroupTopicQuery query = const AssignedGroupTopicQuery(),
    String? clientId,
  }) async {
    topicCalls.add((filter: filter, query: query));
    return const TopicList(
      topics: [_topic],
      moreTopicsUrl: '/assignments?page=2',
    );
  }

  @override
  Future<TopicList> topicPage({
    required String siteUrl,
    required String apiKey,
    required String path,
    String? clientId,
  }) async {
    pageCalls.add(path);
    return const TopicList(topics: []);
  }
}
