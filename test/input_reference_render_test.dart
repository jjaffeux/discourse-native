import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/invites_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/shell/add_instance_sheet.dart';
import 'package:discourse_native/src/shell/invite_editor.dart';
import 'package:discourse_native/src/shell/invites_controller.dart';
import 'package:discourse_native/src/styleguide/examples/input_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/invite_fixtures.dart';

const _captureKey = ValueKey('reference-render');

Future<void> _export(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  final directory = Platform.environment['INPUT_REFERENCE_EXPORT_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await Directory(directory).create(recursive: true);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Widget _app(Widget child, {bool dark = true}) => RepaintBoundary(
  key: _captureKey,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
      platform: TargetPlatform.macOS,
      textTheme: (dark ? AppTheme.dark : AppTheme.light).textTheme.apply(
        fontFamily: 'InputReferenceFont',
      ),
    ),
    home: Scaffold(body: child),
  ),
);

void main() {
  setUpAll(() async {
    final loader = FontLoader('InputReferenceFont')
      ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf'));
    await loader.load();
  });

  testWidgets(
    'registered examples render with loaded repository font in both palettes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final dark in [true, false]) {
        for (var i = 0; i < inputExamples.examples.length; i++) {
          final example = inputExamples.examples[i];
          await tester.pumpWidget(
            _app(
              Center(
                child: SizedBox(
                  width: 320,
                  child: SingleChildScrollView(
                    child: Builder(
                      key: ValueKey('${dark}_$i'),
                      builder: example.builder,
                    ),
                  ),
                ),
              ),
              dark: dark,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.byType(DInput).evaluate().isNotEmpty ||
                find.byType(DFileInput).evaluate().isNotEmpty,
            isTrue,
          );
          await _export(tester, '${dark ? 'dark' : 'light'}-example-$i');
        }
      }
    },
  );

  testWidgets(
    'reference label, description and file gap retain measured spacing',
    (tester) async {
      await tester.pumpWidget(
        _app(
          Center(
            child: SizedBox(
              width: 320,
              child: DInput(
                labelText: 'Username',
                helperText: 'Description',
                hintText: 'Enter text',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final label = tester.getRect(find.text('Username'));
      final editor = tester.getRect(find.byType(EditableText));
      final description = tester.getRect(find.text('Description'));
      expect(label.height, closeTo(19.25, .5));
      expect(description.height, closeTo(21, .1));
      expect(editor.left - label.left, closeTo(11, .1));
      expect(editor.top - label.bottom, closeTo(14, .1));
      await tester.pumpWidget(
        _app(
          Center(
            child: SizedBox(
              width: 320,
              child: DFileInput(onPick: () async => null),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.text('No file chosen')).left -
            tester.getRect(find.byType(DButton)).right,
        closeTo(4, .1),
      );
    },
  );

  testWidgets('real Add Site and Invite editors render migrated controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAddInstanceSheet(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(DInput), findsOneWidget);
    await _export(tester, 'app-add-site');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final controller = InvitesController(
      api: InvitesApi(InviteTransport()),
      credentials: InviteCredentials(),
      instance: inviteSite,
      lifecycle: SiteLifecycle(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          child: InviteEditor(controller: controller, onClose: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DInput).evaluate().length, greaterThan(1));
    await _export(tester, 'app-invite');
  });
}
