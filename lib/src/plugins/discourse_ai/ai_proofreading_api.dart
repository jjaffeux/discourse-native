import '../../data/plugin_transport.dart';
import '../../models/json.dart';

const aiProofreadingPath = '/discourse-ai/ai-helper/suggest';

final class AiProofreadingApi {
  const AiProofreadingApi(this._transport);

  final PluginApiTransport _transport;

  Future<String> proofread({
    required String siteUrl,
    required String apiKey,
    required String text,
  }) async {
    final body = await _transport.pluginWriteJson(
      siteUrl: siteUrl,
      path: aiProofreadingPath,
      method: 'POST',
      apiKey: apiKey,
      body: {'text': text, 'mode': 'proofread'},
    );
    for (final suggestion in jsonArray(body['suggestions'])) {
      if (jsonText(suggestion) case final text?) return text;
    }
    throw const FormatException(
      'Proofreading response contained no suggestion.',
    );
  }
}
