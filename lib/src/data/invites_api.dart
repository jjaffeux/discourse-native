import '../models/invite.dart';
import 'plugin_transport.dart';

final class InvitesApi {
  const InvitesApi(this.transport);

  final PluginApiTransport transport;

  Future<InvitePage> list({
    required String siteUrl,
    required String username,
    required String apiKey,
    String? clientId,
    InviteFilter filter = InviteFilter.pending,
    String search = '',
    int offset = 0,
  }) async => InvitePage.fromJson(
    await transport.pluginGetJson(
      siteUrl: siteUrl,
      path: Uri(
        pathSegments: ['', 'u', username.toLowerCase(), 'invited.json'],
        queryParameters: {
          'filter': filter.name,
          'offset': '$offset',
          if (search.trim().isNotEmpty) 'search': search.trim(),
        },
      ).toString(),
      apiKey: apiKey,
      clientId: clientId,
    ),
  );

  Future<DiscourseInvite> create({
    required String siteUrl,
    required String apiKey,
    String? clientId,
    required InviteDraft draft,
  }) async => DiscourseInvite.fromJson(
    await transport.pluginWriteJson(
      siteUrl: siteUrl,
      path: '/invites.json',
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: draft.toWire(),
    ),
  );

  Future<void> remove({
    required String siteUrl,
    required String apiKey,
    String? clientId,
    required int inviteId,
  }) async {
    await transport.pluginWriteJson(
      siteUrl: siteUrl,
      path: '/invites.json',
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: {'id': inviteId},
    );
  }

  Future<void> resend({
    required String siteUrl,
    required String apiKey,
    String? clientId,
    required String email,
  }) async {
    await transport.pluginWriteJson(
      siteUrl: siteUrl,
      path: '/invites/reinvite.json',
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {'email': email},
    );
  }
}
