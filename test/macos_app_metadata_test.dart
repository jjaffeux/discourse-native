import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS build profiles ship the Discourse application name', () {
    const mainMenus = [
      'macos/Runner/Base.lproj/MainMenu.xib',
      'profiles/full/macos/Runner/Base.lproj/MainMenu.xib',
    ];

    for (final path in mainMenus) {
      final mainMenu = File(path).readAsStringSync();

      expect(
        mainMenu,
        isNot(contains('APP_NAME')),
        reason: '$path must not ship Flutter\'s unsubstituted template token.',
      );
      expect(mainMenu, contains('<menuItem title="Discourse"'));
      expect(mainMenu, contains('<menuItem title="About Discourse"'));
      expect(mainMenu, contains('<menuItem title="Hide Discourse"'));
      expect(mainMenu, contains('<menuItem title="Quit Discourse"'));
      expect(mainMenu, contains('<window title="Discourse"'));
    }
  });
}
