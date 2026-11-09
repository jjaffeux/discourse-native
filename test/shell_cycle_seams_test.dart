import 'package:discourse_native/src/shell/composer/editor_scope.dart';
import 'package:discourse_native/src/shell/composer/presentation_scope.dart';
import 'package:discourse_native/src/shell/desktop_panels_layout.dart';
import 'package:discourse_native/src/shell/user_card_target.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _RecordingPresentation implements ComposerPresentationView {
  var redocks = 0;

  @override
  final panelsLayout = null;
  @override
  final contentKey = GlobalKey();
  @override
  final dockKey = GlobalKey();
  @override
  final ChangeNotifier layoutChanges = ChangeNotifier();
  @override
  var hasVisibleComposer = false;

  @override
  void redockForNavigation() => redocks++;
}

void main() {
  testWidgets(
    'a named user opens through the installed opener, with no shell',
    (tester) async {
      final opened = <(String, String?)>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: UserCardOpenerScope(
              open: ({required context, required username, siteUrl}) async =>
                  opened.add((username, siteUrl)),
              child: const UserCardTarget(
                username: 'sam',
                siteUrl: 'https://meta.example',
                child: Text('sam'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('sam'));
      await tester.pump();

      expect(opened, [('sam', 'https://meta.example')]);
    },
  );

  testWidgets('composer presentation answers from the view it is given', (
    tester,
  ) async {
    final view = _RecordingPresentation()..hasVisibleComposer = true;
    late BuildContext reader;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: ComposerPresentationScope(
          view: view,
          hasMobileSheet: true,
          child: Builder(
            builder: (context) {
              reader = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(ComposerPresentationScope.hasVisibleComposerOf(reader), isTrue);
    expect(ComposerPresentationScope.hasMobileSheetOf(reader), isTrue);
    expect(ComposerPresentationScope.dockKeyOf(reader), view.dockKey);
    ComposerPresentationScope.redockForNavigation(reader);
    expect(view.redocks, 1);
    addTearDown(view.layoutChanges.dispose);
  });

  testWidgets('a component drawn with no composer editor is a wiring error', (
    tester,
  ) async {
    late BuildContext reader;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          reader = context;
          return const SizedBox();
        },
      ),
    );

    expect(ComposerEditorScope.maybeOf(reader), isNull);
    expect(() => ComposerEditorScope.of(reader), throwsStateError);
  });

  test('the panel layout runs its toggle only while the panels enable it', () {
    final layout = DesktopPanelsLayout();
    addTearDown(layout.dispose);
    var toggles = 0;
    layout.toggle = () => toggles++;

    layout.toggleSplit();
    expect(toggles, 0);

    layout.present(visible: true, enabled: true);
    layout.toggleSplit();
    expect(layout.splitVisible, isTrue);
    expect(toggles, 1);
  });

  testWidgets('with no opener a profile link stays an ordinary link', (
    tester,
  ) async {
    late BuildContext reader;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          reader = context;
          return const SizedBox();
        },
      ),
    );

    expect(showUserCardForUrl(reader, 'https://meta.example/u/sam'), isFalse);
  });
}
