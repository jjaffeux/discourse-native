import 'package:flutter/material.dart';

import '../models/topic.dart';
import '../models/topic_feed.dart';
import 'shell_scope.dart';
import 'topic_filter_input.dart';
import 'topic_list_view.dart';

class TopicFilterPage extends StatelessWidget {
  const TopicFilterPage({
    super.key,
    required this.siteUrl,
    required this.feed,
    required this.categories,
  });

  final String siteUrl;
  final TopicFeed feed;
  final List<TopicCategory> categories;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.identityOf(context);
    return Column(
      children: [
        TopicFilterInput(
          siteUrl: siteUrl,
          initialQuery: shell.filterQueryFor(siteUrl),
          options: feed.filterOptions,
          categories: categories,
          onSubmitted: shell.submitTopicFilter,
        ),
        Expanded(child: TopicListView(feed: feed)),
      ],
    );
  }
}
