import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_tag_removal_notice.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ComposerController composer() {
    final result = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://meta.discourse.org',
        topicId: 7,
        slug: 'a-topic',
        topicTitle: 'A topic',
      ),
    );
    addTearDown(result.dispose);
    return result;
  }

  testWidgets('a repeated notice gets seven seconds of its own', (
    tester,
  ) async {
    final controller = composer();
    controller.showNotice('Checking whether that posted…');
    controller.showTagRemovalNotice(categoryName: 'Bugs');
    await tester.pump(const Duration(seconds: 6));
    controller.showTagRemovalNotice(categoryName: 'Bugs');

    await tester.pump(const Duration(seconds: 1));
    expect(controller.tagRemovalNotice, 'They aren’t available in Bugs.');
    await tester.pump(const Duration(seconds: 6));
    expect(controller.tagRemovalNotice, isNull);
    expect(controller.notice, 'Checking whether that posted…');
  });

  testWidgets('changing category or submitting clears an outdated notice', (
    tester,
  ) async {
    final controller = composer();
    controller.showTagRemovalNotice(categoryName: 'Bugs');

    controller.setCategory(5);
    expect(controller.tagRemovalNotice, isNull);

    controller.showTagRemovalNotice();
    expect(
      controller.tagRemovalNotice,
      'They aren’t available in this category.',
    );
    controller.beginSubmit();
    expect(controller.tagRemovalNotice, isNull);
    await tester.pump(const Duration(seconds: 7));
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing a composer cancels its notice timeout', (
    tester,
  ) async {
    final controller = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://meta.discourse.org',
        topicId: 7,
        slug: 'a-topic',
        topicTitle: 'A topic',
      ),
    );
    controller.showTagRemovalNotice(categoryName: 'Bugs');
    controller.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets('a long category fits a narrow notice in ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = composer();
      controller.showTagRemovalNotice(
        categoryName: 'Discourse Native App Development and Support',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: controller.tagRemovalNotice == null
                        ? const SizedBox.shrink()
                        : ComposerTagRemovalNotice(
                            message: controller.tagRemovalNotice!,
                            onDismiss: controller.dismissTagRemovalNotice,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final notice = find.byType(ComposerTagRemovalNotice);
      final bounds = tester.getRect(notice);
      expect(bounds.left, greaterThanOrEqualTo(16));
      expect(bounds.right, lessThanOrEqualTo(304));
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.descendant(of: notice, matching: find.byType(DButton)),
      );
      await tester.pump();
      expect(notice, findsNothing);
    });
  }
}
