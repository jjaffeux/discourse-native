import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/plugin_transport.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';

const inviteSite = DiscourseInstance(
  url: 'https://forum.example/community',
  title: 'Forum',
  user: DiscourseUser(id: 1, username: 'Alice', canInviteToForum: true),
);

Map<String, dynamic> inviteRow(
  int id, {
  String? email,
  bool canDelete = true,
}) => {
  'id': id,
  'email': email,
  'description': 'Invite $id',
  'link': '${inviteSite.url}/invites/key-$id',
  'can_delete_invite': canDelete,
  'max_redemptions_allowed': 10,
  'redemption_count': 2,
  'expires_at': '2026-12-01T12:00:00.000Z',
};

Map<String, dynamic> invitePage(
  List<Map<String, dynamic>> rows, {
  int? pending,
  int expired = 0,
  int redeemed = 0,
  bool canSeeDetails = true,
}) => {
  'invites': rows,
  'can_see_invite_details': canSeeDetails,
  'counts': {
    'pending': pending ?? rows.length,
    'expired': expired,
    'redeemed': redeemed,
    'total': (pending ?? rows.length) + expired,
  },
};

typedef InviteRequest = ({
  String siteUrl,
  String method,
  String path,
  String? apiKey,
  String? clientId,
  Map<String, Object?>? body,
});

class InviteTransport implements PluginApiTransport {
  final requests = <InviteRequest>[];
  FutureOr<Map<String, dynamic>> Function(InviteRequest)? onGet;
  FutureOr<Map<String, dynamic>> Function(InviteRequest)? onWrite;

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    final request = (
      siteUrl: siteUrl,
      method: 'GET',
      path: path,
      apiKey: apiKey,
      clientId: clientId,
      body: null,
    );
    requests.add(request);
    if (onGet case final get?) return get(request);
    return invitePage([]);
  }

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    final request = (
      siteUrl: siteUrl,
      method: method,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
      body: body,
    );
    requests.add(request);
    if (onWrite case final write?) return write(request);
    return inviteRow(99);
  }
}

class InviteCredentials implements ApiCredentialReader {
  Future<String?> Function()? readKey;
  Future<String> Function()? readClientId;

  @override
  Future<String?> apiKeyFor(String siteUrl) async =>
      readKey == null ? 'invite-key' : readKey!();

  @override
  Future<String> clientId() async =>
      readClientId == null ? 'invite-client' : readClientId!();
}
