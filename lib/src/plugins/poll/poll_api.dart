import '../../data/discourse_api_contracts.dart'
    show WriteException, WriteFailure;
import '../../data/plugin_transport.dart';
import 'poll.dart';
import 'polls_api.dart';

final class PollApi implements PollsApi {
  const PollApi(this._transport);

  final PluginApiTransport _transport;

  @override
  Future<PollVoteResponse> votePoll({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String pollName,
    required List<String> options,
    String? clientId,
  }) async {
    _requirePositiveId(postId);
    final body = await _transport.pluginWriteJson(
      siteUrl: siteUrl,
      path: '/polls/vote.json',
      method: 'PUT',
      apiKey: apiKey,
      body: {'post_id': postId, 'poll_name': pollName, 'options': options},
      clientId: clientId,
    );
    return _response(
      body,
      siteUrl: siteUrl,
      pollName: pollName,
      requireVote: true,
    );
  }

  @override
  Future<PollVoteResponse> removePollVote({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String pollName,
    String? clientId,
  }) async {
    _requirePositiveId(postId);
    final body = await _transport.pluginWriteJson(
      siteUrl: siteUrl,
      path: '/polls/vote.json',
      method: 'DELETE',
      apiKey: apiKey,
      body: {'post_id': postId, 'poll_name': pollName},
      clientId: clientId,
    );
    return _response(
      body,
      siteUrl: siteUrl,
      pollName: pollName,
      requireVote: false,
    );
  }

  static PollVoteResponse _response(
    Map<String, dynamic> body, {
    required String siteUrl,
    required String pollName,
    required bool requireVote,
  }) {
    final rawPoll = body['poll'];
    if (rawPoll is! Map<String, dynamic> ||
        rawPoll['name'] is! String ||
        rawPoll['type'] is! String ||
        rawPoll['status'] is! String ||
        rawPoll['results'] is! String ||
        rawPoll['options'] is! List ||
        rawPoll['chart_type'] is! String ||
        (requireVote && body['vote'] is! List)) {
      throw const WriteException(WriteFailure.unreachable);
    }

    final withoutSelection = Poll.fromJson(rawPoll, siteUrl);
    if (withoutSelection == null ||
        withoutSelection.name != pollName ||
        withoutSelection.options.length !=
            (rawPoll['options'] as List).length) {
      throw const WriteException(WriteFailure.unreachable);
    }
    final selection = requireVote
        ? PollSelection.fromJson(body['vote'], type: withoutSelection.type)
        : PollSelection.none;
    if (requireVote &&
        withoutSelection.type != PollType.rankedChoice &&
        selection.optionIds.length != (body['vote'] as List).length) {
      throw const WriteException(WriteFailure.unreachable);
    }
    return PollVoteResponse(
      poll: withoutSelection.withSelection(selection),
      selection: selection,
    );
  }

  static void _requirePositiveId(int value) {
    if (value <= 0) {
      throw RangeError.value(value, 'postId', 'Must be positive.');
    }
  }
}
