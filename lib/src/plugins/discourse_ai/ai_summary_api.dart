import '../../data/discourse_api_contracts.dart';
import 'ai_summary.dart';

/// Typed client for discourse-ai's topic summarization route.
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
    body: {if (stream) 'stream': true, if (regenerate) 'skip_age_check': true},
  );

  static AiTopicSummary _requireSummary(Map<String, dynamic> body) =>
      AiTopicSummary.fromJson(body) ??
      (throw const FormatException('Summary response had no summary.'));
}
