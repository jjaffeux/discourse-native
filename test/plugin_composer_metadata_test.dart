import 'dart:convert';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _site = 'https://forum.example';
const _mode = PluginDataKey<bool>(owner: 'authoring-fixture', name: 'mode');
const _category = PluginDataKey<_Category>(
  owner: 'authoring-fixture',
  name: 'category',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const registry = PluginRegistry([_Plugin(), _CategoryPlugin()]);

  ComposerController editor({
    bool Function()? current,
    ComposerDraft? restore,
  }) {
    late ComposerController result;
    result = ComposerController(
      const NewTopicComposerTarget(
        siteUrl: _site,
        topicTitle: '',
        initialCategoryId: 1,
      ),
      isCurrentComposer: current,
      metadataBindings: registry.composerMetadataBindings,
      pluginStateReader: () => ComposerPluginState(
        categoryData: PluginData.none.withValue(
          _category,
          _Category(result.categoryId == 2),
        ),
      ),
    );
    if (restore != null) result.restore(restore);
    addTearDown(result.dispose);
    return result;
  }

  testWidgets(
    'metadata UI lookup and writes stay with the contributing owner',
    (tester) async {
      final composer = editor();
      final ComposerEditorHost host = composer;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            final owned = PluginUiScope.contextFor(
              context,
              const PluginId('authoring-fixture'),
            );
            final foreign = PluginUiScope.contextFor(
              context,
              const PluginId('other-fixture'),
            );
            expect(host.metadata(owned, _mode), isFalse);
            expect(host.metadata(foreign, _mode), isNull);
            expect(host.updateMetadata(foreign, _mode, true), isFalse);
            expect(host.updateMetadata(owned, _mode, true), isTrue);
            expect(host.metadata(owned, _mode), isTrue);
            return const SizedBox.shrink();
          },
        ),
      );
    },
  );

  test(
    'metadata belongs to canonical editor and resets on category change',
    () {
      final composer = editor();
      expect(composer.metadata(_mode), isFalse);
      expect(composer.updateMetadata(_mode, true), isTrue);
      expect(composer.composerCreateFields, {'fixture_mode': true});
      expect(composer.pluginLabels?.submit, 'Publish fixture');
      composer.setCategory(2);
      expect(composer.metadata(_mode), isTrue);
      composer.setCategory(1);
      expect(composer.metadata(_mode), isFalse);
      expect(composer.composerCreateFields, isEmpty);
    },
  );

  for (final disposed in [false, true]) {
    testWidgets(
      '${disposed ? 'disposed' : 'retired'} editor cannot read metadata or current-account context',
      (tester) async {
        var current = true;
        var reads = 0;
        final composer = ComposerController(
          const NewTopicComposerTarget(siteUrl: _site, topicTitle: ''),
          isCurrentComposer: () => current,
          metadataBindings: registry.composerMetadataBindings,
          pluginStateReader: () {
            reads++;
            return ComposerPluginState(
              currentUser: PluginData.none.withValue(_mode, true),
            );
          },
        );
        if (!disposed) addTearDown(composer.dispose);
        final ComposerEditorHost host = composer;
        late BuildContext owned;
        await tester.pumpWidget(
          Builder(
            builder: (context) {
              owned = PluginUiScope.contextFor(
                context,
                const PluginId('authoring-fixture'),
              );
              return const SizedBox.shrink();
            },
          ),
        );
        expect(host.updateMetadata(owned, _mode, true), isTrue);
        expect(host.metadataContext.currentUserData.get(_mode), isTrue);
        if (disposed) {
          composer.dispose();
        } else {
          current = false;
        }
        final before = reads;
        expect(host.metadata(owned, _mode), isNull);
        expect(host.metadataContext.currentUserData.get(_mode), isNull);
        expect(reads, before);
      },
    );
  }

  test(
    'draft encode and restore retain typed metadata and unknown namespaces',
    () {
      final composer = editor();
      composer.text.text = 'A useful draft';
      composer.updateMetadata(_mode, true);
      final draft = ComposerDraft.decode(composer.draft.encode())!;
      expect(draft.pluginMetadata, {'authoring-fixture/mode': true});
      final restored = editor(restore: draft);
      expect(restored.metadata(_mode), isTrue);
      final opaque = ComposerDraft.fromJson({
        ...draft.toJson(),
        'plugins': {
          ...draft.pluginMetadata,
          'absent/preserved': const {'value': 7},
        },
      });
      final retained = editor(restore: opaque);
      expect(retained.draft.pluginMetadata['absent/preserved'], {'value': 7});
    },
  );

  test(
    'retired or submitting editor refuses metadata writes and payload is frozen',
    () {
      var current = true;
      final composer = editor(current: () => current);
      composer.updateMetadata(_mode, true);
      final sent = composer.composerCreateFields;
      composer.updateMetadata(_mode, false);
      expect(sent, {'fixture_mode': true});
      expect(() => sent['fixture_mode'] = false, throwsUnsupportedError);
      current = false;
      expect(composer.updateMetadata(_mode, true), isFalse);
      current = true;
      composer.beginSubmit(attempt: Object());
      expect(composer.updateMetadata(_mode, true), isFalse);
    },
  );

  test(
    'queued creation starts fresh metadata in the cleared category context',
    () {
      late ComposerController composer;
      composer = ComposerController(
        const NewTopicComposerTarget(
          siteUrl: _site,
          topicTitle: '',
          initialCategoryId: 2,
        ),
        metadataBindings: const PluginRegistry([
          _ExplicitChoicePlugin(),
        ]).composerMetadataBindings,
        pluginStateReader: () => ComposerPluginState(
          categoryData: PluginData.none.withValue(
            _category,
            _Category(composer.categoryId == 2),
          ),
        ),
      );
      addTearDown(composer.dispose);
      composer.restore(
        const ComposerDraft(
          reply: 'Queued body',
          title: 'Queued title',
          categoryId: 2,
          pluginMetadata: {
            'authoring-fixture/mode': false,
            'absent/preserved': {'value': 7},
          },
        ),
      );
      expect(composer.updateMetadata(_mode, true), isTrue);
      final sent = composer.composerCreateFields;

      composer.enqueued(null);

      expect(sent, {'fixture_mode': true});
      expect(composer.raw, isEmpty);
      expect(composer.title.text, isEmpty);
      expect(composer.categoryId, isNull);
      expect(composer.metadata(_mode), isFalse);
      expect(composer.storedPluginMetadata, {'authoring-fixture/mode': false});
      expect(composer.hasChanges, isFalse);
      expect(composer.draftPending, isFalse);
      expect(composer.updateMetadata(_mode, true), isTrue);
      expect(composer.hasChanges, isTrue);
      expect(composer.updateMetadata(_mode, false), isTrue);
      expect(composer.hasChanges, isFalse);
    },
  );

  test(
    'unknown metadata key has no authority and private messages emit no fields',
    () {
      final composer = editor();
      const foreign = PluginDataKey<bool>(owner: 'absent', name: 'mode');
      expect(composer.metadata(foreign), isNull);
      expect(composer.updateMetadata(foreign, true), isFalse);
      final message = ComposerController(
        const PrivateMessageComposerTarget(
          siteUrl: _site,
          topicTitle: '',
          targetRecipients: 'sam',
        ),
        metadataBindings: registry.composerMetadataBindings,
      );
      addTearDown(message.dispose);
      message.updateMetadata(_mode, true);
      expect(message.composerCreateFields, isEmpty);
    },
  );

  test(
    'installed metadata declarations cannot change their field ownership later',
    () {
      final fields = <String>{'fixture_mode'};
      final installed = PluginInstaller.install(
        PluginManifest([_Module(_MutablePlugin(fields))]),
      );
      addTearDown(installed.close);
      fields.clear();
      fields.add('raw');
      expect(
        installed.registry.composerMetadataBindings.single.createWireFields,
        {'fixture_mode'},
      );
    },
  );

  test('reserved, duplicate and undeclared create fields are rejected', () {
    expect(
      () => const PluginRegistry([
        _Plugin(field: 'raw'),
      ]).composerMetadataBindings,
      throwsArgumentError,
    );
    expect(
      () =>
          const PluginRegistry([_Plugin(), _Plugin()]).composerMetadataBindings,
      throwsArgumentError,
    );
    expect(
      () => freezeComposerCreateFields({'foreign': true}, allowed: {'owned'}),
      throwsArgumentError,
    );
    expect(
      () => freezeComposerCreateFields({'raw': 'replace core'}),
      throwsArgumentError,
    );
  });

  test('category decoding survives sparse updates and core mutations', () {
    const models = DiscourseModelCodec(extensions: registry);
    final held = models.category({
      'id': 3,
      'name': 'General',
      'fixture_default': true,
    }, _site);
    final sparse = models.category({'id': 3, 'name': 'Renamed'}, _site);
    final merged = held.merge(sparse);
    expect(merged.plugins.get(_category)?.enabled, isTrue);
    expect(
      merged.withNotificationLevel(CategoryNotificationLevel.watching).plugins,
      merged.plugins,
    );
    final clear = models.category({
      'id': 3,
      'name': 'Renamed',
      'fixture_default': false,
    }, _site);
    expect(merged.merge(clear).plugins.get(_category)?.enabled, isFalse);
  });

  test(
    'ordinary create adapter carries owned fields without replacing core fields',
    () async {
      late Map<String, dynamic> sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'action': 'create_post',
              'post': {
                'id': 41,
                'topic_id': 8,
                'post_number': 1,
                'username': 'sam',
                'cooked': '<p>Body</p>',
              },
            }),
            200,
          );
        }),
      );
      await api.createTopic(
        siteUrl: _site,
        apiKey: 'key',
        title: 'Title',
        raw: 'Body',
        typingDuration: Duration.zero,
        composerOpenDuration: Duration.zero,
        extraFields: {'fixture_mode': true},
      );
      expect(sent['fixture_mode'], isTrue);
      expect(sent['title'], 'Title');
      expect(sent['raw'], 'Body');
      await expectLater(
        api.createTopic(
          siteUrl: _site,
          apiKey: 'key',
          title: 'Title',
          raw: 'Body',
          typingDuration: Duration.zero,
          composerOpenDuration: Duration.zero,
          extraFields: {'raw': 'Override'},
        ),
        throwsArgumentError,
      );
    },
  );
}

