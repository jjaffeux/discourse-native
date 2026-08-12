import 'dart:async';

import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/shell/add_instance_sheet.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('labels the forum address and submits it with the Go action', (
    tester,
  ) async {
    final store = FakeInstanceStore();
    final api = _GatedLookupApi();
    final controller = _controller(store, api);
    addTearDown(controller.dispose);
    await controller.load();

    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_app(controller));
      await tester.tap(find.text('Add site'));
      await tester.pumpAndSettle();

      final field = find.byType(TextField);
      final editable = find.descendant(
        of: field,
        matching: find.byType(EditableText),
      );
      final textField = tester.widget<TextField>(field);
      expect(textField.decoration?.labelText, 'Forum address');
      expect(textField.decoration?.hintText, 'meta.discourse.org');
      expect(
        tester.getSemantics(editable),
        isSemantics(
          label: 'Forum address\nmeta.discourse.org',
          isTextField: true,
          isFocusable: true,
          isFocused: true,
        ),
      );

      await tester.enterText(field, 'meta.example');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pump();
      await api.started.future;

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      api.lookupGate.complete();
      await tester.pumpAndSettle();

      expect(controller.instances, isEmpty);
      expect(store.saveCount, 0);
    } finally {
      if (!api.lookupGate.isCompleted) api.lookupGate.complete();
      semantics.dispose();
    }
  });

  testWidgets('dismissing the sheet cancels a pending add', (tester) async {
    final store = FakeInstanceStore();
    final api = _GatedLookupApi();
    final controller = _controller(store, api);
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(_app(controller));
    await _startLookup(tester, api);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    api.lookupGate.complete();
    await tester.pumpAndSettle();

    expect(controller.instances, isEmpty);
    expect(store.saveCount, 0);
  });

  testWidgets('a pending lookup cannot mutate a replacement shell', (
    tester,
  ) async {
    final firstStore = FakeInstanceStore();
    final secondStore = FakeInstanceStore();
    final api = _GatedLookupApi();
    final first = _controller(firstStore, api);
    final second = _controller(secondStore, FakeDiscourseApi());
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await Future.wait([first.load(), second.load()]);

    await tester.pumpWidget(_app(first));
    await _startLookup(tester, api);

    await tester.pumpWidget(_app(second));
    api.lookupGate.complete();
    await tester.pumpAndSettle();

    expect(first.instances, isEmpty);
    expect(second.instances, isEmpty);
    expect(firstStore.saveCount, 0);
    expect(secondStore.saveCount, 0);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Connect'))
          .onPressed,
      isNotNull,
    );
  });
}

ShellController _controller(FakeInstanceStore store, FakeDiscourseApi api) =>
    ShellController(
      instanceStore: store,
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );

Widget _app(ShellController controller) => ShellScope(
  controller: controller,
  child: MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Builder(
        builder: (context) => FilledButton(
          onPressed: () => unawaited(showAddInstanceSheet(context)),
          child: const Text('Add site'),
        ),
      ),
    ),
  ),
);

Future<void> _startLookup(WidgetTester tester, _GatedLookupApi api) async {
  await tester.tap(find.text('Add site'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'meta.example');
  await tester.tap(find.text('Connect'));
  await tester.pump();
  await api.started.future;
}

final class _GatedLookupApi extends FakeDiscourseApi {
  final lookupGate = Completer<void>();
  final started = Completer<void>();

  @override
  Future<DiscourseInstance> lookup(String term) async {
    started.complete();
    await lookupGate.future;
    return instance('meta.example');
  }
}
