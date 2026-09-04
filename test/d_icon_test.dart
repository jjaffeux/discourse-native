import 'dart:io';

import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:discourse_native/src/theme/d_native_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/finders.dart';

void main() {
  group('DIcon', () {
    testWidgets('every bundled icon renders', (tester) async {
      final icons = {...DIcons.byName.values, ...DNativeIcons.byName.values};
      for (final icon in icons) {
        expect(
          icon.data.fontPackage,
          'lucide_flutter',
          reason: '${icon.name} is not backed by Lucide',
        );
        await tester.pumpWidget(
          MaterialApp(home: Center(child: DIcon(icon, size: 24))),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: '${icon.name} did not render',
        );
        expect(find.dIcon(icon), findsOneWidget);
      }
    });

    testWidgets('sizes to a square box', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(child: DIcon(DIcons.handPointRight, size: 32)),
        ),
      );

      expect(
        tester.getSize(find.dIcon(DIcons.handPointRight)),
        const Size(32, 32),
      );
    });

    testWidgets('takes its size and color from IconTheme', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: IconTheme(
            data: IconThemeData(size: 18, color: Color(0xFF00FF00)),
            child: Center(child: DIcon(DIcons.gear)),
          ),
        ),
      );

      expect(tester.getSize(find.dIcon(DIcons.gear)), const Size(18, 18));
      final glyph = tester.widget<Icon>(
        find.descendant(
          of: find.dIcon(DIcons.gear),
          matching: find.byType(Icon),
        ),
      );
      expect(glyph.icon, DIcons.gear.data);
      expect(glyph.size, 18 * DIcon.glyphScale);
      expect(glyph.color, const Color(0xFF00FF00));
    });

    testWidgets('rejects icon data from another font package', (tester) async {
      const foreignIcon = DIconData('foreign', IconData(0x1234));

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: DIcon(foreignIcon),
        ),
      );

      expect(tester.takeException(), isAssertionError);
    });

    testWidgets('keeps a semantic label in its own image node', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: DIcon(DIcons.lock, semanticLabel: 'Closed topic'),
        ),
      );

      expect(find.bySemanticsLabel('Closed topic'), findsOneWidget);
    });

    test('aliases resolve to the icon Discourse maps them to', () {
      expect(DIcons.byName['d-liked'], DIcons.heart);
      expect(DIcons.byName['d-unliked'], DIcons.farHeart);
      expect(DIcons.byName['topic.closed'], DIcons.lock);
      expect(DIcons.byName['notification.mentioned'], DIcons.at);
    });

    test('core catalog excludes optional plugin resources and aliases', () {
      for (final name in const [
        'discourse-sparkles',
        'gif',
        'square-poll-horizontal',
        'd-chat',
      ]) {
        expect(DIcons.byName, isNot(contains(name)), reason: name);
      }
    });

    test('application source does not use another icon set directly', () {
      const roots = [
        'lib',
        'packages/discourse_plugin_api/lib',
        'packages/discourse_voice/lib',
        'profiles/full/lib',
      ];
      final forbiddenIcon = RegExp(
        r'\b(?:(?:Icons|CupertinoIcons|FontAwesomeIcons)\.[A-Za-z_]|IconData\s*\()',
      );
      final violations = <String>[];

      for (final root in roots) {
        for (final entity in Directory(root).listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) {
            continue;
          }
          final lines = entity.readAsLinesSync();
          for (var index = 0; index < lines.length; index++) {
            if (forbiddenIcon.hasMatch(lines[index])) {
              violations.add('${entity.path}:${index + 1}: ${lines[index]}');
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Use a Lucide-backed DIcon instead:\n${violations.join('\n')}',
      );
    });
  });
}
