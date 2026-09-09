import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_galleries.dart';
import 'package:discourse_native/src/shell/composer_image_gallery.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/toggle_group_review_main.dart';
import 'support/fakes.dart';

void main() {
  testWidgets('review fixture mounts examples and the real local composer', (
    tester,
  ) async {
    final shell = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    await shell.load();
    final composer = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://toggle-group.invalid',
        topicId: 7,
        slug: 'local-review',
        topicTitle: 'Local Toggle Group review',
      ),
      resolveUploadUrls: (_) async => const {},
    );
    composer.text.value = const TextEditingValue(
      text: '[grid]\n![One](upload://one)\n![Two](upload://two)\n[/grid]',
      selection: TextSelection.collapsed(offset: 0),
    );

    await tester.pumpWidget(
      ToggleGroupReviewApp(shell: shell, composer: composer),
    );
    expect(find.byType(DToggleGroup<String>), findsOneWidget);

    await tester.tap(find.text('Show real composer'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposerPanel), findsOneWidget);
    await tester.tap(find.byType(ComposerImageGalleryPreview));
    await tester.pumpAndSettle();
    expect(find.byType(DToggleGroup<ComposerGalleryMode>), findsOneWidget);
    expect(find.bySemanticsLabel('Grid gallery mode'), findsOneWidget);
    expect(find.bySemanticsLabel('Carousel gallery mode'), findsOneWidget);
  });
}
