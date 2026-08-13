import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/shell/add_instance_sheet.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets(
    'debounces a valid address and restarts after another keystroke',
    (tester) async {
      final store = FakeInstanceStore();
      final api = FakeDiscourseApi(
        results: {
          'meta.discourse.org': instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ),
        },
      );
      final controller = _controller(store, api);
      addTearDown(controller.dispose);
      await controller.load();

      await tester.pumpWidget(_app(controller));
      await _openSheet(tester);

      await tester.enterText(find.byType(TextField), 'meta.discourse');
      await tester.pump(
        addInstanceLookupDebounce - const Duration(milliseconds: 1),
      );
      expect(api.lookups, isEmpty);

      await tester.enterText(find.byType(TextField), 'meta.discourse.org');
      await tester.pump(
        addInstanceLookupDebounce - const Duration(milliseconds: 1),
      );
      expect(api.lookups, isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();

      expect(api.lookups, ['meta.discourse.org']);
      final icon = tester.widget<DIcon>(
        find.byKey(const ValueKey('add-site-valid')),
      );
      expect(icon.icon, DIcons.check);
      expect(icon.color, AppTheme.light.discourse.success);
    },
  );

  for (final failure in [
    SiteLookupFailure.unreachable,
    SiteLookupFailure.notDiscourse,
  ]) {
    testWidgets('shows an error icon when lookup reports ${failure.name}', (
      tester,
    ) async {
      final store = FakeInstanceStore();
      final api = FakeDiscourseApi(failure: failure);
      final controller = _controller(store, api);
      addTearDown(controller.dispose);
      await controller.load();

      await tester.pumpWidget(_app(controller));
      await _openSheet(tester);
      await tester.enterText(find.byType(TextField), 'example.com');
      await tester.pump(addInstanceLookupDebounce);
      await tester.pump();

      expect(api.lookups, ['example.com']);
      final icon = tester.widget<DIcon>(
        find.byKey(const ValueKey('add-site-invalid')),
      );
      expect(icon.icon, DIcons.xmark);
      expect(icon.color, AppTheme.light.colorScheme.error);
    });
  }

  testWidgets('rejects a malformed address without making a request', (
    tester,
  ) async {
    final store = FakeInstanceStore();
    final api = FakeDiscourseApi();
    final controller = _controller(store, api);
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(_app(controller));
    await _openSheet(tester);
    await tester.enterText(find.byType(TextField), 'https://');
    await tester.pump(addInstanceLookupDebounce);

    expect(api.lookups, isEmpty);
    expect(find.byKey(const ValueKey('add-site-invalid')), findsOneWidget);
  });

  testWidgets('a stale failed lookup cannot replace a newer valid result', (
    tester,
  ) async {
    final store = FakeInstanceStore();
    final api = _RacingLookupApi();
    final controller = _controller(store, api);
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(_app(controller));
    await _openSheet(tester);
    await tester.enterText(find.byType(TextField), 'old.example');
    await tester.pump(addInstanceLookupDebounce);
    await api.oldStarted.future;

    await tester.enterText(find.byType(TextField), 'new.example');
    await tester.pump(addInstanceLookupDebounce);
    await api.newStarted.future;
    api.newGate.complete();
    await tester.pump();

    expect(find.byKey(const ValueKey('add-site-valid')), findsOneWidget);

    api.oldGate.complete();
    await tester.pump();

    expect(find.byKey(const ValueKey('add-site-valid')), findsOneWidget);
    expect(find.byKey(const ValueKey('add-site-invalid')), findsNothing);
  });

  testWidgets('Connect shares an automatic lookup already in flight', (
    tester,
  ) async {
    final store = FakeInstanceStore();
    final api = _GatedLookupApi();
    final controller = _controller(store, api);
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(_app(controller));
    await _openSheet(tester);
    await tester.enterText(find.byType(TextField), 'meta.example');
    await tester.pump(addInstanceLookupDebounce);
    await api.started.future;

    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(api.lookups, ['meta.example']);

    api.lookupGate.complete();
    await tester.pumpAndSettle();

    expect(api.lookups, ['meta.example']);
    expect(controller.instances.single.url, 'https://meta.example');
    expect(store.saveCount, 1);
  });

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
  await _openSheet(tester);
  await tester.enterText(find.byType(TextField), 'meta.example');
  await tester.tap(find.text('Connect'));
  await tester.pump();
  await api.started.future;
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('Add site'));
  await tester.pumpAndSettle();
}

final class _GatedLookupApi extends FakeDiscourseApi {
  final lookupGate = Completer<void>();
  final started = Completer<void>();

  @override
  Future<DiscourseInstance> lookup(String term) async {
    lookups.add(term);
    started.complete();
    await lookupGate.future;
    return instance('meta.example');
  }
}

final class _RacingLookupApi extends FakeDiscourseApi {
  final oldStarted = Completer<void>();
  final newStarted = Completer<void>();
  final oldGate = Completer<void>();
  final newGate = Completer<void>();

  @override
  Future<DiscourseInstance> lookup(String term) async {
    lookups.add(term);
    if (term == 'old.example') {
      oldStarted.complete();
      await oldGate.future;
      throw SiteLookupException(SiteLookupFailure.unreachable, term);
    }
    newStarted.complete();
    await newGate.future;
    return instance('new.example');
  }
}
