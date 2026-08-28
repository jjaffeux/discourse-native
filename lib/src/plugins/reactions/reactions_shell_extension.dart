import '../../data/discourse_api_contracts.dart';
import '../../models/post.dart';
import '../../shell/shell_controller.dart';
import 'reaction.dart';
import 'reactions_api.dart';
import 'reactions_api_client.dart';
import 'reactions_controller.dart';
import 'reactions_services.dart';

/// Reactions' typed interaction API over core's plugin-neutral write host.
extension ReactionsShellExtension on ShellController {
  ReactionsController get reactions =>
      pluginSession.require(reactionsControllerService);

  Future<String?> toggleReaction(
    Post post,
    String reaction, {
    String? siteUrl,
  }) async {
    final targetSite = siteUrl ?? currentInstance?.url;
    if (targetSite == null || !post.canReact) return null;
    if (!beginPluginPostWrite(targetSite, post.id)) return null;
    final lease = lifecycle.capture(targetSite);

    try {
      final credential = await pluginWriteCredential(targetSite);
      if (!lease.isCurrent) return null;
      if (credential.failure case final failure?) return failure.message;
      final apiKey = credential.apiKey!;
      final held = post.reactions;
      if (held == null) return null;

      final applied = lease.commit(() {
        store.update<Post>(targetSite, post.id, (current) {
          final reactions = current.reactions;
          if (reactions == null) return current;
          return current.withPlugins(
            current.plugins.withValue(
              reactionsDataKey,
              reactions
                  .withToggled(reaction)
                  .withMainReaction(siteConfigFor(targetSite).mainReaction),
            ),
          );
        });
        notifyPluginStateChanged();
      });
      if (!applied) return null;

      void revert() {
        lease.commit(() {
          store.update<Post>(
            targetSite,
            post.id,
            (current) => current.withPlugins(
              current.plugins.withValue(reactionsDataKey, held),
            ),
          );
          notifyPluginStateChanged();
        });
      }

      try {
        final reactionsApi = api is ReactionsWriteApi
            ? api as ReactionsWriteApi
            : ReactionsApiClient(api, api.models);
        final fresh = await reactionsApi.toggleReaction(
          siteUrl: targetSite,
          apiKey: apiKey,
          postId: post.id,
          reaction: reaction,
        );
        if (fresh?.reactions case final answered?) {
          lease.commit(() {
            store.update<Post>(
              targetSite,
              post.id,
              (current) => current.withPlugins(
                current.plugins.withValue(
                  reactionsDataKey,
                  current.reactions?.withMineOf(answered),
                ),
              ),
            );
            notifyPluginStateChanged();
          });
        }
      } on WriteException catch (error) {
        if (error.statusCode == 404) {
          lease.commit(() {
            store.update<Post>(
              targetSite,
              post.id,
              (current) => current.withPlugins(
                current.plugins.withValue(reactionsDataKey, null),
              ),
            );
            notifyPluginStateChanged();
          });
          return null;
        }
        revert();
        return error.message;
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          reportPluginError(error, stackTrace, 'post.toggleReaction');
        }
        revert();
        return const WriteException(WriteFailure.unreachable).message;
      }
      return null;
    } finally {
      lease.commit(() => endPluginPostWrite(targetSite, post.id));
    }
  }
}
