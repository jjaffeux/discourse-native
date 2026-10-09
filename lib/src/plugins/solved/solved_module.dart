import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'solved_controller.dart';
import 'solved_global_search.dart';
import 'solved_post.dart';

const solvedModule = _Module();
const _pluginId = PluginId('discourse-solved');
const solvedControllerService = PluginServiceKey<SolvedController>(
  owner: _pluginId,
  name: 'controller',
);

final class _Module implements PluginModule {
  const _Module();
  @override
  PluginDescriptor get descriptor => const PluginDescriptor(id: _pluginId);
  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const SolvedPlugin());
    registrar.addSession(
      (bindings, _) {
        final controller = SolvedController(
          transport: bindings.require(corePluginTransportPort),
          requests: bindings.require(corePluginRequestPort),
          posts: bindings.require(corePluginPostPort),
          topics: bindings.require(corePluginTopicRefreshPort),
        );
        return PluginSessionContribution(
          lifecycle: _Lifecycle(controller),
          services: [
            PluginService<Object>(solvedControllerService, controller),
          ],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginRequestPort,
        corePluginPostPort,
        corePluginTopicRefreshPort,
      ],
    );
  }
}

final class _Lifecycle extends PluginSessionLifecycle {
  _Lifecycle(this.controller);
  final SolvedController controller;
  @override
  void close() => controller.close();
}

final class SolvedPlugin
    implements
        SitePlugin,
        GlobalSearchPlugin,
        PostRecordPlugin<SolvedPost>,
        PostMenuPlugin,
        PostHeaderPlugin,
        PostCardTonePlugin {
  const SolvedPlugin();
  @override
  String get name => 'discourse-solved';
  @override
  List<GlobalSearchContribution> get searchContributions => const [
    SolvedGlobalSearch(),
  ];
  @override
  PluginDataKey<SolvedPost> get record => solvedPostKey;
  @override
  SolvedPost? readPost(Map<String, dynamic> json, String siteUrl) =>
      SolvedPost.fromJson(json);
  @override
  SolvedPost? mergeAfterPostEdit(SolvedPost? held, SolvedPost? incoming) =>
      incoming ?? held;

  PostAction? _action(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
    Post post,
  ) {
    final state = post.plugins.get(solvedPostKey);
    final controller = PluginUiScope.maybe(context, solvedControllerService);
    if (state == null ||
        controller == null ||
        !controller.canChange(post, !state.accepted)) {
      return null;
    }
    final lease = controller.requests.capture(siteUrl);
    final label = state.accepted
        ? appL10n.removeSolution
        : appL10n.markAsSolution;
    return PostAction(
      icon: DIcons.check,
      label: label,
      tooltip: label,
      placement: PostActionPlacement.overflow,
      enabled: !controller.posts.writeInFlight(siteUrl, post.id),
      onInvoke: () => unawaited(() async {
        final error = await controller.change(
          siteUrl: siteUrl,
          topic: topic,
          postId: post.id,
          accepted: !state.accepted,
          lease: lease,
        );
        if (context.mounted && lease.isCurrent && error != null) {
          DToast.show(context, error, type: DToastType.error);
        }
      }()),
    );
  }

  @override
  PostMenuContribution postMenu(PostMenuContext menu) {
    final topic = menu.topic;
    if (topic == null || menu.currentUser == null) {
      return PostMenuContribution.none;
    }
    final action = _action(menu.buildContext, menu.siteUrl, topic, menu.post);
    return PostMenuContribution(entries: [?action]);
  }

  @override
  Color? postCardTone(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
    Post post,
  ) => post.plugins.get(solvedPostKey)?.accepted == true
      ? DTokens.of(context).success
      : null;

  @override
  List<Widget> postHeaders(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
    Post post,
  ) {
    if (post.plugins.get(solvedPostKey)?.accepted != true) return const [];
    final action = _action(context, siteUrl, topic, post);
    return [
      DItem(
        key: ValueKey('solved-post-${post.id}'),
        size: DItemSize.sm,
        children: [
          const DItemMedia(
            variant: DItemMediaVariant.icon,
            child: DIcon(DIcons.check),
          ),
          DItemContent(
            children: [DItemTitle(child: Text(context.l10n.solution))],
          ),
          if (action != null)
            DItemActions(
              children: [
                DButton(
                  variant: DButtonVariant.ghost,
                  size: DButtonSize.chip,
                  onPressed: action.enabled ? action.onInvoke : null,
                  label: Text(action.label),
                ),
              ],
            ),
        ],
      ),
    ];
  }
}
