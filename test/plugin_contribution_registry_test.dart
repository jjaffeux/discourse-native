import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _siteUrl = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');
const _targetContext = ComposerTargetContext(
  config: SiteConfig(),
  currentUser: _user,
);
const _menuContext = PluginUserMenuContext(
  siteUrl: _siteUrl,
  user: _user,
  totals: null,
);
const _messageTarget = ComposerTargetKind(
  owner: PluginId('messages'),
  name: 'message',
);

void main() {
  test('absent plugins resolve no composer target or user-menu sections', () {
    const request = ComposerTargetRequest(
      kind: _messageTarget,
      siteUrl: _siteUrl,
      title: 'Message',
    );

    expect(
      PluginRegistry.empty.composerTarget(request, _targetContext),
      isNull,
    );
    expect(PluginRegistry.empty.userMenuSections(_menuContext), isEmpty);
    expect(PluginRegistry.empty.notificationFeeds, isEmpty);
  });

  test('one composer target resolves its owning policy', () {
    final registry = PluginRegistry.validated(const [
      _ComposerPlugin('messages', _messageTarget),
    ]);
    const request = ComposerTargetRequest(
      kind: _messageTarget,
      siteUrl: _siteUrl,
      title: 'Direct message',
    );

    final policy = registry.composerTarget(request, _targetContext);

    expect(policy, isNotNull);
    expect(policy!.kind, _messageTarget);
    expect(policy.draftKey, 'messages/Direct message');
    expect(policy.emojiUsageContext.id, 'messages/message');
  });

  test('one user-menu contribution is collected', () {
    final registry = PluginRegistry.validated(const [
      _MenuPlugin('messages', [_MenuDefinition('messages', 'inbox', 'Inbox')]),
    ]);

    final sections = registry.userMenuSections(_menuContext);

    expect(sections, hasLength(1));
    expect(sections.single.id.id, 'messages/inbox');
    expect(sections.single.label, 'Inbox');
  });

  test('multiple distinct user-menu contributions preserve registry order', () {
    final registry = PluginRegistry.validated(const [
      _MenuPlugin('first', [
        _MenuDefinition('first', 'one', 'First one'),
        _MenuDefinition('first', 'two', 'First two'),
      ]),
      _MenuPlugin('second', [_MenuDefinition('second', 'one', 'Second one')]),
    ]);

    final sections = registry.userMenuSections(_menuContext);

    expect(sections.map((section) => section.id.id), [
      'first/one',
      'first/two',
      'second/one',
    ]);
  });

  test('multiple distinct composer targets resolve independently', () {
    const first = ComposerTargetKind(owner: PluginId('first'), name: 'message');
    const second = ComposerTargetKind(
      owner: PluginId('second'),
      name: 'message',
    );
    final registry = PluginRegistry.validated(const [
      _ComposerPlugin(
        'first',
        first,
        uploadType: ComposerUploadType('first-upload'),
        uploadDisposition: ComposerUploadDisposition.retainAttachment,
        uploadsEnabled: true,
        supportsEditing: true,
        validRaw: 'first-valid',
      ),
      _ComposerPlugin(
        'second',
        second,
        uploadType: ComposerUploadType('second-upload'),
        uploadsEnabled: false,
        validRaw: 'second-valid',
      ),
    ]);

    final firstPolicy = registry.composerTarget(
      const ComposerTargetRequest(
        kind: first,
        siteUrl: _siteUrl,
        title: 'First',
      ),
      _targetContext,
    );
    final secondPolicy = registry.composerTarget(
      const ComposerTargetRequest(
        kind: second,
        siteUrl: _siteUrl,
        title: 'Second',
      ),
      _targetContext,
    );

    expect(firstPolicy?.draftKey, 'first/First');
    expect(secondPolicy?.draftKey, 'second/Second');
    expect(firstPolicy?.uploadType, const ComposerUploadType('first-upload'));
    expect(
      firstPolicy?.uploadDisposition,
      ComposerUploadDisposition.retainAttachment,
    );
    expect(firstPolicy?.uploadsEnabled, isTrue);
    expect(firstPolicy?.supportsEditing, isTrue);
    expect(
      firstPolicy?.validate(
        const ComposerValidationContext(
          raw: 'first-valid',
          completedUploadCount: 0,
        ),
      ),
      isTrue,
    );
    expect(
      firstPolicy?.validate(
        const ComposerValidationContext(
          raw: 'second-valid',
          completedUploadCount: 0,
        ),
      ),
      isFalse,
    );
    expect(secondPolicy?.uploadType, const ComposerUploadType('second-upload'));
    expect(
      secondPolicy?.uploadDisposition,
      ComposerUploadDisposition.insertMarkdown,
    );
    expect(secondPolicy?.uploadsEnabled, isFalse);
    expect(secondPolicy?.supportsEditing, isFalse);
    expect(
      secondPolicy?.validate(
        const ComposerValidationContext(
          raw: 'second-valid',
          completedUploadCount: 0,
        ),
      ),
      isTrue,
    );
    expect(
      secondPolicy?.validate(
        const ComposerValidationContext(
          raw: 'first-valid',
          completedUploadCount: 0,
        ),
      ),
      isFalse,
    );
  });

  test('duplicate composer targets are rejected during validation', () {
    expect(
      () => PluginRegistry.validated(const [
        _ComposerPlugin('messages', _messageTarget),
        _ComposerPlugin('messages', _messageTarget),
      ]),
      throwsA(
        isA<ArgumentError>()
            .having(
              (error) => error.message,
              'message',
              contains('messages/message'),
            )
            .having((error) => error.message, 'message', contains('messages')),
      ),
    );
  });

  test('composer targets must belong to their contributing plugin', () {
    expect(
      () => PluginRegistry.validated(const [
        _ComposerPlugin('other', _messageTarget),
      ]),
      throwsArgumentError,
    );
  });

  test('composer emoji contexts must belong to their contributing plugin', () {
    for (final plugin in const [
      _ComposerPlugin('messages', _messageTarget, emojiOwner: 'other'),
      _ComposerPlugin('messages', _messageTarget, emojiName: 'invalid/context'),
      _ComposerPlugin('messages', _messageTarget, emojiName: ' '),
    ]) {
      final registry = PluginRegistry.validated([plugin]);

      expect(
        () => registry.composerTarget(
          const ComposerTargetRequest(
            kind: _messageTarget,
            siteUrl: _siteUrl,
            title: 'Message',
          ),
          _targetContext,
        ),
        throwsStateError,
      );
    }
  });

  test('composer policies must declare a nonempty draft key', () {
    final registry = PluginRegistry.validated(const [
      _ComposerPlugin('messages', _messageTarget, draftKey: ' '),
    ]);

    expect(
      () => registry.composerTarget(
        const ComposerTargetRequest(
          kind: _messageTarget,
          siteUrl: _siteUrl,
          title: 'Message',
        ),
        _targetContext,
      ),
      throwsStateError,
    );
  });

  test('duplicate user-menu ids are rejected when sections are collected', () {
    final registry = PluginRegistry.validated(const [
      _MenuPlugin('shared', [
        _MenuDefinition('shared', 'inbox', 'First'),
        _MenuDefinition('shared', 'inbox', 'Second'),
      ]),
    ]);

    expect(
      () => registry.userMenuSections(_menuContext),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('shared/inbox'),
        ),
      ),
    );
  });

  test('user-menu sections must belong to their contributing plugin', () {
    final registry = PluginRegistry.validated(const [
      _MenuPlugin('messages', [_MenuDefinition('other', 'inbox', 'Inbox')]),
    ]);

    expect(() => registry.userMenuSections(_menuContext), throwsStateError);
  });

  test('multiple notification feeds preserve registry order', () {
    const first = _FeedDefinition('first', 'alerts');
    const second = _FeedDefinition('second', 'mentions');
    final registry = PluginRegistry.validated(const [
      _FeedPlugin('first', [first]),
      _FeedPlugin('second', [second]),
    ]);

    expect(registry.notificationFeeds.map((source) => source.id.id), [
      'first/alerts',
      'second/mentions',
    ]);
    expect(registry.notificationFeed(first.source.id), first.source);
    expect(registry.notificationFeed(second.source.id), second.source);
  });

  test('duplicate and foreign notification feeds are rejected', () {
    expect(
      () => PluginRegistry.validated(const [
        _FeedPlugin('first', [
          _FeedDefinition('first', 'alerts'),
          _FeedDefinition('first', 'alerts'),
        ]),
      ]),
      throwsArgumentError,
    );
    expect(
      () => PluginRegistry.validated(const [
        _FeedPlugin('first', [_FeedDefinition('other', 'alerts')]),
      ]),
      throwsArgumentError,
    );
  });

  test('singular and keyed providers reject ambiguous contributions', () {
    for (final capabilities in <List<SitePlugin>>[
      const [_MaximumPlugin('first'), _MaximumPlugin('second')],
      const [
        _PermissionPlugin('first', 'edit'),
        _PermissionPlugin('second', 'edit'),
      ],
      const [_SiteFeaturePlugin('same'), _SiteFeaturePlugin('same')],
      const [_UserFeaturePlugin('same'), _UserFeaturePlugin('same')],
      const [
        _PreviewCapability('first', 'shared'),
        _PreviewCapability('second', 'shared'),
      ],
      const [
        _DiagnosticsCapability('first', 'shared'),
        _DiagnosticsCapability('second', 'shared'),
      ],
    ]) {
      expect(() => PluginRegistry.validated(capabilities), throwsArgumentError);
    }
  });

  test('keyed providers require nonempty keys', () {
    for (final capability in <SitePlugin>[
      const _PermissionPlugin('permission', ' '),
      const _SiteFeaturePlugin(''),
      const _UserFeaturePlugin(''),
      const _PreviewCapability('preview', ' '),
      const _DiagnosticsCapability('diagnostics', ' '),
    ]) {
      expect(() => PluginRegistry.validated([capability]), throwsArgumentError);
    }
  });

  test('distinct keyed providers compose', () {
    expect(
      () => PluginRegistry.validated(const [
        _MaximumPlugin('maximum'),
        _PermissionPlugin('first', 'edit'),
        _PermissionPlugin('second', 'delete'),
        _SiteFeaturePlugin('site-one'),
        _SiteFeaturePlugin('site-two'),
        _UserFeaturePlugin('user-one'),
        _UserFeaturePlugin('user-two'),
        _PreviewCapability('preview-one', 'one'),
        _PreviewCapability('preview-two', 'two'),
        _DiagnosticsCapability('diagnostics-one', 'one'),
        _DiagnosticsCapability('diagnostics-two', 'two'),
      ]),
      returnsNormally,
    );
  });
}

