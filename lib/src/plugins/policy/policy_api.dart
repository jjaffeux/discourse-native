import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'policies_api.dart';
import 'policy_data.dart';

final class PolicyApi implements PoliciesApi {
  const PolicyApi(this.transport);
  final PluginApiTransport transport;

  @override
  Future<void> mutate({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required int postId,
    required PolicyAction action,
  }) async {
    _requirePost(postId);
    final response = await transport.pluginWriteJson(
      siteUrl: siteUrl,
      path: switch (action) {
        PolicyAction.accept => '/policy/accept.json',
        PolicyAction.revoke => '/policy/unaccept.json',
      },
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'post_id': postId},
    );
    if (response['success'] != 'OK') {
      throw const WriteException(WriteFailure.unreachable);
    }
  }

  @override
  Future<PolicyUsersPage> participants({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required int postId,
    required PolicyParticipantList list,
    required int offset,
  }) async {
    _requirePost(postId);
    if (offset < 0) {
      throw RangeError.value(offset, 'offset', 'Must be nonnegative.');
    }
    final route = switch (list) {
      PolicyParticipantList.accepted => '/policy/accepted.json',
      PolicyParticipantList.outstanding => '/policy/not-accepted.json',
    };
    final response = await transport.pluginGetJson(
      siteUrl: siteUrl,
      path: '$route?post_id=$postId&offset=$offset',
      apiKey: apiKey,
      clientId: clientId,
    );
    final users = PolicyUserSummary.readList(response['users']);
    if (users == null) throw const WriteException(WriteFailure.unreachable);
    return PolicyUsersPage(users: users, receivedCount: users.length);
  }

  static void _requirePost(int postId) {
    if (postId <= 0) {
      throw RangeError.value(postId, 'postId', 'Must be positive.');
    }
  }
}
