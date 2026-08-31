import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/hover_action_toolbar.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_button.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';

void main() {
  testWidgets('hovered post actions use exact toolbar geometry and styling', (
    tester,
  ) async {
    final action = (await _pumpHoveredPostAction(tester)).action;

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
    final button = find
        .ancestor(of: action, matching: find.byType(DButton))
        .first;
    final filledButton = tester.widget<FilledButton>(
      find.descendant(of: button, matching: find.byType(FilledButton)),
    );
    final hoverShape = filledButton.style!.shape!.resolve({
      WidgetState.hovered,
    });
    expect(hoverShape, isA<RoundedRectangleBorder>());
    final theme = Theme.of(tester.element(button));
    expect(
      (hoverShape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(theme.discourseButtons.borderRadius),
    );
    expect(
      filledButton.style!.backgroundColor!.resolve({WidgetState.hovered}),
      theme.shell.hover,
    );
    expect(
      filledButton.style!.fixedSize!.resolve({}),
      const Size.square(DButton.minimumDimension),
    );
  });

  testWidgets('post actions ignore non-finite transformed anchors', (
    tester,
  ) async {
    final transform = ValueNotifier(Matrix4.identity());
    addTearDown(transform.dispose);
    await _pumpHoveredPostAction(tester, transform: transform);

    final postRegion = tester.widget<MouseRegion>(
      find
          .ancestor(
            of: find.text('Post body'),
            matching: find.byWidgetPredicate(
              (widget) => widget is MouseRegion && widget.onHover != null,
            ),
          )
          .first,
    );

    transform.value = Matrix4.zero();
    await tester.pump();
    postRegion.onHover!(const PointerHoverEvent());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(HoverActionToolbar), findsNothing);
  });

  testWidgets('post actions expose enabled button semantics', (tester) async {
    await _withSemantics(tester, () async {
      final action = (await _pumpHoveredPostAction(tester)).action;

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
    });
  });

  testWidgets('focused post actions activate with Enter', (tester) async {
    await _withSemantics(tester, () async {
      final (:action, :api) = await _pumpHoveredPostAction(tester);
      final focus = _buttonFocus(tester, action)..requestFocus();
      await tester.pumpAndSettle();

      expect(focus.hasPrimaryFocus, isTrue);
      expect(
        tester.getSemantics(action),
        isSemantics(isFocusable: true, isFocused: true),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(api.liked, [1]);
    });
  });

  testWidgets('Shift+F10 reveals and focuses the first post action', (
    tester,
  ) async {
    await _withSemantics(tester, () async {
      await _pumpFocusedPostActions(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      _expectFocusedLikeAction(tester);
    });
  });

  testWidgets('the Context Menu key focuses the first post action', (
    tester,
  ) async {
    await _withSemantics(tester, () async {
      await _pumpFocusedPostActions(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();

      _expectFocusedLikeAction(tester);
    });
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

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Make wiki'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.byTooltip('Edit this post'), findsNothing);
    expect(
      find.byTooltip('Allow community members to edit this post'),
      findsNothing,
    );
    expect(find.byTooltip('Delete this post'), findsNothing);

    final editAction = find
        .ancestor(of: find.text('Edit'), matching: find.byType(MenuItemButton))
        .first;
    final editButton = tester.widget<MenuItemButton>(editAction);
    final theme = Theme.of(tester.element(editAction));
    expect(editButton.style?.backgroundColor, isNull);
    expect(
      theme.menuButtonTheme.style!.backgroundColor!.resolve({
        WidgetState.hovered,
      }),
      theme.hoverColor,
    );
  });
}

Future<void> _withSemantics(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final semantics = tester.ensureSemantics();
  try {
    await body();
  } finally {
    semantics.dispose();
  }
}

Future<({Finder action, FakeDiscourseApi api})> _pumpHoveredPostAction(
  WidgetTester tester, {
  ValueNotifier<Matrix4>? transform,
}) async {
  final api = FakeDiscourseApi();
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(
        user: const DiscourseUser(username: 'reader', name: 'Reader'),
      ),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await controller.load();
  addTearDown(controller.dispose);

  const post = SizedBox(
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
  );

  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Center(
            child: transform == null
                ? post
                : ValueListenableBuilder<Matrix4>(
                    valueListenable: transform,
                    builder: (context, value, child) =>
                        Transform(transform: value, child: child),
                    child: post,
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
  return (action: action, api: api);
}

Future<void> _pumpFocusedPostActions(WidgetTester tester) async {
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

  _focusButton(tester, find.byKey(const ValueKey('post-control')));
  await tester.pumpAndSettle();
}

void _expectFocusedLikeAction(WidgetTester tester) {
  final action = find.byTooltip('Like this post');
  expect(action, findsOneWidget);
  expect(_buttonFocus(tester, action).hasPrimaryFocus, isTrue);
  expect(
    tester.getSemantics(action),
    isSemantics(isFocusable: true, isFocused: true),
  );
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
  final button = tester.widget<DButton>(
    find.ancestor(of: tooltip, matching: find.byType(DButton)).first,
  );
  return button.focusNode!;
}
