import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/native_ui_ownership.dart';

List<NativeUiFinding> inspect(
  String source, {
  String path = 'lib/src/example.dart',
}) => inspectNativeUiSource(source, path: path);

List<String> errors(String source) => [
  for (final finding in inspect(source))
    if (finding.isError) finding.symbol,
];

void main() {
  test('application controls belong to Native', () {
    final violations = scanNativeUiOwnership(
      Directory.current,
    ).where((finding) => finding.isError).toList();
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('finds invocations, explicit construction, and named constructors', () {
    expect(
      errors('''
import 'package:flutter/material.dart';
final a = TextField();
final b = const AlertDialog();
final c = new ListTile();
final d = Dialog.fullscreen();
final e = const InputDecoration.collapsed(hintText: 'Find');
final f = ElevatedButton.icon(onPressed: null, label: Text('Save'));
final g = new Dialog.fullscreen();
'''),
      [
        'TextField',
        'AlertDialog',
        'ListTile',
        'Dialog',
        'InputDecoration',
        'ElevatedButton',
        'Dialog',
      ],
    );
  });

  test('finds prefixed and generic constructor references', () {
    expect(
      errors('''
import 'package:flutter/material.dart' as m;
final a = m.TextField();
final b = const m.Dialog.fullscreen();
final c = m.TextField.new;
final d = m.Dialog.fullscreen;
final e = m.DropdownButton<String>.new;
final f = m.Checkbox.adaptive;
'''),
      [
        'TextField',
        'Dialog',
        'TextField',
        'Dialog',
        'DropdownButton',
        'Checkbox',
      ],
    );
  });

  test('finds unprefixed constructor references and local type aliases', () {
    expect(
      errors('''
import 'package:flutter/material.dart';
final a = TextField.new;
final b = Dialog.fullscreen;
typedef Editor = TextField;
typedef SecondEditor = Editor;
final c = Editor();
final d = SecondEditor.new;
'''),
      ['TextField', 'Dialog', 'TextField', 'TextField'],
    );
  });

  test('finds Cupertino controls and raw overlay calls and references', () {
    expect(
      errors('''
import 'package:flutter/cupertino.dart' as c;
import 'package:flutter/material.dart';
final a = c.CupertinoButton.filled(onPressed: null, child: Text('OK'));
final b = c.CupertinoTextField();
final open = showDialog;
final cupertinoOpen = c.showCupertinoDialog;
void go() { showDialog(context: context, builder: build); }
'''),
      [
        'CupertinoButton',
        'CupertinoTextField',
        'showDialog',
        'showCupertinoDialog',
        'showDialog',
      ],
    );
  });

  test('finds inheritance while allowing ordinary type annotations', () {
    expect(
      errors('''
import 'package:flutter/material.dart';
class LocalField extends TextField {}
class LocalDialog implements Dialog {}
TextField? editor;
List<Dialog> dialogs = [];
bool isEditor(Object value) => value is TextField;
final fieldType = TextField;
'''),
      ['TextField', 'Dialog'],
    );
  });

  test('ignores code in strings and comments but examines interpolation', () {
    expect(
      errors(r'''
import 'package:flutter/material.dart';
// TextField();
/* const AlertDialog(); */
final sample = 'TextField()';
final raw = r'${TextField()}';
final executable = '${TextField()}';
'''),
      ['TextField'],
    );
  });

  test(
    'does not confuse local domain names or instance methods with Flutter',
    () {
      expect(
        errors('''
import 'package:flutter/material.dart';
class Dialog { Dialog(); }
final local = Dialog();
void use(dynamic model) { model.TextField(); }
void callback(dynamic TextField) { TextField(); }
void localCallback() { final TextField = () {}; TextField(); }
final actual = TextField();
'''),
        ['TextField'],
      );
      expect(
        errors('''
import 'package:my_domain/models.dart';
final local = Dialog();
final constructor = Dialog.new;
'''),
        isEmpty,
      );
      expect(
        errors('''
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:my_domain/models.dart';
final local = Dialog();
'''),
        isEmpty,
      );
    },
  );

  test('honors import show and hide clauses and namespace prefixes', () {
    expect(
      errors('''
import 'package:flutter/material.dart' show TextField;
import 'package:flutter/cupertino.dart' as c hide CupertinoButton;
final a = TextField();
final b = Dialog();
final c1 = c.CupertinoButton();
final c2 = c.CupertinoTextField();
'''),
      ['TextField', 'CupertinoTextField'],
    );
    expect(
      errors('''
import 'package:flutter/material.dart' as m;
void local(dynamic m) { m.TextField(); }
final actual = m.TextField();
'''),
      ['TextField'],
    );
  });

  test(
    'flags raw interaction controls and separately reports primary taps',
    () {
      final findings = inspect('''
import 'package:flutter/material.dart';
final a = InkWell(onTap: run);
final b = InkResponse(onTap: run);
final c = GestureDetector(onTap: run);
final d = GestureDetector(onTapDown: run);
final e = GestureDetector(onTap: null, onLongPress: run);
final f = GestureDetector(onSecondaryTap: run, onPanUpdate: run);
''');
      expect(
        findings
            .where((finding) => finding.isError)
            .map((finding) => finding.symbol),
        ['InkWell', 'InkResponse'],
      );
      expect(
        findings
            .where((finding) => !finding.isError)
            .map((finding) => finding.symbol),
        ['GestureDetector.onTap', 'GestureDetector.onTapDown'],
      );
    },
  );

  test('allows Native components and text, focus, semantics, and layout', () {
    expect(
      errors('''
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
final content = FocusTraversalGroup(child: Focus(
  child: Semantics(label: 'Save', child: Padding(
    padding: EdgeInsets.all(8),
    child: Column(children: [DButton(label: Text('Save')), DInput()]),
  )),
));
final node = FocusNode();
final field = FormField<String>(builder: build);
'''),
      isEmpty,
    );
  });

  test('restricts internal kit imports and exports to the public facade', () {
    for (final source in [
      "import 'package:discourse_native/src/ui/components/d_button.dart';",
      "import '../ui/components/d_button.dart';",
      "export '../ui/components/d_button.dart';",
      "import 'safe.dart' if (dart.library.io) '../ui/components/d_button.dart';",
    ]) {
      final findings = inspect(source, path: 'lib/src/shell/page.dart');
      expect(findings.map((finding) => finding.kind), [
        NativeUiFindingKind.internalImport,
      ]);
    }
    expect(
      inspect(
        "export 'src/ui/components/d_button.dart';",
        path: 'lib/discourse_ui.dart',
      ),
      isEmpty,
    );
    expect(
      inspect(
        "import 'src/ui/components/d_button.dart';",
        path: 'lib/discourse_ui.dart',
      ).single.kind,
      NativeUiFindingKind.internalImport,
    );
    expect(
      inspect("import 'package:discourse_native/discourse_ui.dart';"),
      isEmpty,
    );
    expect(
      inspect(
        "import 'package:flutter/material.dart'; final b = TextField();",
        path: 'lib/src/ui/components/d_input.dart',
      ),
      isEmpty,
    );
  });

  test('part files inherit the owning library Flutter imports', () {
    final root = Directory.systemTemp.createTempSync('native-parts-');
    addTearDown(() => root.deleteSync(recursive: true));
    final parent = File('${root.path}/lib/page.dart')
      ..parent.createSync(recursive: true);
    parent.writeAsStringSync(
      "import 'package:flutter/material.dart' as m; part 'page_part.dart';",
    );
    File(
      '${root.path}/lib/page_part.dart',
    ).writeAsStringSync("part of 'page.dart'; final editor = m.TextField();");
    final violations = scanNativeUiOwnership(
      root,
    ).where((finding) => finding.isError).toList();
    expect(violations.map((finding) => finding.symbol), ['TextField']);
    expect(violations.single.path, 'lib/page_part.dart');
  });

  test('returns source locations and fails on malformed Dart', () {
    final finding = inspect(
      "import 'package:flutter/material.dart';\nfinal a = TextField();",
    ).single;
    expect(finding.path, 'lib/src/example.dart');
    expect(finding.line, 2);
    expect(finding.column, greaterThan(1));
    expect(
      inspect(
        'final = ;',
      ).any((finding) => finding.kind == NativeUiFindingKind.parseError),
      isTrue,
    );
  });

  test(
    'scans every application surface and excludes only kit implementation',
    () {
      final root = Directory.systemTemp.createTempSync('native-ownership-');
      addTearDown(() => root.deleteSync(recursive: true));
      const source =
          "import 'package:flutter/material.dart'; final a = TextField();";
      for (final relative in [
        'lib/main.dart',
        'lib/src/shell/screen.dart',
        'lib/src/plugins/chat/screen.dart',
        'lib/src/styleguide/examples/example.dart',
        'lib/src/ui/components/d_input.dart',
      ]) {
        final file = File('${root.path}/$relative');
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(source);
      }
      expect(scanNativeUiOwnership(root).map((finding) => finding.path), [
        'lib/main.dart',
        'lib/src/plugins/chat/screen.dart',
        'lib/src/shell/screen.dart',
        'lib/src/styleguide/examples/example.dart',
      ]);
    },
  );

  test('follows directly imported application typedefs and their prefixes', () {
    final root = Directory.systemTemp.createTempSync('native-alias-');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/lib').createSync();
    File('${root.path}/lib/aliases.dart').writeAsStringSync('''
import 'package:flutter/material.dart' as m;
typedef Editor = m.TextField;
typedef Surface = m.Dialog;
''');
    File('${root.path}/lib/consumer.dart').writeAsStringSync('''
import 'aliases.dart' show Editor;
import 'package:discourse_native/aliases.dart' as a;
final field = Editor();
final surface = const a.Surface.fullscreen();
final constructor = a.Editor.new;
final unrelated = Surface();
''');
    expect(scanNativeUiOwnership(root).map((finding) => finding.symbol), [
      'TextField',
      'Dialog',
      'TextField',
    ]);
  });
}
