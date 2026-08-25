import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/hover_action_toolbar.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';

void main() {
  testWidgets('post action buttons have accessible keyboard targets', (
    tester,
  ) async {
    final api = FakeDiscourseApi();
    final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
    final controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.example').copyWith(
          user: const DiscourseUser(username: 'reader', name: 'Reader'),
        ),
      ]),
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    await controller.load();
    addTearDown(controller.dispose);

    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 240,
                  height: 100,
                  child: PostActions(
                    siteUrl: _siteUrl,
                    post: Post(
                      id: 1,
                      postNumber: 1,
                      username: 'author',
                      cooked: '<p>Post body</p>',
                      canLike: true,
                    ),
                    child: ColoredBox(
                      color: Colors.transparent,
                      child: Center(child: Text('Post body')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      await pointer.moveTo(tester.getCenter(find.text('Post body')));
      await tester.pump();

      final action = find.byTooltip('Like this post');
      expect(action, findsOneWidget);
      expect(tester.getSize(action), HoverActionButton.size);
      final menu = find
          .ancestor(
            of: action,
            matching: find.byWidgetPredicate(
              (widget) => widget is Material && widget.elevation == 2,
            ),
          )
          .first;
      expect(tester.getSize(menu).width, HoverActionButton.width);
      expect(
        tester.getRect(menu).right,
        closeTo(tester.getRect(find.byType(PostActions)).right - 8, 0.01),
      );
      expect(
        tester.getSemantics(action),
        isSemantics(
          tooltip: 'Like this post',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );

      final button = find
          .ancestor(of: action, matching: find.byType(IconButton))
          .first;
      final iconButton = tester.widget<IconButton>(button);
      final hoverShape = iconButton.style!.shape!.resolve({
        WidgetState.hovered,
      });
      expect(hoverShape, isA<RoundedRectangleBorder>());
      expect(
        (hoverShape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.zero,
      );
      expect(
        iconButton.style!.overlayColor!.resolve({WidgetState.hovered}),
        Theme.of(tester.element(button)).shell.hover,
      );
      final inkWell = find.descendant(
        of: button,
        matching: find.byType(InkWell),
      );
      expect(inkWell, findsOneWidget);
      final focusChild = find
          .descendant(of: inkWell, matching: find.byType(MouseRegion))
          .first;
      final focus = Focus.of(tester.element(focusChild));
      focus.requestFocus();
      await tester.pumpAndSettle();

      expect(focus.hasPrimaryFocus, isTrue);
      expect(
        tester.getSemantics(action),
        isSemantics(isFocusable: true, isFocused: true),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(api.liked, [1]);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('context menu keys reveal actions and focus the first one', (
    tester,
  ) async {
    final api = FakeDiscourseApi();
    final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
    final controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.example').copyWith(
          user: const DiscourseUser(username: 'reader', name: 'Reader'),
        ),
      ]),
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    await controller.load();
    addTearDown(controller.dispose);

    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 240,
                  height: 100,
                  child: PostActions(
                    siteUrl: _siteUrl,
                    post: const Post(
                      id: 1,
                      postNumber: 1,
                      username: 'author',
                      cooked: '<p>Post body</p>',
                      canLike: true,
                    ),
                    child: TextButton(
                      key: const ValueKey('post-control'),
                      onPressed: () {},
                      child: const Text('Post body'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final postFocus = _focusButton(
        tester,
        find.byKey(const ValueKey('post-control')),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      var action = find.byTooltip('Like this post');
      expect(action, findsOneWidget);
      expect(_buttonFocus(tester, action).hasPrimaryFocus, isTrue);
      expect(
        tester.getSemantics(action),
        isSemantics(isFocusable: true, isFocused: true),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(api.liked, [1]);
      expect(action, findsNothing);

      postFocus.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();

      action = find.byTooltip('Like this post');
      expect(action, findsOneWidget);
      expect(_buttonFocus(tester, action).hasPrimaryFocus, isTrue);
      expect(
        tester.getSemantics(action),
        isSemantics(isFocusable: true, isFocused: true),
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('core hidden actions use one labelled More actions menu', (
    tester,
  ) async {
    final controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.example').copyWith(
          user: const DiscourseUser(username: 'reader', name: 'Reader'),
        ),
      ]),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    await controller.load();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                height: 100,
                child: PostActions(
                  siteUrl: _siteUrl,
                  post: Post(
                    id: 1,
                    postNumber: 1,
                    username: 'author',
                    cooked: '<p>Post body</p>',
                    canLike: true,
                    canEdit: true,
                    canWiki: true,
                    canDelete: true,
                  ),
                  child: Center(child: Text('Post body')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await pointer.moveTo(tester.getCenter(find.text('Post body')));
    await tester.pump();

    expect(find.byTooltip('Like this post'), findsOneWidget);
    expect(find.byTooltip('More actions'), findsOneWidget);
    expect(find.byTooltip('Edit this post'), findsNothing);
    expect(find.byTooltip('Delete this post'), findsNothing);
    expect(
      tester.getSize(find.byType(HoverActionToolbar)),
      const Size(HoverActionButton.width * 2, HoverActionButton.height),
    );

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Edit this post'), findsOneWidget);
    expect(
      find.byTooltip('Allow community members to edit this post'),
      findsOneWidget,
    );
    expect(find.byTooltip('Delete this post'), findsOneWidget);

    final editAction = find
        .ancestor(
          of: find.byTooltip('Edit this post'),
          matching: find.byType(MenuItemButton),
        )
        .first;
    final editButton = tester.widget<MenuItemButton>(editAction);
    final theme = Theme.of(tester.element(editAction));
    expect(
      editButton.style!.backgroundColor!.resolve({WidgetState.hovered}),
      theme.shell.hover,
    );
    expect(
      editButton.style!.backgroundColor!.resolve({WidgetState.focused}),
      theme.shell.hover,
    );
    expect(editButton.style!.backgroundColor!.resolve({}), Colors.transparent);
  });
}

FocusNode _focusButton(WidgetTester tester, Finder button) {
  final inkWell = find.descendant(of: button, matching: find.byType(InkWell));
  expect(inkWell, findsOneWidget);
  final focusChild = find
      .descendant(of: inkWell, matching: find.byType(MouseRegion))
      .first;
  final focus = Focus.of(tester.element(focusChild));
  focus.requestFocus();
  return focus;
}

FocusNode _buttonFocus(WidgetTester tester, Finder tooltip) {
  final button = tester.widget<IconButton>(
    find.ancestor(of: tooltip, matching: find.byType(IconButton)).first,
  );
  return button.focusNode!;
}
