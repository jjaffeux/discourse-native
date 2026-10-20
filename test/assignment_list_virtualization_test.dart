import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:discourse_native/src/plugins/assign/assignment_sheet.dart';
import 'package:discourse_native/src/plugins/assign/assignment_write_result.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() => assignmentListVirtualizationTests();

void assignmentListVirtualizationTests() {
  for (final drawer in [true, false]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '200 assignees stay lazy and reachable in ${drawer ? 'drawer' : 'dialog'} at text scale $scale',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          AssignmentAssignee? saved;
          final suggestions = AssignmentSuggestions(
            assignAllowedForGroups: [
              for (var index = 0; index < 200; index++) 'team-$index',
            ],
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light.copyWith(
                platform: drawer ? TargetPlatform.iOS : TargetPlatform.macOS,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => DButton(
                    label: const Text('Open assignments'),
                    onPressed: () async {
                      Widget editor(VoidCallback close) => AssignmentEditor(
                        drawer: drawer,
                        loadSuggestions: () async => suggestions,
                        searchAssignees: (_, _) async => const [],
                        save: (assignee, {note, status}) async {
                          saved = assignee;
                          return const AssignmentWriteResult.applied();
                        },
                        onComplete: close,
                        onCancel: close,
                      );
                      if (drawer) {
                        await showDDrawer<void>(
                          context: context,
                          requestInitialFocus: false,
                          builder: (_, controller) => editor(controller.close),
                        );
                      } else {
                        await showDDialog<void>(
                          context: context,
                          builder: (_, controller) => editor(controller.close),
                        );
                      }
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open assignments'));
          await tester.pumpAndSettle();
          final rows = find.byType(
            DRadioGroupItem<String>,
            skipOffstage: false,
          );
          final mounted = rows.evaluate().length;
          debugPrint(
            'LAZY_RADIO assignment drawer=$drawer scale=$scale mounted=$mounted total=200',
          );
          expect(mounted, lessThan(20));
          _radio(tester, 0).focusNode.requestFocus();
          await tester.pump();
          for (var index = 0; index < 199; index++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await tester.pumpAndSettle();
          }
          expect(_selected(tester), 'group:team-199');
          expect(_radio(tester, 199).focusNode.hasFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          expect(_selected(tester), 'group:team-0');
          final scrollable = find
              .descendant(
                of: find.byType(DRadioGroup<String>),
                matching: find.byType(Scrollable),
              )
              .first;
          final position = tester.state<ScrollableState>(scrollable).position;
          position.jumpTo(position.maxScrollExtent);
          await tester.pumpAndSettle();
          expect(_radio(tester, 0).focusNode.hasFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          expect(_selected(tester), 'group:team-1');
          final last = find.byKey(
            const Key('assignment-assignee-group:team-199'),
          );
          await tester.scrollUntilVisible(
            last,
            350,
            scrollable: scrollable,
            maxScrolls: 180,
          );
          await tester.tap(last);
          await tester.pumpAndSettle();
          expect(_selected(tester), 'group:team-199');
          final save = find.byKey(const Key('assignment-save'));
          await tester.ensureVisible(save);
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(saved?.identifier, 'team-199');
          expect(find.byType(AssignmentEditor), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

String? _selected(WidgetTester tester) => tester
    .widget<DRadioGroup<String>>(find.byType(DRadioGroup<String>))
    .groupValue;

RawRadio<String> _radio(WidgetTester tester, int index) =>
    tester.widget<RawRadio<String>>(
      find.descendant(
        of: find.byKey(
          Key('assignment-assignee-group:team-$index'),
          skipOffstage: false,
        ),
        matching: find.byType(RawRadio<String>, skipOffstage: false),
        skipOffstage: false,
      ),
    );
