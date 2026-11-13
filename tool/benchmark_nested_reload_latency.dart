import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_controller.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_data.dart';

Future<void> main() async {
  final samples = <int>[];
  for (var run = 0; run < 7; run++) {
    final loader = _Loader();
    final controller = NestedRepliesController(loader: loader);
    await controller.open();
    await controller.loadChildren(2, depth: 1);
    await controller.loadChildren(3, depth: 1);
    await controller.loadChildren(4, depth: 1);
    controller.setCollapsed(4, true);
    loader.requests.clear();
    final watch = Stopwatch()..start();
    await controller.reload();
    watch.stop();
    if (controller.error != null ||
        controller.restoringPages ||
        !controller.isCollapsed(4) ||
        loader.requests.length != 4 ||
        !loader.requests.toSet().containsAll(['roots', '2', '3', '4'])) {
      throw StateError('Expanded reply branches did not restore');
    }
    for (var parent = 2; parent <= 4; parent++) {
      if (controller.childrenFor(parent).single.postNumber != parent + 10) {
        throw StateError('Wrong reply under post $parent');
      }
    }
    controller.dispose();
    if (run >= 2) samples.add(watch.elapsedMicroseconds);
  }
  samples.sort();
  stdout.writeln(jsonEncode({'reload_expanded_nested_replies': samples[2]}));
  exit(0);
}

NestedReplyNode _node(int number, {int? parent}) => NestedReplyNode(
  postId: number + 100,
  postNumber: number,
  data: NestedPostData(replyToPostNumber: parent),
);

NestedPostPayload _payload(NestedReplyNode node) => NestedPostPayload(
  post: Post(
    id: node.postId,
    postNumber: node.postNumber,
    username: 'reader',
    cooked: '<p>Reply</p>',
  ),
  data: node.data,
);

class _Loader implements NestedRepliesLoader {
  final requests = <String>[];
  static const _delay = Duration(milliseconds: 30);
  @override
  bool get isCurrent => true;
  @override
  Future<NestedPageReceipt<NestedRootPage>?> roots({
    required NestedRepliesSort sort,
    required int page,
    required bool trackVisit,
  }) async {
    requests.add('roots');
    await Future<void>.delayed(_delay);
    final roots = [_node(2), _node(3), _node(4)];
    return NestedPageReceipt(
      value: NestedRootPage(
        roots: roots,
        posts: roots.map(_payload),
        page: page,
        hasMore: false,
        effectiveSort: sort,
      ),
      acceptedPostIds: roots.map((row) => row.postId),
    );
  }

  @override
  Future<NestedPageReceipt<NestedContextPage>?> context({
    required NestedRepliesSort sort,
    required int postNumber,
    required int? contextDepth,
    required bool trackVisit,
  }) => throw StateError('Unexpected context request');

  @override
  Future<NestedPageReceipt<NestedChildrenPage>?> children({
    required NestedRepliesSort sort,
    required int parentPostNumber,
    required int depth,
    required int page,
  }) async {
    requests.add('$parentPostNumber');
    await Future<void>.delayed(_delay);
    final child = _node(parentPostNumber + 10, parent: parentPostNumber);
    return NestedPageReceipt(
      value: NestedChildrenPage(
        children: [child],
        posts: [_payload(child)],
        page: page,
        hasMore: false,
      ),
      acceptedPostIds: [child.postId],
    );
  }
}
