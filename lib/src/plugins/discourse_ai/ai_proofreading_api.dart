import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';

import 'ai_generation_write.dart';

const aiProofreadingPath = '/discourse-ai/ai-helper/suggest';

final class AiProofreadingApi {
  const AiProofreadingApi(this._transport);

  final PluginApiTransport _transport;

  Future<String> proofread({
    required String siteUrl,
    required String apiKey,
    required String text,
  }) async {
    final body = await postAiGeneration(
      _transport,
      siteUrl: siteUrl,
      path: aiProofreadingPath,
      apiKey: apiKey,
      body: {'text': text, 'mode': 'proofread'},
    );
    for (final suggestion in jsonArray(body['suggestions'])) {
      if (suggestion is String && suggestion.trim().isNotEmpty) {
        return suggestion;
      }
    }
    throw FormatException(appL10n.proofreadingResponseContainedNoSuggestion);
  }
}
