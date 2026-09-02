import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'bundled_plugins.dart';
import 'fakes.dart';
import 'media_pipeline.dart';

const Size phone = Size(390, 844);
const Size laptop = Size(1000, 800);
const Size desktop = Size(1440, 900);

Finder get activityIndicators => find.byWidgetPredicate(
  (widget) =>
      widget is CircularProgressIndicator ||
      widget is CupertinoActivityIndicator,
  description: 'adaptive activity indicator',
);

Finder minimumHeightDescendants(Finder root, double minimumHeight) =>
    find.descendant(
      of: root,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is ConstrainedBox &&
            widget.constraints.minHeight == minimumHeight,
      ),
    );

Finder minimumHeightAncestors(Finder child, double minimumHeight) =>
    find.ancestor(
      of: child,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is ConstrainedBox &&
            widget.constraints.minHeight == minimumHeight,
      ),
    );

final List<DiscourseInstance> twoSites = List.unmodifiable([
  instance('meta.discourse.org', title: 'Discourse Meta'),
  instance('team.discourse.org', title: 'Discourse Team'),
]);

void replaceEmojiCache(http.Client client) =>
    installTestMediaPipeline(client: client);

Future<void> pumpShell(
  WidgetTester tester,
  Size size, {
  List<DiscourseInstance>? instances,
  FakeDiscourseApi? api,
  FakeInstanceStore? store,
  FakeAuthenticator? authenticator,
  FakeDraftStore? drafts,
  FakeForumTabStore? forumTabs,
  FakeUpdater? updater,
  FakeUpdateStore? updateStore,
  Key? key,
  Future<void> Function()? beforeSettle,
  http.Client? mediaClient,
  PluginManifest? pluginManifest,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // Cooked emoji would otherwise trigger network requests in widget tests.
  replaceEmojiCache(
    mediaClient ?? MockClient((_) async => http.Response('', 404)),
  );

  await tester.pumpWidget(
    DiscourseApp(
      key: key,
      store: store ?? FakeInstanceStore(instances ?? twoSites),
      api: api ?? FakeDiscourseApi(),
      authenticator: authenticator ?? FakeAuthenticator(),
      drafts: drafts ?? FakeDraftStore(),
      forumTabs: forumTabs ?? FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: updater ?? FakeUpdater(),
      updateStore: updateStore ?? FakeUpdateStore(),
      initialRootMode: ShellRootMode.forum,
      pluginManifest: pluginManifest ?? bundledWidgetTestManifest,
    ),
  );
  if (beforeSettle != null) {
    await tester.pump();
    await beforeSettle();
  }
  await tester.pumpAndSettle();
}

/// HtmlWidget renders into a bare RichText, which find.text and
/// find.textContaining both ignore.
Finder renderedText(String text) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText().contains(text),
  description: 'rendered text containing "$text"',
);

List<String> watchBrowser(WidgetTester tester) {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final launched = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'launch') {
      launched.add((call.arguments as Map)['url'] as String);
    }
    return true;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return launched;
}

List<String> watchClipboard(WidgetTester tester) {
  final copied = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return copied;
}

final Finder userMenu = find.byWidgetPredicate(
  (widget) =>
      widget.key == UserMenuButton.avatarKey ||
      widget.key == UserMenuButton.signInKey,
  description: 'account menu or sign-in action',
);

Finder sidebarDestination(String label) => find.byElementPredicate((element) {
  final widget = element.widget;
  if (widget is! Text || widget.data != label) return false;

  var inSidebar = false;
  element.visitAncestorElements((ancestor) {
    inSidebar |= ancestor.widget is InstanceSidebar;
    return true;
  });
  return inSidebar;
}, description: 'sidebar destination labelled "$label"');

Finder contentText(String label) => find.byElementPredicate((element) {
  final widget = element.widget;
  if (widget is! Text || widget.data != label) return false;

  var inMainContent = false;
  var inForumTabs = false;
  element.visitAncestorElements((ancestor) {
    inMainContent |= ancestor.widget is MainContent;
    inForumTabs |= ancestor.widget is ForumTabsBar;
    return true;
  });
  return inMainContent && !inForumTabs;
}, description: 'content text labelled "$label"');

Future<TestGesture> hoverPost(
  WidgetTester tester, {
  String body = 'First post body',
}) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(tester.getCenter(renderedText(body)));
  await tester.pumpAndSettle();
  return gesture;
}

Future<void> tapPostAction(WidgetTester tester, String tooltip) async {
  var action = find.byTooltip(tooltip);
  if (action.evaluate().isEmpty) {
    final more = find.byTooltip('More actions');
    expect(more, findsOneWidget);
    await tester.tap(more);
    await tester.pumpAndSettle();
    final label = switch (tooltip) {
      'Share this post' => 'Share',
      'Edit this post' => 'Edit',
      'Delete this post' => 'Delete',
      'Allow community members to edit this post' => 'Make wiki',
      'Return this to ordinary post editing' => 'Remove wiki',
      'Prevent further edits to this post' => 'Lock post',
      'Allow this post to be edited again' => 'Unlock post',
      'Restore this hidden post' => 'Unhide post',
      'Mark this as an official moderator post' => 'Convert to moderator post',
      'Remove the moderator styling from this post' => 'Revert to regular post',
      'Add a staff notice above this post' => 'Add post notice',
      'Change or remove the staff notice' => 'Change post notice',
      'Assign this post to another account' => 'Change owner',
      'Permanently delete this post' => 'Permanently delete',
      'Put this post back' => 'Undelete',
      _ => throw StateError('No visible label for post action: $tooltip'),
    };
    action = find.widgetWithText(MenuItemButton, label);
  }
  expect(action, findsOneWidget);
  await tester.tap(action);
}

/// A 1x1 transparent PNG — the smallest thing `Image.memory` will accept.
final Uint8List emojiPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
