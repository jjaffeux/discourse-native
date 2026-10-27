import 'dart:async';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bundled_plugins.dart';
import 'fakes.dart';

/// Runs the production phone topic head with an account-free in-memory
/// fixture: a staff reader, a topic two categories deep with five tags, and
/// Assign. Run with `flutter run -d <simulator>` and this file as the target;
/// it opens the topic, opens every tag, draws the head in and opens the
/// actions sheet, printing TOPIC_HEAD_REVIEW and the stage before each wait.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  runApp(_app());
  unawaited(_review());
}

Rect? _rectOf(Key key) {
  Rect? found;
  void visit(Element element) {
    if (found != null) return;
    if (element.widget.key == key) {
      final box = element.findRenderObject();
      if (box is RenderBox && box.hasSize && box.attached) {
        found = box.localToGlobal(Offset.zero) & box.size;
        return;
      }
    }
    element.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return found;
}

var _pointer = 1;

Future<void> _drag(Offset from, Offset by, {int steps = 12}) async {
  final binding = GestureBinding.instance;
  final pointer = _pointer++;
  binding.handlePointerEvent(
    PointerDownEvent(pointer: pointer, position: from),
  );
  for (var i = 1; i <= steps; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    binding.handlePointerEvent(
      PointerMoveEvent(
        pointer: pointer,
        position: from + by * (i / steps),
        delta: by / steps.toDouble(),
      ),
    );
  }
  binding.handlePointerEvent(
    PointerUpEvent(pointer: pointer, position: from + by),
  );
}

Future<void> _tap(Key key) async {
  final rect = _rectOf(key);
  if (rect == null) {
    debugPrint('TOPIC_HEAD_REVIEW missing $key');
    return;
  }
  await _drag(rect.center, Offset.zero, steps: 1);
}

Future<void> _stage(String name, {int seconds = 8}) async {
  debugPrint('TOPIC_HEAD_REVIEW $name');
  await Future<void>.delayed(Duration(seconds: seconds));
}

Future<void> _review() async {
  await Future<void>.delayed(const Duration(seconds: 6));
  await _tap(const ValueKey('topic-card-7'));
  await _stage('expanded');
  await _tap(const ValueKey('topic-header-more-tags'));
  await _stage('all-tags');
  await _drag(const Offset(200, 700), const Offset(0, -500));
  await Future<void>.delayed(const Duration(seconds: 2));
  await _drag(const Offset(200, 500), const Offset(0, 120));
  await _stage('condensed');
  await _tap(const ValueKey('topic-more-actions'));
  await _stage('sheet');
}

const _site = 'https://meta.discourse.org';
const _parent = TopicCategory(
  id: 21,
  name: 'Baking',
  slug: 'baking',
  color: 'E5A33A',
);
const _child = TopicCategory(
  id: 22,
  name: 'Sourdough starters',
  slug: 'sourdough-starters',
  color: '3AB54A',
  parentCategoryId: 21,
);
const _tags = [
  TopicTag(id: 1, name: 'starter'),
  TopicTag(id: 2, name: 'fridge'),
  TopicTag(id: 3, name: 'travel'),
  TopicTag(id: 4, name: 'feeding'),
  TopicTag(id: 5, name: 'hydration'),
];
const _title =
    'Starter maintenance when you bake twice a week and travel most weekends';

Widget _app() {
  const user = DiscourseUser(id: 7, username: 'reader', staff: true);
  return DiscourseApp(
    store: FakeInstanceStore([
      instance(
        'meta.discourse.org',
        title: 'Discourse Meta',
      ).copyWith(user: user),
    ]),
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    notificationOpenUrls: const Stream.empty(),
    pluginManifest: bundledWidgetTestManifest,
    api: FakeDiscourseApi(
      user: user,
      categoryList: const [_parent, _child],
      feeds: const {
        '/latest.json': [
          Topic(
            id: 7,
            title: _title,
            slug: 'starter-maintenance',
            categoryId: 22,
            tags: _tags,
          ),
        ],
      },
      topics: {
        7: topicPayload(
          id: 7,
          title: _title,
          categoryId: 22,
          tags: _tags,
          canCreatePost: true,
          canCloseTopic: true,
          canArchiveTopic: true,
          canDeleteTopic: true,
          canToggleTopicVisibility: true,
          canMovePosts: true,
          stream: [for (var i = 1; i <= 12; i++) 70 + i],
          posts: [
            for (var i = 1; i <= 12; i++)
              Post(
                id: 70 + i,
                postNumber: i,
                username: ['mira', 'solene', 'theo', 'violet'][i % 4],
                cooked:
                    '<p>Mine lives in the fridge and gets fed the night before. '
                    'Works, but the rise is slower than it used to be and I am '
                    'not sure whether that is the flour, the fridge, or me.</p>'
                    '<p>Current routine: feed 1:5:5 on Thursday night, bake '
                    'Saturday morning before I leave.</p>',
              ),
          ],
          plugins: pluginRegistry.readTopic({'can_assign': true}, _site),
        ),
      },
    ),
  );
}
