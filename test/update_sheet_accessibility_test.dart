import 'dart:async';

import 'package:discourse_native/src/data/updater.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/update_sheet.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _release = UpdateRelease(version: '1.4.0', channel: UpdateChannel.stable);

void main() {
  testWidgets('keyboard check progress and success are named and announced', (
    tester,
  ) async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final updater = FakeUpdater(isSupported: true, gate: gate);
    final controller = await _controller(updater);
    addTearDown(controller.dispose);

    final semantics = tester.ensureSemantics();
    try {
      await _openSheet(tester, controller);

      final check = find.widgetWithText(FilledButton, 'Check for updates');
      final focusChild = find
          .descendant(of: check, matching: find.byType(MouseRegion))
          .first;
      final focus = Focus.of(tester.element(focusChild));
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(updater.checkCount, 1);
      final checking = find.bySemanticsLabel('Checking for updates');
      expect(checking, findsOneWidget);
      expect(
        tester.getSemantics(checking),
        isSemantics(
          label: 'Checking for updates',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          isLiveRegion: true,
        ),
      );

      gate.complete();
      await tester.pumpAndSettle();

      final success = find.bySemanticsLabel("You're up to date.");
      expect(success, findsOneWidget);
      expect(
        tester.getSemantics(success),
        isSemantics(label: "You're up to date.", isLiveRegion: true),
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('download progress exposes its exact accessible value', (
    tester,
  ) async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final updater = FakeUpdater(
      isSupported: true,
      releases: const {UpdateChannel.stable: _release},
      progressSteps: const [0.25],
      downloadGate: gate,
    );
    final controller = await _controller(updater, findRelease: true);
    addTearDown(controller.dispose);

    final semantics = tester.ensureSemantics();
    try {
      await _openSheet(tester, controller);
      await tester.tap(find.text('Download 1.4.0'));
      await tester.pump();

      final progress = find.byKey(const ValueKey('update-download-progress'));
      expect(
        tester.getSemantics(progress),
        isSemantics(label: 'Downloading update', value: '25'),
      );
      final announcement = find.bySemanticsLabel('Download in progress.');
      expect(
        tester.getSemantics(announcement),
        isSemantics(label: 'Download in progress.', isLiveRegion: true),
      );

      gate.complete();
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Ready to install.')),
        isSemantics(label: 'Ready to install.', isLiveRegion: true),
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('a download failure is visible, announced, and retryable', (
    tester,
  ) async {
    const failure = UpdateException(UpdateFailure.untrusted);
    final updater = FakeUpdater(
      isSupported: true,
      releases: const {UpdateChannel.stable: _release},
      downloadFailure: failure,
    );
    final controller = await _controller(updater, findRelease: true);
    addTearDown(controller.dispose);

    final semantics = tester.ensureSemantics();
    try {
      await _openSheet(tester, controller);
      await tester.tap(find.text('Download 1.4.0'));
      await tester.pumpAndSettle();

      final error = find.bySemanticsLabel(failure.message);
      expect(error, findsOneWidget);
      expect(
        tester.getSemantics(error),
        isSemantics(label: failure.message, isLiveRegion: true),
      );
      expect(find.text(failure.message), findsOneWidget);
      expect(find.text('Download 1.4.0'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('an install failure is visible, announced, and retryable', (
    tester,
  ) async {
    const failure = UpdateException(UpdateFailure.install);
    final updater = FakeUpdater(
      isSupported: true,
      releases: const {UpdateChannel.stable: _release},
      installFailure: failure,
    );
    final controller = await _controller(updater, findRelease: true);
    addTearDown(controller.dispose);

    final semantics = tester.ensureSemantics();
    try {
      await _openSheet(tester, controller);
      await tester.tap(find.text('Download 1.4.0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restart and install'));
      await tester.pumpAndSettle();

      final error = find.bySemanticsLabel(failure.message);
      expect(error, findsOneWidget);
      expect(
        tester.getSemantics(error),
        isSemantics(label: failure.message, isLiveRegion: true),
      );
      expect(find.text(failure.message), findsOneWidget);
      expect(find.text('Restart and install'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
}

Future<ShellController> _controller(
  FakeUpdater updater, {
  bool findRelease = false,
}) async {
  final controller = ShellController(
    instanceStore: FakeInstanceStore(),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: updater,
    updateStore: FakeUpdateStore(lastChecked: DateTime.now()),
  );
  await controller.updates.load();
  if (findRelease) await controller.updates.check();
  return controller;
}

Future<void> _openSheet(WidgetTester tester, ShellController controller) async {
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => unawaited(showUpdateSheet(context)),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}
