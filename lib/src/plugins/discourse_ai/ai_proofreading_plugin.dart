import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

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
        ComposerOptionsPlugin {
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
  List<Widget> composerOptions(
    BuildContext context,
    ComposerEditorHost editor,
  ) {
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
      return DDropdownMenuCheckboxItem(
        key: const ValueKey('composer-proofread-control'),
        checked: enabled,
        onChanged: interactive
            ? (value) => controller.setEnabled(composer, value)
            : null,
        child: const Text('Proofread'),
      );
    },
  );
}
