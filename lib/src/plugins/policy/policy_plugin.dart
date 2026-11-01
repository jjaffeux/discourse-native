import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;
import 'policy_card.dart';
import 'policy_composer.dart';
import 'policy_controller.dart';
import 'policy_data.dart';
import 'policy_definition.dart';
import 'policy_preferences.dart';
import 'policy_services.dart';

const policyEditorService = PluginServiceKey<PluginPostEditorHost>(
  owner: PluginId('discourse-policy'),
  name: 'post-editor',
);

class PolicyPlugin
    implements
        SitePlugin,
        IsolateTopicDecoderPlugin,
        SiteSettingsPlugin<PolicySettings>,
        CurrentUserPlugin<PolicyCurrentUser>,
        PostRecordPlugin<PolicyPostData>,
        PostBodyPlugin,
        CookedElementPlugin,
        ComposerSyntaxPlugin,
        ComposerToolbarPlugin,
        TopicLivePlugin,
        UserPreferencesPlugin,
        UserPreferenceSectionPlugin {
  const PolicyPlugin();
  @override
  String get name => 'discourse-policy';
  @override
  SitePlugin Function()? get isolateTopicDecoderFactory =>
      runtimeType == PolicyPlugin ? PolicyPlugin.new : null;
  @override
  PluginDataKey<PolicyPostData> get record => policyPostKey;
  @override
  PolicyPostData? readPost(Map<String, dynamic> json, String siteUrl) =>
      PolicyPostData.fromWire(json, siteUrl);
  @override
  PolicyPostData? mergeAfterPostEdit(
    PolicyPostData? held,
    PolicyPostData? incoming,
  ) => incoming;
  @override
  PluginDataPersistenceCodec<PolicySettings> get siteSettingsCodec =>
      policySettingsPersistenceCodec;
  @override
  PolicySettings? readSiteSettings(Map<String, dynamic> json, String siteUrl) =>
      PolicySettings.fromWire(json);
  @override
  PluginDataPersistenceCodec<PolicyCurrentUser> get currentUserCodec =>
      policyCurrentUserPersistenceCodec;
  @override
  PolicyCurrentUser? readCurrentUser(
    Map<String, dynamic> json,
    String siteUrl,
  ) => PolicyCurrentUser.fromWire(json);
  @override
  ComposerSyntaxKind get composerSyntaxKind => policyComposerKind;
  @override
  ComposerSyntaxPolicy createComposerSyntaxPolicy(
    ComposerSyntaxPolicyContext context,
  ) => PolicyComposerPolicy(context);
  @override
  List<ComposerToolbarContribution> composerToolbar(
    BuildContext context,
    ComposerEditorHost editor,
  ) => policyComposerToolbar(context, editor);
  @override
  List<String> topicChannels(int topicId) => ['/topic/$topicId'];
  @override
  List<int> stalePosts(String channel, Object? data) {
    if (!RegExp(r'^/topic/\d+$').hasMatch(channel) ||
        data is! Map ||
        data['type'] != 'policy_change') {
      return const [];
    }
    final id = liveRefreshId(data['id']);
    return id == null ? const [] : [id];
  }

  @override
  List<UserPreferenceCodec> get userPreferenceCodecs => const [
    PolicyEmailCodec(),
  ];
  @override
  PluginUserPreferenceSection? userPreferenceSection(
    BuildContext context,
    PluginUserPreferenceContext preferences,
  ) => preferences.siteSettings.policySettings?.enabled != true
      ? null
      : PluginUserPreferenceSection(
          section: policyEmailSection,
          title: context.l10n.policyTitle,
          icon: DIcons.fileSignature,
          content: policyEmailPreference(context, preferences),
        );

  @override
  Widget? postBodyElement(PluginPostBodyContext context, dom.Element element) {
    if (!element.classes.contains('policy')) return null;
    if (!_authoritativeElement(element)) {
      return cookedElement(context.siteUrl, element);
    }
    return _PolicyPost(
      siteUrl: context.siteUrl,
      post: context.post,
      topic: context.topic,
      definition: PolicyDefinition.fromCookedAttributes({
        for (final entry in element.attributes.entries)
          if (entry.key is String) entry.key as String: entry.value,
      }),
      html: element.innerHtml,
      controller: PluginUiScope.maybe(
        context.buildContext,
        policyControllerService,
      ),
      editor: PluginUiScope.maybe(context.buildContext, policyEditorService),
    );
  }

  @override
  Widget? cookedElement(String? siteUrl, dom.Element element) =>
      !element.classes.contains('policy')
      ? null
      : PolicyCard(
          siteUrl: siteUrl,
          definition: PolicyDefinition.fromCookedAttributes({
            for (final entry in element.attributes.entries)
              if (entry.key is String) entry.key as String: entry.value,
          }),
          body: CookedHtml(html: element.innerHtml, siteUrl: siteUrl),
        );
}