final class _Plugin implements SitePlugin, ComposerMetadataPlugin<bool> {
  const _Plugin({this.field = 'fixture_mode'});
  final String field;
  @override
  String get name => 'authoring-fixture';
  @override
  PluginDataKey<bool> get record => _mode;
  @override
  PluginDataPersistenceCodec<bool> get composerMetadataCodec => const _Codec();
  @override
  Set<String> get createWireFields => {field};
  @override
  bool initialMetadata(PluginComposerContext context) =>
      context.categoryData.get(_category)?.enabled == true;
  @override
  bool reconcileMetadata(
    PluginComposerContext before,
    PluginComposerContext after,
    bool held,
  ) => before.categoryId == after.categoryId ? held : initialMetadata(after);
  @override
  Map<String, Object?> createPayload(
    PluginComposerContext context,
    bool held,
  ) => held ? {field: true} : {};
  @override
  PluginComposerLabels? labels(PluginComposerContext context, bool held) => held
      ? const PluginComposerLabels(
          title: 'Fixture topic',
          submit: 'Publish fixture',
        )
      : null;
}

final class _ExplicitChoicePlugin extends _Plugin {
  const _ExplicitChoicePlugin();

  @override
  bool reconcileMetadata(
    PluginComposerContext before,
    PluginComposerContext after,
    bool held,
  ) => held;
}

