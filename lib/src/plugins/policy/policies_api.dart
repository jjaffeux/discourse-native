import 'policy_data.dart';

enum PolicyAction { accept, revoke }

enum PolicyParticipantList { accepted, outstanding }

abstract interface class PoliciesApi {
  Future<void> mutate({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required int postId,
    required PolicyAction action,
  });
  Future<PolicyUsersPage> participants({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required int postId,
    required PolicyParticipantList list,
    required int offset,
  });
}

final class PolicyUsersPage {
  PolicyUsersPage({
    required List<PolicyUserSummary> users,
    required this.receivedCount,
  }) : users = List.unmodifiable(users);
  final List<PolicyUserSummary> users;
  final int receivedCount;
}
