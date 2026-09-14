import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/gen_icons.dart' as generator;

void main() {
  test(
    'generation retains fixed AI colors without changing ordinary icons',
    () {
      final originalDirectory = Directory.current;
      final temporary = Directory.systemTemp.createTempSync(
        'native-icon-generation-',
      );
      try {
        Directory.current = temporary;
        Directory('tool').createSync();
        Directory('lib/src/theme').createSync(recursive: true);
        File('tool/icons.txt').writeAsStringSync('discourse-ai\nstar\n');
        for (final path in [
          'vendor/assets/svg-icons/fontawesome/solid.svg',
          'vendor/assets/svg-icons/fontawesome/regular.svg',
          'vendor/assets/svg-icons/fontawesome/brands.svg',
          'vendor/assets/svg-icons/discourse-additional.svg',
          'plugins/discourse-ai/svg-icons/icons-sprite.svg',
        ]) {
          final file = File('sprites/$path');
          file.parent.createSync(recursive: true);
          file.writeAsStringSync('<svg/>');
        }
        File(
          'sprites/vendor/assets/svg-icons/fontawesome/solid.svg',
        ).writeAsStringSync(
          '<svg><symbol id="star" viewBox="0 0 16 16">'
          '<path d="M0 0h16v16H0z"/></symbol></svg>',
        );
        File(
          'sprites/plugins/discourse-ai/svg-icons/icons-sprite.svg',
        ).writeAsStringSync(
          '<svg><symbol id="discourse-ai" viewBox="0 0 512 512">'
          '<path fill="#333" d="M0 0h512v512H0z"/>'
          '<path fill="#fff" d="M100 100h50v50h-50z"/>'
          '</symbol></svg>',
        );

        generator.main(['--discourse=${temporary.path}/sprites']);

        final generated = File('lib/src/theme/d_icons.dart').readAsStringSync();
        final declarations = generated.split('static const DIconData ');
        final ai = declarations.singleWhere(
          (part) => part.startsWith('discourseAi'),
        );
        final star = declarations.singleWhere(
          (part) => part.startsWith('star'),
        );
        expect(ai, contains('preserveColors: true'));
        expect(ai, contains('fill="#333"'));
        expect(ai, contains('fill="#fff"'));
        expect(ai, contains('viewBox="0 0 512 512"'));
        expect(star, isNot(contains('preserveColors: true')));
        expect(star, contains('fill="currentColor"'));
      } finally {
        Directory.current = originalDirectory;
        temporary.deleteSync(recursive: true);
      }
    },
  );
}
