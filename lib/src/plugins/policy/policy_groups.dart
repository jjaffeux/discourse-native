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
    final listTransport = switch (transport) {
      final PluginJsonListTransport transport => transport,
      _ => throw const WriteException(WriteFailure.unreachable),
    };
    final rows = await credentials.run(
      () => listTransport.pluginGetJsonList(
        siteUrl: siteUrl,
        path: '/groups/search.json',
        apiKey: credentials.apiKey,
        clientId: credentials.clientId,
      ),
    );
    if (!lease.isCurrent) return const [];
    final result = <PolicyGroup>[];
    for (final row in rows) {
      final id = row['id'];
      final name = row['name'];
      final automatic = row['automatic'];
      if (id is! int || name is! String || name.isEmpty || automatic is! bool) {
        throw const WriteException(WriteFailure.unreachable);
      }
      if (id != 0) result.add(PolicyGroup(id, name, automatic));
    }
    return List.unmodifiable(result);
  }
}
