import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

typedef TopicPostListHandle = ({
  ScrollController? controller,
  ListController? listController,
  EdgeInsetsGeometry? padding,
  Key? key,
});

Finder topicPostListFinder() => find.ancestor(
  of: find.descendant(
    of: find.byType(TopicView),
    matching: find.bySubtype<SuperSliverList>(),
  ),
  matching: find.byType(CustomScrollView),
);

TopicPostListHandle topicPostList(WidgetTester tester) {
  final viewport = topicPostListFinder();
  final scroll = tester.widget<CustomScrollView>(viewport);
  final sliver = tester.widget<SuperSliverList>(
    find.descendant(of: viewport, matching: find.bySubtype<SuperSliverList>()),
  );
  final padding = tester.widget<SliverPadding>(
    find.ancestor(
      of: find.descendant(
        of: viewport,
        matching: find.bySubtype<SuperSliverList>(),
      ),
      matching: find.byType(SliverPadding),
    ),
  );
  return (
    controller: scroll.controller,
    listController: sliver.listController,
    padding: padding.padding,
    key: scroll.key,
  );
}
