import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/shell/forum_settings_controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/theme_settings.dart';

void main() {
  test(
    'rail Settings opens a tab in the current forum without switching forums',
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
      expect(shell.currentContent?.title, 'Settings');
    },
  );

  test('Aggregate Settings is a separate closable tab', () async {
    final shell = controller(
      instances: const [
        DiscourseInstance(url: 'https://a.example', title: 'A'),
      ],
    );
    addTearDown(shell.dispose);
    await shell.load();
    shell.selectAggregate();
    final feedTab = shell.activeAggregateTabId;
    shell.openCurrentSettings();
    expect(shell.rootMode, ShellRootMode.aggregate);
    expect(shell.aggregateSettingsOpen, isTrue);
    expect(shell.activeAggregateTabId, feedTab);
    await shell.forumSettings.setThemeMode(
      ForumSettingsController.homeSite,
      shell.forumSettings.themeModeFor('https://a.example'),
    );
    shell.closeAggregateSettings();
    expect(shell.aggregateSettingsOpen, isFalse);
    expect(shell.activeAggregateTabId, feedTab);
  });

  test('Home theme mode persists separately from forum mode', () async {
    final store = ForumSettingsStore.memory();
    final first = ForumSettingsController(store: store);
    addTearDown(first.dispose);
    await first.load(ForumSettingsController.homeSite);
    await first.setThemeMode(
      ForumSettingsController.homeSite,
      AppThemeMode.dark,
    );
    final second = ForumSettingsController(store: store);
    addTearDown(second.dispose);
    await second.load(ForumSettingsController.homeSite);
    expect(
      second.themeModeFor(ForumSettingsController.homeSite),
      AppThemeMode.dark,
    );
    expect(second.themeModeFor('https://a.example'), AppThemeMode.system);
  });
}
