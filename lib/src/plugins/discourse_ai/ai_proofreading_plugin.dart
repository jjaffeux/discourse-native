import 'package:flutter/material.dart';

import '../../plugin_api/plugin_scope.dart';
import '../../plugin_api/site_plugin_api.dart';
import 'ai_proofreading_controller.dart';
import 'ai_proofreading_data.dart';
import 'discourse_ai_services.dart';

final class AiProofreadingPlugin
    implements
        SitePlugin,
        SiteSettingsPlugin<DiscourseAiSettings>,
        CurrentUserPlugin<DiscourseAiCurrentUser>,
        ComposerHeaderPlugin {
  const AiProofreadingPlugin();

  @override
  String get name => 'discourse-ai';

  @override
  PluginDataPersistenceCodec<DiscourseAiSettings> get siteSettingsCodec =>
      discourseAiSettingsPersistenceCodec;

  @override
  DiscourseAiSettings readSiteSettings(
    Map<String, dynamic> json,
    String siteUrl,
  ) => DiscourseAiSettings.fromWire(json);

  @override
  PluginDataPersistenceCodec<DiscourseAiCurrentUser> get currentUserCodec =>
      discourseAiCurrentUserPersistenceCodec;

  @override
  DiscourseAiCurrentUser? readCurrentUser(
    Map<String, dynamic> json,
    String siteUrl,
  ) => DiscourseAiCurrentUser.fromWire(json);

  @override
  List<Widget> composerHeader(BuildContext context, ComposerEditorHost editor) {
    final controller = PluginUiScope.maybe(
      context,
      aiProofreadingControllerService,
    );
    if (controller == null || !controller.isAvailable(editor)) return const [];
    return [_ProofreadToggle(controller: controller, composer: editor)];
  }
}

class _ProofreadToggle extends StatelessWidget {
  const _ProofreadToggle({required this.controller, required this.composer});

  final AiProofreadingController controller;
  final ComposerEditorHost composer;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final enabled = controller.isEnabled(composer);
      final interactive = composer.isEditing && !composer.loadingBody;
      return Tooltip(
        message: 'Proofread automatically before posting',
        child: Semantics(
          key: const ValueKey('composer-proofread-toggle'),
          button: true,
          enabled: interactive,
          toggled: enabled,
          label: 'Proofread',
          excludeSemantics: true,
          child: InkWell(
            key: const ValueKey('composer-proofread-control'),
            borderRadius: BorderRadius.circular(18),
            onTap: interactive
                ? () => controller.setEnabled(composer, !enabled)
                : null,
            child: Padding(
              padding: const EdgeInsets.only(left: 8, right: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Proofread',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(width: 4),
                  ExcludeSemantics(
                    child: IgnorePointer(
                      child: SizedBox(
                        width: 38,
                        height: 30,
                        child: Transform.scale(
                          scale: 0.72,
                          child: Switch.adaptive(
                            key: const ValueKey('composer-proofread-switch'),
                            value: enabled,
                            onChanged: interactive ? (_) {} : null,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
