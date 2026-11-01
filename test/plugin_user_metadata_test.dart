import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/models/user_directory.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/user_metadata_plugin.dart';

const _site = 'https://community.example';
const _card = UserCard(username: 'reader', title: 'loaded');

void main() {
  testWidgets('absent metadata hooks are empty and labels retain fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            expect(PluginRegistry.empty.hasUserProfileMetadata, isFalse);
            expect(
              PluginRegistry.empty.userCardMetadata(
                context,
                _site,
                _card,
                () {},
              ),
              isEmpty,
            );
            expect(
              PluginRegistry.empty.userProfileMetadata(context, _site, _card),
              isEmpty,
            );
            expect(
              PluginRegistry.empty.userDirectoryColumnLabel(
                context,
                _site,
                'custom_metric',
              ),
              isNull,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });

  testWidgets(
    'metadata callbacks and mounted widgets retain their owner and close action',
    (tester) async {
      const registry = PluginRegistry([UserMetadataTestPlugin()]);
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Column(
              children: [
                ...registry.userCardMetadata(
                  context,
                  _site,
                  _card,
                  () => closed = true,
                ),
                ...registry.userProfileMetadata(context, _site, _card),
              ],
            ),
          ),
        ),
      );
      expect(
        find.text(
          'Card metadata reader: loaded user-metadata-test/user-metadata-test',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Profile metadata reader: loaded user-metadata-test/user-metadata-test',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Close metadata'));
      expect(closed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('two plugins cannot claim the same directory label', (
    tester,
  ) async {
    const registry = PluginRegistry([
      UserMetadataTestPlugin(name: 'alpha'),
      UserMetadataTestPlugin(name: 'beta'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            expect(
              () => registry.userDirectoryColumnLabel(
                context,
                _site,
                'custom_metric',
              ),
              throwsA(
                isA<StateError>().having(
                  (e) => e.message,
                  'owners',
                  allOf(contains('alpha'), contains('beta')),
                ),
              ),
            );
            expect(
              registry.userDirectoryColumnLabel(context, _site, 'unknown'),
              isNull,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });

  testWidgets(
    'directory renders contributor label while retaining server column sort key',
    (tester) async {
      String? sorted;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PluginRegistryScope(
            registry: const PluginRegistry([UserMetadataTestPlugin()]),
            child: Scaffold(
              body: UsersPage(
                siteUrl: _site,
                data: const UsersPageData(
                  loaded: true,
                  columns: [
                    UserDirectoryColumn(
                      id: 5,
                      name: 'custom_metric',
                      type: UserDirectoryColumnType.plugin,
                      position: 1,
                    ),
                  ],
                  items: [
                    UserDirectoryItem(
                      id: 1,
                      user: UserDirectoryUser(id: 1, username: 'reader'),
                      values: {'custom_metric': 42},
                    ),
                  ],
                ),
                onSortChanged: (key, direction) => sorted = key,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Community metric'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      await tester.tap(find.text('Community metric'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sort ascending'));
      await tester.pumpAndSettle();
      expect(sorted, 'custom_metric');
    },
  );
}
