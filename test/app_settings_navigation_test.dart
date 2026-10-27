import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/theme_settings.dart';

void main() {
  test(
    'rail Interface opens a tab in the current forum without switching forums',
    () async {
      final shell = controller(
        instances: const [
          DiscourseInstance(url: 'https://a.example', title: 'A'),
          DiscourseInstance(url: 'https://b.example', title: 'B'),
        ],
      );
      addTearDown(shell.dispose);
      await shell.load();
      final original = shell.currentInstance!.url;
      shell.openCurrentSettings();
      expect(shell.rootMode, ShellRootMode.forum);
      expect(shell.currentInstance!.url, original);
      expect(shell.currentContent?.isAppearance, isTrue);
      expect(shell.currentContent?.title, 'Interface');
    },
  );
}
