import 'package:discourse_native/discourse_plugin_contracts.dart';

final class PolicyGroup {
  const PolicyGroup(this.id, this.name, this.automatic);
  final int id;
  final String name;
  final bool automatic;
}

final class PolicyGroups {
  const PolicyGroups(this.transport, this.requests);
  final PluginApiTransport transport;
  final PluginRequestHost requests;

  Future<List<PolicyGroup>> load(String siteUrl) async {
    final lease = requests.capture(siteUrl);
    final credentials = await requests.credentialsFor(siteUrl);
    if (!lease.isCurrent || credentials.apiKey == null) return const [];
    final body = await credentials.run(
      () => transport.pluginGetJson(
        siteUrl: siteUrl,
        path: '/groups/search.json',
        apiKey: credentials.apiKey,
        clientId: credentials.clientId,
      ),
    );
    if (!lease.isCurrent) return const [];
    final raw = body['groups'];
    if (raw is! List) throw const WriteException(WriteFailure.unreachable);
    final result = <PolicyGroup>[];
    for (final entry in raw) {
      final json = jsonObjectFields(entry);
      final id = json?['id'];
      final name = json?['name'];
      final automatic = json?['automatic'];
      if (id is! int || name is! String || name.isEmpty || automatic is! bool) {
        throw const WriteException(WriteFailure.unreachable);
      }
      if (id != 0) result.add(PolicyGroup(id, name, automatic));
    }
    return List.unmodifiable(result);
  }
}
