import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'post_voting_actions.dart';
import 'post_voting_api.dart';

final class PostVotingCategoryController extends ChangeNotifier {
  PostVotingCategoryController({
    required this.reader,
    required PostVotingApi api,
    required this.requests,
    this.available,
  }) : categories = PluginCategorySettingsApi(api.transport),
       lease = requests.capture(reader.siteUrl),
       categoryId = reader.topic?.categoryId {
    reader.addListener(_changed);
  }
  void _changed() {
    if (!disposed) {
      if (!current) category = null;
      notifyListeners();
    }
  }

  final PluginTopicReader reader;
  final PluginRequestHost requests;
  final PluginCategorySettingsApi categories;
  final PluginSiteLease lease;
  final int? categoryId;
  final bool Function()? available;
  PluginCategorySettingsSnapshot? category;
  bool busy = false, uncertain = false, disposed = false;
  Object? error;
  bool get current =>
      !disposed &&
      lease.isCurrent &&
      reader.isCurrent &&
      reader.foreground &&
      reader.currentUserId != null &&
      reader.topic?.categoryId == categoryId &&
      (available?.call() ?? true);
  bool get canEdit =>
      current && category?.canEdit == true && !busy && !uncertain;
  bool get defaultOn =>
      category?.customFields['create_as_post_voting_default'] == true;
  bool get requiredOn =>
      category?.customFields['only_post_voting_in_this_category'] == true;
  Future<void> load() async {
    if (!current || busy || categoryId == null) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final credentials = await requests.credentialsFor(reader.siteUrl);
      if (!current) return;
      final result = await categories.read(
        siteUrl: reader.siteUrl,
        categoryId: categoryId!,
        credentials: credentials,
      );
      if (current) {
        category = result;
        uncertain = false;
      }
    } catch (failure) {
      if (current) error = failure;
    } finally {
      if (!disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> save({required bool defaultOn, required bool requiredOn}) async {
    if (!canEdit) return;
    final original = category!;
    busy = true;
    error = null;
    notifyListeners();
    var sent = false;
    try {
      final auth = await requests.writeCredentialFor(reader.siteUrl);
      if (!current) return;
      if (auth.failure case final failure?) throw failure;
      final credentials = auth.credentials;
      if (credentials == null) {
        throw const WriteException(WriteFailure.forbidden);
      }
      sent = true;
      final result = await categories.save(
        siteUrl: reader.siteUrl,
        snapshot: original,
        settings: const {},
        customFields: {
          ...original.customFields,
          'create_as_post_voting_default': defaultOn,
          'only_post_voting_in_this_category': requiredOn,
        },
        credentials: credentials,
      );
      if (current) category = result;
    } catch (failure) {
      if (current) {
        error = failure;
        uncertain =
            sent &&
            (failure is! WriteException ||
                failure.failure == WriteFailure.unreachable &&
                    !failure.notSent);
      }
    } finally {
      if (!disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    reader.removeListener(_changed);
    disposed = true;
    super.dispose();
  }
}

Future<void> showPostVotingCategorySettings(
  BuildContext context, {
  required PluginTopicReader reader,
  required PostVotingApi api,
  required PluginRequestHost requests,
  bool Function()? available,
}) async {
  final controller = PostVotingCategoryController(
    reader: reader,
    api: api,
    requests: requests,
    available: available,
  );
  try {
    if (!controller.current) return;
    unawaited(controller.load());
    await showShellSheet<void>(
      context: context,
      title: context.l10n.postVotingCategorySettings,
      dialogOnDesktop: true,
      builder: (context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            if (controller.busy) const DSpinner(),
            if (controller.error != null)
              DAlert(
                variant: DAlertVariant.destructive,
                description: DAlertDescription(
                  child: Text(
                    controller.uncertain
                        ? context.l10n.postVotingUncertain
                        : postVotingError(controller.error!),
                  ),
                ),
                action: DAlertAction(
                  child: DButton(
                    label: Text(context.l10n.postVotingRefreshStatus),
                    onPressed: controller.busy ? null : controller.load,
                  ),
                ),
              ),
            if (controller.current && controller.category != null) ...[
              Text(controller.category!.name),
              DToggle(
                pressed: controller.defaultOn,
                enabled: controller.canEdit,
                onPressedChanged: (value) => unawaited(
                  controller.save(
                    defaultOn: value,
                    requiredOn: controller.requiredOn,
                  ),
                ),
                child: Text(context.l10n.postVotingCategoryDefault),
              ),
              DToggle(
                pressed: controller.requiredOn,
                enabled: controller.canEdit,
                onPressedChanged: (value) => unawaited(
                  controller.save(
                    defaultOn: controller.defaultOn,
                    requiredOn: value,
                  ),
                ),
                child: Text(context.l10n.postVotingCategoryOnly),
              ),
            ],
          ],
        ),
      ),
    );
  } finally {
    controller.dispose();
  }
}
