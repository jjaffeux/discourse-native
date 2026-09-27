import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'ai_summary.dart';

final class AiSummaryApi {
  const AiSummaryApi(this._transport);

  final PluginApiTransport _transport;

  Future<AiTopicSummary> cached({
    required String siteUrl,
    required int topicId,
    String? apiKey,
    String? clientId,
  }) async {
    final body = await _transport.pluginGetJson(
      siteUrl: siteUrl,
      path: '/discourse-ai/summarization/t/$topicId.json',
      apiKey: apiKey,
      clientId: clientId,
    );
    return _requireSummary(body);
  }

  Future<Map<String, dynamic>> generate({
    required String siteUrl,
    required int topicId,
    required String apiKey,
    bool stream = true,
    bool regenerate = false,
    String? clientId,
  }) => _transport.pluginWriteJson(
    siteUrl: siteUrl,
    path: '/discourse-ai/summarization/t/$topicId.json',
    method: 'POST',
    apiKey: apiKey,
    clientId: clientId,
    body: {
      // The controller only tests `stream` for truthiness, so a boolean works.
      if (stream) 'stream': true,
      // The controller compares `skip_age_check == "true"`; a JSON boolean
      // re-serves the outdated cached summary.
      if (regenerate) 'skip_age_check': 'true',
    },
  );

  static AiTopicSummary _requireSummary(Map<String, dynamic> body) =>
      AiTopicSummary.fromJson(body) ??
      (throw const FormatException('Summary response had no summary.'));
}
