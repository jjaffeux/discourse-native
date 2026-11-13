import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/foundation.dart';

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