final class _MaximumPlugin implements SitePlugin, ComposerMaximumOptionsPlugin {
  const _MaximumPlugin(this.name);

  @override
  final String name;

  @override
  int composerMaximumOptions(PluginData siteSettings) => 20;
}

final class _PermissionPlugin implements SitePlugin, PluginPermissionPlugin {
  const _PermissionPlugin(this.name, this.permissionId);

  @override
  final String name;

  @override
  final String permissionId;

  @override
  bool allowsPermission(PluginData currentUser, bool? recordPermission) => true;
}

final class _SiteFeaturePlugin implements SitePlugin, PluginSiteFeature {
  const _SiteFeaturePlugin(this.name);

  @override
  final String name;

  @override
  bool siteFeatureEnabled(PluginData siteSettings) => true;
}

final class _UserFeaturePlugin implements SitePlugin, PluginCurrentUserFeature {
  const _UserFeaturePlugin(this.name);

  @override
  final String name;

  @override
  bool currentUserFeatureEnabled(PluginData currentUser) => true;
}

final class _PreviewCapability implements ChatMessagePreviewPlugin {
  const _PreviewCapability(this.name, this.previewFeatureId);

  @override
  final String name;

  @override
  final String previewFeatureId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _DiagnosticsCapability implements SitePlugin, DiagnosticsPlugin {
  const _DiagnosticsCapability(this.name, this.diagnosticsId);

  @override
  final String name;

  @override
  final String diagnosticsId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ComposerPlugin implements SitePlugin, ComposerTargetPlugin {
  const _ComposerPlugin(
    this.name,
    this.composerTargetKind, {
    this.emojiOwner,
    this.emojiName,
    this.draftKey,
    this.uploadType = ComposerUploadType.composer,
    this.uploadDisposition = ComposerUploadDisposition.insertMarkdown,
    this.uploadsEnabled,
    this.supportsEditing = false,
    this.validRaw,
  });

  @override
  final String name;

  @override
  final ComposerTargetKind composerTargetKind;

  final String? emojiOwner;
  final String? emojiName;
  final String? draftKey;
  final ComposerUploadType uploadType;
  final ComposerUploadDisposition uploadDisposition;
  final bool? uploadsEnabled;
  final bool supportsEditing;
  final String? validRaw;

  @override
  ComposerTargetPolicy createComposerTarget(
    ComposerTargetRequest request,
    ComposerTargetContext context,
  ) => ComposerTargetPolicy(
    kind: composerTargetKind,
    draftKey: draftKey ?? '$name/${request.title}',
    uploadType: uploadType,
    uploadDisposition: uploadDisposition,
    uploadsEnabled:
        uploadsEnabled ?? context.config.chatSettings.uploadsEnabled,
    supportsEditing: supportsEditing,
    emojiUsageContext: EmojiUsageContext(
      owner: PluginId(emojiOwner ?? name),
      name: emojiName ?? composerTargetKind.name,
    ),
    validate: (context) => validRaw == null || context.raw == validRaw,
  );
}

final class _MenuPlugin implements SitePlugin, UserMenuSectionPlugin {
  const _MenuPlugin(this.name, this.definitions);

  @override
  final String name;

  final List<_MenuDefinition> definitions;

  @override
  List<PluginUserMenuSection> userMenuSections(PluginUserMenuContext context) =>
      [for (final definition in definitions) definition.section];
}

final class _MenuDefinition {
  const _MenuDefinition(this.owner, this.name, this.label);

  final String owner;
  final String name;
  final String label;

  PluginUserMenuSection get section => PluginUserMenuSection(
    id: PluginUserMenuSectionId(owner: PluginId(owner), name: name),
    icon: DIcons.bell,
    label: label,
    builder: (_, _) => Text(label),
  );
}

final class _FeedPlugin implements SitePlugin, NotificationFeedPlugin {
  const _FeedPlugin(this.name, this.definitions);

  @override
  final String name;

  final List<_FeedDefinition> definitions;

  @override
  List<PluginNotificationFeedSource> get notificationFeeds => [
    for (final definition in definitions) definition.source,
  ];
}

final class _FeedDefinition {
  const _FeedDefinition(this.owner, this.name);

  final String owner;
  final String name;

  PluginNotificationFeedSource get source => PluginNotificationFeedSource(
    id: PluginNotificationFeedId(owner: PluginId(owner), name: name),
    filterByTypes: const [NotificationKind.chatMessage],
    reconnectMessage: 'Reconnect.',
    failureMessage: 'Failed.',
    emptyMessage: 'Empty.',
  );
}