final class _Codec extends PluginDataPersistenceCodec<bool> {
  const _Codec();
  @override
  PluginDataKey<bool> get key => _mode;
  @override
  bool? decode(Object? value) => value is bool ? value : null;
  @override
  Object encode(bool value) => value;
}

final class _Category implements TopicRecordValue {
  const _Category(this.enabled);
  final bool? enabled;
  @override
  Object mergeTopicRecord(Object? held) =>
      _Category(enabled ?? (held is _Category ? held.enabled : null));
}

final class _CategoryPlugin
    implements SitePlugin, CategoryRecordPlugin<_Category> {
  const _CategoryPlugin();
  @override
  String get name => 'authoring-fixture';
  @override
  PluginDataKey<_Category> get record => _category;
  @override
  _Category? readCategory(
    Map<String, dynamic> json,
    String siteUrl, {
    TopicRecordDecodeContext context = const TopicRecordDecodeContext.partial(),
  }) => _Category(json['fixture_default'] as bool?);
}

final class _MutablePlugin extends _Plugin {
  _MutablePlugin(this.fields);
  final Set<String> fields;
  @override
  Set<String> get createWireFields => fields;
}

final class _Module implements PluginModule {
  const _Module(this.plugin);
  final SitePlugin plugin;
  @override
  PluginDescriptor get descriptor =>
      PluginDescriptor(id: PluginId(plugin.name));
  @override
  void register(PluginRegistrar registrar) => registrar.addCapability(plugin);
}
