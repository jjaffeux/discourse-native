import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/plugin_data.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:discourse_native/src/plugins/assign/assignment_sheet.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _renderDir = 'ASSIGNMENT_RENDER_DIR';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    if (Platform.environment[_renderDir] == null) return;
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in fonts.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  for (final (name, width, dark) in [
    ('phone-light', 390.0, false),
    ('phone-dark', 390.0, true),
    ('desktop-light', 900.0, false),
  ]) {
    testWidgets('the topic is assigned as first-post news and a post in its '
        'note box on $name', (tester) async {
      await _pumpTopic(tester, width: width, dark: dark);
      await _capture(tester, 'assigned-$name');

      final news = find.byKey(const Key('assign-topic-news'));
      final line = find.descendant(
        of: news,
        matching: find.text('Topic assigned to Sam'),
      );
      expect(line, findsOneWidget);
      final tokens = DTokens.of(tester.element(line));
      final style = DefaultTextStyle.of(tester.element(line)).style;
      expect(style.fontSize, 13);
      expect(style.color, DAlert.postNoticeColorOf(tester.element(line)));
      // The mark is the assignee's face in the news line's 30-point room.
      final face = find.descendant(
        of: news,
        matching: find.byType(AssignmentAssigneeAvatar),
      );
      expect(tester.getSize(face), const Size.square(30));
      expect(
        find.descendant(
          of: news,
          matching: find.byTooltip('Change assignment'),
        ),
        findsOneWidget,
      );
      // The topic's news is on the first post alone.
      expect(find.byKey(const Key('assign-post-2-assignment')), findsOneWidget);
      expect(find.text('Post #2 assigned to support'), findsOneWidget);

      // The note box: the quiet fill, after the body and before the post's
      // controls, a 36 face and the group's name as Discourse names it.
      final note = find.byKey(const Key('assign-post-2-assignment'));
      final box = find.descendant(of: note, matching: find.byType(DItem));
      final body = find.text('Support will pick this up.', findRichText: true);
      expect(
        tester.getTopLeft(box).dy,
        greaterThan(tester.getBottomLeft(body).dy),
      );
      expect(tester.getTopLeft(box).dx, tester.getTopLeft(body).dx - 8);
      expect(
        tester.getSize(
          find.descendant(
            of: box,
            matching: find.byType(AssignmentAssigneeAvatar),
          ),
        ),
        const Size.square(36),
      );
      expect(
        find.descendant(of: note, matching: find.text('support')),
        findsOneWidget,
      );
      expect(
        tester.widget<DItem>(box).variant,
        DItemVariant.note,
        reason: 'the ink at 6% of ${tokens.foreground}',
      );
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pumpTopic(
  WidgetTester tester, {
  required double width,
  required bool dark,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1400);
  addTearDown(tester.view.reset);
  const user = DiscourseUser(id: 9, username: 'moderator', staff: true);
  final created = DateTime(2026, 11, 10);
  PluginData assignments({Assignment? direct, Map<int, Assignment>? posts}) =>
      PluginData.none.withValue(
        assignmentsDataKey,
        Assignments(
          canAssign: true,
          direct: direct,
          postAssignments: posts ?? const {},
        ),
      );
  const sam = Assignment(
    assignee: AssignmentUser(username: 'sam', name: 'Sam'),
  );
  const support = Assignment(
    assignee: AssignmentGroup(name: 'support'),
    postId: 2,
    postNumber: 2,
  );
  final posts = [
    Post(
      id: 1,
      postNumber: 1,
      createdAt: created,
      username: 'opener',
      cooked: '<p>The sign-in page times out on slow links.</p>',
      plugins: assignments(),
    ),
    Post(
      id: 2,
      postNumber: 2,
      createdAt: created,
      username: 'reader',
      cooked: '<p>Support will pick this up.</p>',
      plugins: assignments(direct: support),
    ),
    Post(
      id: 3,
      postNumber: 3,
      createdAt: created,
      username: 'staffer',
      cooked: '<p>Thanks, both.</p>',
      plugins: assignments(),
    ),
  ];
  final controller = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: user),
    ]),
    api: FakeDiscourseApi(
      user: user,
      topics: {
        7: topicPayload(
          id: 7,
          title: 'Sign-in times out',
          posts: posts,
          plugins: assignments(direct: sam, posts: {2: support}),
        ),
      },
    ),
    authenticator: FakeAuthenticator()..keys['https://meta.example'] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(controller.dispose);
  await controller.load();
  controller.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'sign-in', title: 'Sign-in times out'),
  );
  await controller.loadTopic(7, 'sign-in');
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme:
            AppTheme.forBrightness(
              dark ? Brightness.dark : Brightness.light,
              fontFamily: 'Lato',
              readingFontFamily: 'Lato',
            ).copyWith(
              platform: width > 600 ? TargetPlatform.macOS : TargetPlatform.iOS,
            ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: DToaster(child: child!),
        ),
        home: const Scaffold(body: TopicView()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final path = Platform.environment[_renderDir];
  if (path == null) return;
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final builder = ui.SceneBuilder();
    view.debugLayer!.addToScene(builder);
    final scene = builder.build();
    final image = await scene.toImage(
      view.size.width.round(),
      view.size.height.round(),
    );
    scene.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(path).create(recursive: true);
    await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
