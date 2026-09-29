import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';

final class TopicVotingGlobalSearch extends GlobalSearchContribution {
  const TopicVotingGlobalSearch() : super('discourse-topic-voting');
  @override
  List<GlobalSearchFilter> get filters => [
    GlobalSearchFilter(
      id: "votes",
      label: appL10n.topicVotes,
      scope: GlobalSearchScope.forum,
      kind: GlobalSearchFilterKind.number,
      icon: "heart",
      group: appL10n.extensions,
      operators: [GlobalSearchFilterOperator("gte", appL10n.atLeast)],
      token: "min_vote_count",
      placeholder: "5",
      help: appL10n.matchTheNumberOfVotesOnATopic,
      opTokens: const {"gte": "min_vote_count"},
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
      ? [GlobalSearchOrder('votes', appL10n.mostVotes)]
      : const [];
}
