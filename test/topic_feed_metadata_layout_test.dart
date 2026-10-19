import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/shared_appearance.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _child = TopicCategory(
  id: 10,
  name: 'Private child',
  color: '3188CC',
  styleType: 'icon',
  icon: 'folder',
  readRestricted: true,
  parentCategoryId: 20,
);
const _parent = TopicCategory(id: 20, name: 'Parent', color: '9760CC');

final class _GatedApi extends FakeDiscourseApi {
  _GatedApi()
    : super(
        feeds: {
          '/latest.json': [
            for (var id = 1; id <= 3; id++)
              Topic(
                id: id,
                title: 'Usable topic $id',
                slug: 'topic-$id',
                categoryId: 10,
                replyCount: 241,
                views: 19342,
                lastPosterUsername: 'sam',
                tags: const [
                  TopicTag(name: 'design'),
                  TopicTag(name: 'mobile'),
                ],
              ),
          ],
        },
      );

  final child = Completer<List<TopicCategory>>();
  final parent = Completer<List<TopicCategory>>();

  @override
  Future<List<TopicCategory>> findCategories({
    required String siteUrl,
    required Iterable<int> ids,
    String? apiKey,
    String? clientId,
  }) {
    categoryIdsRequested.add(ids.toList());
    return ids.contains(10) ? child.future : parent.future;
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('METADATA_CAPTURE_DIRECTORY');
  if (directory.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in fonts.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'discourse_native.appearance': jsonEncode(
        const SharedAppearance(
          font: ForumFont.openSans,
          interfaceFont: ForumFont.openSans,
        ).toJson(),
      ),
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });

  for (final (platform, width, scale) in [
    (TargetPlatform.macOS, 1440.0, 1.0),
    (TargetPlatform.iOS, 390.0, 1.0),
    (TargetPlatform.iOS, 320.0, 2.0),
  ]) {
    testWidgets(
      'rows retain geometry through taxonomy enrichment at $width/$scale',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final api = _GatedApi();
        addTearDown(() {
          if (!api.child.isCompleted) api.child.complete(const []);
          if (!api.parent.isCompleted) api.parent.complete(const []);
        });
        await pumpShell(
          tester,
          Size(width, 900),
          instances: [instance('meta.discourse.org')],
          api: api,
        );
        final shell = ShellScope.read(
          tester.element(find.byType(TopicListView).first),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        final first = find.byKey(const ValueKey('topic-card-1'));
        expect(first, findsOneWidget);
        expect(shell.currentFeed?.topicIds, [1, 2, 3]);

        expect(api.categoryIdsRequested, [
          [10],
        ]);
        final before = tester.getRect(first);
        final activity = tester.getRect(
          find.byKey(const ValueKey('topic-card-activity-1')),
        );
        await _capture(tester, 'pending-$width-$scale');

        api.child.complete(const [_child]);
        await tester.pumpAndSettle();
        expect(tester.getRect(first), before);
        expect(
          tester
              .getRect(find.byKey(const ValueKey('topic-card-activity-1')))
              .top,
          activity.top,
        );
        expect(
          find.byKey(const ValueKey(('topic-row-category', 10))),
          findsWidgets,
        );
        expect(api.categoryIdsRequested, [
          [10],
          [20],
        ]);
        api.parent.complete(const [_parent]);
        await tester.pumpAndSettle();
        expect(tester.getRect(first), before);
        expect(
          tester
              .getRect(find.byKey(const ValueKey('topic-card-activity-1')))
              .top,
          activity.top,
        );
        expect(
          shell.topicCategoryPathLabel(_child, siteUrl: _site),
          'Parent › Private child',
        );
        expect(find.bySemanticsLabel('Category: Private child'), findsWidgets);
        expect(tester.takeException(), isNull);
        await _capture(tester, 'enriched-$width-$scale');
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
}
