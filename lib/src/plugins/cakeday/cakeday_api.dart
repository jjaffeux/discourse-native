import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'cakeday_data.dart';

final class CakedayApi {
  const CakedayApi(this.transport);
  final PluginApiTransport transport;
  Future<CakedayPage> load(
    String site,
    CakedayQuery query,
    int page,
    PluginRequestCredentials credentials,
  ) async {
    final json = await transport.pluginGetJson(
      siteUrl: site,
      path: query.path(page),
      apiKey: credentials.apiKey,
      clientId: credentials.clientId,
    );
    final kind = query.kind.name;
    final rows = json[kind], total = json['total_rows_$kind'];
    if (rows is! List || total is! int || total < 0) {
      throw const FormatException('Invalid celebration directory');
    }
    final members = List<CakedayMember>.unmodifiable(
      rows.map((v) => CakedayMember.read(v, query.kind)),
    );
    final more = json['load_more_$kind'];
    if (members.isNotEmpty && total > members.length && more == null) {
      throw const FormatException('Missing celebration continuation');
    }
    final next = more == null ? null : _next(site, query, page, more);
    return CakedayPage(
      members,
      total,
      members.isEmpty || (page == 0 && members.length >= total) ? null : next,
    );
  }

  int _next(String site, CakedayQuery query, int page, Object? value) {
    if (value is! String) throw const FormatException('Invalid continuation');
    final uri = Uri.tryParse(value), base = Uri.parse(site);
    if (uri == null ||
        uri.hasFragment ||
        (uri.hasScheme && uri.scheme != 'http' && uri.scheme != 'https') ||
        (uri.hasScheme && !uri.hasAuthority) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasAuthority && (uri.origin != base.origin))) {
      throw const FormatException('Invalid continuation origin');
    }
    var path = uri.path;
    final prefix = base.path.replaceAll(RegExp(r'/$'), '');
    if (prefix.isNotEmpty && path.startsWith('$prefix/')) {
      path = path.substring(prefix.length);
    }
    if (path != '/cakeday/${query.kind.name}' &&
        path != '/cakeday/${query.kind.name}.json') {
      throw const FormatException('Invalid continuation path');
    }
    final fields = uri.queryParametersAll;
    if (fields.values.any((v) => v.length != 1) ||
        fields.keys.any((key) => !{'page', 'filter', 'month'}.contains(key))) {
      throw const FormatException('Invalid continuation query');
    }
    final next = int.tryParse(uri.queryParameters['page'] ?? '');
    if (next != page + 1) {
      throw const FormatException('Nonadvancing continuation');
    }
    if (query.period == CakedayPeriod.month) {
      if (int.tryParse(uri.queryParameters['month'] ?? '') != query.month ||
          (uri.queryParameters['filter']?.isNotEmpty ?? false)) {
        throw const FormatException('Changed continuation month');
      }
    } else if (uri.queryParameters['filter'] != query.period.name ||
        uri.queryParameters.containsKey('month')) {
      throw const FormatException('Changed continuation filter');
    }
    return next!;
  }
}
