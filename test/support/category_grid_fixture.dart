import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/categories_page.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import 'fakes.dart';

/// Public Meta root categories captured on 2026-09-18, without user data.
List<TopicCategory> categoryGridFixture({int copies = 1}) {
  final path =
      Platform.environment['CATEGORY_FIXTURE_FILE'] ??
      'test/fixtures/categories/meta.json';
  const embedded = String.fromEnvironment('CATEGORY_FIXTURE_BASE64');
  final data =
      (jsonDecode(
                embedded.isEmpty
                    ? File(path).readAsStringSync()
                    : utf8.decode(base64Decode(embedded)),
              )
              as List)
          .cast<Map<String, dynamic>>();
  return [
    for (var copy = 0; copy < copies; copy++)
      for (final item in data)
        TopicCategory.fromJson({
          ...item,
          'id': (item['id'] as int) + copy * 10000,
        }),
  ];
}

Future<ShellController> categoryGridController(
  List<TopicCategory> categories,
) async {
  final site = instance('meta.discourse.org', title: 'Discourse Meta');
  final controller = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      categoryList: categories,
    ),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  await controller.load();
  await controller.loadCategories(site.url);
  while (!controller.categoryFeedFor(site.url).loaded) {
    await Future<void>.delayed(Duration.zero);
  }
  return controller;
}

Widget categoryGridHost(
  ShellController controller,
  double width, {
  Key? pageKey,
}) {
  const siteUrl = 'https://meta.discourse.org';
  return ContentSettingsScope(
    controller: controller.appSettings,
    child: ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: CategoriesPage(
                key: pageKey,
                siteUrl: siteUrl,
                feed: controller.categoryFeedFor(siteUrl),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