bool _quoted(dom.Element element) {
  for (var parent = element.parent; parent != null; parent = parent.parent) {
    if (parent.localName == 'blockquote' || parent.classes.contains('quote')) {
      return true;
    }
  }
  return false;
}

bool _authoritativeElement(dom.Element element) {
  if (_quoted(element)) return false;
  dom.Node root = element;
  while (root.parentNode != null) {
    root = root.parentNode!;
  }
  return identical(
    _elements(root)
        .where((item) => item.classes.contains('policy') && !_quoted(item))
        .firstOrNull,
    element,
  );
}

Iterable<dom.Element> _elements(dom.Node node) sync* {
  if (node is dom.Element) yield node;
  for (final child in node.nodes) {
    yield* _elements(child);
  }
}

class _PolicyPost extends StatefulWidget {
  const _PolicyPost({
    required this.siteUrl,
    required this.post,
    required this.topic,
    required this.definition,
    required this.html,
    required this.controller,
    required this.editor,
  });
  final String siteUrl, html;
  final Post post;
  final PluginContainingTopic? topic;
  final PolicyDefinition definition;
  final PolicyController? controller;
  final PluginPostEditorHost? editor;
  @override
  State<_PolicyPost> createState() => _PolicyPostState();
}

class _PolicyPostState extends State<_PolicyPost> {
  PluginSiteLease? _lease;
  VoidCallback? _release;
  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    _release?.call();
    _lease = widget.controller?.captureSiteSession(widget.siteUrl);
    final topic = widget.topic;
    _release = topic == null
        ? null
        : widget.controller?.retain(
            siteUrl: widget.siteUrl,
            topicId: topic.id,
            postId: widget.post.id,
          );
  }

  @override
  void didUpdateWidget(_PolicyPost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.post.id != widget.post.id ||
        oldWidget.controller != widget.controller ||
        _lease?.isCurrent == false) {
      _bind();
    }
  }

  @override
  void dispose() {
    _release?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.controller == null
      ? _card()
      : ListenableBuilder(
          listenable: widget.controller!,
          builder: (context, _) => _card(),
        );
  Widget _card() {
    final controller = widget.controller;
    final lease = _lease;
    final topic = widget.topic;
    final current =
        controller != null &&
        lease?.isCurrent == true &&
        controller.enabled(widget.siteUrl);
    final post = current
        ? controller.readPost(widget.siteUrl, widget.post.id)
        : null;
    final data = post?.plugins.policy;
    final state = controller?.interaction(widget.siteUrl, widget.post.id);
    return PolicyCard(
      key: ValueKey((widget.siteUrl, lease)),
      siteUrl: widget.siteUrl,
      definition: widget.definition,
      body: CookedHtml(html: widget.html, siteUrl: widget.siteUrl),
      data: data,
      pending: current && state?.pending == true,
      uncertain: current && state?.phase == PolicyWritePhase.uncertain,
      error: current ? state?.error : null,
      canPage: current && controller.isConnected(widget.siteUrl),
      onAct: !current || topic == null || data == null
          ? null
          : (action) async {
              if (lease!.isCurrent) {
                await controller.act(
                  siteUrl: widget.siteUrl,
                  topicId: topic.id,
                  postId: widget.post.id,
                  action: action,
                  lease: lease,
                );
              }
            },
      onLoadParticipants: !current || data == null
          ? null
          : (list, offset) => controller.participants(
              siteUrl: widget.siteUrl,
              postId: widget.post.id,
              list: list,
              offset: offset,
              lease: lease!,
            ),
      onCheckStatus: !current || topic == null
          ? null
          : () => controller.checkStatus(
              siteUrl: widget.siteUrl,
              topicId: topic.id,
              postId: widget.post.id,
              lease: lease!,
            ),
      onEditSettings:
          !current ||
              post == null ||
              !controller.canManage(widget.siteUrl, post) ||
              widget.editor == null
          ? null
          : () {
              if (lease!.isCurrent) {
                widget.editor!.open(
                  widget.siteUrl,
                  post.id,
                  focusText: '[policy',
                  editReason: context.l10n.policySettingsModified,
                );
              }
            },
    );
  }
}
