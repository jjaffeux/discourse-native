import 'package:discourse_native/src/shell/start_page_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const site = 'https://meta.discourse.org';
  const otherSite = 'https://team.discourse.org';
  late StartPageController controller;

  setUp(() => controller = StartPageController());
  tearDown(() => controller.dispose());

  test('Recently closed and Topics are independent default pins', () {
    expect(controller.pinsFor(site), ['recently-closed', 'topics']);
    controller.togglePin(site, 'topics');
    expect(controller.pinsFor(site), ['recently-closed']);
    controller.togglePin(site, 'recently-closed');
    expect(controller.pinsFor(site), isEmpty);
    controller.togglePin(site, 'topics');
    expect(controller.pinsFor(site), ['topics']);
    expect(controller.pinsFor(otherSite), ['recently-closed', 'topics']);
  });

  test(
    'Recently closed leads after repinning without reordering other pins',
    () {
      controller.togglePin(site, 'recently-closed');
      controller.togglePin(site, 'categories');
      controller.togglePin(site, 'bookmarks');
      controller.togglePin(site, 'recently-closed');
      expect(controller.pinsFor(site), [
        'recently-closed',
        'topics',
        'categories',
        'bookmarks',
      ]);
      controller.togglePin(site, 'categories');
      controller.togglePin(site, 'categories');
      expect(controller.pinsFor(site), [
        'recently-closed',
        'topics',
        'bookmarks',
        'categories',
      ]);
    },
  );

  test('account retirement resets only its forum and notifies Start tabs', () {
    var changes = 0;
    controller.addListener(() => changes++);
    controller.togglePin(site, 'topics');
    controller.togglePin(otherSite, 'categories');
    final previous = controller.pinsFor(site);
    controller.forget(site);
    expect(changes, 3);
    expect(previous, ['recently-closed']);
    expect(controller.pinsFor(site), ['recently-closed', 'topics']);
    expect(controller.pinsFor(otherSite), [
      'recently-closed',
      'topics',
      'categories',
    ]);
    expect(() => previous.add('badges'), throwsUnsupportedError);
    controller.forget(site);
    expect(changes, 3);
  });
}
