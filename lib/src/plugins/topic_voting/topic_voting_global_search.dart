import 'package:discourse_native/discourse_plugin_sdk.dart';

final class TopicVotingGlobalSearch extends GlobalSearchContribution {
  const TopicVotingGlobalSearch() : super('discourse-topic-voting');
  @override
  List<GlobalSearchFilter> get filters => const [
    GlobalSearchFilter(
      id: "votes",
      label: "Topic votes",
      scope: GlobalSearchScope.forum,
      kind: GlobalSearchFilterKind.number,
      icon: "heart",
      group: "Extensions",
      operators: [GlobalSearchFilterOperator("gte", "at least")],
      token: "min_vote_count",
      placeholder: "5",
      help: "Match the number of votes on a topic.",
      opTokens: {"gte": "min_vote_count"},
    ),
  ];
  @override
  bool available(
    Map<String, dynamic> settings,
    Map<String, dynamic> user,
    bool authenticated,
  ) => settings['topic_voting_enabled'] == true;
  @override
  List<GlobalSearchOrder> orders(GlobalSearchScope scope) =>
      scope == GlobalSearchScope.forum
      ? const [GlobalSearchOrder('votes', 'Most votes')]
      : const [];
}
