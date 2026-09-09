import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {double scale = 1, ThemeData? theme}) => MaterialApp(
  theme: (theme ?? AppTheme.light).copyWith(platform: TargetPlatform.macOS),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Center(child: SizedBox(width: 300, child: child)),
    ),
  ),
);
void main() {
  testWidgets(
    'form saves edits, validates, resets to mount value and reports reset once',
    (tester) async {
      final form = GlobalKey<FormState>();
      final controller = TextEditingController(text: 'original');
      addTearDown(controller.dispose);
      final changes = <String>[];
      String? saved;
      await tester.pumpWidget(
        host(
          Form(
            key: form,
            child: DInput(
              controller: controller,
              labelText: 'Name',
              onChanged: changes.add,
              validator: (v) => v!.isEmpty ? 'Required' : null,
              onSaved: (v) => saved = v,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '');
      expect(form.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Required'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'edited');
      form.currentState!.save();
      expect(saved, 'edited');
      form.currentState!.reset();
      await tester.pump();
      expect(controller.text, 'original');
      expect(changes, ['', 'edited', 'original']);
      expect(find.text('Required'), findsNothing);
    },
  );

  testWidgets(
    'reset restores the mount snapshot after parent defaults change and keeps Form value synchronized',
    (tester) async {
      final form = GlobalKey<FormState>();
      String initial = 'first';
      late StateSetter update;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return host(
              Form(
                key: form,
                child: DInput(initialValue: initial),
              ),
            );
          },
        ),
      );
      await tester.enterText(find.byType(TextField), 'local edit');
      update(() => initial = 'new default');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'local edit',
      );
      form.currentState!.reset();
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'first',
      );
      await tester.pumpWidget(
        host(
          Form(
            key: form,
            child: DInput(value: 'controlled'),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'edited');
      form.currentState!.reset();
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'first',
      );
    },
  );

  testWidgets(
    'one user edit notifies Form once and marks required semantics on the editable node',
    (tester) async {
      int changes = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          Form(
            onChanged: () => changes++,
            child: DInput(
              isRequired: true,
              labelText: 'Name',
              prefix: const Icon(Icons.search),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump();
      expect(changes, 1);
      expect(
        tester.getSemantics(find.byType(EditableText)),
        isSemantics(
          label: 'Name',
          value: 'a',
          isTextField: true,
          isRequired: true,
        ),
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'IME composition and selection survive equal controlled updates and theme changes',
    (tester) async {
      String value = 'hello';
      late StateSetter update;
      bool dark = false;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return host(
              DInput(value: value, onChanged: (v) => update(() => value = v)),
              theme: dark ? AppTheme.dark : AppTheme.light,
            );
          },
        ),
      );
      await tester.showKeyboard(find.byType(TextField));
      const editing = TextEditingValue(
        text: '你好',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      tester.testTextInput.updateEditingValue(editing);
      await tester.pump();
      expect(value, '你好');
      update(() => dark = true);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.value,
        editing,
      );
      update(() => value = 'replacement');
      await tester.pump();
      final result = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
          .value;
      expect(result.text, 'replacement');
      expect(result.composing, TextRange.empty);
      expect(result.selection.baseOffset, 11);
    },
  );

  testWidgets(
    'controller handoffs preserve full editing value and never dispose borrowed owners',
    (tester) async {
      final first = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'first',
          selection: TextSelection(baseOffset: 1, extentOffset: 3),
          composing: TextRange(start: 0, end: 4),
        ),
      );
      final second = TextEditingController(text: 'second');
      final focus = FocusNode();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      addTearDown(focus.dispose);
      TextEditingController? current = first;
      late StateSetter update;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return host(DInput(controller: current, focusNode: focus));
          },
        ),
      );
      update(() => current = null);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.value,
        first.value,
      );
      update(() => current = second);
      await tester.pump();
      expect(find.text('second'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      first.text = 'still alive';
      second.text = 'also alive';
      focus.requestFocus();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'programmatic controller text is saved without user callback and selection-only edits do not change form',
    (tester) async {
      final form = GlobalKey<FormState>();
      final controller = TextEditingController(text: 'abc');
      addTearDown(controller.dispose);
      int callbacks = 0;
      String? saved;
      await tester.pumpWidget(
        host(
          Form(
            key: form,
            child: DInput(
              controller: controller,
              onChanged: (_) => callbacks++,
              onSaved: (v) => saved = v,
            ),
          ),
        ),
      );
      controller.text = 'updated';
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 3,
      );
      form.currentState!.save();
      expect(saved, 'updated');
      expect(callbacks, 0);
    },
  );

  testWidgets(
    'read-only allows focus and selection, disabled removes focus and blocks editing',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      bool enabled = true;
      late StateSetter update;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return host(
              DInput(
                initialValue: 'copy',
                readOnly: true,
                enabled: enabled,
                focusNode: focus,
                labelText: 'Read only',
              ),
            );
          },
        ),
      );
      await tester.tap(find.text('Read only'));
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      update(() => enabled = false);
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      await tester.tap(find.byType(TextField), warnIfMissed: false);
      await tester.pump();
      expect(focus.hasFocus, isFalse);
    },
  );

  testWidgets(
    'formatters and keyboard submission retain native secure editing configuration',
    (tester) async {
      String? submitted;
      await tester.pumpWidget(
        host(
          DInput(
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (v) => submitted = v,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '1a23456');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(submitted, '1234');
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isTrue);
      expect(field.autocorrect, isFalse);
    },
  );

  testWidgets(
    '32px desktop bounds grow for 200% text without changing inset or overflowing RTL',
    (tester) async {
      await tester.pumpWidget(host(DInput(hintText: 'Email')));
      expect(tester.getSize(find.byType(DInput)).height, 32);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.style!.fontSize, 14);
      await tester.pumpWidget(
        host(
          Directionality(
            textDirection: TextDirection.rtl,
            child: DInput(
              initialValue: 'مرحبا world long text '.padRight(300, 'x'),
              prefix: const Icon(Icons.search, size: 16),
            ),
          ),
          scale: 2,
        ),
      );
      expect(tester.getSize(find.byType(DInput)).height, greaterThan(32));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'file input retains 32px desktop geometry and grows for large text',
    (tester) async {
      await tester.pumpWidget(host(DFileInput(onPick: () async => null)));
      expect(tester.getSize(find.byType(DFileInput)).height, 32);
      await tester.pumpWidget(
        host(DFileInput(onPick: () async => null), scale: 2),
      );
      expect(tester.getSize(find.byType(DFileInput)).height, 48);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'file failure is retryable and a disabled picker completion cannot change selection',
    (tester) async {
      bool fail = true, enabled = true;
      final pending = Completer<List<String>?>();
      late StateSetter update;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return host(
              DFileInput(
                enabled: enabled,
                onPick: () async {
                  if (fail) throw StateError('picker failed');
                  return pending.future;
                },
              ),
            );
          },
        ),
      );
      await tester.tap(find.text('Choose file'));
      await tester.pumpAndSettle();
      expect(find.text('Could not choose a file. Try again.'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Choose file'));
      await tester.pump();
      update(() => enabled = false);
      await tester.pump();
      update(() => enabled = true);
      await tester.pump();
      pending.complete(['late.png']);
      await tester.pumpAndSettle();
      expect(find.text('late.png'), findsNothing);
      expect(find.text('Choose file'), findsOneWidget);
    },
  );

  testWidgets(
    'file cancellation preserves selection and reset invalidates a pending picker',
    (tester) async {
      final form = GlobalKey<FormState>();
      var pending = Completer<List<String>?>();
      List<String>? saved;
      await tester.pumpWidget(
        host(
          Form(
            key: form,
            child: DFileInput(
              initialValue: const ['old.png'],
              onPick: () => pending.future,
              onSaved: (v) => saved = v,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose file'));
      pending.complete(null);
      await tester.pumpAndSettle();
      form.currentState!.save();
      expect(saved, ['old.png']);
      pending = Completer<List<String>?>();
      await tester.tap(find.text('Choose file'));
      form.currentState!.reset();
      pending.complete(['late.png']);
      await tester.pumpAndSettle();
      expect(find.text('old.png'), findsOneWidget);
      expect(find.text('late.png'), findsNothing);
    },
  );
}
